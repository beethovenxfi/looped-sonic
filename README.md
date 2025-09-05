# LoopedSonicVault

LoopedSonicVault is an ERC20 vault token that implements a looped LST strategy combining stS with Aave v3 on the Sonic network. The vault uses a flash-accounting execution flow similar to Uni V4 and Balncer V3. This allows for custom router implementations for managing the deposit and withdrawal of assets, supporting flexibility in sourcing the best rate when looping and unwinding. The vault maintains strict safety invariants during an operation.


## Contracts

- [`LoopedSonicVault`](./src/LoopedSonicVault.sol): The core ERC20 vault contract
- [`BaseLoopedSonicRouter`](./src/BaseLoopedSonicRouter.sol): An abstract contract that implements the basic Router logic for managing deposits and withdraws to the `LoopedSonicVault`
- [`AaveCapoRatePovider`](./src/AaveCapoRatePovider.sol): A thin wrapper around Aave's [`StsPriceCapAdapter`](https://sonicscan.org/address/0x5BA5D5213B47DFE020B1F8d6fB54Db3F74F9ea9a#code)

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Coverage Report

```bash
$ forge coverage --report lcov
$ genhtml lcov.info -o coverage-report --branch-coverage --function-coverage --show-details --ignore-errors inconsistent
```

This will generate a coverage report that can be found in `./coverage-report/index.html`.
