#!/usr/bin/env python3
"""
Fetches the SIA SSH CA public key for the tenant and prints it as JSON:

    {"public_key": "ssh-rsa AAAAB3Nza..."}

Shaped for Terraform's `data "external"`, which passes its query as JSON on
stdin, but works standalone with the subdomain as an argument.

Why this exists: the provider's idsec_sia_ssh_public_key resource installs the
CA by SSHing into the target machine from wherever Terraform runs. That would
force the demo target to accept inbound SSH from your laptop, defeating the
premise of the demo. The same CA is available from the API, so we fetch it here
and bake it into the target's cloud-init instead -- letting the target sit in a
private subnet with no public IP and no internet egress.

Usage:
    IDSEC_SERVICE_USER=... IDSEC_SERVICE_TOKEN=... ./scripts/get-sia-ssh-ca.py <subdomain>
"""

import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request

ROOT_DOMAIN = "cyberark.cloud"
# The OIDC app the idsec SDK authenticates service users against.
AUTHORIZED_APP = os.environ.get("IDSEC_SERVICE_AUTHORIZED_APP", "__idaptive_cybr_user_oidc")
TIMEOUT = 30


def fail(msg):
    # data.external requires a bare error on stderr and a non-zero exit.
    print(f"get-sia-ssh-ca: {msg}", file=sys.stderr)
    sys.exit(1)


def request(url, *, data=None, params=None, headers=None, method=None, allow_redirect=True):
    if params:
        url = f"{url}?{urllib.parse.urlencode(params)}"
    body = None
    if data is not None:
        body = urllib.parse.urlencode(data).encode()
    req = urllib.request.Request(url, data=body, method=method)
    for key, value in (headers or {}).items():
        req.add_header(key, value)

    opener = urllib.request.build_opener()
    if not allow_redirect:
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *_args, **_kwargs):
                return None

        opener = urllib.request.build_opener(NoRedirect)

    try:
        return opener.open(req, timeout=TIMEOUT)
    except urllib.error.HTTPError as exc:
        if not allow_redirect and exc.code in (301, 302, 303, 307, 308):
            return exc  # The redirect *is* the response we want.
        detail = exc.read().decode("utf-8", "replace")[:400]
        fail(f"HTTP {exc.code} from {url}\n{detail}")
    except urllib.error.URLError as exc:
        fail(f"could not reach {url}: {exc.reason}")


def read_subdomain():
    if len(sys.argv) > 1 and sys.argv[1]:
        return sys.argv[1]
    raw = sys.stdin.read().strip()
    if raw:
        try:
            value = json.loads(raw).get("subdomain", "")
        except json.JSONDecodeError:
            fail("stdin was not valid JSON")
        if value:
            return value
    fail("no tenant subdomain supplied (pass as an argument or as {\"subdomain\": \"...\"} on stdin)")


def main():
    subdomain = read_subdomain()

    service_user = os.environ.get("IDSEC_SERVICE_USER", "")
    service_token = os.environ.get("IDSEC_SERVICE_TOKEN", "")
    if not service_user or not service_token:
        fail("IDSEC_SERVICE_USER and IDSEC_SERVICE_TOKEN must both be set")

    # 1. Resolve the tenant's Identity FQDN via platform discovery.
    discovery = request(
        f"https://platform-discovery.{ROOT_DOMAIN}/api/identity-endpoint/{subdomain}"
    )
    identity_fqdn = json.load(discovery).get("endpoint", "").rstrip("/")
    if not identity_fqdn:
        fail(f"platform discovery returned no endpoint for subdomain '{subdomain}'")
    if not identity_fqdn.startswith("http"):
        identity_fqdn = f"https://{identity_fqdn}"

    # 2. Exchange the service user's credentials for an access token.
    basic = base64.b64encode(f"{service_user}:{service_token}".encode()).decode()
    token_resp = request(
        f"{identity_fqdn}/OAuth2/Token/{AUTHORIZED_APP}",
        data={"grant_type": "client_credentials", "scope": "api"},
        headers={
            "Authorization": f"Basic {basic}",
            "Content-Type": "application/x-www-form-urlencoded",
        },
    )
    access_token = json.load(token_resp).get("access_token")
    if not access_token:
        fail("service user authentication succeeded but returned no access_token")

    # 3. Trade the access token for the platform id_token, which comes back in
    #    the fragment of the redirect's Location header rather than the body.
    #
    #    This must be a GET with query parameters, and redirect_uri is required
    #    even though nothing follows the redirect -- omitting it makes the
    #    endpoint return a 500 rather than a validation error.
    authorize_resp = request(
        f"{identity_fqdn}/OAuth2/Authorize/{AUTHORIZED_APP}",
        params={
            "client_id": AUTHORIZED_APP,
            "response_type": "id_token",
            "scope": "openid profile api",
            "redirect_uri": "https://cyberark.cloud/redirect",
        },
        headers={"Authorization": f"Bearer {access_token}"},
        allow_redirect=False,
    )
    location = authorize_resp.headers.get("Location", "")
    if "#" not in location:
        fail("authorize step did not return a redirect containing an id_token")
    id_token = urllib.parse.parse_qs(location.split("#", 1)[1]).get("id_token", [None])[0]
    if not id_token:
        fail("could not parse id_token out of the authorize redirect")

    # 4. Fetch the SSH CA public key from the SIA (dpa) service.
    ca_resp = request(
        f"https://{subdomain}.dpa.{ROOT_DOMAIN}/api/public-keys",
        headers={"Authorization": f"Bearer {id_token}"},
    )
    public_key = ca_resp.read().decode("utf-8").strip()
    if not public_key.startswith(("ssh-rsa", "ssh-ed25519", "ecdsa-")):
        fail(f"unexpected CA key format: {public_key[:80]!r}")

    # data.external requires a flat string->string map.
    json.dump({"public_key": public_key}, sys.stdout)


if __name__ == "__main__":
    main()
