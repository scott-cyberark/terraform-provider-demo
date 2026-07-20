# Idira SIA — Terraform Provider Demo

A self-contained demo of the [`cyberark/idsec`](https://registry.terraform.io/providers/cyberark/idsec/latest/docs)
Terraform provider. One `terraform apply` builds an AWS network, installs a
Secure Infrastructure Access connector, launches a target server, and creates the
Idira access policy that governs it. One `terraform destroy` removes all of it,
from both AWS and the tenant.

The point it makes to a customer: **identity controls ship in the same commit,
the same state file, and the same pipeline as the infrastructure they protect.**

## What gets built

```
                 ┌─────────────────────────────────────────────┐
   you ─────────▶│ Idira tenant                                │
   (SIA client)  │   connector pool ── VM access policy        │
                 └──────────────────┬──────────────────────────┘
                                    │ outbound tunnel
   ┌────────────────────────────────┼────────────────────────────────┐
   │ VPC 10.42.0.0/16               │                                │
   │                                ▼                                │
   │  ┌──────────────────────┐            ┌───────────────────────┐  │
   │  │ public 10.42.1.0/24  │            │ private 10.42.2.0/24  │  │
   │  │                      │  :22 only  │                       │  │
   │  │  SIA connector    ───┼───────────▶│  target server        │  │
   │  │  (public IP, egress) │            │  no public IP         │  │
   │  │                      │            │  no egress, no NAT    │  │
   │  └──────────────────────┘            │  no SSH key anywhere  │  │
   │                                      └───────────────────────┘  │
   └─────────────────────────────────────────────────────────────────┘
```

The target server has no public IP, no route to the internet gateway, no NAT
gateway, and no SSH keypair in AWS or on your laptop. Its security group has
exactly one inbound rule, referencing the connector's security group. You will
still land a shell on it seconds after apply finishes.

## Idira resources used

| Resource | Role in the demo |
|---|---|
| `idsec_cmgr_network` | Logical network the pool belongs to |
| `idsec_cmgr_pool` | Connector pool |
| `idsec_cmgr_pool_identifier` | Scopes the pool to the **AWS subnet ID** Terraform just created |
| `idsec_sia_access_connector` | Installs the connector onto the EC2 host over SSH |
| `idsec_policy_vm` | Grants SSH to the target's private IP, as an ephemeral user |

Files map one-to-one: [network.tf](network.tf), [connector.tf](connector.tf),
[target.tf](target.tf), [idira.tf](idira.tf).

## Before you present

1. **Tooling.** `brew install hashicorp/tap/terraform`. Note that plain
   `brew install terraform` silently does nothing — Terraform lives in
   HashiCorp's tap since the license change.

2. **Idira service user** with the **DpaAdmin** role (required for both the
   connector install and the SSH CA), plus Connector Management rights. The
   service user must also be permitted on the `__idaptive_cybr_user_oidc` OAuth
   app — if it is not, authentication fails with `access_denied` / "client not
   allowed" even though the credentials are correct.

   ```bash
   cp idira-demo.env.example idira-demo.env   # then fill it in
   ```

   Single-quote the values. Service tokens routinely contain `) + < > ?`, and an
   unquoted token fails with a shell parse error that looks nothing like a
   credential problem.

   Service-user auth is used specifically so an MFA prompt cannot interrupt a
   live demo. Every `make` target sources this file, so nothing needs to be
   exported in your shell.

3. **AWS credentials** for an account you are happy to build a throwaway VPC in.
   Note these are typically short-lived assumed-role tokens — refresh them
   immediately before presenting, since an expiry mid-apply strands a
   half-registered connector.

4. **Config:**
   ```bash
   cp terraform.tfvars.example terraform.tfvars   # set idsec_subdomain + policy_role_name
   make preflight
   ```

`make preflight` authenticates end to end and retrieves the SSH CA. If it
passes, the apply will work.

## Running it

```bash
make up       # ~5 min, mostly the connector install
make access   # how to connect
make proof    # commands that substantiate the claims, to run on screen
make down     # tear down AWS + tenant config
```

See [DEMO.md](DEMO.md) for the run-of-show.

## The one design decision worth knowing

The provider ships `idsec_sia_ssh_public_key`, which installs the SSH CA on a
target by **SSHing into it from wherever Terraform runs**. Using it would force
the target to accept inbound SSH from your laptop — which contradicts the entire
premise of the demo.

The same CA is available from the tenant API (`GET /api/public-keys`), so
[`scripts/get-sia-ssh-ca.py`](scripts/get-sia-ssh-ca.py) fetches it once and
[target.tf](target.tf) bakes it into cloud-init. The target is provisioned
without ever being reachable from outside the VPC, and no NAT gateway is needed.

The installed result is identical: same `/etc/ssh/SIA_ssh_public_CA.pub` path,
same `TrustedUserCAKeys` directive, same validate-before-restart guard the SDK's
own script uses.

Before a high-stakes demo, pin the key so the plan makes no live API call:

```bash
./scripts/get-sia-ssh-ca.py "$SUBDOMAIN" \
  | python3 -c 'import json,sys;print(json.load(sys.stdin)["public_key"])'
# paste into terraform.tfvars as sia_ssh_ca_public_key
```

## Cost

Roughly **$0.05/hour** — one `t3.medium` connector and one `t3.micro` target. No
NAT gateway, no load balancer, no elastic IP. A forgotten `make down` is the only
real cost risk.

## Known rough edges

- **The connector install is the slow, fragile step** (3–5 min). `retry_count`
  and `retry_delay` in [connector.tf](connector.tf) absorb the race between the
  EC2 API reporting *running* and sshd actually accepting connections. Rehearse
  at least one full cycle before presenting.
- **Policy propagation is not instant.** Give it a beat after apply before
  connecting — the run-of-show in [DEMO.md](DEMO.md) fills that gap deliberately.
- **Interrupted destroys can orphan a connector** in the tenant. `force_delete`
  is set to make a re-run self-healing, but always confirm the tenant is clean
  after teardown.
- **`admin_cidr` auto-detects your public IP** for the connector install. On a
  VPN with rotating egress, pin it in `terraform.tfvars`.
