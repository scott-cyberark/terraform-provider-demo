.DEFAULT_GOAL := help
.PHONY: help preflight init plan up verify access proof down clean fmt validate

# Which cloud to stand the demo up on. Every target runs against the matching
# root directory (aws/ or azure/) via `terraform -chdir`.
#   make up            -> AWS (default)
#   make up CLOUD=azure -> Azure
CLOUD ?= aws

# Idira credentials live in a gitignored env file at the repo root, scoped to
# this project. Each recipe line runs in its own shell, so the source has to be
# prefixed onto the same line as the command that needs it.
ENV_FILE ?= idira-demo.env
LOAD_ENV = set -a; if [ -f $(ENV_FILE) ]; then . ./$(ENV_FILE); fi; set +a;

TF = terraform -chdir=$(CLOUD)

# AWS access (provider + the aws CLI in verify/proof) uses this profile, where
# your SCA-elevated credentials land. Only relevant when CLOUD=aws. Azure auth
# comes from your `az login` session.
ifeq ($(CLOUD),aws)
AWS_PROFILE ?= cyberark_elevated
export AWS_PROFILE
endif

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'
	@printf "\n  Set CLOUD=aws (default) or CLOUD=azure on any target.\n"

check-cloud:
	@case "$(CLOUD)" in aws|azure) ;; *) echo "CLOUD must be 'aws' or 'azure' (got '$(CLOUD)')"; exit 1 ;; esac

# Fail early with guidance if cloud credentials are missing, rather than partway
# through an apply. AWS creds are short-lived (SCA) -- refresh them first.
ensure-creds: check-cloud
	@if [ "$(CLOUD)" = "aws" ]; then \
	  $(LOAD_ENV) aws sts get-caller-identity >/dev/null 2>&1 || { echo "AWS credentials missing/expired. Refresh them (SCA) and retry."; exit 1; }; \
	else \
	  az account show >/dev/null 2>&1 || { echo "Not logged in to Azure. Run 'az login' (and 'az account set --subscription <id>') and retry."; exit 1; }; \
	fi

preflight: check-cloud ## Check tooling, cloud creds, Idira creds, and CA reachability
	@$(LOAD_ENV) CLOUD=$(CLOUD) ./scripts/preflight.sh

init: check-cloud ## Download providers for the selected cloud
	@$(TF) init -input=false

plan: ensure-creds init ## Show what would be created
	@$(LOAD_ENV) $(TF) plan

up: ensure-creds preflight init ## Stand up the whole demo (~5 min, most of it the connector install)
	@$(LOAD_ENV) $(TF) apply -auto-approve
	@echo
	@$(LOAD_ENV) ./scripts/verify.py --cloud $(CLOUD) || true
	@$(LOAD_ENV) $(TF) output -raw connect

verify: check-cloud ## Check the deployed demo is in the state the pitch claims
	@$(LOAD_ENV) ./scripts/verify.py --cloud $(CLOUD)

access: check-cloud ## Print how to connect through SIA
	@$(LOAD_ENV) $(TF) output -raw connect

proof: check-cloud ## Print the commands that substantiate the demo's claims
	@$(LOAD_ENV) $(TF) output -raw proof

down: ensure-creds ## Tear everything down, in the cloud and in the tenant
	@$(LOAD_ENV) $(TF) destroy -auto-approve
	@echo
	@echo "Verify the tenant is clean: the connector, pool, network, and policy"
	@echo "should all be gone. An orphaned connector will trip up the next run."

clean: down ## Tear down and remove local state and generated keys
	@rm -rf $(CLOUD)/keys/ $(CLOUD)/.terraform/ $(CLOUD)/terraform.tfstate*

fmt: ## Format all roots and the shared module
	@terraform fmt -recursive

validate: init ## Validate the selected cloud against the provider schemas
	@$(TF) validate
