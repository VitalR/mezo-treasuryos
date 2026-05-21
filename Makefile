SHELL := /bin/bash
.DEFAULT_GOAL := help

NVM_NODE_BIN := $(dir $(firstword $(wildcard $(HOME)/.nvm/versions/node/v20*/bin/node)))
ifneq ($(strip $(NVM_NODE_BIN)),)
export PATH := $(NVM_NODE_BIN):$(PATH)
endif
NODE_BIN := $(if $(strip $(NVM_NODE_BIN)),$(NVM_NODE_BIN)node,node)

ENV_FILE := .env
CONTRACTS_ROOT := contracts
DEPLOY_SCRIPT := script/DeployTreasuryOS.s.sol:DeployTreasuryOS
CORE_DEPLOY_SCRIPT := script/DeployTreasuryOSCore.s.sol:DeployTreasuryOSCore
CLIENT_ONBOARD_SCRIPT := script/OnboardTreasuryClient.s.sol:OnboardTreasuryClient
BTC_SLEEVE_BROADCAST_SCRIPT := script/ValidateBTCSleeveBroadcast.s.sol:ValidateBTCSleeveBroadcast
LOCAL_DEPLOY_SCRIPT := script/DeployLocalTreasuryOS.s.sol:DeployLocalTreasuryOS
BLOCKSCOUT_API := https://api.explorer.test.mezo.org/api/
ANVIL_RPC_URL ?= http://127.0.0.1:8545

.PHONY: help
help:
	@echo "Mezo TreasuryOS commands:"
	@echo "  make build                        - compile contracts"
	@echo "  make test                         - run contract tests"
	@echo "  make coverage                     - run production contract coverage"
	@echo "  make coverage-all                 - run raw coverage including scripts and test helpers"
	@echo "  make coverage-report              - run production contract coverage with lcov output"
	@echo "  make fmt                          - format contracts"
	@echo "  make clean                        - clean Foundry artifacts"
	@echo "  make rpc-health                   - test Spectrum Mezo RPC candidates and fallback"
	@echo "  make state-probe                  - probe selected Mezo testnet RPC"
	@echo "  make yield-targets                - inspect Mezo yield sleeve targets through selected RPC"
	@echo "  make btc-sleeve-targets           - inspect mcbBTC/BTC BTC sleeve mechanics through selected RPC"
	@echo "  make demo-status                  - print final demo readiness and live validation status"
	@echo "  make scenario-proof               - print live scenario matrix for judge/demo proof"
	@echo "  make predeploy-check              - validate Mezo RPC/env/policy defaults before testnet deploy"
	@echo "  make post-deploy-smoke            - print post-deploy status and keeper proposal readiness"
	@echo "  make mezo-yield-fork-test         - simulate Mezo yield integrations on a live testnet fork"
	@echo "  make btc-sleeve-broadcast-dry-run - simulate tiny guarded mcbBTC/BTC deposit/unwind"
	@echo "  make btc-sleeve-broadcast-validation - broadcast tiny guarded mcbBTC/BTC deposit/unwind"
	@echo "  make yield-console-demo           - render sample Treasury Yield Console"
	@echo "  make term-planner-demo            - render sample 7/30/60-day Term Yield Planner"
	@echo "  make btc-sleeve-plan-demo         - render sample mcbBTC/BTC sleeve preview"
	@echo "  make risk-keeper-demo             - render warning idle-MUSD repayment keeper report"
	@echo "  make risk-keeper-propose          - render keeper calldata/proposal for demo action"
	@echo "  make anvil                        - start local Anvil node"
	@echo "  make deploy-anvil                 - deploy simplified local TreasuryOS stack"
	@echo "  make check-env                    - verify required Mezo testnet env vars are set"
	@echo "  make check-core-env               - verify protocol core deployment env vars"
	@echo "  make check-client-env             - verify client onboarding env vars"
	@echo "  make deploy-mezo-testnet-core     - deploy verified protocol core only"
	@echo "  make onboard-mezo-client-multisig - onboard one client with 1-of-1 TreasuryMultisig"
	@echo "  make onboard-mezo-client-2of3     - onboard one client with 2-of-3 TreasuryMultisig"
	@echo "  make onboard-mezo-client-eoa      - onboard one client with EOA owner"
	@echo "  make onboard-mezo-client-external - onboard one client with external multisig/custody owner"
	@echo "  make deploy-mezo-testnet          - deploy protocol + one client treasury stack to Mezo testnet"
	@echo "  make deploy-mezo-testnet-verify   - deploy protocol + one client treasury stack and verify"
	@echo "  make deploy-mezo-testnet-eoa      - deploy verified stack with client EOA Treasury Account owner"
	@echo "  make deploy-mezo-testnet-multisig - deploy verified stack with client 1-of-1 TreasuryMultisig owner"
	@echo "  make deploy-mezo-testnet-2of3     - deploy verified stack with client 2-of-3 TreasuryMultisig owner"
	@echo "  make deploy-mezo-testnet-external - deploy verified stack for external client multisig/custody owner"
	@echo "  make multisig-confirm-batch-mezo  - confirm a pending TreasuryMultisig setup batch"
	@echo "  make verify-mezo-testnet-deployed - verify current deployed TreasuryOS contracts on Mezo Blockscout"
	@echo "  make verify-mezo-testnet-status   - query Blockscout source status for deployed contracts"
	@echo "  make verify-mezo-testnet-resume   - resume verification for the latest deployment"

.PHONY: build
build:
	forge build --root $(CONTRACTS_ROOT)

.PHONY: test
test:
	forge test --root $(CONTRACTS_ROOT) --offline

.PHONY: coverage
coverage:
	forge coverage --root $(CONTRACTS_ROOT) --offline --no-match-coverage "(script|test)"

.PHONY: coverage-all
coverage-all:
	forge coverage --root $(CONTRACTS_ROOT) --offline

.PHONY: coverage-report
coverage-report:
	forge coverage --root $(CONTRACTS_ROOT) --offline --no-match-coverage "(script|test)" --report lcov

.PHONY: fmt
fmt:
	forge fmt --root $(CONTRACTS_ROOT)

.PHONY: clean
clean:
	forge clean --root $(CONTRACTS_ROOT)

.PHONY: state-probe
state-probe:
	npm run state:probe

.PHONY: yield-targets
yield-targets:
	npm run yield:targets

.PHONY: btc-sleeve-targets
btc-sleeve-targets:
	npm run btc:sleeve-targets

.PHONY: demo-status
demo-status:
	npm run demo:status

.PHONY: scenario-proof
scenario-proof:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(NODE_BIN) services/scenario-proof/run.mjs; \
	'

.PHONY: mezo-yield-fork-test
mezo-yield-fork-test:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		ACTIVE_MEZO_RPC_URL="$${ACTIVE_MEZO_RPC_URL:-$${MEZO_RPC_URL:-}}"; \
		if [ -z "$$ACTIVE_MEZO_RPC_URL" ]; then \
			echo "Missing MEZO_RPC_URL or ACTIVE_MEZO_RPC_URL in .env"; \
			exit 1; \
		fi; \
		echo "Selected Mezo RPC provider: $${ACTIVE_MEZO_RPC_PROVIDER:-MEZO_RPC_URL}"; \
		RUN_MEZO_FORK_TESTS=true ACTIVE_MEZO_RPC_URL="$$ACTIVE_MEZO_RPC_URL" \
			forge test --root $(CONTRACTS_ROOT) --match-path test/fork/MezoYieldTargetsFork.t.sol \
	'

.PHONY: btc-sleeve-broadcast-dry-run
btc-sleeve-broadcast-dry-run:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_mezo_rpc_candidate) \
		$(call select_active_mezo_rpc) \
		cd $(CONTRACTS_ROOT) && BTC_SLEEVE_DRY_RUN=true \
			forge script $(BTC_SLEEVE_BROADCAST_SCRIPT) \
			--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
			-vvvv \
	'

.PHONY: btc-sleeve-broadcast-validation
btc-sleeve-broadcast-validation:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		[ "$${BTC_SLEEVE_BROADCAST_CONFIRM:-false}" = "true" ] || { echo "Set BTC_SLEEVE_BROADCAST_CONFIRM=true in .env for the tiny live BTC sleeve validation."; exit 1; }; \
		$(call require_mezo_rpc_candidate) \
		$(call select_active_mezo_rpc) \
		cd $(CONTRACTS_ROOT) && \
		forge script $(BTC_SLEEVE_BROADCAST_SCRIPT) \
			--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
			--broadcast \
			-vvvv \
	'

.PHONY: rpc-health
rpc-health:
	npm run rpc-health

.PHONY: yield-console-demo
yield-console-demo:
	npm run demo:yield-console

.PHONY: term-planner-demo
term-planner-demo:
	npm run demo:term-planner

.PHONY: btc-sleeve-plan-demo
btc-sleeve-plan-demo:
	npm run demo:btc-sleeve-plan

.PHONY: risk-keeper-demo
risk-keeper-demo:
	npm run risk-keeper:demo

.PHONY: risk-keeper-propose
risk-keeper-propose:
	npm run risk-keeper:propose

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
		echo "Missing or empty $(ENV_FILE). Fill the real .env before running this target."; \
		exit 1; \
	fi
endef

define load_env
	set -a && source "$(ENV_FILE)" && set +a;
endef

define require_mezo_rpc_candidate
	[ -n "$${SPECTRUM_MEZO_RPC_URL_1:-}$${SPECTRUM_MEZO_RPC_URL_2:-}$${SPECTRUM_MEZO_RPC_URL_3:-}$${SPECTRUM_MEZO_RPC_URL:-}$${MEZO_RPC_URL:-}" ] || { echo "Missing a Mezo RPC endpoint. Set SPECTRUM_MEZO_RPC_URL_1/2/3 or MEZO_RPC_URL in .env"; exit 1; };
endef

define select_active_mezo_rpc
	eval "$$($(NODE_BIN) services/spectrum-state/rpc-health.mjs --shell)"; \
	ACTIVE_MEZO_RPC_URL="$${!ACTIVE_MEZO_RPC_ENV}"; \
	[ -n "$$ACTIVE_MEZO_RPC_URL" ] || { echo "Selected Mezo RPC env is empty: $$ACTIVE_MEZO_RPC_ENV"; exit 1; }; \
	export ACTIVE_MEZO_RPC_URL ACTIVE_MEZO_RPC_PROVIDER ACTIVE_MEZO_RPC_ENV ACTIVE_MEZO_RPC_KIND; \
	echo "Selected Mezo RPC provider: $$ACTIVE_MEZO_RPC_PROVIDER ($$ACTIVE_MEZO_RPC_ENV)";
endef

define require_testnet_env
	$(call require_mezo_rpc_candidate) \
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

define require_core_deploy_env
	$(call require_mezo_rpc_candidate) \
	[ -n "$$DEPLOYER_PRIVATE_KEY" ] || { echo "Missing DEPLOYER_PRIVATE_KEY"; exit 1; }; \
	[ -n "$$MEZO_MUSD_TOKEN" ] || { echo "Missing MEZO_MUSD_TOKEN"; exit 1; };
endef

define require_client_onboard_env
	$(call require_mezo_rpc_candidate) \
	[ -n "$$DEPLOYER_PRIVATE_KEY" ] || { echo "Missing DEPLOYER_PRIVATE_KEY"; exit 1; }; \
	[ -n "$$TREASURY_POLICY_ENGINE" ] || { echo "Missing TREASURY_POLICY_ENGINE"; exit 1; }; \
	[ -n "$$TREASURY_ACCOUNT_FACTORY" ] || { echo "Missing TREASURY_ACCOUNT_FACTORY"; exit 1; }; \
	if [ "$${DEPLOY_CLIENT_TREASURY_MULTISIG:-$${DEPLOY_TREASURY_MULTISIG:-true}}" = "true" ]; then \
		[ -n "$${CLIENT_TREASURY_MULTISIG_OWNER_1:-$${TREASURY_MULTISIG_OWNER_1:-}}" ] || { echo "Missing CLIENT_TREASURY_MULTISIG_OWNER_1 or TREASURY_MULTISIG_OWNER_1"; exit 1; }; \
		if [ "$${PROPOSE_CLIENT_TREASURY_MULTISIG_SETUP:-$${PROPOSE_TREASURY_MULTISIG_SETUP:-true}}" != "false" ]; then \
			[ -n "$${CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY:-$${TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY:-}}" ] || { echo "Missing CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY or TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY"; exit 1; }; \
		fi; \
	else \
		[ -n "$${CLIENT_TREASURY_OWNER:-$${TREASURY_OWNER:-}}" ] || { echo "Missing CLIENT_TREASURY_OWNER or TREASURY_OWNER"; exit 1; }; \
		if [ "$${EXECUTE_CLIENT_OWNER_SETUP:-$${EXECUTE_OWNER_CONTROLLED_SETUP:-true}}" != "false" ]; then \
			if [ -z "$${CLIENT_TREASURY_OWNER_PRIVATE_KEY:-$${TREASURY_OWNER_PRIVATE_KEY:-}}" ]; then echo "CLIENT_TREASURY_OWNER_PRIVATE_KEY not set; setup can only continue if client owner is the protocol admin."; fi; \
		fi; \
	fi; \
	[ -n "$$TREASURY_APPROVER" ] || { echo "Missing TREASURY_APPROVER"; exit 1; }; \
	[ -n "$$TREASURY_OPERATOR" ] || { echo "Missing TREASURY_OPERATOR"; exit 1; }; \
	[ -n "$$MEZO_MUSD_TOKEN" ] || { echo "Missing MEZO_MUSD_TOKEN"; exit 1; }; \
	[ -n "$$MEZO_BORROWER_OPERATIONS" ] || { echo "Missing MEZO_BORROWER_OPERATIONS"; exit 1; };
endef

define forge_deploy_testnet_verified
	$(call select_active_mezo_rpc) \
	forge script $(DEPLOY_SCRIPT) \
		--root $(CONTRACTS_ROOT) \
		--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
		--broadcast \
		--slow \
		--verify \
		--verifier blockscout \
		--verifier-url "$${BLOCKSCOUT_API:-$(BLOCKSCOUT_API)}" \
		-vvvv
endef

define forge_deploy_core_verified
	$(call select_active_mezo_rpc) \
	forge script $(CORE_DEPLOY_SCRIPT) \
		--root $(CONTRACTS_ROOT) \
		--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
		--broadcast \
		--slow \
		--verify \
		--verifier blockscout \
		--verifier-url "$${BLOCKSCOUT_API:-$(BLOCKSCOUT_API)}" \
		-vvvv
endef

define forge_onboard_client_verified
	$(call select_active_mezo_rpc) \
	forge script $(CLIENT_ONBOARD_SCRIPT) \
		--root $(CONTRACTS_ROOT) \
		--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
		--broadcast \
		--slow \
		--verify \
		--verifier blockscout \
		--verifier-url "$${BLOCKSCOUT_API:-$(BLOCKSCOUT_API)}" \
		-vvvv
endef

.PHONY: check-env
check-env:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		echo "Required TreasuryOS Mezo testnet env vars are set."; \
		if [ -n "$$MEZO_MUSDC_TOKEN" ]; then echo "MEZO_MUSDC_TOKEN=SET"; else echo "MEZO_MUSDC_TOKEN=MISSING (Tigris handler will be skipped)"; fi; \
		if [ -n "$$MEZO_MUSD_SAVINGS_RATE" ]; then echo "MEZO_MUSD_SAVINGS_RATE=SET"; else echo "MEZO_MUSD_SAVINGS_RATE=MISSING (MUSD Savings handler will be skipped; set the real Mezo testnet vault for final demo)"; fi; \
	'

.PHONY: check-core-env
check-core-env:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_core_deploy_env) \
		echo "Required TreasuryOS protocol core env vars are set."; \
	'

.PHONY: check-client-env
check-client-env:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_client_onboard_env) \
		echo "Required TreasuryOS client onboarding env vars are set."; \
		if [ -n "$$MEZO_MUSDC_TOKEN" ]; then echo "MEZO_MUSDC_TOKEN=SET"; else echo "MEZO_MUSDC_TOKEN=MISSING (Tigris handler will be skipped)"; fi; \
		if [ -n "$$MEZO_MUSD_SAVINGS_RATE" ]; then echo "MEZO_MUSD_SAVINGS_RATE=SET"; else echo "MEZO_MUSD_SAVINGS_RATE=MISSING (MUSD Savings handler will be skipped; set the real Mezo testnet vault for final demo)"; fi; \
	'

.PHONY: predeploy-check
predeploy-check:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		$(call select_active_mezo_rpc) \
		DEPLOYER_ADDRESS="$$(cast wallet address --private-key "$$DEPLOYER_PRIVATE_KEY")"; \
		DEPLOYER_BALANCE="$$(cast balance "$$DEPLOYER_ADDRESS" --rpc-url "$$ACTIVE_MEZO_RPC_URL")"; \
		echo "Deployer: $$DEPLOYER_ADDRESS"; \
		echo "Deployer native BTC balance: $$DEPLOYER_BALANCE wei"; \
		[ "$$DEPLOYER_BALANCE" != "0" ] || { echo "Deployer has zero native BTC for gas"; exit 1; }; \
		MIN_OPEN="$${DEMO_TREASURY_MIN_OPEN_COLLATERAL_RATIO_BPS:-18000}"; \
		TARGET="$${DEMO_TREASURY_TARGET_COLLATERAL_RATIO_BPS:-20000}"; \
		STRESS="$${DEMO_TREASURY_STRESS_DROP_BPS:-2500}"; \
		POST="$${DEMO_TREASURY_MIN_POST_STRESS_COLLATERAL_RATIO_BPS:-14000}"; \
		MAX_TOP_UP="$${DEMO_TREASURY_MAX_AUTO_IDLE_BTC_TOP_UP:-250000000000000000}"; \
		[ "$$TARGET" -ge "$$MIN_OPEN" ] || { echo "Invalid policy: target CR below min open CR"; exit 1; }; \
		[ "$$STRESS" -le 10000 ] || { echo "Invalid policy: stress drop above 10000 bps"; exit 1; }; \
		[ "$$POST" -gt 0 ] || { echo "Invalid policy: min post-stress CR is zero"; exit 1; }; \
		echo "Policy defaults: minOpen=$$MIN_OPEN target=$$TARGET stressDrop=$$STRESS minPostStress=$$POST maxAutoIdleBTCTopUp=$$MAX_TOP_UP"; \
		if [ "$${RISK_KEEPER_MODE:-dry-run}" = "execute" ] || [ -n "$${RISK_KEEPER_PRIVATE_KEY:-}" ]; then \
			[ -n "$${RISK_KEEPER_TREASURY_ACCOUNT:-$${TREASURY_ACCOUNT:-}}" ] || { echo "Keeper configured but missing RISK_KEEPER_TREASURY_ACCOUNT/TREASURY_ACCOUNT"; exit 1; }; \
			[ -n "$${TREASURY_AUTOMATION_EXECUTOR:-$${RISK_KEEPER_AUTOMATION_EXECUTOR:-}}" ] || { echo "Keeper configured but missing TREASURY_AUTOMATION_EXECUTOR/RISK_KEEPER_AUTOMATION_EXECUTOR"; exit 1; }; \
			[ "$${RISK_KEEPER_MAX_ACTIONS_PER_RUN:-1}" = "1" ] || { echo "Keeper max actions must be 1"; exit 1; }; \
			if [ "$${RISK_KEEPER_MODE:-dry-run}" = "execute" ]; then [ "$${RISK_KEEPER_EXECUTE_CONFIRM:-false}" = "true" ] || { echo "Execute mode requires RISK_KEEPER_EXECUTE_CONFIRM=true"; exit 1; }; fi; \
			echo "Keeper env: complete for configured mode $${RISK_KEEPER_MODE:-dry-run}"; \
		else \
			echo "Keeper env: dry-run/propose only"; \
		fi; \
		if [ "$${BTC_SLEEVE_BROADCAST_CONFIRM:-false}" = "true" ]; then \
			[ -n "$${BTC_SLEEVE_TREASURY_ACCOUNT:-}" ] || { echo "BTC sleeve validation enabled but missing BTC_SLEEVE_TREASURY_ACCOUNT"; exit 1; }; \
			[ -n "$${BTC_SLEEVE_VALIDATOR_PRIVATE_KEY:-}" ] || { echo "BTC sleeve validation enabled but missing BTC_SLEEVE_VALIDATOR_PRIVATE_KEY"; exit 1; }; \
			echo "BTC sleeve validation env: complete for guarded tiny broadcast"; \
		else \
			echo "BTC sleeve validation env: disabled or dry-run only"; \
		fi; \
		echo "Fee contracts: deployed by core/full scripts, disabled by default, not wired into treasury execution."; \
	'

.PHONY: post-deploy-smoke
post-deploy-smoke:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_mezo_rpc_candidate) \
		$(call select_active_mezo_rpc) \
		$(NODE_BIN) services/spectrum-state/demo-status.mjs; \
		echo ""; \
		RISK_KEEPER_MODE=propose $(NODE_BIN) services/treasury-risk-keeper/run.mjs services/treasury-risk-keeper/sample-warning-repay-snapshot.json; \
	'

.PHONY: deploy-mezo-testnet
deploy-mezo-testnet:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		$(call select_active_mezo_rpc) \
		forge script $(DEPLOY_SCRIPT) \
			--root $(CONTRACTS_ROOT) \
			--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
			--broadcast \
			-vvvv \
	'

.PHONY: deploy-mezo-testnet-core
deploy-mezo-testnet-core:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_core_deploy_env) \
		$(call forge_deploy_core_verified) \
	'

.PHONY: onboard-mezo-client-multisig
onboard-mezo-client-multisig:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		if [ -z "$$CLIENT_TREASURY_MULTISIG_OWNER_1" ] && [ -n "$$TREASURY_MULTISIG_OWNER_1" ]; then export CLIENT_TREASURY_MULTISIG_OWNER_1="$$TREASURY_MULTISIG_OWNER_1"; fi; \
		if [ -z "$$CLIENT_TREASURY_MULTISIG_OWNER_1" ] && [ -n "$$TREASURY_OWNER" ]; then export CLIENT_TREASURY_MULTISIG_OWNER_1="$$TREASURY_OWNER"; fi; \
		if [ -z "$$CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] && [ -n "$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ]; then export CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY="$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY"; fi; \
		if [ -z "$$CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] && [ -n "$$TREASURY_OWNER_PRIVATE_KEY" ]; then export CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY="$$TREASURY_OWNER_PRIVATE_KEY"; fi; \
		export DEPLOY_CLIENT_TREASURY_MULTISIG=true; \
		export CLIENT_TREASURY_MULTISIG_THRESHOLD=1; \
		unset CLIENT_TREASURY_MULTISIG_OWNER_2 CLIENT_TREASURY_MULTISIG_OWNER_3 CLIENT_TREASURY_MULTISIG_OWNER_4 CLIENT_TREASURY_MULTISIG_OWNER_5; \
		export PROPOSE_CLIENT_TREASURY_MULTISIG_SETUP=true; \
		$(call require_client_onboard_env) \
		$(call forge_onboard_client_verified) \
	'

.PHONY: onboard-mezo-client-2of3
onboard-mezo-client-2of3:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		if [ -z "$$CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] && [ -n "$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ]; then export CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY="$$TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY"; fi; \
		if [ -z "$$CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY" ] && [ -n "$$TREASURY_OWNER_PRIVATE_KEY" ]; then export CLIENT_TREASURY_MULTISIG_PROPOSER_PRIVATE_KEY="$$TREASURY_OWNER_PRIVATE_KEY"; fi; \
		export DEPLOY_CLIENT_TREASURY_MULTISIG=true; \
		export CLIENT_TREASURY_MULTISIG_THRESHOLD=2; \
		unset CLIENT_TREASURY_MULTISIG_OWNER_4 CLIENT_TREASURY_MULTISIG_OWNER_5; \
		export PROPOSE_CLIENT_TREASURY_MULTISIG_SETUP=true; \
		[ -n "$${CLIENT_TREASURY_MULTISIG_OWNER_1:-$${TREASURY_MULTISIG_OWNER_1:-}}" ] || { echo "Missing CLIENT_TREASURY_MULTISIG_OWNER_1 or TREASURY_MULTISIG_OWNER_1"; exit 1; }; \
		[ -n "$${CLIENT_TREASURY_MULTISIG_OWNER_2:-$${TREASURY_MULTISIG_OWNER_2:-}}" ] || { echo "Missing CLIENT_TREASURY_MULTISIG_OWNER_2 or TREASURY_MULTISIG_OWNER_2"; exit 1; }; \
		[ -n "$${CLIENT_TREASURY_MULTISIG_OWNER_3:-$${TREASURY_MULTISIG_OWNER_3:-}}" ] || { echo "Missing CLIENT_TREASURY_MULTISIG_OWNER_3 or TREASURY_MULTISIG_OWNER_3"; exit 1; }; \
		$(call require_client_onboard_env) \
		$(call forge_onboard_client_verified) \
	'

.PHONY: onboard-mezo-client-eoa
onboard-mezo-client-eoa:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		if [ -z "$$CLIENT_TREASURY_OWNER" ] && [ -n "$$TREASURY_OWNER" ]; then export CLIENT_TREASURY_OWNER="$$TREASURY_OWNER"; fi; \
		if [ -z "$$CLIENT_TREASURY_OWNER_PRIVATE_KEY" ] && [ -n "$$TREASURY_OWNER_PRIVATE_KEY" ]; then export CLIENT_TREASURY_OWNER_PRIVATE_KEY="$$TREASURY_OWNER_PRIVATE_KEY"; fi; \
		export DEPLOY_CLIENT_TREASURY_MULTISIG=false; \
		export EXECUTE_CLIENT_OWNER_SETUP=true; \
		$(call require_client_onboard_env) \
		[ -n "$$CLIENT_TREASURY_OWNER_PRIVATE_KEY" ] || { echo "Missing CLIENT_TREASURY_OWNER_PRIVATE_KEY for EOA setup execution"; exit 1; }; \
		$(call forge_onboard_client_verified) \
	'

.PHONY: onboard-mezo-client-external
onboard-mezo-client-external:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		if [ -z "$$CLIENT_TREASURY_OWNER" ] && [ -n "$$TREASURY_OWNER" ]; then export CLIENT_TREASURY_OWNER="$$TREASURY_OWNER"; fi; \
		export DEPLOY_CLIENT_TREASURY_MULTISIG=false; \
		export EXECUTE_CLIENT_OWNER_SETUP=false; \
		$(call require_client_onboard_env) \
		$(call forge_onboard_client_verified) \
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
		$(call require_mezo_rpc_candidate) \
		$(call select_active_mezo_rpc) \
		[ -n "$$MULTISIG_ADDRESS" ] || { echo "Missing TREASURY_MULTISIG_ADDRESS or MULTISIG_ADDRESS=<address>"; exit 1; }; \
		[ -n "$$BATCH_ID_VALUE" ] || { echo "Missing BATCH_ID=<id>"; exit 1; }; \
		[ -n "$$SIGNER_KEY" ] || { echo "Missing SIGNER_PRIVATE_KEY=<private key>"; exit 1; }; \
		cast send "$$MULTISIG_ADDRESS" "confirmBatchTransaction(uint256)" "$$BATCH_ID_VALUE" \
			--private-key "$$SIGNER_KEY" \
			--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
	'

.PHONY: verify-mezo-testnet-resume
verify-mezo-testnet-resume:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_testnet_env) \
		$(call select_active_mezo_rpc) \
		forge script $(DEPLOY_SCRIPT) \
			--root $(CONTRACTS_ROOT) \
			--rpc-url "$$ACTIVE_MEZO_RPC_URL" \
			--resume \
			--verify \
			--verifier blockscout \
			--verifier-url "$${BLOCKSCOUT_API:-$(BLOCKSCOUT_API)}" \
			-vvvv \
	'

.PHONY: verify-mezo-testnet-deployed
verify-mezo-testnet-deployed:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		$(call require_mezo_rpc_candidate) \
		$(call select_active_mezo_rpc) \
		BLOCKSCOUT_API_URL="$${BLOCKSCOUT_API:-$(BLOCKSCOUT_API)}"; \
		[ -n "$$BLOCKSCOUT_API_URL" ] || { echo "Missing BLOCKSCOUT_API"; exit 1; }; \
		for var in PROTOCOL_FEE_VAULT PROTOCOL_FEE_MANAGER TREASURY_POLICY_ENGINE BTC_RESERVE_POLICY TREASURY_ACCOUNT_IMPLEMENTATION TREASURY_ACCOUNT_FACTORY CLIENT_TREASURY_MULTISIG TREASURY_AUTOMATION_EXECUTOR ALLOCATION_ROUTER MUSD_SAVINGS_RATE_HANDLER TIGRIS_STABLE_POOL_HANDLER; do \
			value="$${!var:-}"; \
			[ -n "$$value" ] || { echo "Missing $$var"; exit 1; }; \
		done; \
		verify_old() { \
			local addr="$$1"; local contract="$$2"; \
			echo "Verifying old-profile $$contract at $$addr"; \
			FOUNDRY_OPTIMIZER_RUNS=1000 FOUNDRY_VIA_IR=false FOUNDRY_BYTECODE_HASH=ipfs FOUNDRY_CBOR_METADATA=true \
				forge verify-contract --root $(CONTRACTS_ROOT) --chain 31611 --rpc-url "$$ACTIVE_MEZO_RPC_URL" \
					--verifier blockscout --verifier-url "$$BLOCKSCOUT_API_URL" \
					--compiler-version v0.8.34+commit.2a4b3df4 --num-of-optimizations 1000 \
					--guess-constructor-args --flatten --force "$$addr" "$$contract" --watch; \
		}; \
		verify_current() { \
			local addr="$$1"; local contract="$$2"; \
			echo "Verifying current-profile $$contract at $$addr"; \
			forge verify-contract --root $(CONTRACTS_ROOT) --chain 31611 --rpc-url "$$ACTIVE_MEZO_RPC_URL" \
				--verifier blockscout --verifier-url "$$BLOCKSCOUT_API_URL" \
				--compiler-version v0.8.34+commit.2a4b3df4 --num-of-optimizations 1 --via-ir \
				--guess-constructor-args "$$addr" "$$contract" --watch; \
		}; \
		verify_old "$$PROTOCOL_FEE_VAULT" src/fees/ProtocolFeeVault.sol:ProtocolFeeVault; \
		verify_old "$$PROTOCOL_FEE_MANAGER" src/fees/ProtocolFeeManager.sol:ProtocolFeeManager; \
		verify_old "$$TREASURY_POLICY_ENGINE" src/core/TreasuryPolicyEngine.sol:TreasuryPolicyEngine; \
		verify_old "$$BTC_RESERVE_POLICY" src/core/BTCReservePolicy.sol:BTCReservePolicy; \
		verify_current "$$TREASURY_ACCOUNT_IMPLEMENTATION" src/core/TreasuryAccount.sol:TreasuryAccount; \
		verify_current "$$TREASURY_ACCOUNT_FACTORY" src/core/TreasuryAccountFactory.sol:TreasuryAccountFactory; \
		verify_current "$$CLIENT_TREASURY_MULTISIG" src/multisig/TreasuryMultisig.sol:TreasuryMultisig; \
		verify_current "$$TREASURY_AUTOMATION_EXECUTOR" src/core/TreasuryAutomationExecutor.sol:TreasuryAutomationExecutor; \
		verify_current "$$ALLOCATION_ROUTER" src/adapters/AllocationRouter.sol:AllocationRouter; \
		verify_current "$$MUSD_SAVINGS_RATE_HANDLER" src/adapters/MUSDSavingsRateHandler.sol:MUSDSavingsRateHandler; \
		verify_current "$$TIGRIS_STABLE_POOL_HANDLER" src/adapters/TigrisStablePoolHandler.sol:TigrisStablePoolHandler; \
	'

.PHONY: verify-mezo-testnet-status
verify-mezo-testnet-status:
	$(call require_env_file)
	@bash -lc '$(call load_env) \
		BLOCKSCOUT_API_URL="$${BLOCKSCOUT_API:-$(BLOCKSCOUT_API)}"; \
		[ -n "$$BLOCKSCOUT_API_URL" ] || { echo "Missing BLOCKSCOUT_API"; exit 1; }; \
		for item in \
			"ProtocolFeeVault:$$PROTOCOL_FEE_VAULT" \
			"ProtocolFeeManager:$$PROTOCOL_FEE_MANAGER" \
			"TreasuryPolicyEngine:$$TREASURY_POLICY_ENGINE" \
			"BTCReservePolicy:$$BTC_RESERVE_POLICY" \
			"TreasuryAccountImplementation:$$TREASURY_ACCOUNT_IMPLEMENTATION" \
			"TreasuryAccountFactory:$$TREASURY_ACCOUNT_FACTORY" \
			"ClientTreasuryMultisig:$$CLIENT_TREASURY_MULTISIG" \
			"TreasuryAutomationExecutor:$$TREASURY_AUTOMATION_EXECUTOR" \
			"AllocationRouter:$$ALLOCATION_ROUTER" \
			"MUSDSavingsRateHandler:$$MUSD_SAVINGS_RATE_HANDLER" \
			"TigrisStablePoolHandler:$$TIGRIS_STABLE_POOL_HANDLER" \
			"TreasuryAccountClone:$$TREASURY_ACCOUNT"; do \
			label="$${item%%:*}"; addr="$${item#*:}"; \
			if [ -z "$$addr" ]; then echo "$$label missing"; continue; fi; \
			res=$$(curl -sS "$${BLOCKSCOUT_API_URL}?module=contract&action=getsourcecode&address=$$addr"); \
			name=$$(printf "%s" "$$res" | jq -r ".result[0].ContractName // empty"); \
			if [ -n "$$name" ]; then echo "$$label $$addr verified as $$name"; \
			elif [ "$$label" = "TreasuryAccountClone" ]; then echo "$$label $$addr is an EIP-1167 clone; verify TreasuryAccountImplementation for source"; \
			else echo "$$label $$addr not verified"; fi; \
		done; \
	'
