// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts@5.0.0/token/ERC20/ERC20.sol";

contract BondingCurveToken is ERC20 {
    uint256 public constant SLOPE = 0.0001 ether;
    uint256 public constant COOLDOWN_DURATION = 5 minutes;

    mapping(address => uint256) public lastTransactionTime;

    modifier tokenOwnerCooldownOver(address tokenOwner) {
        require(block.timestamp >= lastTransactionTime[tokenOwner] + COOLDOWN_DURATION, "Token owner cooldown not over");
        _;
    }

    constructor() ERC20("BondingCurveToken", "BCT") {}

    function buy(uint256 amount) external payable {
        uint256 cost = buyPriceInWei(amount);
        require(msg.value == cost, "Sent value does not equal price");

        _mint(msg.sender, amount);

        lastTransactionTime[msg.sender] = block.timestamp;
    }

    function sell(uint256 amount) external tokenOwnerCooldownOver(msg.sender) {
        require(balanceOf(msg.sender) >= amount, "Insufficient tokens to sell");

        _burn(msg.sender, amount);

        uint256 weiToReturn = sellPriceInWei(amount);
        (bool success,) = payable(msg.sender).call{value: weiToReturn}("");
        require(success, "Failed to transfer ether payout");

        lastTransactionTime[msg.sender] = block.timestamp;
    }

    function decimals() public view override returns (uint8) {
        return 0;
    }

    function transfer(address recipient, uint256 amount)
        public
        override
        tokenOwnerCooldownOver(msg.sender)
        returns (bool)
    {
        super.transfer(recipient, amount);

        lastTransactionTime[msg.sender] = block.timestamp;
        lastTransactionTime[recipient] = block.timestamp;

        return true;
    }

    function transferFrom(address sender, address recipient, uint256 amount)
        public
        override
        tokenOwnerCooldownOver(sender)
        returns (bool)
    {
        super.transferFrom(sender, recipient, amount);

        lastTransactionTime[sender] = block.timestamp;
        lastTransactionTime[recipient] = block.timestamp;

        return true;
    }

    function buyPriceInWei(uint256 amount) public view returns (uint256) {
        uint256 buyPrice = SLOPE * amount * (2 * totalSupply() + 1 + amount) / 2;
        return buyPrice;
    }

    function sellPriceInWei(uint256 amount) public view returns (uint256) {
        uint256 sellPrice = SLOPE * amount * (2 * totalSupply() + 1 - amount) / 2;
        return sellPrice;
    }
}
