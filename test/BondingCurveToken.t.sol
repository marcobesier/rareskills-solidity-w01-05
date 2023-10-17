// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {BondingCurveToken} from "../src/BondingCurveToken.sol";

contract BondingCurveTokenTest is Test {
    BondingCurveToken public bondingCurveToken;
    address public user1;
    address public user2;

    event Buy(address indexed buyer, uint256 amount, uint256 cost);
    event Sell(address indexed seller, uint256 amount, uint256 payout);

    error TokenOwnerCooldownNotOverYet(uint256 timeSinceLastTransaction, uint256 cooldownDuration);
    error SentValueDoesNotEqualPrice(uint256 sentValue, uint256 price);
    error InsufficientTokensToSell(uint256 balance, uint256 amount);
    error FailedToTransferEtherPayout();

    function setUp() public {
        user1 = address(0x123);
        user2 = address(0x456);
        bondingCurveToken = new BondingCurveToken("BondingCurveToken", "BCT");
    }
}
