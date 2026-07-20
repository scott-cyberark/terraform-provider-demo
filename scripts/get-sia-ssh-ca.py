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

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from idira_auth import SIA, IdiraError, platform_token, request, service_url  # noqa: E402


def fail(msg):
    # data.external requires a bare error on stderr and a non-zero exit.
    print(f"get-sia-ssh-ca: {msg}", file=sys.stderr)
    sys.exit(1)


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
    fail('no tenant subdomain supplied (pass as an argument or as {"subdomain": "..."} on stdin)')


def main():
    subdomain = read_subdomain()
    try:
        token = platform_token(subdomain)
        resp = request(
            f"{service_url(subdomain, SIA)}/api/public-keys",
            headers={"Authorization": f"Bearer {token}"},
        )
    except IdiraError as exc:
        fail(str(exc))

    public_key = resp.read().decode("utf-8").strip()
    if not public_key.startswith(("ssh-rsa", "ssh-ed25519", "ecdsa-")):
        fail(f"unexpected CA key format: {public_key[:80]!r}")

    # data.external requires a flat string->string map.
    json.dump({"public_key": public_key}, sys.stdout)


if __name__ == "__main__":
    main()
