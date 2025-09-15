# Beets Aave Looped Sonic

## Overview

LoopedSonicVault is an ERC20 vault token that implements a looped LST strategy combining stS with Aave v3 on the Sonic network. The vault uses a flash-accounting execution flow similar to Uni V4 and Balncer V3. This allows for custom router implementations for managing the deposit and withdrawal of assets, supporting flexibility in sourcing the best rate when looping and unwinding. The vault maintains strict safety invariants during an operation.


## Core Components

### Contracts

- **LoopedSonicVault** - Main ERC20 vault contract that handles deposits, withdrawals, and manages the looped strategy
- **BaseLoopedSonicRouter** - Abstract router contract that provides the basic logic for deposit and withdrawal operations
- **MagpieLoopedSonicRouter** - Concrete implementation of the router using Magpie protocol integration
- **AaveCapoRateProvider** - Rate provider that wraps Aave's StsPriceCapAdapter for pricing

### Interfaces

- **ILoopedSonicVault** - Main vault interface
- **ISonicStaking** - Interface for Sonic network staking operations
- **IBalancerVault** - Interface for Balancer vault interactions
- **IMagpieRouterV3_1** - Interface for Magpie router integration

### Libraries

- **VaultSnapshot** - Library for capturing vault state snapshots
- **VaultSnapshotComparison** - Library for comparing vault states to ensure invariants


## Functionality

### Deposit Flow

The deposit function implements a leveraged looping strategy:

1. **Initial Setup** - User sends S which gets wrapped to wS
2. **Callback Execution** - Vault calls the router's depositCallback with flash-accounting
3. **Looping Strategy** - Router performs up to MAX_LOOP_ITERATIONS:
   - Converts wS to stS (Sonic staking tokens) via staking or DEX
   - Supplies stS as collateral to Aave
   - Borrows wS against the stS collateral
   - Repeats until borrowing capacity is exhausted or minimum thresholds reached
4. **Share Minting** - Vault mints shares proportional to NAV increase

### Withdraw Flow

Two withdrawal mechanisms are available:

#### Standard Withdraw
For smaller withdrawals:
1. **Share Burning** - Burns user's vault shares upfront
2. **Collateral Withdrawal** - Withdraws proportional stS collateral from Aave
3. **Asset Conversion** - Router converts stS to wS via DEX or redemption
4. **Debt Repayment** - Repays proportional wS debt to Aave
5. **User Payout** - Transfers remaining wS to user after debt settlement

#### Flash Loan Withdraw
For larger withdrawals:
1. **Flash Loan** - Takes Aave flash loan to temporarily repay debt
2. **Full Withdrawal** - Withdraws all needed collateral without health factor issues
3. **Asset Conversion** - Converts stS to wS
4. **Loan Repayment** - Repays flash loan with 5 basis point fee
5. **User Payout** - Transfers remaining wS to user

### Unwind Flow

Administrative operation for vault management (requires UNWIND_ROLE):

1. **LST Withdrawal** - Withdraws specified amount of stS from Aave collateral
2. **External Sale** - Calls external contract to sell stS for wS
3. **Slippage Protection** - Ensures wS received meets minimum threshold based on redemption value
4. **Debt Reduction** - Uses wS proceeds to repay vault's Aave debt
5. **Vault Deleveraging** - Reduces overall leverage and improves health factor

The unwind operation allows authorized operators to reduce vault leverage during market stress or rebalance positions while maintaining protocol safety through slippage controls.

## Access Controls

The vault implements role-based access control using OpenZeppelin's AccessControl:

### Roles

- **DEFAULT_ADMIN_ROLE** - Full administrative control
  - Configure vault parameters (health factor, slippage limits, protocol fees)
  - Set treasury address and rate provider
  - Pause/unpause individual operations (deposits, withdrawals, unwinds)
  - Grant and revoke other roles

- **OPERATOR_ROLE** - Emergency response capabilities
  - Emergency pause all vault operations simultaneously
  - Cannot unpause operations (requires admin)
  - Designed for rapid response to potential issues

- **UNWIND_ROLE** - Vault management operations
  - Execute unwind operations to reduce leverage
  - Typically granted to automated systems or trusted operators
  - Critical for maintaining vault health during market stress


## Development

### Prerequisites

- Foundry toolkit
- Solidity ^0.8.30

### Build

```shell
forge build
```

### Test

```shell
forge test
```

### Coverage

Generate coverage report:

```shell
forge coverage --report lcov
genhtml lcov.info -o coverage-report --branch-coverage --function-coverage --show-details --ignore-errors inconsistent
```

View coverage report at `./coverage-report/index.html`
