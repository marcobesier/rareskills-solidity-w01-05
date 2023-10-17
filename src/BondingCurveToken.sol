// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts@5.0.0/token/ERC20/ERC20.sol";

contract BondingCurveToken is ERC20 {
    uint256 public constant SLOPE = 0.0001 ether;
    uint256 public constant COOLDOWN_DURATION = 5 minutes;

    mapping(address => uint256) public lastTransactionTime;

    event Buy(address indexed buyer, uint256 amount, uint256 cost);
    event Sell(address indexed seller, uint256 amount, uint256 payout);

    error TokenOwnerCooldownNotOverYet(uint256 timeSinceLastTransaction, uint256 cooldownDuration);
    error SentValueDoesNotEqualPrice(uint256 sentValue, uint256 price);
    error InsufficientTokensToSell(uint256 balance, uint256 amount);
    error FailedToTransferEtherPayout();

    modifier tokenOwnerCooldownOver(address tokenOwner) {
        uint256 timeSinceLastTransaction = block.timestamp - lastTransactionTime[tokenOwner];
        if (timeSinceLastTransaction < COOLDOWN_DURATION) {
            revert TokenOwnerCooldownNotOverYet(timeSinceLastTransaction, COOLDOWN_DURATION);
        }
        _;
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    function buy(uint256 amount) external payable {
        uint256 cost = buyPriceInWei(amount);

        if (msg.value != cost) {
            revert SentValueDoesNotEqualPrice(msg.value, cost);
        }

        _mint(msg.sender, amount);

        lastTransactionTime[msg.sender] = block.timestamp;

        emit Buy(msg.sender, amount, cost);
    }

    function sell(uint256 amount) external tokenOwnerCooldownOver(msg.sender) {
        if (balanceOf(msg.sender) < amount) {
            revert InsufficientTokensToSell(balanceOf(msg.sender), amount);
        }

        uint256 weiToReturn = sellPriceInWei(amount);

        // Note that it's crucial to burn the tokens only AFTER the price has been computed since the price
        // formula depends on the total supply.
        _burn(msg.sender, amount);

        lastTransactionTime[msg.sender] = block.timestamp;

        emit Sell(msg.sender, amount, weiToReturn);

        (bool success,) = payable(msg.sender).call{value: weiToReturn}("");
        if (!success) {
            revert FailedToTransferEtherPayout();
        }
    }

    function decimals() public pure override returns (uint8) {
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
