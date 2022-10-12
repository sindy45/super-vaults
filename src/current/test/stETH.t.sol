// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import {StETHERC4626} from "../eth-staking/stETH.sol";
import {FixedPointMathLib} from "solmate/utils/FixedPointMathLib.sol";

interface IStETH {
    function getTotalShares() external view returns (uint256);

    function submit(address) external payable returns (uint256);

    function burnShares(address, uint256) external returns (uint256);

    function approve(address, uint256) external returns (bool);

    function sharesOf(address) external view returns (uint256);

    function getPooledEthByShares(uint256) external view returns (uint256);

    function balanceOf(address) external returns (uint256);
}

interface wstETH {
    function wrap(uint256) external returns (uint256);

    function unwrap(uint256) external returns (uint256);

    function getStETHByWstETH(uint256) external view returns (uint256);

    function balanceOf(address) external view returns (uint256);
}

interface IWETH {
    function approve(address, uint256) external returns (bool);

    function balanceOf(address) external returns (uint256);

    function allowance(address, address) external returns (uint256);

    function wrap(uint256) external payable returns (uint256);

    function unwrap(uint256) external returns (uint256);
}

interface ICurve {
    function exchange(
        int128,
        int128,
        uint256,
        uint256
    ) external returns (uint256);

    function get_dy(
        int128,
        int128,
        uint256
    ) external view returns (uint256);
}


contract stEthTest is Test {
    uint256 public ethFork;
    uint256 public immutable ONE_THOUSAND_E18 = 1000 ether;
    uint256 public immutable HUNDRED_E18 = 100 ether;

    using FixedPointMathLib for uint256;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");

    StETHERC4626 public vault;

    address public weth = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    address public stEth = 0xae7ab96520DE3A18E5e111B5EaAb095312D7fE84;
    address public wstEth = 0x7f39C581F595B53c5cb19bD0b3f8dA6c935E2Ca0;
    address public curvePool = 0xDC24316b9AE028F1497c275EB9192a3Ea0f67022;

    address public alice;
    address public manager;

    IWETH public _weth = IWETH(weth);
    IStETH public _stEth = IStETH(stEth);
    wstETH public _wstEth = wstETH(wstEth);
    ICurve public _curvePool = ICurve(curvePool);

    function setUp() public {
        ethFork = vm.createFork(ETH_RPC_URL);
        vm.selectFork(ethFork);

        vault = new StETHERC4626(weth, stEth, wstEth);
        alice = address(0x1);
        manager = msg.sender;

        /// Seed Vault with init deposit() to hack around rebasing stEth <> wstEth underlying
        /// wstEth balance on first deposit() is zero, user gets 100 shares, equal 1:1 with underlying
        deal(weth, alice, ONE_THOUSAND_E18);
        deal(weth, manager, ONE_THOUSAND_E18);

        // vm.prank(manager);
        // _weth.approve(address(vault), 1 ether);

        // vm.prank(manager);
        // vault.deposit(1 ether, manager);
    }

    // function testDepositWithdraw() public {
    //     uint256 aliceUnderlyingAmount = HUNDRED_E18;

    //     vm.prank(alice);
    //     _weth.approve(address(vault), aliceUnderlyingAmount);
    //     assertEq(_weth.allowance(alice, address(vault)), aliceUnderlyingAmount);

    //     vm.prank(alice);
    //     uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);
    //     console.log("aliceShareAmount", aliceShareAmount);
    //     uint256 aliceAssetsFromShares = vault.convertToAssets(aliceShareAmount);
    //     console.log("aliceAssetsFromShares", aliceAssetsFromShares);

    //     vm.prank(alice);
    //     // / This returns 99.06 from 100 eth deposited
    //     vault.withdraw(aliceAssetsFromShares, alice, alice);
    // }

    function testPureSteth() public {
        //   deposit shares 1000000000000000000
        //   eth balance deposit 6656000000000000000
        //   ethAmount aD 1000000000000000000
        //   stEthAmount aD 917486753626076131
        //   wstEthAmount aD 841781943079316122

        //   deposit shares 118795610694844273761
        //   eth balance deposit 105656000000000000000
        //   ethAmount aD 100000000000000000000
        //   stEthAmount aD 91748675362607613147
        //   wstEthAmount aD 84178194307931612337
        //   aliceShareAmount 118795610694844273761
        //   aliceAssetsFromShares 84310267641840075158

        vm.startPrank(alice);

        uint256 stEthAmount = _stEth.submit{value: 1 ether}(alice);
        uint256 sharesOfAmt = _stEth.sharesOf(alice);
        uint256 ethFromStEth = _stEth.getPooledEthByShares(sharesOfAmt);
        uint256 balanceOfStEth = _stEth.balanceOf(alice);

        /// Works! It's curve swap which needs solving... 

        console.log("sharesOfAmt", sharesOfAmt); /// <= This equals SHARES, not amount of stETH (rebasing)
        console.log("ethFromStEth", ethFromStEth);
        console.log("balanceOfStEth", balanceOfStEth); /// <= This is actual number of tokens held (and transferable)

        _stEth.approve(wstEth, stEthAmount);
        uint256 wstEthAmount = _wstEth.wrap(stEthAmount);

        console.log("stEthAmount", stEthAmount);
        console.log("wstEthAmount", wstEthAmount);

        stEthAmount = _wstEth.unwrap(wstEthAmount);
        console.log("stEthAmount unwraped", stEthAmount);

        _stEth.approve(address(curvePool), balanceOfStEth);

        uint256 min_dy = (_curvePool.get_dy(1, 0, balanceOfStEth) * 9900) / 10000; /// 1% slip
        console.log("min dy", min_dy);
        /// 1 = 0xEeE, 0 = stEth
        uint256 amount = _curvePool.exchange(1, 0, balanceOfStEth, min_dy);
        console.log("curve amount", amount);

        //   shares withdraw 118795610694844273761
        //   stEthAmount bW 91892626578673114639
        //   amount 91423768717583208551
        //   eth balance withdraw 97079768717583208551

        //   deposit shares 1000000000000000000
        //   eth balance deposit 6656000000000000000
        //   ethAmount aD 1000000000000000000
        //   stEthAmount aD 917486753626076131
        //   wstEthAmount aD 841781943079316122
    }
}
