// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {ERC20} from "solmate/src/tokens/ERC20.sol";
import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";
import {BalanceDelta} from "v4-core/types/BalanceDelta.sol";
import {StateLibrary} from "v4-core/libraries/StateLibrary.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";

import {IV4Router} from "v4-periphery/interfaces/IV4Router.sol";
import {Actions} from "v4-periphery/libraries/Actions.sol";
import {LiquidityAmounts} from "v4-periphery/libraries/LiquidityAmounts.sol";
import {IAllowanceTransfer} from "permit2/src/interfaces/IAllowanceTransfer.sol";

import {Commands} from "universal-router/libraries/Commands.sol";

import {IUniversalRouter} from "src/interfaces/external/IUniversalRouter.sol";

import {BHookPoc} from "src/BHook.sol";

import {HookMiner} from "test/utils/HookMiner.sol";
import {UniswapDeployer} from "test/utils/UniswapDeployer.sol";

contract BHookTest is Test {
    using StateLibrary for IPoolManager;

    BHookPoc bhook;

    address permit2;
    IPoolManager poolManager;
    IUniversalRouter universalRouter;
    MockERC20 token0;
    MockERC20 token1;

    PoolKey poolKey;

    address poolManagerAdmin = makeAddr("poolManagerAdmin");
    address user = makeAddr("user");

    int24 initialActiveTick = -100_000;

    function setUp() public {

        (token0, token1) = _deployTokens();

        // Deploy poolmanager
        permit2 = UniswapDeployer.deployPermit2();
        poolManager = IPoolManager(UniswapDeployer.deployPoolManager(poolManagerAdmin));
        universalRouter = IUniversalRouter(
            UniswapDeployer.deployUniversalRouter(
                address(token0),
                address(permit2),
                address(poolManager)
            )
        );

        // Deploy hook
        (,bytes32 salt) = HookMiner.find(
            address(this),
            Hooks.ALL_HOOK_MASK,
            type(BHookPoc).creationCode,
            new bytes(0)
        );
        bhook = new BHookPoc{salt: salt}();

        poolKey = PoolKey({
            currency0: Currency.wrap(address(token0)),
            currency1: Currency.wrap(address(token1)),
            fee: 10_000,
            tickSpacing: 200,
            hooks: IHooks(address(bhook))
        });

        // Initialize pool
        poolManager.initialize(poolKey, TickMath.getSqrtPriceAtTick(initialActiveTick));

        token0.mint(address(this), type(uint128).max);
        token1.mint(address(this), type(uint128).max);
        token0.approve(address(poolManager), type(uint256).max);
        token1.approve(address(poolManager), type(uint256).max);
        _addReserves(initialActiveTick - 200, initialActiveTick + 200, 1_000e18);

    }

    function test_bHookPoc() public {
        token0.mint(user, 100e18);
        vm.startPrank(user);
        _swap(SwapType.EXACT_INPUT, address(token0), address(token1), 100e18);
        vm.stopPrank();
    }

    enum SwapType {
        EXACT_INPUT,
        EXACT_OUTPUT
    }

    function _swap(
        SwapType swapType,
        address tokenIn,
        address tokenOut,
        uint256 amount
    ) internal returns (uint256 ret) {

        (,address caller,) = vm.readCallers();

        ERC20 retToken;

        // approve permit2
        ERC20(tokenIn).approve(address(permit2), type(uint256).max);
        IAllowanceTransfer(permit2).approve(tokenIn, address(universalRouter), uint160(amount), uint48(block.timestamp + 100));

        // construct calldata
        bytes memory commands = abi.encodePacked(uint8(Commands.V4_SWAP));
        bytes memory actions;
        bytes[] memory params = new bytes[](3);
        bytes[] memory inputs = new bytes[](1);

        if (swapType == SwapType.EXACT_INPUT) {
            retToken = ERC20(tokenOut);
            actions = abi.encodePacked(uint8(Actions.SWAP_EXACT_IN_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
            params[0] = abi.encode(IV4Router.ExactInputSingleParams({
                poolKey: poolKey,
                zeroForOne: tokenIn == address(token0) ? true : false,
                amountIn: uint128(amount),
                amountOutMinimum: 0,
                hookData: new bytes(0)
            }));

            // settle all
            params[1] = abi.encode(Currency.wrap(address(tokenIn)), amount);

            // take all
            params[2] = abi.encode(Currency.wrap(address(retToken)), 0);

            // encode inputs
            inputs[0] = abi.encode(actions, params);

            uint256 balBefore = retToken.balanceOf(caller);

            universalRouter.execute(commands, inputs, block.timestamp);

            return retToken.balanceOf(caller) - balBefore;
        } else {
            retToken = ERC20(tokenIn);
            actions = abi.encodePacked(uint8(Actions.SWAP_EXACT_OUT_SINGLE), uint8(Actions.SETTLE_ALL), uint8(Actions.TAKE_ALL));
            params[0] = abi.encode(IV4Router.ExactOutputSingleParams({
                poolKey: poolKey,
                zeroForOne: tokenIn == address(token0) ? true : false,
                amountOut: uint128(amount),
                amountInMaximum: 0,
                hookData: new bytes(0)
            }));

            // settle all
            params[1] = abi.encode(Currency.wrap(address(tokenIn)), 0);

            // take all
            params[2] = abi.encode(Currency.wrap(address(retToken)), amount);

            inputs[0] = abi.encode(actions, params);

            uint256 balBefore = retToken.balanceOf(caller);

            universalRouter.execute(commands, inputs, block.timestamp);

            return balBefore - retToken.balanceOf(caller);
        }
    }

    function _addReserves(int24 lower, int24 upper, uint256 amount1) internal returns (BalanceDelta, BalanceDelta) {

        uint128 liquidity = _getLiquidityOptimistic(lower, upper, amount1);

        bytes memory result = poolManager.unlock(abi.encodeCall(this.addLiquidityCallback, (lower, upper, liquidity)));

        (BalanceDelta callerDelta, BalanceDelta feesAccrued) = abi.decode(result, (BalanceDelta, BalanceDelta));

        return (callerDelta, feesAccrued);
    }

    function _deployTokens() internal returns (MockERC20 t0, MockERC20 t1) {
        t0 = new MockERC20("Token0", "T0", 18);
        t1 = new MockERC20("Token1", "T1", 18);
        if (address(t0) > address(t1)) {
            (t0, t1) = (t1, t0);
        }
    }


    function addLiquidityCallback(int24 _lower, int24 _upper, uint128 liquidity) public returns (BalanceDelta, BalanceDelta) {
        (BalanceDelta callerDelta, BalanceDelta feesAccrued) = poolManager.modifyLiquidity(
            poolKey,
            IPoolManager.ModifyLiquidityParams({
                tickLower: _lower,
                tickUpper: _upper,
                liquidityDelta: int256(int128(liquidity)),
                salt: bytes32(0)
            }),
            new bytes(0)
        );

        poolManager.sync(Currency.wrap(address(token0)));
        token0.mint(address(poolManager), uint256(uint128(-callerDelta.amount0())));
        poolManager.settle();

        poolManager.sync(Currency.wrap(address(token1)));
        token1.mint(address(poolManager), uint256(uint128(-callerDelta.amount1())));
        poolManager.settle();

        return (callerDelta, feesAccrued);
    }

    function unlockCallback(bytes calldata data) public returns (bytes memory) {

        (bool success, bytes memory result) = address(this).call(data);
        if (!success) revert("Failed");

        return result;
    }

    function _getLiquidityOptimistic(
        int24 _lower,
        int24 _upper,
        uint256 _reserves
    ) internal view returns (uint128 newLiquidity_) {
        (uint160 sqrtPriceA,,,) = poolManager.getSlot0(poolKey.toId());

        uint160 sqrtPriceL = TickMath.getSqrtPriceAtTick(_lower);
        uint160 sqrtPriceU = TickMath.getSqrtPriceAtTick(_upper);

        newLiquidity_ = LiquidityAmounts.getLiquidityForAmount1(
            sqrtPriceL,
            sqrtPriceA < sqrtPriceU ? sqrtPriceA : sqrtPriceU,
            _reserves
        );

    }

}
