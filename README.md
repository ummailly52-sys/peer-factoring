# Peer Factoring Smart Contract System

A decentralized peer-to-peer invoice factoring platform built on the Stacks blockchain using Clarity smart contracts.

## Overview

This smart contract system enables businesses to sell their unpaid invoices to investors, providing immediate liquidity while allowing investors to earn returns by purchasing receivables at a discount.

## Key Features

### For Businesses (Invoice Sellers)
- **Submit Invoices**: Upload invoice details including amount, due date, and debtor information
- **Set Discount Rates**: Define the discount percentage they're willing to accept
- **Receive Immediate Payment**: Get paid instantly when an investor purchases the invoice
- **Track Status**: Monitor invoice status from submission to collection

### For Investors (Invoice Buyers)
- **Browse Opportunities**: View available invoices with risk assessments
- **Purchase Invoices**: Buy invoices at discounted rates
- **Collect Payments**: Receive full invoice amount when debtors pay
- **Portfolio Management**: Track invested amounts and expected returns

### Smart Contract Features
- **Automated Escrow**: Secure handling of funds during transactions
- **Time-based Logic**: Automatic handling of overdue invoices
- **Dispute Resolution**: Built-in mechanisms for handling payment disputes
- **Fee Management**: Transparent platform fee structure

## How It Works

1. **Invoice Submission**: Business submits invoice details and desired discount rate
2. **Investor Review**: Investors browse and evaluate available invoices
3. **Purchase Transaction**: Investor purchases invoice, funds transferred to business
4. **Payment Collection**: When debtor pays, full amount goes to invoice owner (investor)
5. **Dispute Handling**: If payment is overdue, dispute resolution mechanisms activate

## Contract Architecture

The system consists of two main smart contracts:

- **`invoice-manager`**: Handles invoice creation, management, and basic operations
- **`peer-factoring`**: Core factoring logic, investor matching, and payment processing

## Security Features

- Multi-signature requirements for high-value transactions
- Time-locked escrow for secure fund handling
- Role-based access control
- Automatic refund mechanisms for failed transactions

## Getting Started

### Prerequisites
- Clarinet CLI installed
- Stacks wallet with STX tokens
- Node.js for running tests

### Installation

```bash
# Clone the repository
git clone <repository-url>
cd peer-factoring

# Install dependencies
npm install

# Check contract syntax
clarinet check

# Run tests
npm test
```

### Deployment

```bash
# Deploy to devnet
clarinet deploy --devnet

# Deploy to testnet
clarinet deploy --testnet
```

## Usage Examples

### Submitting an Invoice (Business)
```clarity
(contract-call? .peer-factoring submit-invoice 
  u100000    ;; amount in microSTX
  u30        ;; days until due
  u15        ;; discount rate (15%)
  "Invoice #12345")
```

### Purchasing an Invoice (Investor)
```clarity
(contract-call? .peer-factoring purchase-invoice 
  u1         ;; invoice ID
  u85000)    ;; purchase amount (after discount)
```

## Contract Functions

### Core Functions
- `submit-invoice`: Submit new invoice for factoring
- `purchase-invoice`: Buy an available invoice
- `collect-payment`: Process debtor payment
- `resolve-dispute`: Handle payment disputes
- `calculate-discount`: Determine discounted purchase price

### Query Functions
- `get-invoice`: Retrieve invoice details
- `get-available-invoices`: List purchasable invoices
- `get-investor-portfolio`: View investor's invoice holdings
- `get-platform-stats`: System-wide statistics

## Risk Management

- Invoice verification processes
- Debtor creditworthiness assessment
- Maximum investment limits per investor
- Diversification requirements
- Automated risk scoring

## Platform Economics

- **Platform Fee**: 2.5% of transaction value
- **Minimum Invoice Amount**: 1,000 STX
- **Maximum Discount Rate**: 25%
- **Payment Grace Period**: 7 days after due date

## Development

### Running Tests
```bash
# Run all tests
npm test

# Run specific test suite
npm test -- --grep "invoice-manager"
```

### Contract Validation
```bash
# Check syntax
clarinet check

# Analyze contracts
clarinet analyze
```

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Ensure all tests pass
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Disclaimer

This software is provided as-is for educational and demonstration purposes. Users should conduct thorough testing and security audits before deploying to mainnet or using with real funds.

## Support

For questions, issues, or contributions, please open an issue on GitHub or contact the development team.
