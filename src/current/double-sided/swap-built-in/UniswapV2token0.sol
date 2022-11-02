// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.8.14;

import {ERC20} from "solmate/tokens/ERC20.sol";
import {ERC4626} from "solmate/mixins/ERC4626.sol";
import {SafeTransferLib} from "solmate/utils/SafeTransferLib.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../interfaces/IUniswapV2Router.sol";
import {UniswapV2Library} from "../utils/UniswapV2Library.sol";

import {DexSwap} from "../../utils/swapUtils.sol";

import "forge-std/console.sol";

/// @notice Custom ERC4626 Wrapper for UniV2 Pools with built-in swap
/// https://v2.info.uniswap.org/pair/0xae461ca67b15dc8dc81ce7615e0320da1a9ab8d5 (DAI-USDC LP/PAIR on ETH)
contract UniswapV2WrapperERC4626Swap is ERC4626 {
    using SafeTransferLib for ERC20;
    using FixedPointMathLib for uint256;

    address public immutable manager;

    uint256 public slippage;
    uint256 public immutable slippageFloat = 10000;

    IUniswapV2Pair public immutable pair;
    IUniswapV2Router public immutable router;

    /// For simplicity, we use solmate's ERC20 interface
    ERC20 public token0;
    ERC20 public token1;

    ERC20 public uniswapLpToken;

    /// Act like this Vault's underlying is DAI (token0)
    constructor(
        string memory name_,
        string memory symbol_,
        ERC20 asset_, /// token0 address (Vault's underlying)
        IUniswapV2Router router_,
        IUniswapV2Pair pair_, /// Pair address
        uint256 slippage_
    ) ERC4626(asset_, name_, symbol_) {
        manager = msg.sender;

        pair = pair_;
        router = router_;

        token0 = ERC20(pair.token0());
        token1 = ERC20(pair.token1());
        uniswapLpToken = ERC20(address(pair));

        slippage = slippage_;

        /// Approve management TODO
        token0.approve(address(router), type(uint256).max);
        token1.approve(address(router), type(uint256).max);
        asset.approve(address(router), type(uint256).max);
    }

    function beforeWithdraw(uint256 assets, uint256) internal override {
        (uint256 assets0, uint256 assets1) = getAssetBalance();

        /// temp implementation, we should call directly on a pair
        router.removeLiquidity(
            address(token0),
            address(token1),
            assets,
            getSlippage(assets0),
            getSlippage(assets1),
            address(this),
            block.timestamp + 100
        );
    }

    function afterDeposit(uint256, uint256) internal override {
        (uint256 assets0, uint256 assets1) = getAssetBalance();

        /// temp implementation, we should call directly on a pair
        router.addLiquidity(
            address(token0),
            address(token1),
            assets0,
            assets1,
            getSlippage(assets0),
            getSlippage(assets1),
            address(this),
            block.timestamp + 100
        );
    }

    /// User gives N amount of an underlying asset (DAI)
    function deposit(uint256 assets, address receiver)
        public
        override
        returns (uint256 shares)
    {
        /// Assume that it's token0 (DAI).
        asset.safeTransferFrom(msg.sender, address(this), assets);

        swap(assets);

        require((shares = previewDeposit(assets)) != 0, "ZERO_SHARES");

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function swap(uint256 assets) internal {
        (uint256 resA, uint256 resB) = UniswapV2Library.getReserves(
            address(pair),
            pair.token0(),
            pair.token1()
        );

        uint256 swapAmt = UniswapV2Library.getSwapAmt(assets, resA);

        console.log("swapAmt", swapAmt);

        DexSwap.swap(
            /// amt to swap
            swapAmt,
            /// from asset (DAI)
            pair.token0(),
            /// to asset (USDC)
            pair.token1(),
            /// pair address
            address(pair)
        );
    }

    function getAssetBalance() internal view returns (uint256 a0, uint256 a1) {
        /// Doesn't account for a leftover!
        a0 = token0.balanceOf(address(this));
        a1 = token1.balanceOf(address(this));
    }

    function mint(uint256 shares, address receiver)
        public
        override
        returns (uint256 assets)
    {
        assets = previewMint(shares);

        /// Assume that it's token0 (DAI).
        asset.safeTransferFrom(msg.sender, address(this), assets);

        swap(assets);

        _mint(receiver, shares);

        emit Deposit(msg.sender, receiver, assets, shares);

        afterDeposit(assets, shares);
    }

    function withdraw(
        uint256 assets,
        address receiver,
        address owner
    ) public override returns (uint256 shares) {
        shares = previewWithdraw(assets);

        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender];

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

    }

    function redeem(
        uint256 shares,
        address receiver,
        address owner
    ) public override returns (uint256 assets) {
        if (msg.sender != owner) {
            uint256 allowed = allowance[owner][msg.sender]; // Saves gas for limited approvals.

            if (allowed != type(uint256).max)
                allowance[owner][msg.sender] = allowed - shares;
        }

        // Check for rounding error since we round down in previewRedeem.
        require((assets = previewRedeem(shares)) != 0, "ZERO_ASSETS");

        beforeWithdraw(assets, shares);

        _burn(owner, shares);

        emit Withdraw(msg.sender, receiver, owner, assets, shares);

        asset.safeTransfer(receiver, assets);

    }

    /// Pool's LP token on contract balance
    function totalAssets() public view override returns (uint256) {
        return uniswapLpToken.balanceOf(address(this));
    }

    function setSlippage(uint256 amount) external {
        require(msg.sender == manager, "owner");
        require(amount < 10000 && amount > 9000); /// 10% max slippage
        slippage = amount;
    }

    function getSlippage(uint256 amount) internal view returns (uint256) {
        return (amount * slippage) / slippageFloat;
    }

}
