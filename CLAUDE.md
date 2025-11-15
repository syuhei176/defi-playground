# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a DeFi playground project built with Foundry, a Solidity development framework. The project includes Uniswap V4 core and periphery libraries as dependencies for experimenting with DeFi protocols.

## Development Commands

### Build
```bash
forge build
```

### Testing
```bash
# Run all tests
forge test

# Run a specific test
forge test --match-test test_Increment

# Run tests with verbosity (useful for debugging)
forge test -vvv

# Run fuzz tests
forge test --match-test testFuzz_
```

### Formatting
```bash
forge fmt
```

### Gas Snapshots
```bash
forge snapshot
```

### Local Development
```bash
# Start local Ethereum node
anvil
```

### Deployment
```bash
forge script script/Counter.s.sol:CounterScript --rpc-url <your_rpc_url> --private-key <your_private_key>
```

## Architecture

### Directory Structure
- `src/` - Smart contract source files
- `test/` - Test files (suffix: `.t.sol`)
- `script/` - Deployment and interaction scripts (suffix: `.s.sol`)
- `lib/` - External dependencies managed by Foundry
  - `forge-std` - Foundry's standard library for testing
  - `uniswap-v4-core` - Uniswap V4 core contracts
  - `uniswap-v4-periphery` - Uniswap V4 periphery contracts

### Testing Pattern
Tests inherit from `forge-std/Test.sol` which provides:
- `setUp()` - Runs before each test
- Assertion helpers: `assertEq()`, `assertTrue()`, etc.
- Fuzz testing support (prefix test functions with `testFuzz_`)
- Cheat codes via `vm` object for blockchain state manipulation

### Deployment Pattern
Scripts inherit from `forge-std/Script.sol` and use:
- `vm.startBroadcast()` / `vm.stopBroadcast()` to wrap deployment transactions
- `run()` function as the entry point

## Foundry Configuration

The project uses default Foundry configuration in `foundry.toml`:
- Source directory: `src`
- Output directory: `out`
- Libraries: `lib`
