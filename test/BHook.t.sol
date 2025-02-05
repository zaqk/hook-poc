// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import {Test} from "forge-std/Test.sol";

import {MockERC20} from "solmate/src/test/utils/mocks/MockERC20.sol";

import {PoolKey} from "v4-core/types/PoolKey.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {TickMath} from "v4-core/libraries/TickMath.sol";
import {BHookPoc} from "src/BHook.sol";

import {HookMiner} from "test/utils/HookMiner.sol";
import {UniswapDeployer} from "test/utils/UniswapDeployer.sol";

contract BHookTest is Test {
    BHookPoc public bhook;
    IPoolManager public poolManager;

    address poolManagerAdmin = makeAddr("poolManagerAdmin");

    int24 initialActiveTick = -100_000;

    function setUp() public {

        MockERC20 token0 = new MockERC20("Token0", "T0", 18);
        MockERC20 token1 = new MockERC20("Token1", "T1", 18);

        // Deploy poolmanager
        IPoolManager poolManager = IPoolManager(UniswapDeployer.deployPoolManager(poolManagerAdmin));

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
                token0: address(token0),
                token1: address(token1),
                fee: 10_000,
                tickSpacing: 200,
                hooks: IHooks(address(bhook))
            }),
            TickMath.getSqrtPriceAtTick(initialActiveTick)
        );

    }

    function test_bHookPoc() public {


    }

}
