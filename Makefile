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
	@echo "  make deploy-mezo-testnet-eoa      - deploy verified stack with EOA Treasury Account owner"
	@echo "  make deploy-mezo-testnet-multisig - deploy verified stack with 1-of-1 TreasuryMultisig owner"
	@echo "  make deploy-mezo-testnet-2of3     - deploy verified stack with 2-of-3 TreasuryMultisig owner"
	@echo "  make deploy-mezo-testnet-external - deploy verified stack for external multisig/custody owner"
	@echo "  make multisig-confirm-batch-mezo  - confirm a pending TreasuryMultisig setup batch"
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
	if [ "$${DEPLOY_TREASURY_MULTISIG:-false}" = "true" ]; then \
		[ -n "$$TREASURY_MULTISIG_OWNER_1" ] || { echo "Missing TREASURY_MULTISIG_OWNER_1"; exit 1; }; \
		if [ "$${PROPOSE_TREASURY_MULTISIG_SETUP:-true}" != "false" ]; then \
			[ -n "$${TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY:-$$DEPLOYER_PRIVATE_KEY}" ] || { echo "Missing TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY or DEPLOYER_PRIVATE_KEY"; exit 1; }; \
		fi; \
	else \
		[ -n "$$TREASURY_OWNER" ] || { echo "Missing TREASURY_OWNER"; exit 1; }; \
		if [ "$${EXECUTE_OWNER_CONTROLLED_SETUP:-true}" != "false" ]; then \
			if [ -z "$$TREASURY_OWNER_PRIVATE_KEY" ]; then echo "TREASURY_OWNER_PRIVATE_KEY not set; deploy script can only continue if TREASURY_OWNER is the deployer."; fi; \
		fi; \
	fi; \
	[ -n "$$TREASURY_APPROVER" ] || { echo "Missing TREASURY_APPROVER"; exit 1; }; \
	[ -n "$$TREASURY_OPERATOR" ] || { echo "Missing TREASURY_OPERATOR"; exit 1; }; \
	[ -n "$$MEZO_MUSD_TOKEN" ] || { echo "Missing MEZO_MUSD_TOKEN"; exit 1; }; \
	[ -n "$$MEZO_BORROWER_OPERATIONS" ] || { echo "Missing MEZO_BORROWER_OPERATIONS"; exit 1; };
endef

define forge_deploy_testnet_verified
	forge script $(DEPLOY_SCRIPT) \
		--root $(CONTRACTS_ROOT) \
		--rpc-url "$$MEZO_RPC_URL" \
		--broadcast \
		--verify \
		--verifier blockscout \
		--verifier-url "$(BLOCKSCOUT_API)" \
		-vvvv
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
		$(call forge_deploy_testnet_verified) \
	'

.PHONY: deploy-mezo-testnet-eoa deploy-mezo-testnet-eos
deploy-mezo-testnet-eoa:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		export DEPLOY_TREASURY_MULTISIG=false; \
		export EXECUTE_OWNER_CONTROLLED_SETUP=true; \
		$(call require_testnet_env) \
		[ -n "$$TREASURY_OWNER_PRIVATE_KEY" ] || { echo "Missing TREASURY_OWNER_PRIVATE_KEY for EOA setup execution"; exit 1; }; \
		$(call forge_deploy_testnet_verified) \
	'

deploy-mezo-testnet-eos: deploy-mezo-testnet-eoa

.PHONY: deploy-mezo-testnet-multisig
deploy-mezo-testnet-multisig:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		if [ -z "$$TREASURY_MULTISIG_OWNER_1" ] && [ -n "$$TREASURY_OWNER" ]; then export TREASURY_MULTISIG_OWNER_1="$$TREASURY_OWNER"; fi; \
		if [ -z "$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] && [ -n "$$TREASURY_OWNER_PRIVATE_KEY" ]; then export TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY="$$TREASURY_OWNER_PRIVATE_KEY"; fi; \
		export DEPLOY_TREASURY_MULTISIG=true; \
		export TREASURY_MULTISIG_THRESHOLD=1; \
		unset TREASURY_MULTISIG_OWNER_2 TREASURY_MULTISIG_OWNER_3 TREASURY_MULTISIG_OWNER_4 TREASURY_MULTISIG_OWNER_5; \
		export PROPOSE_TREASURY_MULTISIG_SETUP=true; \
		[ -n "$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] || { echo "Missing TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY or TREASURY_OWNER_PRIVATE_KEY"; exit 1; }; \
		$(call require_testnet_env) \
		$(call forge_deploy_testnet_verified) \
	'

.PHONY: deploy-mezo-testnet-2of3
deploy-mezo-testnet-2of3:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		if [ -z "$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] && [ -n "$$TREASURY_OWNER_PRIVATE_KEY" ]; then export TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY="$$TREASURY_OWNER_PRIVATE_KEY"; fi; \
		export DEPLOY_TREASURY_MULTISIG=true; \
		export TREASURY_MULTISIG_THRESHOLD=2; \
		unset TREASURY_MULTISIG_OWNER_4 TREASURY_MULTISIG_OWNER_5; \
		export PROPOSE_TREASURY_MULTISIG_SETUP=true; \
		[ -n "$$TREASURY_MULTISIG_OWNER_1" ] || { echo "Missing TREASURY_MULTISIG_OWNER_1"; exit 1; }; \
		[ -n "$$TREASURY_MULTISIG_OWNER_2" ] || { echo "Missing TREASURY_MULTISIG_OWNER_2"; exit 1; }; \
		[ -n "$$TREASURY_MULTISIG_OWNER_3" ] || { echo "Missing TREASURY_MULTISIG_OWNER_3"; exit 1; }; \
		[ -n "$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] || { echo "Missing TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY or TREASURY_OWNER_PRIVATE_KEY"; exit 1; }; \
		$(call require_testnet_env) \
		$(call forge_deploy_testnet_verified) \
	'

.PHONY: deploy-mezo-testnet-external
deploy-mezo-testnet-external:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		export DEPLOY_TREASURY_MULTISIG=false; \
		export EXECUTE_OWNER_CONTROLLED_SETUP=false; \
		$(call require_testnet_env) \
		$(call forge_deploy_testnet_verified) \
	'

.PHONY: multisig-confirm-batch-mezo
multisig-confirm-batch-mezo:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		MULTISIG_ADDRESS="$${TREASURY_MULTISIG_ADDRESS:-$(MULTISIG_ADDRESS)}"; \
		BATCH_ID_VALUE="$${BATCH_ID:-$(BATCH_ID)}"; \
		SIGNER_KEY="$${SIGNER_PRIVATE_KEY:-$(SIGNER_PRIVATE_KEY)}"; \
		[ -n "$$MEZO_RPC_URL" ] || { echo "Missing MEZO_RPC_URL"; exit 1; }; \
		[ -n "$$MULTISIG_ADDRESS" ] || { echo "Missing TREASURY_MULTISIG_ADDRESS or MULTISIG_ADDRESS=<address>"; exit 1; }; \
		[ -n "$$BATCH_ID_VALUE" ] || { echo "Missing BATCH_ID=<id>"; exit 1; }; \
		[ -n "$$SIGNER_KEY" ] || { echo "Missing SIGNER_PRIVATE_KEY=<private key>"; exit 1; }; \
		cast send "$$MULTISIG_ADDRESS" "confirmBatchTransaction(uint256)" "$$BATCH_ID_VALUE" \
			--private-key "$$SIGNER_KEY" \
			--rpc-url "$$MEZO_RPC_URL" \
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
