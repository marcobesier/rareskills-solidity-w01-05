# BondingCurveToken

This contract implements a bonding curve token that allows users to buy and sell tokens. At any given time, the price for buying and selling tokens is determined by the bonding curve. The curve that is used in this contract is given by the equation

```solidity
y = 0.0001 ether * x + 0.0001 ether / 2
```

where `y` is the current price per unit and `x` is the number of tokens in existence. To keep things simple, the token has no decimals.

To guard against sandwich attacks, the contract implements a cooldown period of 5 minutes for the token recipient. During this period, the recipient cannot sell the tokens back, nor can the recpient or an approved account transfer tokens from the recipient's account.

## Setup

### Install Foundry

If you haven't installed Foundry yet, you can do so by following the installation instructions in the [Foundry Book](https://book.getfoundry.sh/getting-started/installation).

### Clone the Repository

Clone the repository to your local machine:

```bash
git clone https://github.com/marcobesier/rareskills-solidity-w01-04.git
```

### Install Dependencies

Install the necessary dependencies using forge:

```bash
forge install
```

This will install the Solmate contracts which are used in the GodMode contract.

## License

MIT

## Acknowledgements

This project was a practice assignment during the [RareSkills Solidity Bootcamp (Advanced)](https://www.rareskills.io/solidity-bootcamp).

A huge shout-out to Jeffrey Scholz and the RareSkills team for putting together such a great bootcamp!
