# swornbyswarm (SWORN)

An immutable, fixed-supply ERC-20 for swornbyswarm. The constructor mints all
1,000,000,000 SWORN to its immediate deployer. Project links supplied in the brief:
[sworn.sites.imd.fun](https://sworn.sites.imd.fun) and
[x.com/swornbyswarm](https://x.com/swornbyswarm).

## Contract and deployment parameters

| Parameter | Value |
| --- | --- |
| Contract | `src/SwornToken.sol:SwornToken` |
| Name | `swornbyswarm` |
| Symbol | `SWORN` |
| Decimals | `18` |
| Whole-token supply | `1,000,000,000` |
| Base-unit supply | `1000000000000000000000000000` (`10^27`) |
| Named constant | `INITIAL_SUPPLY = 1_000_000_000 * 10 ** 18` |
| Constructor arguments | None; ABI-encoded arguments are empty bytes |
| Initial recipient | Constructor `msg.sender`, the launch factory for this launch |
| Target network | Ethereum, chain ID `1` |
| Compiler / EVM | Solidity `0.8.26` / Cancun |
| Optimizer | Enabled, 200 runs |
| Bytecode metadata hash | `none` |

The token is deployed directly from creation bytecode, without a proxy,
initializer, owner address, or linked libraries. Its constructor makes no external
calls. The constructor's deployment sender receives the entire supply; an
intermediate deployment helper would receive it instead of that helper's caller.
The included factory fixture demonstrates this behavior using CREATE2.

## Behavior and assumptions

The brief specifies standard token behavior, so there are no taxes, rebases,
transfer limits, allowlists, blocklists, pausing, minting after construction, public
burn functions, governance, or administrative privileges. The project links are
branding references; they introduce no oracle, website integration, or on-chain
service dependency. No application contracts are required.

Transfers deliver exactly the requested number of base units. A successful
`transfer`, `approve`, or `transferFrom` returns `true`; invalid operations revert
with OpenZeppelin's ERC-6093 errors. Zero-value transfers between nonzero addresses
are valid and emit `Transfer`. A self-transfer requires sufficient balance and
preserves the balance. Transfers to the zero address and approvals to the zero
spender are rejected.

`approve` replaces the caller's existing allowance. `transferFrom` spends the
caller's allowance, including when the caller is the holder or deployer. An
allowance of `type(uint256).max` follows OpenZeppelin's standard unlimited-approval
semantics and is not decremented. A failed transfer leaves both balances and
allowances unchanged. `Approval` is emitted on `approve`; OpenZeppelin v5 does not
emit it for allowance consumption during `transferFrom`, so integrations should
query `allowance` for its current value.

## Launch responsibilities

IMD's separate manifest and deployment process identifies `SwornToken`, its empty
constructor-argument list, 18 decimals, and the exact base-unit supply above. No
manifest, signing keys, deployment transaction, or live contract address is
produced by this project.

The factory receives the whole supply, then handles the brief's allocation:
10% (100,000,000 SWORN) to the launch's MerkleDistributor, 70% (700,000,000 SWORN)
for the pool, and 20% (200,000,000 SWORN) to
`0xee2aaa315cf7ed169f93148d30d24af9318dbb66`. These are factory operations, not
constructor transfers or token-level reserves. The token does not exempt or
privilege any of these addresses because every transfer is exact already.

For the later launch configuration, the brief fixes the Ethereum pair to IMD at
`0xd34a99bc0f67ae1bbd63c660e6d0b0dd03e263b7`, pool fee `12500` (1.25%), tick spacing
`60`, and initial-price provenance `79228162514264337593543950336`. The deployer
derives the actual opening price from the supplied economics:
`poolBps = 7000`, `initialMarketCapWei = 2500000000000000000000`, and the remainder
recipient above. These values are external launch settings, not token fees or
constructor parameters.

## After launch

There are no settings to configure, ownership to transfer, roles to renounce, or
maintenance transactions to run. The launch operator is responsible for verifying
the deployed source and metadata, checking the constructor mint and allocation
receipts, and publishing the actual token address. Wallet and exchange operators
must display 18 decimals and use base units for transfers and approvals.

Holders control their transfers and approvals. They should approve only intended
spenders and amounts; when replacing a nonzero allowance, first revoke it and wait
for confirmation to reduce the standard ERC-20 allowance-change race. The token
has no recovery mechanism for assets sent to the token contract or an unintended
recipient. Direct native-ETH payments revert; forcibly received ETH cannot be
recovered. No operator can freeze holders or fix the deployed contract by upgrade.

## Local verification

Foundry and Solidity 0.8.26 are the required toolchain. Solidity dependencies are
vendored as ordinary files in `lib/`; no install step, submodule, RPC endpoint,
environment-dependent test configuration, FFI, or filesystem cheatcode access is
needed. Once the pinned compiler is available, build and tests require no network.

```sh
forge build
FOUNDRY_FUZZ_SEED=0xcaeaff394b7a3ed41606ea8be104800948d981b729136d1331d3696ac6ad27a3 forge test
forge fmt --check
```

Unit tests cover constructor metadata and mint events, exact transfers, full-supply
round trips, zero and self-transfers, allowances, revocation, unlimited approval,
revert atomicity, unauthorized spending, and unsupported admin/mint/burn calls.
Four fuzz properties run 512 cases each. A stateful invariant exercises randomized
transfers, approvals, and delegated transfers across four holders (128 runs of 64
calls) and checks supply and balance conservation.

The launch tests cover CREATE2 deployment to a factory and exact allocation,
claim, and pool-facing token movements. They model the token side of these flows;
they do not execute a Uniswap v4 pool or validate its pricing. The supplied
protected checks require IMD's separate launch harness and resolved manifest;
the network performs that full integration verification independently.

## Dependencies and review

The production contract inherits the unmodified OpenZeppelin Contracts `v5.4.0`
ERC-20 implementation. Only its required Solidity files and MIT license are
vendored. Tests use the vendored `forge-std` `v1.9.7` sources and their MIT/Apache
licenses. `dependencies.json` records source archives, versions, archive SHA-256
digests, and per-file SHA-256 digests. Upstream library source is kept unchanged.

The security reference supplied with the assignment informed the review: the
contract makes no external calls, has no privileged or upgrade path, and exposes
no supply-changing operation after deployment. Its constructor is the only caller
of `_mint`; the inherited `_burn` function remains internal and unreachable from
the deployed public interface. Only standard ERC-20 state transitions are exposed.
Local verification consists of Foundry build, unit/fuzz/invariant tests and format
checks. Slither, Mythril, a live deployment, and an independent security audit are
not part of the local verification; production release remains subject to the
network's independent review.
