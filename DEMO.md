# Run-of-show

About 12 minutes. Rehearse it once end to end before presenting — the connector
install is slow and is the only part that can genuinely fail.

## Before the room joins

```bash
make preflight          # must be all green
export PATH="/opt/homebrew/bin:$PATH"
```

Have two terminals and the Idira portal open. Pin the SSH CA in
`terraform.tfvars` (see README) so nothing depends on a live API call at plan
time.

---

## 1. The premise (1 min, no terminal)

> Every organization has the same gap. Infrastructure is code — reviewed, version
> controlled, reproducible. Access to that infrastructure is a ticket someone
> files afterwards, approved by a human, and forgotten about.
>
> I'm going to build a server that nobody can reach, and grant myself scoped
> access to it, in one command. Then I'll take both away in one command.

Open `idira.tf` and `network.tf` side by side. Same repo, same commit, same
state file.

## 2. Show the intent (2 min)

Walk `network.tf` first — the target's subnet has an empty route table, and its
security group's only inbound rule references the connector's security group,
not a CIDR. Then `target.tf` — no `key_name`, `associate_public_ip_address =
false`.

> There is no SSH key for this box. Not in AWS, not on my laptop. Nobody has one.

Then `idira.tf`:

- `targets.fqdnip_resource.ip_rules` is derived from `aws_instance.target.private_ip`
  — an attribute of the instance being created in the same apply.
- `behavior.ssh_profile.username` is the ephemeral user.
- `conditions` caps the session at 1 hour and 10 idle minutes.

## 3. Apply (4–5 min, keep talking)

```bash
make up
```

While the connector installs, narrate the dependency graph: network → pool →
pool identifier scoped to the AWS subnet ID → connector → policy. Point out that
the pool is identified by the subnet Terraform created moments ago, so the
mapping between "where the workload lives" and "which connectors can reach it"
is derived, not maintained by hand.

Good moment to take questions — you need to burn a little time anyway while the
policy propagates.

## 4. Show the tenant (1 min)

In the Idira portal, while apply finishes or just after:

- Connector Management → the pool, one connector, **Online**
- The pool identifier showing the AWS subnet ID
- Access policies → the new VM policy, **Active**

> None of this was clicked. It came out of the same plan that created the VPC.

## 5. The proof (1 min)

```bash
make proof     # then run the printed commands
```

Three facts on screen: no public IP, one inbound rule referencing the connector's
security group, and a route table with no path off the VPC.

## 6. Connect (2 min) — the payoff

```bash
make access
```

Connect through SIA. You land on the target. Show:

```bash
whoami          # demo_user
hostname -I     # 10.42.2.x
cat /etc/motd
```

Then, the line worth pausing on:

> This account did not exist sixty seconds ago and won't exist in an hour.
> I authenticated with a certificate that's valid for this session only. There is
> no password, no key, and no standing access to revoke — because none was ever
> granted.

If someone asks how the box trusts the certificate: `sudo cat /etc/ssh/sshd_config
| grep TrustedUserCAKeys`. The CA went on at boot via cloud-init; the target has
never had an inbound connection from outside the VPC.

## 7. Tear down (1 min)

```bash
make down
```

> The servers are gone, and so is the entitlement. No orphaned policy granting
> access to an IP that now belongs to someone else's workload. That's the part
> that usually rots.

Refresh the portal to show the connector, pool, and policy are gone.

---

## Questions you should expect

**"Does this work with our existing VPC?"**
Yes — this builds its own for blast-radius reasons. Swap the `aws_vpc` resource
for a data source and pass in subnet IDs.

**"What about Windows?"**
Supported, via RDP. It needs a strong account — a local admin credential in a
Privilege Cloud safe, wired through `idsec_sia_secrets_vm` and
`idsec_sia_workspaces_target_set`. Deliberately left out here to keep the demo to
one prerequisite-free path.

**"Can policies target tags instead of IPs?"**
Yes. `idsec_policy_vm` supports `targets.aws_resource` with regions, VPC IDs,
account IDs, and tag matchers, so a policy can cover every instance tagged
`env=staging` without enumerating hosts. This demo uses an exact IP because it's
verifiable on screen in one line.

**"Who can grant this to themselves?"**
Nobody — the policy's `principals` are declared in code and reviewed like any
other change. This demo grants whichever role you set as `policy_role_name`,
resolved by name at plan time through the `idsec_identity_role` data source
rather than a hardcoded ID. Membership of that role is the complete answer to
"who can reach this box".

**"Is the session recorded?"**
Yes — `idsec_sia_settings_ssh_recording` and `idsec_sia_settings_ssh_command_audit`
are provider-managed too, so audit configuration is code as well.

## If something breaks

| Symptom | Fix |
|---|---|
| Connector install times out | Your public IP changed after apply started. `terraform apply` again; `admin_cidr` re-detects. |
| Connect fails right after apply | Policy propagation lag. Wait ~60s. Do step 4 or 5 in the meantime. |
| "connector already exists" | Orphan from an interrupted destroy. `make down`, confirm the tenant is clean, retry. |
| Preflight can't fetch the CA | Service user is missing the DpaAdmin role. |
