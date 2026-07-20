"""
Shared Idira Identity service-user authentication.

Mirrors what the idsec SDK does, so anything built on this behaves the same way
the Terraform provider does:

  1. GET  platform-discovery/api/identity-endpoint/<subdomain>  -> tenant FQDN
  2. POST <fqdn>/OAuth2/Token/<app>      (Basic user:token)     -> access_token
  3. GET  <fqdn>/OAuth2/Authorize/<app>  (Bearer access_token)  -> id_token,
     returned in the fragment of a 302 Location header

Step 3 must be a GET with query parameters and must include redirect_uri, even
though nothing follows the redirect. Omitting it returns a 500, not a validation
error.

Service hostnames differ per API and are easy to get wrong -- policies live on
"uap", not "dpa". Use service_url() rather than assembling hosts by hand.
"""

import base64
import json
import os
import urllib.error
import urllib.parse
import urllib.request

ROOT_DOMAIN = "cyberark.cloud"
AUTHORIZED_APP = os.environ.get("IDSEC_SERVICE_AUTHORIZED_APP", "__idaptive_cybr_user_oidc")
TIMEOUT = 30

# API host prefixes, as the SDK registers them.
SIA = "dpa"
CMGR = "connectormanagement"
POLICIES = "uap"


class IdiraError(Exception):
    """Raised when authentication or an API call fails."""


def request(url, *, data=None, params=None, headers=None, allow_redirect=True):
    """Issue an HTTP request. Returns the response object.

    With allow_redirect=False, a 3xx is returned rather than followed -- the
    Location header is the payload we want from the authorize step.
    """
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    body = urllib.parse.urlencode(data).encode() if data is not None else None
    req = urllib.request.Request(url, data=body)
    for key, value in (headers or {}).items():
        req.add_header(key, value)

    opener = urllib.request.build_opener()
    if not allow_redirect:
        class _NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *_args, **_kwargs):
                return None

        opener = urllib.request.build_opener(_NoRedirect)

    try:
        return opener.open(req, timeout=TIMEOUT)
    except urllib.error.HTTPError as exc:
        if not allow_redirect and exc.code in (301, 302, 303, 307, 308):
            return exc
        detail = exc.read().decode("utf-8", "replace")[:400]
        raise IdiraError(f"HTTP {exc.code} from {url}\n{detail}") from exc
    except urllib.error.URLError as exc:
        raise IdiraError(f"could not reach {url}: {exc.reason}") from exc


def service_url(subdomain, service):
    """Base URL for an Idira service, e.g. service_url("acme", CMGR)."""
    return f"https://{subdomain}.{service}.{ROOT_DOMAIN}"


def platform_token(subdomain, service_user=None, service_token=None):
    """Authenticate as a service user and return the platform id_token."""
    service_user = service_user or os.environ.get("IDSEC_SERVICE_USER", "")
    service_token = service_token or os.environ.get("IDSEC_SERVICE_TOKEN", "")
    if not service_user or not service_token:
        raise IdiraError("IDSEC_SERVICE_USER and IDSEC_SERVICE_TOKEN must both be set")

    discovery = request(
        f"https://platform-discovery.{ROOT_DOMAIN}/api/identity-endpoint/{subdomain}"
    )
    fqdn = json.load(discovery).get("endpoint", "").rstrip("/")
    if not fqdn:
        raise IdiraError(f"platform discovery returned no endpoint for '{subdomain}'")
    if not fqdn.startswith("http"):
        fqdn = f"https://{fqdn}"

    basic = base64.b64encode(f"{service_user}:{service_token}".encode()).decode()
    token_resp = request(
        f"{fqdn}/OAuth2/Token/{AUTHORIZED_APP}",
        data={"grant_type": "client_credentials", "scope": "api"},
        headers={
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    access_token = json.load(token_resp).get("access_token")
    if not access_token:
        raise IdiraError("authentication returned no access_token")

    authorize = request(
        f"{fqdn}/OAuth2/Authorize/{AUTHORIZED_APP}",
        params={
            "client_id": AUTHORIZED_APP,
            "response_type": "id_token",
            "scope": "openid profile api",
            "redirect_uri": f"https://{ROOT_DOMAIN}/redirect",
        },
        headers={"Authorization": f"Bearer {access_token}"},
        allow_redirect=False,
    )
    location = authorize.headers.get("Location", "")
    if "#" not in location:
        raise IdiraError("authorize step returned no id_token redirect")
    id_token = urllib.parse.parse_qs(location.split("#", 1)[1]).get("id_token", [None])[0]
    if not id_token:
        raise IdiraError("could not parse id_token from the authorize redirect")
    return id_token


def get_json(subdomain, service, path, token, params=None):
    """GET an API path and return parsed JSON."""
    url = f"{service_url(subdomain, service)}/{path.lstrip('/')}"
    resp = request(url, params=params, headers={"Authorization": f"Bearer {token}"})
    return json.loads(resp.read())


def as_list(payload, *keys):
    """Normalise the several shapes these APIs use for collections."""
    if isinstance(payload, list):
        return payload
    if isinstance(payload, dict):
        for key in (*keys, "resources", "results", "items", "identifiers"):
            value = payload.get(key)
            if isinstance(value, list):
                return value
    return []
