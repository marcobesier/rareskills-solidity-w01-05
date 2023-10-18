// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {BondingCurveToken} from "../src/BondingCurveToken.sol";

contract BondingCurveTokenTest is Test {
    BondingCurveToken public bondingCurveToken;
    address public user1;
    address public user2;
    uint256 public constant COOLDOWN_DURATION = 5 minutes;

    event Buy(address indexed buyer, uint256 amount, uint256 paidInWei, uint256 costInWei, uint256 changeInWei);
    event Sell(address indexed seller, uint256 amount, uint256 payoutInWei);

    error TokenOwnerCooldownNotOverYet(uint256 timeSinceLastTransaction, uint256 cooldownDuration);
    error SentValueNotSufficient(uint256 sentValue, uint256 price);
    error InsufficientTokensToSell(uint256 balance, uint256 amount);
    error FailedToTransferChange();
    error FailedToTransferPayout();

    function setUp() public {
        user1 = address(0x123);
        user2 = address(0x456);
        bondingCurveToken = new BondingCurveToken("BondingCurveToken", "BCT");
    }

    receive() external payable {
        revert("This contract should not receive ether");
    }

    function test_Buy() public {
        // NOTE: buyPriceInWei runs into an overflow/underflow if passed
        // amount = 34028236692093846346337460743177 during fuzzing
        //
        // NOTE: amount >= 39806573 leads to test contract not having enough ether balance to buy the tokens
        uint256 cost = bondingCurveToken.buyPriceInWei(39806572);
        bondingCurveToken.buy{value: cost}(39806572);
        assertEq(bondingCurveToken.balanceOf(address(this)), 39806572);
    }

    function test_RevertsIfSentValueIsNotSufficient() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.expectRevert(abi.encodeWithSelector(SentValueNotSufficient.selector, cost - 1, cost));
        bondingCurveToken.buy{value: cost - 1}(100);
    }

    function test_UpdatesLastTransactionTimeOfBuyer() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        assertEq(bondingCurveToken.lastTransactionTime(address(this)), block.timestamp);
    }

    function test_BuyEvent() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.expectEmit();
        emit Buy(address(this), 100, cost, cost, 0);
        bondingCurveToken.buy{value: cost}(100);
    }

    function test_TransfersChangeToBuyer() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.deal(user1, cost + 1);
        vm.prank(user1);
        bondingCurveToken.buy{value: cost + 1}(100);
        assertEq(user1.balance, 1);
    }

    function test_RevertsIfChangeTransferFails() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.expectRevert(abi.encodeWithSelector(FailedToTransferChange.selector));
        bondingCurveToken.buy{value: cost + 1}(100);
    }

    function test_Sell() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.startPrank(user1);
        vm.deal(user1, cost);
        bondingCurveToken.buy{value: cost}(100);
        vm.warp(5 minutes + 1 seconds);
        bondingCurveToken.sell(60);
        assertEq(bondingCurveToken.balanceOf(user1), 40);
    }

    function test_RevertsIfCooldownIsNotCompleted() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.startPrank(user1);
        vm.deal(user1, cost);
        bondingCurveToken.buy{value: cost}(100);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenOwnerCooldownNotOverYet.selector,
                block.timestamp - bondingCurveToken.lastTransactionTime(user1),
                COOLDOWN_DURATION
            )
        );
        bondingCurveToken.sell(60);
    }

    function test_RevertsIfUserTriesToSellMoreThanSheOwns() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.startPrank(user1);
        vm.deal(user1, cost);
        bondingCurveToken.buy{value: cost}(100);
        vm.warp(5 minutes + 1 seconds);
        vm.expectRevert(abi.encodeWithSelector(InsufficientTokensToSell.selector, 100, 101));
        bondingCurveToken.sell(101);
    }

    function test_SellEvent() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        vm.startPrank(user1);
        vm.deal(user1, cost);
        bondingCurveToken.buy{value: cost}(100);
        vm.warp(5 minutes + 1 seconds);
        uint256 payout = bondingCurveToken.sellPriceInWei(60);
        vm.expectEmit();
        emit Sell(user1, 60, payout);
        bondingCurveToken.sell(60);
    }

    function test_RevertsIfPayoutTransferFails() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        vm.warp(5 minutes + 1 seconds);
        vm.expectRevert(abi.encodeWithSelector(FailedToTransferPayout.selector));
        bondingCurveToken.sell(60);
    }

    function test_ReturnsCorrectDecimals() public {
        assertEq(bondingCurveToken.decimals(), 0);
    }

    function test_Transfer() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        vm.warp(5 minutes + 1 seconds);
        bondingCurveToken.transfer(user1, 60);
        assertEq(bondingCurveToken.balanceOf(address(this)), 40);
        assertEq(bondingCurveToken.balanceOf(user1), 60);
    }

    function test_TransferRevertsIfCooldownIsNotCompleted() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenOwnerCooldownNotOverYet.selector,
                block.timestamp - bondingCurveToken.lastTransactionTime(address(this)),
                COOLDOWN_DURATION
            )
        );
        bondingCurveToken.transfer(user1, 60);
    }

    function test_TransferUpdatesLastTransactionTimeOfRecipient() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        vm.warp(5 minutes + 1 seconds);
        bondingCurveToken.transfer(user1, 60);
        assertEq(bondingCurveToken.lastTransactionTime(user1), block.timestamp);
    }

    function test_TransferFrom() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        vm.warp(5 minutes + 1 seconds);
        bondingCurveToken.approve(user1, 60);
        vm.prank(user1);
        bondingCurveToken.transferFrom(address(this), user1, 60);
        assertEq(bondingCurveToken.balanceOf(address(this)), 40);
        assertEq(bondingCurveToken.balanceOf(user1), 60);
    }

    function test_TransferFromRevertsIfCooldownIsNotCompleted() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        bondingCurveToken.approve(user1, 60);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenOwnerCooldownNotOverYet.selector,
                block.timestamp - bondingCurveToken.lastTransactionTime(address(this)),
                COOLDOWN_DURATION
            )
        );
        vm.prank(user1);
        bondingCurveToken.transferFrom(address(this), user1, 60);
    }

    function test_TransferFromUpdatesLastTransactionTimeOfRecipient() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(100);
        bondingCurveToken.buy{value: cost}(100);
        bondingCurveToken.approve(user1, 60);
        vm.warp(5 minutes + 1 seconds);
        vm.prank(user1);
        bondingCurveToken.transferFrom(address(this), user1, 60);
        assertEq(bondingCurveToken.lastTransactionTime(user1), block.timestamp);
    }

    function test_BuyPriceInWei() public {
        assertEq(bondingCurveToken.buyPriceInWei(2), 3 * 0.0001 ether);
    }

    function test_SellPriceInWei() public {
        uint256 cost = bondingCurveToken.buyPriceInWei(2);
        bondingCurveToken.buy{value: cost}(2);
        assertEq(bondingCurveToken.sellPriceInWei(1), 2 * 0.0001 ether);
    }
}
