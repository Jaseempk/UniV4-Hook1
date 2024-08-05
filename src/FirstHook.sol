//SPDX-License-Identifier:MIT

pragma solidity ^0.8.24;

import {BaseHook} from "v4-periphery/src/base/hooks/BaseHook.sol";
import {ERC20} from "permit2/lib/solmate/src/tokens/ERC20.sol";
import {CurrencyLibrary, Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "v4-core/types/PoolKey.sol";
import {BalanceDeltaLibrary, BalanceDelta} from "@uniswap/v4-core/src/types/BalanceDelta.sol";
import {IPoolManager} from "v4-core/interfaces/IPoolManager.sol";
import {Hooks} from "v4-core/libraries/Hooks.sol";

contract FirstHook is BaseHook, ERC20 {
    using CurrencyLibrary for Currency;
    using BalanceDeltaLibrary for BalanceDelta;

    mapping(address => address) public referredBy;

    uint256 public constant REFERRAL_POINTS_TOKEN = 500e18;

    constructor(
        IPoolManager _manager,
        string memory name,
        string memory symbol
    ) BaseHook(_manager) ERC20(name, symbol, 18) {}

    /**
     * we  are setting hookfunctions we are using to true and all others are kept as false
     */
    function getHookPermissions()
        public
        pure
        override
        returns (Hooks.Permissions memory)
    {
        return
            Hooks.Permissions({
                beforeInitialize: false,
                afterInitialize: false,
                beforeAddLiquidity: false,
                afterAddLiquidity: true,
                beforeRemoveLiquidity: false,
                afterRemoveLiquidity: false,
                beforeSwap: false,
                afterSwap: true,
                beforeDonate: false,
                afterDonate: false,
                beforeSwapReturnDelta: false,
                afterSwapReturnDelta: false,
                afterAddLiquidityReturnDelta: false,
                afterRemoveLiquidityReturnDelta: false
            });
    }

    function getHookData(
        address referrer,
        address referree
    ) public pure returns (bytes memory) {
        return abi.encode(referrer, referree);
    }

    function _assignPoints(
        bytes calldata hookData,
        uint256 referreePoints
    ) internal {
        (address referrer, address referree) = abi.decode(
            hookData,
            (address, address)
        );

        if (referree == address(0)) return;

        if (referredBy[referree] == address(0) && referrer != address(0)) {
            referredBy[referree] = referrer;
            _mint(referrer, REFERRAL_POINTS_TOKEN);
        }

        if (referredBy[referree] == referrer) {
            uint256 referralBonus = (referreePoints / 20);
            _mint(referrer, referralBonus);
        }

        _mint(referree, referreePoints);
    }

    function afterSwap(
        address,
        PoolKey calldata poolKey,
        IPoolManager.SwapParams calldata swapParams,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyByPoolManager returns (bytes4, int128) {
        if (!poolKey.currency0.isNative() || !swapParams.zeroForOne)
            return (this.afterSwap.selector, 0);

        /**
         * amountSpecified<0: its considered as "exact input for output", so the ETH value will be |amountSpecified|
         * amluntSpecified>0: it;'s considered as "exact output for input", so the ETH value will be delta.amount0
         */

        uint256 amountEthSpend = swapParams.amountSpecified < 0
            ? uint256(-swapParams.amountSpecified)
            : uint256(int256(-delta.amount0()));
        // amountsOfPointsToMint is equivalent to 20% of ETH value
        uint256 amountPointsToMint = amountEthSpend / 5;
        _assignPoints(hookData, amountPointsToMint);

        return (this.afterSwap.selector, 0);
    }

    /**
     * @param _poolKey PoolKey struct
     * @param delta BalanceDelta param which stores the values of amount0 & amount1
     * @param hookData referrer & referree address encoded
     * @return
     * @return
     */
    function afterAddLiquidity(
        address /*_someAddress*/,
        PoolKey calldata _poolKey,
        IPoolManager.ModifyLiquidityParams calldata /*_liquidityParams*/,
        BalanceDelta delta,
        bytes calldata hookData
    ) external override onlyByPoolManager returns (bytes4, BalanceDelta) {
        if (!_poolKey.currency0.isNative())
            return (this.afterSwap.selector, delta);

        //Here we have the ratio of 1:1 in the liquidity pool, i.e 1 ETH for 1 POINT
        uint256 pointsForAddingLiquidity = uint256(int256(-delta.amount0()));
        _assignPoints(hookData, pointsForAddingLiquidity);

        return (this.afterAddLiquidity.selector, delta);
    }
}
