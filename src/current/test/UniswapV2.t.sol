// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {UniswapV2WrapperERC4626} from "../double-sided/UniswapV2.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

import {IUniswapV2Pair} from "../double-sided/interfaces/IUniswapV2Pair.sol";
import {IUniswapV2Router} from "../double-sided/interfaces/IUniswapV2Router.sol";

contract UniswapV2Test is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;
    uint256 public immutable ONE_E18 = 1 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    UniswapV2WrapperERC4626 public vault;

    string name = "UniV2ERC4626ishWrapperooo";
    string symbol = "UFC4626";
    ERC20 public dai = ERC20(0x6B175474E89094C44Da98b954EedeAC495271d0F);
    ERC20 public usdc = ERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48);
    ERC20 public pairToken = ERC20(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    IUniswapV2Pair public pair = IUniswapV2Pair(0xAE461cA67B15dc8dc81CE7615e0320dA1A9aB8D5);
    IUniswapV2Router public router = IUniswapV2Router(0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D);

    address public alice;
    address public manager;

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new UniswapV2WrapperERC4626(name, symbol, pairToken, dai, usdc, router, pair);
        alice = address(0x1);
        manager = msg.sender;

        deal(address(dai), alice, ONE_THOUSAND_E18);
        deal(address(usdc), alice, 1000e6);

    }

    function testDepositWithdraw() public {
        uint256 uniLpRequested = 1000000000; // 886625547612323
                                             // 2735732499
        vm.startPrank(alice);

        /// Should calc underlying amount beforehand
        uint256 poolAmount = vault.getLiquidityAmountOutFor(ONE_THOUSAND_E18, 1000e6);
        (uint256 assets0, uint256 assets1) = vault.getTokensToDeposit(poolAmount);
        console.log("assets0", assets0, "assets1", assets1);
        console.log("liq0", poolAmount);
        
        dai.approve(address(vault), assets0);
        usdc.approve(address(vault), assets1);
        
        uint256 expectedSharesFromUniLP = vault.convertToShares(poolAmount);
        uint256 aliceShareAmount = vault.deposit(poolAmount, alice);
        
        assertEq(expectedSharesFromUniLP, aliceShareAmount);
        console.log("aliceShareAmount", aliceShareAmount);

        // uint256 aliceAssetsFromShares = vault.convertToAssets(aliceShareAmount);
        // console.log("aliceAssetsFromShares", aliceAssetsFromShares);
        // vault.withdraw(aliceAssetsFromShares, alice, alice);
    }

}
