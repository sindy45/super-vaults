// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.14;

import "forge-std/Test.sol";
import {ERC20} from "solmate/tokens/ERC20.sol";
import {AaveV2StrategyWrapperNoHarvester} from "../aave-v2/AaveV2StrategyWrapperNoHarvester.sol";
import {AaveV2StrategyWrapperWithHarvester} from "../aave-v2/AaveV2StrategyWrapperWithHarvester.sol";
import {IMultiFeeDistribution} from "../utils/aave/IMultiFeeDistribution.sol";
import {ILendingPool} from "../utils/aave/ILendingPool.sol";

import {Harvester} from "../utils/harvest/Harvester.sol";

contract AaveV2StrategyWrapperTest is Test {
    uint256 public ethFork;
    uint256 public ftmFork;

    string ETH_RPC_URL = vm.envString("ETH_MAINNET_RPC");
    string FTM_RPC_URL = vm.envString("FTM_MAINNET_RPC");

    AaveV2StrategyWrapperNoHarvester public vault;
    AaveV2StrategyWrapperWithHarvester public vaultHarvester;

    Harvester public harvester;

    /// Fantom's Geist Forked AAVE-V2 Protocol DAI Pool Config
    ERC20 public underlying = ERC20(0x8D11eC38a3EB5E956B052f67Da8Bdc9bef8Abf3E); /// DAI
    ERC20 public aToken = ERC20(0x07E6332dD090D287d3489245038daF987955DCFB); // gDAI
    IMultiFeeDistribution public rewards =
        IMultiFeeDistribution(0x49c93a95dbcc9A6A4D8f77E59c038ce5020e82f8);
    ILendingPool public lendingPool =
        ILendingPool(0x9FAD24f572045c7869117160A571B2e50b10d068);
    address rewardToken = 0xd8321AA83Fb0a4ECd6348D4577431310A6E0814d;

    function setUp() public {
        ftmFork = vm.createFork(FTM_RPC_URL);
        address manager = msg.sender;
        console.log("manager", manager);
        vm.selectFork(ftmFork);

        vault = new AaveV2StrategyWrapperNoHarvester(
            underlying,
            aToken,
            rewards,
            lendingPool,
            rewardToken,
            manager
        );

        address swapToken = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83; /// FTM
        address swapPair1 = 0x668AE94D0870230AC007a01B471D02b2c94DDcB9; /// Geist - Ftm
        address swapPair2 = 0xe120ffBDA0d14f3Bb6d6053E90E63c572A66a428; /// Ftm - Dai
        vm.prank(manager);

        vault.setRoute(swapToken, swapPair1, swapPair2);

        /// Simulate rewards accrued to the vault contract
        deal(rewardToken, address(vault), 1000 ether);
    }

    function setUpWithHarvester() public {
        ftmFork = vm.createFork(FTM_RPC_URL);
        address manager = msg.sender;
        vm.selectFork(ftmFork);

        vaultHarvester = new AaveV2StrategyWrapperWithHarvester(
            underlying,
            aToken,
            rewards,
            lendingPool,
            rewardToken,
            manager
        );

        harvester = new Harvester(
            manager
        );

        vm.makePersistent(address(harvester));

        vm.startPrank(manager);
        vaultHarvester.enableHarvest(harvester);

        address swapToken = 0x21be370D5312f44cB42ce377BC9b8a0cEF1A4C83; /// FTM
        address swapPair1 = 0x668AE94D0870230AC007a01B471D02b2c94DDcB9; /// Geist - Ftm
        address swapPair2 = 0xe120ffBDA0d14f3Bb6d6053E90E63c572A66a428; /// Ftm - Dai
        
        harvester.setVault(vaultHarvester, ERC20(rewardToken));
        harvester.setRoute(swapToken, swapPair1, swapPair2);

        vm.stopPrank();
        /// Simulate rewards accrued to the vault contract
        deal(rewardToken, address(vaultHarvester), 1000 ether);
    }

    function makeDeposit() public returns (uint256 shares) {
        address alice = address(0x1cA60862a771f1F47d94F87bebE4226141b19C9c);
        vm.startPrank(alice);
        uint256 amount = 100 ether;

        uint256 aliceUnderlyingAmount = amount;

        underlying.approve(address(vault), aliceUnderlyingAmount);
        assertEq(
            underlying.allowance(alice, address(vault)),
            aliceUnderlyingAmount
        );

        shares = vault.deposit(aliceUnderlyingAmount, alice);
        vm.stopPrank();
    }

    function testSingleDepositWithdraw() public {
        address alice = address(0x1cA60862a771f1F47d94F87bebE4226141b19C9c);
        vm.startPrank(alice);

        uint256 amount = 100 ether;

        uint256 aliceUnderlyingAmount = amount;

        underlying.approve(address(vault), aliceUnderlyingAmount);
        assertEq(
            underlying.allowance(alice, address(vault)),
            aliceUnderlyingAmount
        );

        uint256 alicePreDepositBal = underlying.balanceOf(alice);
        uint256 aliceShareAmount = vault.deposit(aliceUnderlyingAmount, alice);

        // Expect exchange rate to be 1:1 on initial deposit.
        assertEq(aliceUnderlyingAmount, aliceShareAmount);
        assertEq(
            vault.previewWithdraw(aliceShareAmount),
            aliceUnderlyingAmount
        );
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceShareAmount);
        assertEq(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceUnderlyingAmount
        );
        assertEq(
            underlying.balanceOf(alice),
            alicePreDepositBal - aliceUnderlyingAmount
        );

        vault.withdraw(aliceUnderlyingAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(underlying.balanceOf(alice), alicePreDepositBal);
    }

    function testSingleMintRedeem() public {
        address alice = address(0x1cA60862a771f1F47d94F87bebE4226141b19C9c);
        vm.startPrank(alice);

        uint256 amount = 100 ether;

        uint256 aliceShareAmount = amount;

        underlying.approve(address(vault), aliceShareAmount);
        assertEq(underlying.allowance(alice, address(vault)), aliceShareAmount);

        uint256 alicePreDepositBal = underlying.balanceOf(alice);

        uint256 aliceUnderlyingAmount = vault.mint(aliceShareAmount, alice);

        // Expect exchange rate to be 1:1 on initial mint.
        assertEq(aliceShareAmount, aliceUnderlyingAmount);
        assertEq(
            vault.previewWithdraw(aliceShareAmount),
            aliceUnderlyingAmount
        );
        assertEq(vault.previewDeposit(aliceUnderlyingAmount), aliceShareAmount);
        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), aliceUnderlyingAmount);
        assertEq(vault.balanceOf(alice), aliceUnderlyingAmount);
        assertEq(
            vault.convertToAssets(vault.balanceOf(alice)),
            aliceUnderlyingAmount
        );
        assertEq(
            underlying.balanceOf(alice),
            alicePreDepositBal - aliceUnderlyingAmount
        );

        vault.redeem(aliceShareAmount, alice, alice);

        assertEq(vault.totalAssets(), 0);
        assertEq(vault.balanceOf(alice), 0);
        assertEq(vault.convertToAssets(vault.balanceOf(alice)), 0);
        assertEq(underlying.balanceOf(alice), alicePreDepositBal);
    }

    function testWithoutHarvester() public {
        uint256 aliceShareAmount = makeDeposit();

        assertEq(vault.totalSupply(), aliceShareAmount);
        assertEq(vault.totalAssets(), 100 ether);
        console.log("totalAssets before harvest", vault.totalAssets());

        assertEq(ERC20(rewardToken).balanceOf(address(vault)), 1000 ether);
        vault.harvest();
        assertEq(ERC20(rewardToken).balanceOf(address(vault)), 0);
        console.log("totalAssets after harvest", vault.totalAssets());
    }

}
