SHELL := /bin/bash
.DEFAULT_GOAL := help

ENV_FILE := .env
CONTRACTS_ROOT := contracts
DEPLOY_SCRIPT := script/DeployTreasuryOS.s.sol:DeployTreasuryOS
LOCAL_DEPLOY_SCRIPT := script/DeployLocalTreasuryOS.s.sol:DeployLocalTreasuryOS
BLOCKSCOUT_API := https://api.explorer.test.mezo.org/api/
ANVIL_RPC_URL ?= http://127.0.0.1:8545

.PHONY: help
help:
	@echo "Mezo TreasuryOS commands:"
	@echo "  make build                        - compile contracts"
	@echo "  make test                         - run contract tests"
	@echo "  make coverage                     - run contract coverage"
	@echo "  make coverage-report              - run contract coverage with lcov output"
	@echo "  make fmt                          - format contracts"
	@echo "  make clean                        - clean Foundry artifacts"
	@echo "  make anvil                        - start local Anvil node"
	@echo "  make deploy-anvil                 - deploy simplified local TreasuryOS stack"
	@echo "  make check-env                    - verify required Mezo testnet env vars are set"
	@echo "  make deploy-mezo-testnet          - deploy TreasuryOS stack to Mezo testnet"
	@echo "  make deploy-mezo-testnet-verify   - deploy and verify on Mezo testnet Blockscout"
	@echo "  make verify-mezo-testnet-resume   - resume verification for the latest deployment"

.PHONY: build
build:
	forge build --root $(CONTRACTS_ROOT)

.PHONY: test
test:
	forge test --root $(CONTRACTS_ROOT) --offline

.PHONY: coverage
coverage:
	forge coverage --root $(CONTRACTS_ROOT) --offline

.PHONY: coverage-report
coverage-report:
	forge coverage --root $(CONTRACTS_ROOT) --offline --report lcov

.PHONY: fmt
fmt:
	forge fmt --root $(CONTRACTS_ROOT)

.PHONY: clean
clean:
	forge clean --root $(CONTRACTS_ROOT)

.PHONY: anvil
anvil:
	anvil

.PHONY: deploy-anvil
deploy-anvil:
	@forge script $(LOCAL_DEPLOY_SCRIPT) \
		--root $(CONTRACTS_ROOT) \
		--rpc-url "$(ANVIL_RPC_URL)" \
		--broadcast \
		-vvvv

define require_env_file
	@if [ ! -s "$(ENV_FILE)" ]; then \
		echo "Missing or empty $(ENV_FILE). Fill it from .env.example first."; \
		exit 1; \
	fi
endef

define load_env
	set -a && source "$(ENV_FILE)" && set +a;
endef

define require_testnet_env
	[ -n "$$MEZO_RPC_URL" ] || { echo "Missing MEZO_RPC_URL"; exit 1; }; \
	[ -n "$$DEPLOYER_PRIVATE_KEY" ] || { echo "Missing DEPLOYER_PRIVATE_KEY"; exit 1; }; \
	[ -n "$$TREASURY_OWNER" ] || { echo "Missing TREASURY_OWNER"; exit 1; }; \
	[ -n "$$TREASURY_OWNER_PRIVATE_KEY" ] || { echo "Missing TREASURY_OWNER_PRIVATE_KEY"; exit 1; }; \
	[ -n "$$TREASURY_APPROVER" ] || { echo "Missing TREASURY_APPROVER"; exit 1; }; \
	[ -n "$$TREASURY_OPERATOR" ] || { echo "Missing TREASURY_OPERATOR"; exit 1; }; \
	[ -n "$$MEZO_MUSD_TOKEN" ] || { echo "Missing MEZO_MUSD_TOKEN"; exit 1; }; \
	[ -n "$$MEZO_BORROWER_OPERATIONS" ] || { echo "Missing MEZO_BORROWER_OPERATIONS"; exit 1; };
endef

.PHONY: check-env
check-env:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		echo "Required TreasuryOS Mezo testnet env vars are set."; \
		if [ -n "$$MEZO_MUSDC_TOKEN" ]; then echo "MEZO_MUSDC_TOKEN=SET"; else echo "MEZO_MUSDC_TOKEN=MISSING (Tigris handler will be skipped)"; fi; \
		if [ -n "$$MEZO_MUSD_SAVINGS_RATE" ]; then echo "MEZO_MUSD_SAVINGS_RATE=SET"; else echo "MEZO_MUSD_SAVINGS_RATE=MISSING (external savings mock path expected)"; fi; \
	'

.PHONY: deploy-mezo-testnet
deploy-mezo-testnet:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		forge script $(DEPLOY_SCRIPT) \
			--root $(CONTRACTS_ROOT) \
			--rpc-url "$$MEZO_RPC_URL" \
			--broadcast \
			-vvvv \
	'

.PHONY: deploy-mezo-testnet-verify
deploy-mezo-testnet-verify:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		forge script $(DEPLOY_SCRIPT) \
			--root $(CONTRACTS_ROOT) \
			--rpc-url "$$MEZO_RPC_URL" \
			--broadcast \
			--verify \
			--verifier blockscout \
			--verifier-url "$(BLOCKSCOUT_API)" \
			-vvvv \
	'

.PHONY: verify-mezo-testnet-resume
verify-mezo-testnet-resume:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		forge script $(DEPLOY_SCRIPT) \
			--root $(CONTRACTS_ROOT) \
			--rpc-url "$$MEZO_RPC_URL" \
			--resume \
			--verify \
			--verifier blockscout \
			--verifier-url "$(BLOCKSCOUT_API)" \
			-vvvv \
	'
