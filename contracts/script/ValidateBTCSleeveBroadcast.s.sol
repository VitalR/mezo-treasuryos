// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import { Script, console2 } from "@forge-std/Script.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { IERC20Metadata } from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";

import { BTCReserveRouter } from "../src/adapters/BTCReserveRouter.sol";
import { TigrisBTCStablePoolHandler } from "../src/adapters/TigrisBTCStablePoolHandler.sol";
import { BTCReservePolicy } from "../src/core/BTCReservePolicy.sol";
import { TreasuryAccount } from "../src/core/TreasuryAccount.sol";
import { IBTCReserveHandler } from "../src/interfaces/IBTCReserveHandler.sol";
import { ITigrisBasicRouter } from "../src/interfaces/ITigrisBasicRouter.sol";

interface ITigrisBasicPool is IERC20 {
    function token0() external view returns (address);
    function token1() external view returns (address);
    function stable() external view returns (bool);
    function factory() external view returns (address);
    function getReserves() external view returns (uint256 reserve0, uint256 reserve1, uint256 blockTimestampLast);
}

/// @title ValidateBTCSleeveBroadcast
/// @notice Runs a tiny controlled Mezo testnet validation of the guarded mcbBTC/BTC sleeve path.
/// @dev This is a V1.5 validation tool, not the primary V1 demo path. It requires a direct EOA-owned Treasury
///      Account, explicit broadcast confirmation, live quote-derived min-outs, and a tiny amount. Multisig-owned
///      treasury accounts should reuse the same calls through the multisig path after this direct validation passes.
contract ValidateBTCSleeveBroadcast is Script {
    // =============================================================
    // Constants
    // =============================================================

    uint256 internal constant _MEZO_TESTNET_CHAIN_ID = 31_611;
    uint256 internal constant _DEFAULT_TEST_AMOUNT = 1e14;
    uint256 internal constant _DEFAULT_MAX_TEST_AMOUNT = 1e15;
    uint256 internal constant _DEFAULT_DEADLINE_WINDOW = 15 minutes;
    uint256 internal constant _DEFAULT_MAX_SLIPPAGE_BPS = 100;
    uint256 internal constant _DEFAULT_MAX_PRICE_IMPACT_BPS = 500;
    uint256 internal constant _DEFAULT_MAX_YIELD_BPS = 10_000;
    uint256 internal constant _DEFAULT_MAX_PER_SLEEVE_BPS = 10_000;
    uint256 internal constant _BPS_DENOMINATOR = 10_000;

    // =============================================================
    // Types
    // =============================================================

    struct ValidationConfig {
        uint256 ownerPrivateKey;
        address owner;
        bool dryRun;
        bool confirmed;
        TreasuryAccount treasuryAccount;
        BTCReservePolicy btcReservePolicy;
        BTCReserveRouter btcReserveRouter;
        TigrisBTCStablePoolHandler handler;
        ITigrisBasicRouter tigrisRouter;
        ITigrisBasicPool pool;
        address poolFactory;
        bool poolStable;
        IERC20 btcToken;
        IERC20 mcbtcToken;
        address rewardToken;
        uint256 testAmount;
        uint256 maxTestAmount;
        uint256 deadlineWindow;
        uint256 maxSlippageBps;
        uint256 minIdleReserve;
        uint256 emergencyReserve;
        uint256 maxPriceImpactBps;
        string manifestPath;
    }

    struct DepositPlan {
        uint256 btcAmount;
        uint256 quoteInputBTC;
        uint256 quotedMcbtcOut;
        uint256 btcToSwap;
        uint256 expectedMcbtcOut;
        uint256 btcToPair;
        uint256 expectedMcbtcUsed;
        uint256 expectedBTCUsed;
        uint256 expectedLiquidity;
        uint256 minMcbtcOut;
        uint256 minMcbtcUsed;
        uint256 minBTCUsed;
        uint256 minLiquidity;
        uint256 priceImpactBps;
    }

    struct ValidationResult {
        uint256 idleBTCBefore;
        uint256 lpBefore;
        uint256 lpAfterDeposit;
        uint256 lpAfterWithdraw;
        uint256 principalAfterDeposit;
        uint256 principalAfterWithdraw;
        uint256 idleBTCAfter;
        uint256 liquidityMinted;
        uint256 btcUsed;
        uint256 unusedBTC;
        uint256 pairedUsed;
        uint256 pairedReceived;
        uint256 btcReturnedDirect;
        uint256 btcReturnedFromPaired;
    }

    // =============================================================
    // Errors
    // =============================================================

    error BroadcastConfirmationRequired();
    error DirectOwnerRequired(address treasuryOwner, address signer);
    error ExistingHandlerPolicyMismatch(address handler, address expectedPolicy, address actualPolicy);
    error InvalidAddress(string key);
    error InvalidBasisPoints(uint256 value);
    error InvalidPoolTokenOrder(address token0, address token1);
    error InvalidPrivateKey(string key);
    error InvalidTreasuryAccountContract(address value);
    error InvalidTestAmount(uint256 amount, uint256 maxAmount);
    error InvalidTreasuryOwner(address treasuryAccount);
    error MezoTestnetOnly(uint256 chainId);
    error NoRouterQuote();
    error PolicyBlocked(BTCReservePolicy.BTCAllocationDecisionCode reason);
    error SignerBalanceTooLow(uint256 balance, uint256 required);
    error UnexpectedPoolMetadata();
    error UnexpectedSwapPathLength(uint256 pathLength);
    error ValidationInvariantFailed(string invariant);

    // =============================================================
    // External Functions
    // =============================================================

    /// @notice Performs the tiny BTC sleeve validation sequence.
    /// @return result Deposit, unwind, and accounting result for the validation run.
    function run() external returns (ValidationResult memory result) {
        ValidationConfig memory config = _loadConfig();
        _validateConfig(config);

        if (config.dryRun) {
            console2.log("BTC sleeve validation mode: dry-run");
        } else {
            console2.log("BTC sleeve validation mode: broadcast");
        }
        console2.log("TreasuryAccount:", address(config.treasuryAccount));
        console2.log("Signer / treasury owner:", config.owner);
        console2.log("mcbBTC/BTC pool:", address(config.pool));
        console2.log("BTC test amount:", config.testAmount);

        vm.startBroadcast(config.ownerPrivateKey);

        _ensureRouterAndHandler(config);
        DepositPlan memory plan = _buildDepositPlan(config);
        _configurePolicyForValidation(config, plan);

        BTCReservePolicy.BTCAllocationPreview memory preview = config.btcReservePolicy
            .recordBTCAllocationPreview(address(config.treasuryAccount), address(config.pool), config.testAmount);
        console2.log("BTC policy allowed:", preview.allowed);
        console2.log("BTC policy reason:", uint256(preview.reason));
        require(preview.allowed, PolicyBlocked(preview.reason));

        result = _executeDepositAndUnwind(config, plan);
        _syncPolicyAfterValidation(config);

        vm.stopBroadcast();

        _logResult(plan, result);
        if (!config.dryRun) {
            _writeManifest(config, plan, result);
        }
    }

    // =============================================================
    // Config
    // =============================================================

    function _loadConfig() internal view returns (ValidationConfig memory config) {
        config.ownerPrivateKey = _envPrivateKey();
        config.owner = vm.addr(config.ownerPrivateKey);
        config.dryRun = vm.envOr("BTC_SLEEVE_DRY_RUN", false);
        config.confirmed = vm.envOr("BTC_SLEEVE_BROADCAST_CONFIRM", false);
        config.treasuryAccount =
            TreasuryAccount(payable(_envAddress("BTC_SLEEVE_TREASURY_ACCOUNT", "TREASURY_ACCOUNT")));
        config.btcReservePolicy = BTCReservePolicy(vm.envOr("BTC_RESERVE_POLICY", address(0)));
        config.btcReserveRouter = BTCReserveRouter(vm.envOr("BTC_RESERVE_ROUTER", address(0)));
        config.handler = TigrisBTCStablePoolHandler(vm.envOr("TIGRIS_BTC_STABLE_POOL_HANDLER", address(0)));
        config.tigrisRouter = ITigrisBasicRouter(_envAddress("MEZO_TIGRIS_BTC_ROUTER", "MEZO_TIGRIS_ROUTER"));
        config.pool = ITigrisBasicPool(_envAddress("MEZO_TIGRIS_MCBTC_BTC_POOL", "BTC_SLEEVE_POOL"));
        config.poolFactory = _envAddress("MEZO_TIGRIS_POOL_FACTORY", "TIGRIS_POOL_FACTORY");
        config.poolStable = vm.envOr("MEZO_TIGRIS_MCBTC_BTC_STABLE", true);
        config.btcToken = IERC20(_envAddress("MEZO_BTC_TOKEN", "BTC_TOKEN"));
        config.mcbtcToken = IERC20(_envAddress("MEZO_MCBTC_TOKEN", "MCBTC_TOKEN"));
        config.rewardToken = _envOptionalAddress("BTC_SLEEVE_REWARD_TOKEN", "MEZO_REWARD_TOKEN");
        config.testAmount = vm.envOr("BTC_SLEEVE_TEST_AMOUNT_WEI", _DEFAULT_TEST_AMOUNT);
        config.maxTestAmount = vm.envOr("BTC_SLEEVE_MAX_TEST_AMOUNT_WEI", _DEFAULT_MAX_TEST_AMOUNT);
        config.deadlineWindow = vm.envOr("BTC_SLEEVE_DEADLINE_WINDOW", _DEFAULT_DEADLINE_WINDOW);
        config.maxSlippageBps = vm.envOr("BTC_SLEEVE_MAX_SLIPPAGE_BPS", _DEFAULT_MAX_SLIPPAGE_BPS);
        config.minIdleReserve = vm.envOr("BTC_SLEEVE_MIN_IDLE_RESERVE_WEI", uint256(0));
        config.emergencyReserve = vm.envOr("BTC_SLEEVE_EMERGENCY_RESERVE_WEI", uint256(0));
        config.maxPriceImpactBps = vm.envOr("BTC_SLEEVE_POLICY_MAX_PRICE_IMPACT_BPS", _DEFAULT_MAX_PRICE_IMPACT_BPS);
        config.manifestPath =
            vm.envOr("BTC_SLEEVE_VALIDATION_MANIFEST_PATH", string("../deployments/btc-sleeve-validation.json"));
    }

    function _validateConfig(ValidationConfig memory config) internal view {
        require(block.chainid == _MEZO_TESTNET_CHAIN_ID, MezoTestnetOnly(block.chainid));
        if (!config.dryRun && !config.confirmed) revert BroadcastConfirmationRequired();
        if (address(config.treasuryAccount) == address(0)) revert InvalidAddress("BTC_SLEEVE_TREASURY_ACCOUNT");
        if (address(config.treasuryAccount).code.length == 0) {
            revert InvalidTreasuryAccountContract(address(config.treasuryAccount));
        }
        if (address(config.tigrisRouter) == address(0)) revert InvalidAddress("MEZO_TIGRIS_BTC_ROUTER");
        if (address(config.pool) == address(0)) revert InvalidAddress("MEZO_TIGRIS_MCBTC_BTC_POOL");
        if (config.poolFactory == address(0)) revert InvalidAddress("MEZO_TIGRIS_POOL_FACTORY");
        if (address(config.btcToken) == address(0)) revert InvalidAddress("MEZO_BTC_TOKEN");
        if (address(config.mcbtcToken) == address(0)) revert InvalidAddress("MEZO_MCBTC_TOKEN");
        if (config.maxSlippageBps > _BPS_DENOMINATOR) revert InvalidBasisPoints(config.maxSlippageBps);
        if (config.maxPriceImpactBps > _BPS_DENOMINATOR) revert InvalidBasisPoints(config.maxPriceImpactBps);
        require(
            config.testAmount > 0 && config.testAmount <= config.maxTestAmount,
            InvalidTestAmount(config.testAmount, config.maxTestAmount)
        );
        require(config.owner.balance > config.testAmount, SignerBalanceTooLow(config.owner.balance, config.testAmount));

        address treasuryOwner = config.treasuryAccount.owner();
        require(treasuryOwner != address(0), InvalidTreasuryOwner(address(config.treasuryAccount)));
        require(treasuryOwner == config.owner, DirectOwnerRequired(treasuryOwner, config.owner));

        require(
            config.pool.token0() == address(config.mcbtcToken),
            InvalidPoolTokenOrder(config.pool.token0(), config.pool.token1())
        );
        require(
            config.pool.token1() == address(config.btcToken),
            InvalidPoolTokenOrder(config.pool.token0(), config.pool.token1())
        );
        require(
            config.pool.factory() == config.poolFactory && config.pool.stable() == config.poolStable,
            UnexpectedPoolMetadata()
        );
    }

    function _envPrivateKey() internal view returns (uint256 privateKey) {
        privateKey = vm.envOr("BTC_SLEEVE_VALIDATOR_PRIVATE_KEY", uint256(0));
        if (privateKey == 0) privateKey = vm.envOr("CLIENT_TREASURY_OWNER_PRIVATE_KEY", uint256(0));
        if (privateKey == 0) privateKey = vm.envOr("TREASURY_OWNER_PRIVATE_KEY", uint256(0));
        if (privateKey == 0) privateKey = vm.envOr("DEPLOYER_PRIVATE_KEY", uint256(0));
        if (privateKey == 0) revert InvalidPrivateKey("BTC_SLEEVE_VALIDATOR_PRIVATE_KEY");
    }

    function _envAddress(string memory primary, string memory fallbackKey) internal view returns (address value) {
        value = vm.envOr(primary, address(0));
        if (value == address(0)) value = vm.envOr(fallbackKey, address(0));
        if (value == address(0)) revert InvalidAddress(primary);
    }

    function _envOptionalAddress(string memory primary, string memory fallbackKey)
        internal
        view
        returns (address value)
    {
        value = vm.envOr(primary, address(0));
        if (value == address(0)) value = vm.envOr(fallbackKey, address(0));
    }

    // =============================================================
    // Validation Flow
    // =============================================================

    function _ensureRouterAndHandler(ValidationConfig memory config) internal {
        if (address(config.btcReservePolicy) == address(0)) {
            config.btcReservePolicy = new BTCReservePolicy(config.treasuryAccount.policyEngine());
            console2.log("Deployed validation BTCReservePolicy:", address(config.btcReservePolicy));
        }

        if (address(config.btcReserveRouter) == address(0)) {
            address currentRouter = config.treasuryAccount.btcReserveRouter();
            if (currentRouter != address(0)) {
                config.btcReserveRouter = BTCReserveRouter(currentRouter);
            } else {
                config.btcReserveRouter = new BTCReserveRouter(config.owner);
                console2.log("Deployed validation BTCReserveRouter:", address(config.btcReserveRouter));
            }
        }

        if (config.treasuryAccount.btcReserveRouter() != address(config.btcReserveRouter)) {
            config.treasuryAccount.setBTCReserveRouter(address(config.btcReserveRouter));
        }

        address registeredHandler = config.btcReserveRouter.handlers(address(config.pool));
        if (address(config.handler) == address(0) && registeredHandler != address(0)) {
            config.handler = TigrisBTCStablePoolHandler(registeredHandler);
        }

        if (address(config.handler) == address(0)) {
            config.handler = new TigrisBTCStablePoolHandler(
                address(config.btcReserveRouter),
                config.btcReservePolicy,
                config.tigrisRouter,
                address(config.pool),
                config.poolFactory,
                config.poolStable,
                address(config.btcToken),
                address(config.mcbtcToken),
                config.rewardToken,
                config.deadlineWindow,
                config.maxSlippageBps
            );
            console2.log("Deployed validation TigrisBTCStablePoolHandler:", address(config.handler));
        } else {
            _requireHandlerMatchesPolicy(config);
        }

        if (config.btcReserveRouter.handlers(address(config.pool)) != address(config.handler)) {
            config.btcReserveRouter.setHandler(address(config.pool), config.handler);
        }
    }

    function _requireHandlerMatchesPolicy(ValidationConfig memory config) internal view {
        BTCReservePolicy actualPolicy = config.handler.btcReservePolicy();
        require(
            address(actualPolicy) == address(config.btcReservePolicy),
            ExistingHandlerPolicyMismatch(
                address(config.handler), address(config.btcReservePolicy), address(actualPolicy)
            )
        );
        require(config.handler.destination() == address(config.pool), UnexpectedPoolMetadata());
        require(config.handler.principalAsset() == address(config.btcToken), UnexpectedPoolMetadata());
        require(config.handler.pairedAsset() == address(config.mcbtcToken), UnexpectedPoolMetadata());
        require(config.handler.poolFactory() == config.poolFactory, UnexpectedPoolMetadata());
        require(config.handler.poolStable() == config.poolStable, UnexpectedPoolMetadata());
    }

    function _configurePolicyForValidation(ValidationConfig memory config, DepositPlan memory plan) internal {
        config.treasuryAccount.fundIdleBTC{ value: config.testAmount }();

        BTCReservePolicy.BTCReservePolicyConfig memory policy = BTCReservePolicy.BTCReservePolicyConfig({
            minIdleBTCReserve: config.minIdleReserve,
            emergencyBTCReserve: config.emergencyReserve,
            maxYieldBTCBps: _DEFAULT_MAX_YIELD_BPS,
            maxPerSleeveBTCBps: _DEFAULT_MAX_PER_SLEEVE_BPS,
            maxDirectionalBTCBps: 0,
            maxBTCAssetDepegBps: _BPS_DENOMINATOR,
            maxSwapPriceImpactBps: config.maxPriceImpactBps,
            maxSlippageBps: config.maxSlippageBps,
            collateralWarningCRBps: 0,
            btcYieldPaused: false,
            initialized: false
        });
        config.btcReservePolicy.configureBTCReservePolicy(address(config.treasuryAccount), policy);

        BTCReservePolicy.BTCReserveBuckets memory buckets = BTCReservePolicy.BTCReserveBuckets({
            idleBTCReserve: config.treasuryAccount.idleBTC(),
            collateralBTC: config.treasuryAccount.positionCollateral(),
            emergencyBTCReserve: config.emergencyReserve,
            yieldActiveBTC: config.treasuryAccount.btcSleevePrincipalAllocations(address(config.pool)),
            pendingWithdrawBTC: 0
        });
        config.btcReservePolicy.updateBTCReserveBuckets(address(config.treasuryAccount), buckets);

        BTCReservePolicy.BTCSleeveConfig memory sleeve = BTCReservePolicy.BTCSleeveConfig({
            riskClass: BTCReservePolicy.BTCSleeveRiskClass.BTC_CORRELATED,
            enabled: true,
            sleeveCapBps: _DEFAULT_MAX_PER_SLEEVE_BPS,
            assetDepegBps: 0,
            withdrawalDelaySeconds: 0,
            swapPriceImpactBps: plan.priceImpactBps,
            slippageBps: config.maxSlippageBps,
            approvalLevel: BTCReservePolicy.BTCApprovalLevel.MULTISIG
        });
        config.btcReservePolicy.configureBTCSleeve(address(config.treasuryAccount), address(config.pool), sleeve);
        config.btcReservePolicy
            .updateBTCSleeveExposure(
                address(config.treasuryAccount),
                address(config.pool),
                config.treasuryAccount.btcSleevePrincipalAllocations(address(config.pool))
            );
    }

    function _executeDepositAndUnwind(ValidationConfig memory config, DepositPlan memory plan)
        internal
        returns (ValidationResult memory result)
    {
        result.idleBTCBefore = config.treasuryAccount.idleBTC();
        result.lpBefore = config.pool.balanceOf(address(config.treasuryAccount));

        IBTCReserveHandler.BTCDepositRequest memory depositRequest = IBTCReserveHandler.BTCDepositRequest({
            btcAmount: plan.btcAmount,
            btcToSwap: plan.btcToSwap,
            minPairedOut: plan.minMcbtcOut,
            minBTCUsed: plan.minBTCUsed,
            minPairedUsed: plan.minMcbtcUsed,
            minLiquidity: plan.minLiquidity
        });

        IBTCReserveHandler.BTCDepositResult memory depositResult =
            config.btcReserveRouter.deposit(address(config.treasuryAccount), address(config.pool), depositRequest);
        result.pairedReceived = depositResult.pairedReceived;
        result.btcUsed = depositResult.btcUsed;
        result.pairedUsed = depositResult.pairedUsed;
        result.liquidityMinted = depositResult.liquidityMinted;
        result.unusedBTC = depositResult.unusedBTC;
        result.lpAfterDeposit = config.pool.balanceOf(address(config.treasuryAccount));
        result.principalAfterDeposit = config.treasuryAccount.btcSleevePrincipalAllocations(address(config.pool));

        require(result.liquidityMinted > 0, ValidationInvariantFailed("NO_LP_MINTED"));
        require(
            result.lpAfterDeposit >= result.lpBefore + result.liquidityMinted,
            ValidationInvariantFailed("LP_RECEIPT_NOT_HELD")
        );
        require(
            result.principalAfterDeposit == result.btcUsed, ValidationInvariantFailed("PRINCIPAL_ACCOUNTING_MISMATCH")
        );

        IBTCReserveHandler.BTCWithdrawRequest memory withdrawRequest =
            _buildWithdrawRequest(config, result.liquidityMinted, result.btcUsed);
        IBTCReserveHandler.BTCWithdrawResult memory withdrawResult =
            config.btcReserveRouter.withdraw(address(config.treasuryAccount), address(config.pool), withdrawRequest);

        result.btcReturnedDirect = withdrawResult.btcReceived;
        result.btcReturnedFromPaired = withdrawResult.btcFromPairedSwap;
        result.lpAfterWithdraw = config.pool.balanceOf(address(config.treasuryAccount));
        result.principalAfterWithdraw = config.treasuryAccount.btcSleevePrincipalAllocations(address(config.pool));
        result.idleBTCAfter = config.treasuryAccount.idleBTC();

        require(result.lpAfterWithdraw == result.lpBefore, ValidationInvariantFailed("LP_NOT_UNWOUND"));
        require(result.principalAfterWithdraw == 0, ValidationInvariantFailed("PRINCIPAL_NOT_CLEARED"));
        require(result.idleBTCAfter > 0, ValidationInvariantFailed("IDLE_BTC_NOT_RESTORED"));
    }

    function _syncPolicyAfterValidation(ValidationConfig memory config) internal {
        BTCReservePolicy.BTCReserveBuckets memory buckets = BTCReservePolicy.BTCReserveBuckets({
            idleBTCReserve: config.treasuryAccount.idleBTC(),
            collateralBTC: config.treasuryAccount.positionCollateral(),
            emergencyBTCReserve: config.emergencyReserve,
            yieldActiveBTC: config.treasuryAccount.btcSleevePrincipalAllocations(address(config.pool)),
            pendingWithdrawBTC: 0
        });
        config.btcReservePolicy.updateBTCReserveBuckets(address(config.treasuryAccount), buckets);
        config.btcReservePolicy
            .updateBTCSleeveExposure(
                address(config.treasuryAccount),
                address(config.pool),
                config.treasuryAccount.btcSleevePrincipalAllocations(address(config.pool))
            );
    }

    // =============================================================
    // Quote Helpers
    // =============================================================

    function _buildDepositPlan(ValidationConfig memory config) internal view returns (DepositPlan memory plan) {
        (uint256 reserveMcbtc, uint256 reserveBTC,) = config.pool.getReserves();
        uint256 quoteInputBTC = _quoteInput(config.testAmount);
        uint256 quotedMcbtcOut =
            _quoteFinalOut(config, quoteInputBTC, address(config.btcToken), address(config.mcbtcToken));
        require(quotedMcbtcOut > 0, NoRouterQuote());

        uint256 btcToSwap = (config.testAmount * quoteInputBTC * reserveMcbtc)
            / ((quotedMcbtcOut * reserveBTC) + (quoteInputBTC * reserveMcbtc));
        uint256 expectedMcbtcOut =
            _quoteFinalOut(config, btcToSwap, address(config.btcToken), address(config.mcbtcToken));

        plan = DepositPlan({
            btcAmount: config.testAmount,
            quoteInputBTC: quoteInputBTC,
            quotedMcbtcOut: quotedMcbtcOut,
            btcToSwap: btcToSwap,
            expectedMcbtcOut: expectedMcbtcOut,
            btcToPair: config.testAmount - btcToSwap,
            expectedMcbtcUsed: 0,
            expectedBTCUsed: 0,
            expectedLiquidity: 0,
            minMcbtcOut: _amountAfterSlippage(expectedMcbtcOut, config.maxSlippageBps),
            minMcbtcUsed: 0,
            minBTCUsed: 0,
            minLiquidity: 0,
            priceImpactBps: _priceImpactForQuote(config, quoteInputBTC, quotedMcbtcOut)
        });

        plan = _fillDepositLiquidityBounds(config, plan);
        require(plan.btcToSwap > 0 && plan.btcToSwap < plan.btcAmount, ValidationInvariantFailed("INVALID_SPLIT"));
        require(plan.minMcbtcOut > 0 && plan.minLiquidity > 0, ValidationInvariantFailed("DUST_MIN_OUT"));
    }

    function _fillDepositLiquidityBounds(ValidationConfig memory config, DepositPlan memory plan)
        internal
        view
        returns (DepositPlan memory)
    {
        (plan.expectedMcbtcUsed, plan.expectedBTCUsed, plan.expectedLiquidity) =
            config.tigrisRouter
                .quoteAddLiquidity(
                    address(config.mcbtcToken),
                    address(config.btcToken),
                    config.poolStable,
                    config.poolFactory,
                    plan.expectedMcbtcOut,
                    plan.btcToPair
                );
        plan.minMcbtcUsed = _amountAfterSlippage(plan.expectedMcbtcUsed, config.maxSlippageBps);
        plan.minBTCUsed = _amountAfterSlippage(plan.expectedBTCUsed, config.maxSlippageBps);
        plan.minLiquidity = _amountAfterSlippage(plan.expectedLiquidity, config.maxSlippageBps);

        return plan;
    }

    function _buildWithdrawRequest(ValidationConfig memory config, uint256 liquidity, uint256 principalReduction)
        internal
        view
        returns (IBTCReserveHandler.BTCWithdrawRequest memory request)
    {
        (uint256 expectedMcbtcOut, uint256 expectedBTCOut) = config.tigrisRouter
            .quoteRemoveLiquidity(
                address(config.mcbtcToken), address(config.btcToken), config.poolStable, config.poolFactory, liquidity
            );
        uint256 pairedSwapInput = _amountAfterSlippage(expectedMcbtcOut, config.maxSlippageBps);
        uint256 expectedBTCFromPaired =
            _quoteFinalOut(config, pairedSwapInput, address(config.mcbtcToken), address(config.btcToken));

        request = IBTCReserveHandler.BTCWithdrawRequest({
            liquidity: liquidity,
            principalReductionBTC: principalReduction,
            minPairedOut: pairedSwapInput,
            minBTCOut: _amountAfterSlippage(expectedBTCOut, config.maxSlippageBps),
            swapPairedToBTC: true,
            minBTCFromPaired: _amountAfterSlippage(expectedBTCFromPaired, config.maxSlippageBps)
        });
    }

    function _quoteFinalOut(ValidationConfig memory config, uint256 amountIn, address from, address to)
        internal
        view
        returns (uint256 amountOut)
    {
        if (amountIn == 0) return 0;
        ITigrisBasicRouter.Route[] memory routes = new ITigrisBasicRouter.Route[](1);
        routes[0] =
            ITigrisBasicRouter.Route({ from: from, to: to, stable: config.poolStable, factory: config.poolFactory });
        uint256[] memory amounts = config.tigrisRouter.getAmountsOut(amountIn, routes);
        require(amounts.length >= 2, UnexpectedSwapPathLength(amounts.length));
        amountOut = amounts[amounts.length - 1];
    }

    function _quoteInput(uint256 amount) internal pure returns (uint256 quoteAmount) {
        quoteAmount = amount / 10;
        if (quoteAmount == 0) quoteAmount = amount;
    }

    function _amountAfterSlippage(uint256 amount, uint256 slippageBps) internal pure returns (uint256) {
        return (amount * (_BPS_DENOMINATOR - slippageBps)) / _BPS_DENOMINATOR;
    }

    function _priceImpactForQuote(ValidationConfig memory config, uint256 input, uint256 output)
        internal
        view
        returns (uint256)
    {
        return _priceImpactBps(
            input,
            output,
            IERC20Metadata(address(config.btcToken)).decimals(),
            IERC20Metadata(address(config.mcbtcToken)).decimals()
        );
    }

    function _priceImpactBps(uint256 input, uint256 output, uint8 inputDecimals, uint8 outputDecimals)
        internal
        pure
        returns (uint256)
    {
        if (input == 0 || output == 0) return _BPS_DENOMINATOR;

        uint256 quoteRateScaled =
            (output * (10 ** uint256(inputDecimals)) * 1e18) / (input * (10 ** uint256(outputDecimals)));
        uint256 delta = quoteRateScaled > 1e18 ? quoteRateScaled - 1e18 : 1e18 - quoteRateScaled;
        return (delta * _BPS_DENOMINATOR) / 1e18;
    }

    // =============================================================
    // Output
    // =============================================================

    function _logResult(DepositPlan memory plan, ValidationResult memory result) internal pure {
        console2.log("BTC -> mcbBTC quote input:", plan.quoteInputBTC);
        console2.log("BTC -> mcbBTC quoted out:", plan.quotedMcbtcOut);
        console2.log("Computed BTC to swap:", plan.btcToSwap);
        console2.log("Computed BTC LP side:", plan.btcToPair);
        console2.log("Min mcbBTC out:", plan.minMcbtcOut);
        console2.log("Min LP out:", plan.minLiquidity);
        console2.log("Computed price impact bps:", plan.priceImpactBps);
        console2.log("LP minted:", result.liquidityMinted);
        console2.log("LP after withdraw:", result.lpAfterWithdraw);
        console2.log("BTC principal after withdraw:", result.principalAfterWithdraw);
        console2.log("Idle BTC after validation:", result.idleBTCAfter);
    }

    function _writeManifest(ValidationConfig memory config, DepositPlan memory plan, ValidationResult memory result)
        internal
    {
        string memory json = string.concat(
            "{",
            '"manifestVersion":1,',
            '"scenario":"btc-sleeve-broadcast-validation",',
            '"broadcastValidationPerformed":true,',
            '"network":',
            _networkJson(),
            ",",
            '"contracts":',
            _contractsJson(config),
            ",",
            '"plan":',
            _planJson(plan),
            ",",
            '"result":',
            _resultJson(result),
            "}"
        );

        vm.writeJson(json, config.manifestPath);
        console2.log("BTC sleeve validation manifest:", config.manifestPath);
    }

    function _networkJson() internal view returns (string memory) {
        return string.concat('{"name":"Mezo Testnet","chainId":', vm.toString(block.chainid), "}");
    }

    function _contractsJson(ValidationConfig memory config) internal pure returns (string memory) {
        return string.concat(
            '{"treasuryAccount":"',
            vm.toString(address(config.treasuryAccount)),
            '","btcReservePolicy":"',
            vm.toString(address(config.btcReservePolicy)),
            '","btcReserveRouter":"',
            vm.toString(address(config.btcReserveRouter)),
            '","tigrisBTCStablePoolHandler":"',
            vm.toString(address(config.handler)),
            '","mcbtcBtcPool":"',
            vm.toString(address(config.pool)),
            '"}'
        );
    }

    function _planJson(DepositPlan memory plan) internal pure returns (string memory) {
        return string.concat(
            '{"btcAmount":"',
            vm.toString(plan.btcAmount),
            '","btcToSwap":"',
            vm.toString(plan.btcToSwap),
            '","expectedMcbtcOut":"',
            vm.toString(plan.expectedMcbtcOut),
            '","btcToPair":"',
            vm.toString(plan.btcToPair),
            '","minMcbtcOut":"',
            vm.toString(plan.minMcbtcOut),
            '","minLiquidity":"',
            vm.toString(plan.minLiquidity),
            '","priceImpactBps":"',
            vm.toString(plan.priceImpactBps),
            '"}'
        );
    }

    function _resultJson(ValidationResult memory result) internal pure returns (string memory) {
        return string.concat(
            '{"liquidityMinted":"',
            vm.toString(result.liquidityMinted),
            '","btcUsed":"',
            vm.toString(result.btcUsed),
            '","pairedReceived":"',
            vm.toString(result.pairedReceived),
            '","pairedUsed":"',
            vm.toString(result.pairedUsed),
            '","btcReturnedDirect":"',
            vm.toString(result.btcReturnedDirect),
            '","btcReturnedFromPaired":"',
            vm.toString(result.btcReturnedFromPaired),
            '","idleBTCAfter":"',
            vm.toString(result.idleBTCAfter),
            '","principalAfterWithdraw":"',
            vm.toString(result.principalAfterWithdraw),
            '"}'
        );
    }
}
