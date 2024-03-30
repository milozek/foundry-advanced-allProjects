Stability Architecture:

1. Relative -> Anchored/Pegged -> 1.00 (US$)
   1. Chainlink Price Feed
   2. Set a fn to exchange ETH, BTC -> $$
2. Mechanism (Minting) -> Algorithmic (Decentralized)
   1. People can only mint stablecoin with enough collateral (coded)
3. Collateral Type -> Exogenous (Crypto)
   1. wETH
   2. wBTC

- calculate health factor fn
- set health factor if debt is 0
- added a bunch of view fns.

1. What are our invariants/properties

- <!--  -->

1. Some proper oracle use
2. Write more tests
3. Smart Contract Audit Preparation

<!-- openzeppelin-contracts-06/=lib/openzeppelin-contracts-06 -->

## Foundry

**Foundry is a blazing fast, portable and modular toolkit for Ethereum application development written in Rust.**

Foundry consists of:

- **Forge**: Ethereum testing framework (like Truffle, Hardhat and DappTools).
- **Cast**: Swiss army knife for interacting with EVM smart contracts, sending transactions and getting chain data.
- **Anvil**: Local Ethereum node, akin to Ganache, Hardhat Network.
- **Chisel**: Fast, utilitarian, and verbose solidity REPL.

## Documentation

https://book.getfoundry.sh/

## Usage

### Build

```shell
$ forge build
```

### Test

```shell
$ forge test
```

### Format

```shell
$ forge fmt
```

### Gas Snapshots

```shell
$ forge snapshot
```

### Anvil

```shell
$ anvil
```

### Deploy

```shell
$ forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

### Cast

```shell
$ cast <subcommand>
```

### Help

```shell
$ forge --help
$ anvil --help
$ cast --help
```
