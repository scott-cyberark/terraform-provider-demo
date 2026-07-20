.DEFAULT_GOAL := help
.PHONY: help preflight init plan up access proof down clean fmt validate

help: ## Show this help
	@grep -E '^[a-z-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

preflight: ## Check tooling, AWS creds, Idira creds, and CA reachability
	@./scripts/preflight.sh

init: ## Download providers
	@terraform init -input=false

plan: init ## Show what would be created
	@terraform plan

up: preflight init ## Stand up the whole demo (~5 min, most of it the connector install)
	@terraform apply -auto-approve
	@echo
	@terraform output -raw connect

access: ## Print how to connect through SIA
	@terraform output -raw connect

proof: ## Print the commands that substantiate the demo's claims
	@terraform output -raw proof

down: ## Tear everything down, in AWS and in the tenant
	@terraform destroy -auto-approve
	@echo
	@echo "Verify the tenant is clean: the connector, pool, network, and policy"
	@echo "should all be gone. An orphaned connector will trip up the next run."

clean: down ## Tear down and remove local state and generated keys
	@rm -rf keys/ .terraform/ terraform.tfstate*

fmt: ## Format
	@terraform fmt -recursive

validate: init ## Validate against the provider schemas
	@terraform validate
