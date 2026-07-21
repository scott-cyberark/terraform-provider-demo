# Idira SIA — Terraform Provider Demo

A self-contained demo of the [`cyberark/idsec`](https://registry.terraform.io/providers/cyberark/idsec/latest/docs)
Terraform provider, on **AWS or Azure**. One `make up` builds a cloud network,
installs a Secure Infrastructure Access connector, launches a target server, and
creates the Idira access policy that governs it. One `make down` removes all of
it, from both the cloud and the tenant.

The point it makes to a customer: **identity controls ship in the same commit,
the same state file, and the same pipeline as the infrastructure they protect.**

```bash
make up               # AWS (default)
make up CLOUD=azure   # Azure
```

## Layout

The two clouds are separate Terraform roots that share one module for all the
Idira/tenant wiring, so a tenant-side fix is made once:

```
modules/idira/   connector-mgmt network/pool/identifier, connector install, VM policy
aws/             VPC, EC2 connector + target, calls modules/idira with AWS facts
azure/           VNet, VM connector + target, calls modules/idira with Azure facts
scripts/         shared: SSH-CA fetch, tenant auth, preflight, verify
```

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

The target server has no public IP, no route off the network, and no usable SSH
key (on AWS it has none; on Azure a generated admin key is discarded at apply).
The only way in is on 22 from the connector, on a certificate SIA signs per
session. The diagram shows AWS; Azure is the same shape (VNet, NSGs, private
subnet with no egress).

## Idira resources used (shared module)

| Resource | Role in the demo |
|---|---|
| `idsec_cmgr_network` | Logical network the pool belongs to |
| `idsec_cmgr_pool` | Connector pool |
| `idsec_cmgr_pool_identifier` | Scopes the pool to the subnet (`AWS_SUBNET` / `AZURE_SUBNET`) |
| `idsec_sia_access_connector` | Installs the connector onto the connector host over SSH |
| `idsec_policy_vm` | Grants SSH to the target (matched by cloud attrs + tag, or private IP), via a short-lived certificate |

All live in [modules/idira/main.tf](modules/idira/main.tf); each root supplies the
cloud-specific values.

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

3. **Cloud credentials** for an account/subscription you can build a throwaway
   network in:
   - **AWS** — short-lived (SCA-elevated) creds in the `cyberark_elevated`
     profile. Refresh them immediately before presenting; an expiry mid-apply
     strands a half-registered connector.
   - **Azure** — `az login`, then `az account set --subscription <id>`.

4. **Config** (per cloud — each root has its own tfvars):
   ```bash
   cp aws/terraform.tfvars.example   aws/terraform.tfvars      # set idsec_subdomain + policy_role_name
   cp azure/terraform.tfvars.example azure/terraform.tfvars    # (only if using Azure)
   make preflight                # AWS
   make preflight CLOUD=azure    # Azure
   ```

`make preflight` authenticates end to end and retrieves the SSH CA. If it
passes, the apply will work.

## Running it

Add `CLOUD=azure` to any target for Azure (default is AWS):

```bash
make up       # ~5 min, mostly the connector install
make access   # how to connect
make proof    # commands that substantiate the claims, to run on screen
make verify   # assert the deployed demo matches the pitch
make down     # tear down the cloud + tenant config
```

See [DEMO.md](DEMO.md) for the run-of-show.

### Azure notes

- Auth is `az login`; the region defaults to `eastus` (`azure_location`).
- Policy targeting defaults to `fqdnip` (match the private IP) because Azure
  cloud discovery for VM policies is unverified in this tenant. Set
  `policy_target_mode = "azure"` once the subscription is confirmed onboarded.
- Two Azure identifier value formats are best-effort guesses until a first live
  run confirms them — the `AZURE_SUBNET` pool-identifier value and the policy's
  `vnet_ids`. Both are flagged in [azure/idira.tf](azure/idira.tf); if an apply
  returns a 400 on the identifier, that is the value to adjust.

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
