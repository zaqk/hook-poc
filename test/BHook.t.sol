// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {IHooks} from "v4-core/interfaces/IHooks.sol";
import {Currency} from "v4-core/types/Currency.sol";

import {BHookPoc} from "src/BHook.sol";

import {HookMiner} from "test/utils/HookMiner.sol";
import {UniswapDeployer} from "test/utils/UniswapDeployer.sol";

contract BHookTest is Test {
    BHookPoc public bhook;


    IPoolManager public poolManager;
    MockERC20 public token0;
    MockERC20 public token1;

    address poolManagerAdmin = makeAddr("poolManagerAdmin");

    int24 initialActiveTick = -100_000;

    function setUp() public {

        (token0, token1) = _deployTokens();

        // Deploy poolmanager
        poolManager = IPoolManager(UniswapDeployer.deployPoolManager(poolManagerAdmin));

        // Deploy hook
        (,bytes32 salt) = HookMiner.find(
            address(this),
            Hooks.ALL_HOOK_MASK,
            type(BHookPoc).creationCode,
            new bytes(0)
        );
        bhook = new BHookPoc{salt: salt}();

        // Initialize pool
        poolManager.initialize(
            PoolKey({
                currency0: Currency.wrap(address(token0)),
                currency1: Currency.wrap(address(token1)),
                fee: 10_000,
                tickSpacing: 200,
                hooks: IHooks(address(bhook))
            }),
            TickMath.getSqrtPriceAtTick(initialActiveTick)
        );

    }

    function test_bHookPoc() public {


    }

    function _deployTokens() internal returns (MockERC20 t0, MockERC20 t1) {
        t0 = new MockERC20("Token0", "T0", 18);
        t1 = new MockERC20("Token1", "T1", 18);
        if (address(t0) > address(t1)) {
            (t0, t1) = (t1, t0);
        }
    }

}
