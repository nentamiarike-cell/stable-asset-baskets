# Stable Asset Baskets 🗂️

A decentralized smart contract system for creating and managing stable tokens pegged to multiple commodities. The Stable Asset Baskets protocol allows users to mint tokens backed by a diversified basket of commodity assets, providing enhanced stability and reduced volatility compared to single-asset pegged tokens.

## Overview

The Stable Asset Baskets system consists of two main smart contracts:

1. **Basket Manager**: Manages the creation and configuration of commodity baskets, handles asset weights and pricing.
2. **Stable Token**: Implements the SIP-010 fungible token standard for the stable tokens backed by commodity baskets.

## Key Features

- **Multi-Commodity Pegging**: Tokens are backed by a basket of multiple commodities (gold, silver, oil, wheat, etc.)
- **Dynamic Weight Adjustment**: Basket composition can be adjusted to maintain stability
- **Collateralization**: Users must provide collateral to mint stable tokens
- **Price Oracle Integration**: Uses external price feeds for accurate commodity pricing
- **Governance Controls**: Administrative functions for system management
- **Liquidity Pool Support**: Integration with liquidity providers for enhanced stability

## System Architecture

### Basket Manager Contract
- Manages commodity basket configurations
- Handles collateral requirements and ratios
- Provides price aggregation from multiple commodities
- Controls minting and burning operations
- Manages administrative functions

### Stable Token Contract
- SIP-010 compliant fungible token
- Handles token minting based on collateral provided
- Manages token burning and collateral redemption
- Tracks user balances and allowances
- Provides transfer and approval functionality

## Commodity Support

The system supports the following commodity types:
- Precious Metals (Gold, Silver, Platinum)
- Energy (Crude Oil, Natural Gas)
- Agricultural (Wheat, Corn, Soybeans)
- Industrial Metals (Copper, Aluminum)

## Usage

### Minting Stable Tokens
1. Provide STX collateral to the system
2. System calculates the current basket value based on commodity prices
3. Mint stable tokens proportional to the collateral provided

### Redeeming Tokens
1. Burn stable tokens to retrieve collateral
2. System calculates the current redemption value
3. Returns STX collateral minus any fees

### Managing Baskets
1. Admin can update commodity weights in the basket
2. Add or remove supported commodities
3. Adjust collateralization ratios for risk management

## Security Features

- Multi-signature administrative controls
- Collateralization requirements to prevent under-collateralized positions
- Emergency pause functionality
- Rate limiting on large operations
- Input validation and overflow protection

## Development

This project is built using the Clarinet development environment for Stacks blockchain smart contracts.

### Prerequisites
- Clarinet CLI
- Node.js and npm
- Stacks wallet for testing

### Installation
```bash
git clone <repository-url>
cd stable-asset-baskets
npm install
```

### Testing
```bash
npm test
clarinet check
```

### Deployment
The contracts can be deployed to the Stacks blockchain using Clarinet's deployment tools.

## Contributing

Contributions are welcome! Please ensure all contracts pass `clarinet check` and include appropriate tests.

## License

This project is open source and available under the MIT License.
