#!/usr/bin/env bash
#
# Checks every prerequisite before you stand in front of a customer.
# Run this first. It is much cheaper to fail here than three minutes into an apply.

set -uo pipefail

cd "$(dirname "$0")/.." || exit 1

# Which cloud root we are checking (aws|azure).
CLOUD="${CLOUD:-aws}"

# Load credentials the same way the Makefile does, so running this script
# directly behaves identically to `make preflight`. Anything already exported in
# the environment wins over the file.
ENV_FILE="${ENV_FILE:-idira-demo.env}"
if [ -f "$ENV_FILE" ]; then
  _pre_user="${IDSEC_SERVICE_USER:-}"
  _pre_token="${IDSEC_SERVICE_TOKEN:-}"
  set -a
  # shellcheck disable=SC1090
  . "./$ENV_FILE"
  set +a
  [ -n "$_pre_user" ] && export IDSEC_SERVICE_USER="$_pre_user"
  [ -n "$_pre_token" ] && export IDSEC_SERVICE_TOKEN="$_pre_token"
fi

PASS=0
FAIL=0

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; PASS=$((PASS + 1)); }
bad()  { printf '  \033[31m✗\033[0m %s\n' "$1"; FAIL=$((FAIL + 1)); }
note() { printf '    \033[2m%s\033[0m\n' "$1"; }

echo
echo "Tooling"
if command -v terraform >/dev/null 2>&1; then
  ok "terraform $(terraform version -json 2>/dev/null | python3 -c 'import json,sys;print(json.load(sys.stdin)["terraform_version"])' 2>/dev/null || echo present)"
else
  bad "terraform not on PATH"
  note "brew install terraform"
fi

command -v python3 >/dev/null 2>&1 && ok "python3" || bad "python3 not on PATH"

echo
echo "Cloud: $CLOUD"
if [ "$CLOUD" = "azure" ]; then
  if ! command -v az >/dev/null 2>&1; then
    bad "az CLI not on PATH"
    note "brew install azure-cli"
  else
    ACCT=$(az account show --output json 2>&1)
    if [ $? -eq 0 ]; then
      ok "Azure logged in: $(echo "$ACCT" | python3 -c 'import json,sys;d=json.load(sys.stdin);print(d["name"],"("+d["id"]+")")' 2>/dev/null)"
      # The demo needs these resource providers registered on the subscription.
      # Terraform's auto-registration is disabled (a restricted account can't do it),
      # so check here and point at the one-time fix.
      for RP in Microsoft.Network Microsoft.Compute; do
        STATE=$(az provider show -n "$RP" --query registrationState -o tsv 2>/dev/null)
        if [ "$STATE" = "Registered" ]; then
          ok "$RP registered"
        else
          bad "$RP not registered (state: ${STATE:-unknown})"
          note "az provider register --namespace $RP --wait"
        fi
      done
    else
      bad "not logged in to Azure"
      note "az login   (then: az account set --subscription <id>)"
    fi
  fi
else
  CALLER=$(aws sts get-caller-identity --output json 2>&1)
  if [ $? -eq 0 ]; then
    ok "AWS credentials valid for $(echo "$CALLER" | python3 -c 'import json,sys;print(json.load(sys.stdin)["Arn"])')"
    ok "AWS profile: ${AWS_PROFILE:-default}"
  else
    bad "aws sts get-caller-identity failed (profile ${AWS_PROFILE:-default})"
    note "$(echo "$CALLER" | head -1)"
    note "refresh your SCA-elevated credentials"
  fi
fi

echo
echo "Idira"
if [ -f "$ENV_FILE" ]; then
  ok "credentials file: $ENV_FILE"
else
  bad "no credentials file at $ENV_FILE"
  note "cp idira-demo.env.example $ENV_FILE, then fill it in"
  note "quote the values -- service tokens often contain shell metacharacters"
fi
if [ -n "${IDSEC_SERVICE_USER:-}" ]; then ok "IDSEC_SERVICE_USER set"; else bad "IDSEC_SERVICE_USER not set"; fi
if [ -n "${IDSEC_SERVICE_TOKEN:-}" ]; then ok "IDSEC_SERVICE_TOKEN set"; else bad "IDSEC_SERVICE_TOKEN not set"; fi

SUBDOMAIN=""
TFVARS="$CLOUD/terraform.tfvars"
if [ -f "$TFVARS" ]; then
  SUBDOMAIN=$(grep -E '^\s*idsec_subdomain' "$TFVARS" 2>/dev/null | head -1 | cut -d'"' -f2)
fi

if [ -z "$SUBDOMAIN" ] || [ "$SUBDOMAIN" = "CHANGEME" ]; then
  bad "idsec_subdomain not set in $TFVARS"
  note "cp $CLOUD/terraform.tfvars.example $TFVARS, then fill it in"
else
  ok "tenant subdomain: $SUBDOMAIN"

  # The real end-to-end check: authenticate and pull the SSH CA.
  CA=$(./scripts/get-sia-ssh-ca.py "$SUBDOMAIN" 2>&1)
  if [ $? -eq 0 ]; then
    KEY=$(echo "$CA" | python3 -c 'import json,sys;print(json.load(sys.stdin)["public_key"])' 2>/dev/null)
    ok "SIA SSH CA retrieved (${KEY:0:28}...)"
  else
    bad "could not retrieve the SIA SSH CA"
    note "$(echo "$CA" | head -3)"
    note "check the service user has the DpaAdmin role"
  fi
fi

echo
echo "Your public IP (must reach the connector on 22 during install)"
MYIP=$(curl -fsS --max-time 10 https://checkip.amazonaws.com 2>/dev/null | tr -d '[:space:]')
if [ -n "$MYIP" ]; then ok "$MYIP"; else bad "could not determine your public IP"; fi

echo
if [ "$FAIL" -eq 0 ]; then
  printf '\033[32mAll %d checks passed. Ready to demo.\033[0m\n\n' "$PASS"
  exit 0
fi
printf '\033[31m%d check(s) failed.\033[0m Fix these before presenting.\n\n' "$FAIL"
exit 1
