// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import {ERC20} from "@openzeppelin/contracts@5.0.0/token/ERC20/ERC20.sol";

/**
 * @title Bonding Curve Token
 * @author Marco Besier
 * @dev This contract implements a bonding curve token that allows users to buy and sell tokens. At any given time,
 * the price for buying and selling tokens is determined by the bonding curve.
 * The curve that is used in this contract is given by the equation
 *     y = 0.0001 ether * x + 0.0001 ether / 2
 * where y is the current price per unit and x is the number of tokens in existence.
 * To keep things simple, the token has no decimals.
 */
contract BondingCurveToken is ERC20 {
    // SLOPE needs to be a multiple of 2 wei to avoid rounding errors in buyPriceInWei and sellPriceInWei
    // due to the division by 2 at the end of the respective formula.
    uint256 public constant SLOPE = 0.0001 ether;
    uint256 public constant COOLDOWN_DURATION = 5 minutes;

    mapping(address => uint256) public lastTransactionTime;

    event Buy(address indexed buyer, uint256 amount, uint256 paidInWei, uint256 costInWei, uint256 changeInWei);
    event Sell(address indexed seller, uint256 amount, uint256 payoutInWei);

    error TokenOwnerCooldownNotOverYet(uint256 timeSinceLastTransaction, uint256 cooldownDuration);
    error SentValueNotSufficient(uint256 sentValue, uint256 price);
    error InsufficientTokensToSell(uint256 balance, uint256 amount);
    error FailedToTransferChange();
    error FailedToTransferPayout();

    // Ensures that the token owners have to wait at least COOLDOWN_DURATION since the last transaction in which they
    // received tokens. This is to prevent users from executing sandwich attacks.
    // See here: https://medium.com/coinmonks/defi-sandwich-attack-explain-776f6f43b2fd
    modifier tokenOwnerCooldownOver(address tokenOwner) {
        uint256 timeSinceLastTransaction = block.timestamp - lastTransactionTime[tokenOwner];
        if (timeSinceLastTransaction < COOLDOWN_DURATION) {
            revert TokenOwnerCooldownNotOverYet(timeSinceLastTransaction, COOLDOWN_DURATION);
        }
        _;
    }

    constructor(string memory name, string memory symbol) ERC20(name, symbol) {}

    /**
     * @dev Allows users to buy `amount` tokens by sending an `msg.value` to the contract that is equal or greater than
     * the price that's given by buyPriceInWei.
     * If the sent value is not sufficient to cover the cost, the transaction is reverted.
     * The tokens are minted to the `msg.sender` address, and the lastTransactionTime
     * is updated for that address.
     * If there is any change in wei after the purchase, it is transferred back to the
     * `msg.sender` address.
     * Emits a {Buy} event with the buyer's address, the amount of tokens bought, the
     * sent value in wei, the cost in wei, and the change in wei.
     * @param amount The amount of tokens to buy.
     */
    function buy(uint256 amount) external payable {
        uint256 costInWei = buyPriceInWei(amount);

        if (msg.value < costInWei) {
            revert SentValueNotSufficient(msg.value, costInWei);
        }

        _mint(msg.sender, amount);

        lastTransactionTime[msg.sender] = block.timestamp;

        uint256 changeInWei = msg.value - costInWei;

        emit Buy(msg.sender, amount, msg.value, costInWei, changeInWei);

        if (changeInWei != 0) {
            (bool success,) = payable(msg.sender).call{value: changeInWei}("");
            if (!success) {
                revert FailedToTransferChange();
            }
        }
    }

    /**
     * @dev Allows users to sell `amount` tokens. The caller must have at least `amount` tokens.
     * The tokens are burned and the caller receives a payout in Ether, calculated using sellPriceInWei.
     * The payout is transferred to the caller's address.
     * Emits a {Sell} event.
     *
     * Requirements:
     * - The caller must have at least `amount` tokens.
     * - The cooldown period for caller must have passed.
     *
     * @param amount The amount of tokens to sell.
     */
    function sell(uint256 amount) external tokenOwnerCooldownOver(msg.sender) {
        if (balanceOf(msg.sender) < amount) {
            revert InsufficientTokensToSell(balanceOf(msg.sender), amount);
        }

        uint256 payoutInWei = sellPriceInWei(amount);

        // Note that it's crucial to burn the tokens only AFTER the price has been computed since the price
        // formula depends on the total supply.
        _burn(msg.sender, amount);

        emit Sell(msg.sender, amount, payoutInWei);

        (bool success,) = payable(msg.sender).call{value: payoutInWei}("");
        if (!success) {
            revert FailedToTransferPayout();
        }
    }

    /**
     * @dev Overrides OpenZeppelin's default ERC20 decimals function to return 0 for the sake of simplicity.
     * @return 0 as the number of decimals.
     */
    function decimals() public pure override returns (uint8) {
        return 0;
    }

    /**
     * @dev Overrides OpenZeppelin's default ERC20 transfer function to add an additional check
     * for the cooldown period and update the recepient's lastTransactionTime.
     *
     * Requirements:
     * - The cooldown period for caller must have passed.
     *
     * @param recipient The address of the recipient.
     * @param amount The amount of tokens to transfer.
     * @return A boolean value indicating whether the transfer was successful.
     */
    function transfer(address recipient, uint256 amount)
        public
        override
        tokenOwnerCooldownOver(msg.sender)
        returns (bool)
    {
        lastTransactionTime[recipient] = block.timestamp;

        return super.transfer(recipient, amount);
    }

    /**
     * @dev Overrides OpenZeppelin's default ERC20 transferFrom function to add an additional check
     * for the cooldown period and update the recepient's lastTransactionTime.
     *
     * Requirements:
     * - The cooldown period for sender must have passed.
     */
    function transferFrom(address sender, address recipient, uint256 amount)
        public
        override
        tokenOwnerCooldownOver(sender)
        returns (bool)
    {
        lastTransactionTime[recipient] = block.timestamp;

        return super.transferFrom(sender, recipient, amount);
    }

    /**
     * @notice Users can call this function to determine the buy price in wei for a given amount of tokens.
     * Since other users might submit transactions in between the call to this function and the actual buy, the price
     * that the user ends up paying might be higher than the one returned by this function. However, the user can
     * conveniently determine the minimum price that they will have to pay by calling this function, and specify the
     * sent value accordingly.
     * @dev Calculates the buy price in wei for a given amount of tokens. The price is determined as follows:
     * First, compute the poolBalance(x) as the antiderivative of the bonding curve function y(x).
     * The result is poolBalance(x) = SLOPE * x^2 / 2 + x * SLOPE / 2.
     * Second, compute the buyPriceInWei via
     *     buyPriceInWei(amount) = poolBalance(amount + totalSupply) - poolBalance(totalSupply).
     * Lastly, simplify the formula to get the one below.
     * @param amount The amount of tokens to calculate the buy price for.
     * @return The buy price in wei.
     */
    function buyPriceInWei(uint256 amount) public view returns (uint256) {
        uint256 buyPrice = SLOPE * amount * (2 * totalSupply() + 1 + amount) / 2;
        return buyPrice;
    }

    /**
     * @notice Users can call this function to determine the sell price in wei for a given amount of tokens.
     * Since other users might submit transactions in between the call to this function and the actual sell, the price
     * that the user ends up receiving might be lower than the one returned by this function. However, the user can
     * conveniently determine the maximum price that they will receive by calling this function.
     * @dev Calculates the sell price in wei based on the amount of tokens being sold. The price is determined as
     * follows:
     *     sellPriceInWei(amount) = - buyPriceInWei(- amount)
     * Notice that the first minus sign is due to the fact that, strictly speaking, the sell price that we compute
     * via buyPriceInWei(- amount) yields a negative number. However, since we want to work with the uint256 data type,
     * we need to negate the result of buyPriceInWei(- amount).
     * @param amount The amount of tokens being sold.
     * @return The sell price of the token in wei.
     */
    function sellPriceInWei(uint256 amount) public view returns (uint256) {
        uint256 sellPrice = SLOPE * amount * (2 * totalSupply() + 1 - amount) / 2;
        return sellPrice;
    }
}
