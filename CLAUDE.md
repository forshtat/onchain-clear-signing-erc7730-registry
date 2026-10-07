# CLAUDE.md

Reference implementation of ERC-8283, an on-chain registry of attested ERC-7730 Clear Signing descriptors.
Not audited. The architecture is still changing, and `README.md` and `docs/` are intentionally minimal until it settles.
The code in `contracts/` is the source of truth; do not trust older docs or git history for design intent.

## Commands

Hardhat 3 + viem, ESM, Node's built-in test runner (`node:test`).

```bash
npm install
npm run compile
npm test
npx hardhat test test/<file>.ts
```

Solidity 0.8.37 (pinned), `evmVersion: cancun`, `viaIR`, OpenZeppelin pinned to 5.0.2.

## Layout (`contracts/`)

- `ClearSigningRegistry.sol` — thin composition of the modules.
- `modules/` — one contract per concern; each carries its own NatSpec. No registry-wide interface.
- `I<Module>.sol` — events and errors only, inherited by the matching module.
- `IRevocationController.sol` — the one real interface: an optional attester-declared contract wallets may query. The registry never calls it.
- `structs/` — one file per struct.

## Conventions

- New files use `SPDX-License-Identifier: CC0-1.0`.
- No relayed calls: every write is by `msg.sender` as the attester.
- Loop indices are `i`, `j`; descriptive names are for real variables only.
- Checks use `require(cond, CustomError())`, not `if (!cond) revert`; prefer plain assignment over copy loops (the toolchain supports it).
