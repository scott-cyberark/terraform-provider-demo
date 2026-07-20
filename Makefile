.DEFAULT_GOAL := help
.PHONY: help preflight init plan up verify access proof down clean fmt validate

# Idira credentials live in a gitignored env file rather than your shell profile,
# so they are scoped to this project. Every target that talks to the tenant
# sources it first -- Make runs each recipe line in its own shell, so this has to
# be prefixed onto the same line as the command that needs it.
#
# Override with: make up ENV_FILE=/path/to/other.env
ENV_FILE ?= idira-demo.env
LOAD_ENV = set -a; if [ -f $(ENV_FILE) ]; then . ./$(ENV_FILE); fi; set +a;

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

preflight: ## Check tooling, AWS creds, Idira creds, and CA reachability
	@$(LOAD_ENV) ./scripts/preflight.sh

init: ## Download providers
	@terraform init -input=false

plan: init ## Show what would be created
	@$(LOAD_ENV) terraform plan

up: preflight init ## Stand up the whole demo (~5 min, most of it the connector install)
	@$(LOAD_ENV) terraform apply -auto-approve
	@echo
	@$(LOAD_ENV) ./scripts/verify.py || true
	@$(LOAD_ENV) terraform output -raw connect

verify: ## Check the deployed demo is in the state the pitch claims
	@$(LOAD_ENV) ./scripts/verify.py

access: ## Print how to connect through SIA
	@$(LOAD_ENV) terraform output -raw connect

proof: ## Print the commands that substantiate the demo's claims
	@$(LOAD_ENV) terraform output -raw proof

down: ## Tear everything down, in AWS and in the tenant
	@$(LOAD_ENV) terraform destroy -auto-approve
	@echo
	@echo "Verify the tenant is clean: the connector, pool, network, and policy"
	@echo "should all be gone. An orphaned connector will trip up the next run."

clean: down ## Tear down and remove local state and generated keys
	@rm -rf keys/ .terraform/ terraform.tfstate*

fmt: ## Format
	@terraform fmt -recursive

validate: init ## Validate against the provider schemas
	@terraform validate
