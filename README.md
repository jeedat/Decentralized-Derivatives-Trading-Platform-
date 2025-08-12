# Decentralized Derivatives Trading Platform

A comprehensive smart contract for decentralized derivatives trading on the Stacks blockchain, enabling users to create, trade, and settle financial derivatives with automated margin management and secure collateral handling.

## Overview

This smart contract provides a complete infrastructure for derivatives trading, supporting both long and short positions with automatic settlement mechanisms, robust margin management, and comprehensive access controls.

## Key Features

### Core Trading Functions
- **Position Creation**: Create long/short derivative positions with customizable parameters
- **Position Transfer**: Transfer ownership of derivative positions between users
- **Position Purchase**: Buy existing positions from creators with automatic fee handling
- **Automated Settlement**: Settle positions manually or automatically upon maturity

### Margin Management
- **Deposit/Withdraw**: Secure margin deposit and withdrawal system
- **Automatic Locking**: Smart margin locking during position creation
- **Collateral Release**: Automatic margin release upon settlement or expiry

### Security & Administration
- **Access Controls**: Role-based permissions for platform administration
- **Emergency Functions**: Platform suspension and critical mode activation
- **Fee Management**: Configurable platform commission rates

## Contract Structure

### Data Maps
- `derivatives-ledger`: Primary registry of all derivative positions
- `creator-margins`: Tracks margin balances for position creators
- `rate-feeds`: Price feed data for automated settlements

### Position States
- `state-open` (1): Active position available for trading
- `state-settled` (2): Position has been exercised/settled
- `state-matured` (3): Position expired without settlement

### Position Types
- `long-position-type` (1): Long derivative position
- `short-position-type` (2): Short derivative position

## Usage Guide

### 1. Deposit Margin
Before creating positions, deposit margin to the contract:
```clarity
(contract-call? .derivatives-contract deposit-margin u1000000) ;; 1 STX
```

### 2. Create Derivative Position
```clarity
(contract-call? .derivatives-contract create-derivative-position
  u5000000    ;; target-price (5 STX)
  u100000     ;; fee-amount (0.1 STX)
  u1000       ;; maturity-block (current + 1000 blocks)
  u1          ;; long-position-type
  u10)        ;; position-size
```

### 3. Purchase Position
```clarity
(contract-call? .derivatives-contract purchase-position u1) ;; derivative-id
```

### 4. Settle Position
For long positions:
```clarity
(contract-call? .derivatives-contract settle-long-position u1)
```

For short positions:
```clarity
(contract-call? .derivatives-contract settle-short-position u1)
```

## Platform Limits

| Parameter | Minimum | Maximum |
|-----------|---------|---------|
| Maturity Period | 144 blocks (~24 hours) | 52,560 blocks (~1 year) |
| Target Price | 1,000 μSTX (0.001 STX) | 100,000,000 μSTX (100 STX) |
| Position Size | 1 unit | 1,000,000 units |
| Platform Commission | 0% | 10% |

## Error Codes

| Code | Constant | Description |
|------|----------|-------------|
| u1000 | ERR-UNAUTHORIZED-USER | User lacks required permissions |
| u1001 | ERR-INVALID-DERIVATIVE-ID | Invalid or non-existent derivative ID |
| u1002 | ERR-DERIVATIVE-EXPIRED | Attempting to operate on expired derivative |
| u1003 | ERR-DERIVATIVE-ALREADY-SETTLED | Position already settled |
| u1004 | ERR-INSUFFICIENT-FUNDS | Insufficient balance for operation |
| u1011 | ERR-INSUFFICIENT-MARGIN | Insufficient margin for position creation |
| u1014 | ERR-PLATFORM-SUSPENDED | Platform operations suspended |

## Read-Only Functions

### Get Position Details
```clarity
(contract-call? .derivatives-contract get-derivative-details u1)
```

### Check Margin Balance
```clarity
(contract-call? .derivatives-contract get-creator-margin 'SP123...)
```

### Platform Configuration
```clarity
(contract-call? .derivatives-contract get-platform-configuration)
```

## Administrative Functions

### Platform Control
- `suspend-platform`: Pause all trading operations
- `resume-platform`: Resume normal operations
- `activate-critical-mode`: Emergency shutdown with suspension

### Fee Management
- `set-platform-commission`: Adjust platform commission rate (max 10%)

## Security Considerations

1. **Margin Requirements**: All positions require adequate margin collateral
2. **Access Controls**: Admin functions restricted to platform administrator
3. **Input Validation**: Comprehensive validation of all parameters
4. **Emergency Controls**: Multiple levels of emergency stops available
5. **Automated Settlement**: Time-based settlement prevents stuck positions

## Integration Notes

- Built for Stacks blockchain using Clarity smart contract language
- Compatible with standard STX token transfers
- Supports external price feed integration
- Designed for integration with frontend trading interfaces
