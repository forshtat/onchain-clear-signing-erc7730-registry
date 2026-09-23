# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Reference implementation of [ERC-8283](https://ethereum-magicians.org/t/erc-8283-on-chain-registry-for-erc-7730-clear-signing-descriptors/28717), an on-chain registry mapping contexts (contracts, factories, EIP-712 domains) to attested ERC-7730 Clear Signing descriptors. It is **not audited** and exists for specification clarity. `README.md` is a viem-based walkthrough of every registry function (`publishMirrorLists` → `createAttestations` → `resolveDescriptors` → `revokeAttestations` → …) plus an errors table; keep it consistent when changing the interface or error semantics.

## Commands

Hardhat 3 + viem, ESM (`"type": "module"`), Node's built-in test runner (`node:test`, not Mocha/Chai).

```bash
npm install
npm run compile                       # hardhat compile
npm test                              # hardhat test (all tests, in-process EDR network)
npx hardhat test test/ClearSigningRegistry.smoke.test.ts   # a single test file
npx hardhat test --grep "relayed ECDSA"                    # filter by test name
npx hardhat --build-profile production compile             # optimizer on (runs: 200)
```

Solidity is 0.8.24 with `evmVersion: cancun`; OpenZeppelin is pinned to exactly `5.0.2`.

## Architecture

All contracts are in `contracts/`; there is no deployment script or non-test TypeScript.

- `IClearSigningRegistry.sol` — the ERC's interface: structs (`DescriptorInfo`, `AttestationIdentifier`, `RevocationEntry`), events, errors and NatSpec. This is the spec; the implementation inherits it.
- `ClearSigningRegistry.sol` — the implementation (`IClearSigningRegistry` + OZ `EIP712`, domain `"ClearSigningRegistry"` v`"1"`).
- `ClearSigningRegistryConstants.sol` — EIP-712 typehashes (used on-chain) and context/format tags (reference values only; the registry never reads them, wallets derive IDs off-chain).
- `RegistrationHashLib.sol` — EIP-712 struct/array hashing for batches. **Typehash strings in the Constants file, the hashing here, and the `registrationTypes` in the README/tests must all match exactly.**
- `UriFilterLib.sol` — prefix filtering (`ipfs:`, `https:`) of stored MirrorList URIs for `resolveDescriptors`/`getMirrorListById`.

### Data model (needs reading across the implementation)

- **Everything is scoped per attester.** The active record is `_activeAttestationSetIds[attester][contextKeyId][descriptorSchemaMajor]`; different schema MAJORs never displace each other.
- **Context keys are opaque `bytes32`.** Derived off-chain as `keccak256(abi.encode(tag, ...))` (contract, factory+deploy event, EIP-712 deployment, domain separator); the registry cannot tell which kind an ID is.
- **Attestation sets.** A descriptor registers a set of `(attestationId, attestationFormatId)` members. A single-member set's ID *is* that member's attestation ID; larger sets use a content hash (`_deriveAttestationSetId`). Set details/contents are write-once; a revoked ID is consumed forever and can never be re-registered.
- **MirrorLists** are a global, content-addressed store (`id = keccak256(abi.encode(string[]))`), written only by `publishMirrorLists`. Attesters then *point* to them per descriptor hash / attestation set. `createAttestations` and the update functions only accept already-published list IDs.
- **Revocation is a separate step.** `createAttestations` never revokes; displacing an active record whose set isn't already revoked reverts `MissingRevocation`. Callers needing atomicity must batch revoke+create themselves (multicall / EIP-5792). Set IDs and individual attestation IDs share the single `_revokedAt` namespace.
- **Auth model.** Every attester-scoped write (`createAttestations`, `revokeAttestations`, `updateDescriptorMirrorList`, `updateAttestationMirrorList`, `setAttesterProfileURI`) takes an `attester` argument: if `msg.sender == attester` the signature is skipped; otherwise an EIP-712 signature is verified via OZ `SignatureChecker` (ECDSA for EOAs, ERC-1271 for contracts) and a single per-attester nonce (`_nonces`, burnable via `invalidateNonce`) is consumed. Code-bearing EOAs (EIP-7702) must still work with plain ECDSA — see `test/ClearSigningRegistry.eip7702.test.ts`.

## Tests

Tests deploy via `network.create()` → `viem.deployContract("ClearSigningRegistry")` and compute MirrorList IDs / context IDs off-chain to mirror the contract's derivations. The EIP-7702 test simulates delegation with the `hardhat_setCode` RPC rather than a real type-4 tx.

## Conventions

- New files use `SPDX-License-Identifier: CC0-1.0`.
- Descriptive identifiers (`descriptorSchemaMajor`, `attestationMirrorListId`, loop vars like `descriptorIndex`) and `@dev`/`@inheritdoc` NatSpec on private helpers — match this style.
