# Spot 🐕 [![License: LGPL3.0](https://img.shields.io/badge/License-LGPL%20v3-008033.svg)](https://opensource.org/licenses/lgpl-3.0)

Spot is a multi-pool type DEX built on Fuel.

| Package                                                   | Description                                                        |
| --------------------------------------------------------- | ------------------------------------------------------------------------------------- |
| [`@spot/abis`](/abis)                                     | Contract ABIs used throughout the whole repo                                          |
| [`@spot/factory_registry`](/factory_registry)             | The contract where all Spot factories are whitelisted                                 |
| [`@spot/fee_swapper`](/fee_swapper)                       | The contract where all protocol fees are swapped to a single token                    |
| [`@spot/pools/constant_product`](/pools/constant_product) | The XYK pool type and its associated factory                                          |
| [`@spot/pools/stable`](/pools/stable)                     | The stableswap pool type and its associated factory                                   |
| [`@spot/router`](/router)                                 | The contract used to swap tokens as well as LP and withdraw liquidity from Spot pools |

## Usage :hammer_and_pick:

To compile the smart contracts, you need to have [fuelup](https://fuellabs.github.io/sway/v0.20.2/introduction/installation.html) and the Fuel toolkit installed locally and then execute the following (in any of the smart contract packages):

```bash
$ forc build
```

### Requirements

- `fuelup` 0.2.2
- `rustc` 1.62.1 (e092d0b6b 2022-07-16)
- `forc` 0.20.2

### Clean

To clean up smart contract builds, run the following in either of the packages:

```bash
$ forc clean
```

### Test

To run tests in any package, execute:

```bash
$ forc test
```

## TODOs 💻

- [ ] Lots and lots of unit/integration tests
- [ ] Check contract binaries when adding pools in factories
- [ ] Add logic to handle block timestamps in pool contracts
- [ ] Remove unnecessary casting to `u64` in pool code to avoid precision loss
- [ ] Implement `sqrt` directly for U128 instead of casting to `u64` before applying it
- [ ] Use `u256` for math
