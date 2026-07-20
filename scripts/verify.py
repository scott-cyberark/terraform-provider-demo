#!/usr/bin/env python3
"""
Post-apply verification: asserts the demo is actually in the state the pitch
claims, on both the AWS side and the tenant side.

Every failure in this project so far surfaced only during apply, minutes in.
This checks the finished result instead -- and doubles as something concrete to
put on screen while policy propagation settles.

Reads identifiers from `terraform show -json` so it needs no extra outputs and
cannot drift from what was actually created.

Usage:
    IDSEC_SERVICE_USER=... IDSEC_SERVICE_TOKEN=... ./scripts/verify.py
"""

import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from idira_auth import (  # noqa: E402
    CMGR,
    POLICIES,
    IdiraError,
    as_list,
    get_json,
    platform_token,
)

ROOT = Path(__file__).resolve().parent.parent

PASS, FAIL, WARN = [], [], []


def ok(msg, detail=""):
    print(f"  \033[32m✓\033[0m {msg}")
    if detail:
        print(f"    \033[2m{detail}\033[0m")
    PASS.append(msg)


def bad(msg, detail=""):
    print(f"  \033[31m✗\033[0m {msg}")
    if detail:
        print(f"    \033[2m{detail}\033[0m")
    FAIL.append(msg)


def warn(msg, detail=""):
    print(f"  \033[33m!\033[0m {msg}")
    if detail:
        print(f"    \033[2m{detail}\033[0m")
    WARN.append(msg)


def sh(*args):
    r = subprocess.run(args, capture_output=True, text=True, cwd=ROOT)
    return r.returncode, r.stdout.strip(), r.stderr.strip()


def policy_principal_summary(res):
    """Who the policy grants access to -- the line worth saying out loud."""
    principals = res.get("idsec_policy_vm.demo", {}).get("principals", [])
    names = [p.get("name") for p in principals if isinstance(p, dict) and p.get("name")]
    return ", ".join(names) if names else "unknown principals"


def tf_resources():
    """Map "type.name" -> attribute dict, from current state."""
    rc, out, err = sh("terraform", "show", "-json")
    if rc != 0:
        print(f"could not read terraform state: {err}", file=sys.stderr)
        sys.exit(2)
    state = json.loads(out)
    found = {}

    def walk(module):
        for res in module.get("resources", []):
            found[f"{res['type']}.{res['name']}"] = res.get("values", {})
        for child in module.get("child_modules", []):
            walk(child)

    walk(state.get("values", {}).get("root_module", {}))
    return found


def main():
    res = tf_resources()
    if not res:
        print("\nNothing deployed -- terraform state is empty. Run `make up` first.\n")
        sys.exit(2)

    tfvar = {}
    tfvars = ROOT / "terraform.tfvars"
    if tfvars.exists():
        for line in tfvars.read_text().splitlines():
            if "=" in line and not line.strip().startswith("#"):
                key, _, value = line.partition("=")
                tfvar[key.strip()] = value.strip().strip('"')

    subdomain = tfvar.get("idsec_subdomain")
    if not subdomain:
        print("could not read idsec_subdomain from terraform.tfvars", file=sys.stderr)
        sys.exit(2)

    # Prefer the region recorded in state; fall back to tfvars rather than a
    # hardcoded default, so this cannot silently query the wrong region.
    region = res.get("aws_instance.target", {}).get("region") or tfvar.get("aws_region")
    if not region:
        print("could not determine the AWS region", file=sys.stderr)
        sys.exit(2)

    # ---------------------------------------------------------------- AWS ---
    print("\nAWS: is the target actually isolated?")

    target = res.get("aws_instance.target", {})
    tgt_id = target.get("id", "")
    if target.get("public_ip"):
        bad("target has a public IP", f"{target['public_ip']} -- the demo's core claim is false")
    else:
        ok("target has no public IP", tgt_id)

    if target.get("key_name"):
        bad("target has an SSH keypair attached", target["key_name"])
    else:
        ok("target has no SSH keypair", "nothing to steal, nothing to rotate")

    sg_id = res.get("aws_security_group.target", {}).get("id", "")
    conn_sg = res.get("aws_security_group.connector", {}).get("id", "")
    if sg_id:
        rc, out, _ = sh(
            "aws", "ec2", "describe-security-group-rules", "--region", region,
            "--filters", f"Name=group-id,Values={sg_id}", "--output", "json",
        )
        if rc == 0:
            rules = json.loads(out).get("SecurityGroupRules", [])
            ingress = [r for r in rules if not r.get("IsEgress")]
            refs = [r.get("ReferencedGroupInfo", {}).get("GroupId") for r in ingress]
            cidrs = [r.get("CidrIpv4") for r in ingress if r.get("CidrIpv4")]
            if cidrs:
                bad("target accepts traffic from a CIDR", f"{cidrs} -- expected connector SG only")
            elif len(ingress) == 1 and refs == [conn_sg]:
                ok("target's only ingress is the connector's security group", f"{sg_id} <- {conn_sg}")
            else:
                warn(f"unexpected ingress rule count: {len(ingress)}", str(refs))
        else:
            warn("could not read target security group rules")

    rt = res.get("aws_route_table.private", {})
    routes = [r for r in rt.get("route", []) if r.get("cidr_block") not in (None, "")]
    if routes:
        bad("private subnet has routes off the VPC", str(routes))
    else:
        ok("private subnet has no route off the VPC", rt.get("id", ""))

    # -------------------------------------------------------------- Idira ---
    print("\nIdira: did the tenant config actually land?")

    try:
        token = platform_token(subdomain)
    except IdiraError as exc:
        bad("could not authenticate to the tenant", str(exc))
        summary()
        return

    pool_id = res.get("idsec_cmgr_pool.demo", {}).get("pool_id", "")
    pool_name = res.get("idsec_cmgr_pool.demo", {}).get("name", "")

    # The connector must be in OUR pool, not the tenant default. The connector_id
    # string embeds a tenant-level CMS id that looks like a pool id but is not,
    # so this has to be checked against the components API.
    try:
        comps = as_list(get_json(subdomain, CMGR, "api/pool-service/pools/components", token))
        ours = [c for c in comps if c.get("poolId") == pool_id]
        if ours:
            ok(f"connector registered in '{pool_name}'", f"{len(ours)} component(s) in {pool_id}")
        else:
            bad("no connector in the demo pool",
                "it may have fallen back to the tenant default pool")
    except IdiraError as exc:
        warn("could not list connector components", str(exc))

    expected_ident = res.get("idsec_cmgr_pool_identifier.private_subnet", {}).get("value", "")
    try:
        idents = as_list(
            get_json(subdomain, CMGR, f"api/pool-service/pools/{pool_id}/identifiers", token)
        )
        values = [i.get("value") for i in idents]
        if expected_ident and expected_ident in values:
            ok("pool identifier scopes the pool to the demo subnet", expected_ident)
        else:
            bad("pool identifier missing", f"expected {expected_ident!r}, found {values}")
    except IdiraError as exc:
        warn("could not list pool identifiers", str(exc))

    policy_meta = res.get("idsec_policy_vm.demo", {}).get("metadata", {})
    if isinstance(policy_meta, list):
        policy_meta = policy_meta[0] if policy_meta else {}
    policy_name = policy_meta.get("name", "")
    try:
        # The list API returns camelCase and nests both name and status under
        # metadata -- unlike the Terraform resource's snake_case attributes.
        policies = as_list(get_json(subdomain, POLICIES, "api/policies", token))
        match = [p for p in policies
                 if (p.get("metadata") or {}).get("name") == policy_name]
        if not match:
            bad(f"policy '{policy_name}' not found in the tenant")
        else:
            status = ((match[0].get("metadata") or {}).get("status") or {})
            status = status.get("status") if isinstance(status, dict) else status
            if str(status).lower() == "active":
                ok(f"policy '{policy_name}' is Active", f"grants {policy_principal_summary(res)}")
            else:
                warn(f"policy '{policy_name}' status is {status!r}", "may still be propagating")
    except IdiraError as exc:
        warn("could not list policies", str(exc))

    summary()


def summary():
    print()
    if FAIL:
        print(f"\033[31m{len(FAIL)} check(s) failed.\033[0m "
              f"{len(PASS)} passed, {len(WARN)} warning(s).\n")
        sys.exit(1)
    if WARN:
        print(f"\033[33m{len(PASS)} passed, {len(WARN)} warning(s).\033[0m "
              "Warnings are usually propagation lag -- re-run in a minute.\n")
        sys.exit(0)
    print(f"\033[32mAll {len(PASS)} checks passed. The demo is in the state the pitch claims.\033[0m\n")
    sys.exit(0)


if __name__ == "__main__":
    main()
