# Per-function descriptors in the ERC-8283 registry — design

Status: draft for review. Date: 2026-09-23.

## Goal

Allow an ERC-7730 descriptor file to cover a **single function** (or a single EIP-712 primary type) instead of a whole contract, so that a memory-limited hardware wallet can receive, hash and verify the attestation of exactly the descriptors it uses. The proposal spans ERC-7730, ERC-8176 and this registry.

Scope: the on-chain registry only. The existing off-chain registry (`ethereum/clear-signing-erc7730-registry`) does not change. The ERC has no production deployments, so backward compatibility is not a constraint.

## Decisions

These were settled while scoping the work.

1. **One attestation per function descriptor.** No Merkle root. A device does what it does today: hash one file, verify one signature.
2. **Double-nested index.** The registry keeps its contract-level context key. It points at a *manifest* that maps each function to its descriptor and attestations.
3. **Registration is unchanged.** `createAttestations`, `contextKeyId` and `descriptorHash` keep their meaning; the registry treats them as opaque `bytes32`.
4. **Each function descriptor is self-contained and signed.** It carries its own chain, address and selector (EIP-712: verifying contract and primary type). All `includes` are flattened into it and attested with it. The maximum flattened size will be formalized separately.
5. **Revocation is one flow, one shape.** An attester states that a *function at a context* is no longer correct: `(contextKeyId, functionKey)`. It mirrors what an attestation says ("this contract on this chain has this function, and it is correct"). There is no revocation by attestation ID, no wildcard, and no second entry type.
6. **Revoke-before-replace is normative, not enforced.** The registry cannot see which functions a manifest contains, so it cannot check per-function replacement. ERC-8283 states the obligation as a MUST on attesters instead.
7. **The tuple revocation is the only revocation mechanism in ERC-8283.** The `erc8283-index-revocation-killswitch` side branch (kill switch, revocation oracle) is not the basis of this work; it was superseded by `create-erc7730-onchain-registry`.

## Design

### Trust chain (what the device verifies)

`function descriptor → its attestation → attester's signature`. The device checks that the descriptor's hash matches the attestation and that the signature is valid, then that the embedded context matches the transaction. It never sees the manifest. Revocation and "is this the active release" are checked by the host wallet, as today; a device cannot read chain state.

### Function descriptor

An ERC-7730 document that contains one format entry plus everything that entry needs (flattened `includes`, referenced definitions, enums, constants, metadata). Its `context` names every deployment it applies to (chain and address) and, through its single format key, the selector or EIP-712 primary type. The attestation signs these bytes, so the context binding cannot be replayed against another contract or function.

### Manifest

A JSON file, one per contract release, registered on-chain as the record's descriptor.

- Keyed by function: `functionKey`.
- Each entry gives the function descriptor's hash, its mirror URIs, and its attestation IDs with formats.
- Its hash is the `descriptorHash` in `DescriptorInfo`. It carries an ordinary attestation, because `createAttestations` requires at least one (`EmptyAttestationIds`). That attestation is an integrity marker; devices never use it.
- The manifest is an **index only**. It is superseded by registering a newer one, never revoked.
- The wallet can tell it apart from a plain descriptor by its `$schema`.

Function attestations are **not** registered on-chain. They live in the manifest and the attestation index.

### Keys

- `contextKeyId`: unchanged. The contract, factory, EIP-712 deployment or domain-separator key the wallet already derives for `resolveDescriptors`. For a deployed contract it is the hash of chain and address.
- `functionKey`: the 4-byte selector left-aligned in a `bytes32` (the same value as a Solidity `bytes4`-to-`bytes32` cast), or the EIP-712 type hash for typed data.

### Revocation

One write, one event, one read:

```solidity
struct FunctionRevocation { bytes32 contextKeyId; bytes32 functionKey; }

function revokeFunctions(address attester, FunctionRevocation[] calldata revocations, bytes calldata signature) external;

event FunctionRevoked(address indexed attester, bytes32 indexed contextKeyId, bytes32 functionKey, uint64 timestamp);

function getFunctionRevocationTimestamp(address attester, bytes32 contextKeyId, bytes32 functionKey) external view returns (uint64);
```

Storage: `[attester][contextKeyId][functionKey] → uint64`.

**Validity rule.** An attestation for `(contextKeyId, functionKey)` is void when its signed issue time is **at or before** the recorded revocation timestamp. An attestation issued after it is valid. The host wallet applies the rule using the `contextKeyId` it resolved through.

Consequences:

- Re-revoking a tuple **moves the timestamp forward** to the current block time (unlike the old first-wins rule). A later revocation voids everything issued up to that moment.
- **Supersession is not revocation.** Registering a newer manifest replaces the index only. An attestation for a wrong descriptor stays valid until the tuple is revoked. ERC-8283 therefore requires (MUST) that an attester revoke the tuple of every function whose descriptor is replaced or removed. The registry does not enforce this, because manifests are opaque to it.
- The attester must sign a corrected attestation with an issue time strictly after the revocation's block timestamp (whole seconds), or clock skew can make the correction look void.
- Every attestation format must carry a signed issue time. EAS offchain attestations have one. ERC-8176 must require it, and so must any other format.
- Retiring a whole contract means revoking each of its function tuples. The context's manifest pointer remains; register an empty manifest if you want it cleaner.
- Authorization matches every other attester write: a direct call needs no signature; a relayed call carries an EIP-712 signature (ECDSA or ERC-1271) and consumes the shared nonce. New typehashes: `FunctionRevocation(bytes32 contextKeyId,bytes32 functionKey)` and `ClearSigningFunctionRevocationBatch(FunctionRevocation[] revocations,uint256 nonce)`.

**Removed from the registry** (replaced by the flow above):

- `revokeAttestations`, `RevocationEntry`, the `AttestationRevoked` event and the two-argument `getRevocationTimestamp`.
- The `MissingRevocation` error and the revoke-before-replace rule: `createAttestations` simply overwrites the active pointer.
- Pointer clearing on revocation.
- The "a revoked ID is consumed forever" rule. `AttestationIdAlreadyUsed` remains only for a reused set ID whose stored record does not match.
- `ResolvedAttestation.revokedAt`.
- The old `REVOCATION_ENTRY_TYPEHASH` / `REVOCATION_BATCH_TYPEHASH` and `hashRevocationEntries`.

### Wallet flow

1. Derive the contract-level `contextKeyId` from the transaction; call `resolveDescriptors`.
2. Fetch the manifest and check its hash.
3. Look up the function key; fetch the function descriptor and its attestation.
4. Call `getFunctionRevocationTimestamp(attester, contextKeyId, functionKey)`; reject the attestation if its issue time is at or before a non-zero result.
5. Send the descriptor and attestation to the device, which verifies hash and signature and matches the embedded context.

### Attester flow

1. **New or added function:** sign a flattened descriptor and its attestation, add it to a new manifest, `publishMirrorLists`, then `createAttestations` for the manifest. Reuse unchanged functions' attestations.
2. **Correcting a function:** call `revokeFunctions` for the tuple(s) and wait for it to be mined; then sign the corrected descriptor's attestation with an issue time after that block; then publish the new manifest.

## Cost

Measured on the current contract, 2 deployments, one EAS attestation per descriptor, gas per `createAttestations`:

| Registration model | 1 unit | 5 | 20 | 60 |
|---|---|---|---|---|
| Per-function context keys (rejected) | 255k | 1.16M | 4.54M | 13.6M |
| Manifest (this design) | ≈255k regardless of function count | | | |

The manifest figure follows from the on-chain data being independent of function count; it was not measured separately. A revocation row is one storage write plus an event; it has not been measured for the new function.

## Alternatives considered

- **Per-function context keys** (`tag, chainId, address, selector`): needs no contract change, but gas and calldata grow linearly, and every upgrade must re-register every function. Caps out around 60 functions per block.
- **Merkle root over a release**: constant gas and atomic release semantics, but the device must verify a proof and ERC-8176 must sign a root. Rejected for device complexity.
- **Revocation by attestation ID** (with or without a context or function scope): needs no issue-time rule, but the revocation no longer mirrors the attestation, forces the attester to track every ID ever issued for a function, and grew into several entry shapes once scoped. Rejected.
- **Derived-ID convention** on the existing revocation mapping: works without contract changes but keeps two revocation flows and emits opaque hashes. Rejected.

## Changes by component

- **ERC-7730:** permit single-function descriptors; define flattening (all `includes` inlined and attested) and the required embedded context.
- **ERC-8176:** attestation over a function descriptor including its context and a signed issue time; integrity attestation over a manifest; the revocation validity rule above.
- **ERC-8283** (worktree `~/ERCS2/.worktrees/erc-8283`, branch `per-function-descriptors-8283`, from `create-erc7730-onchain-registry`; not pushed): rewritten revocation text, manifests, function keys, and the MUST obligation above; the normative interface asset is synced with this repo.
- **ERC-8176** (worktree `~/ERCS2/.worktrees/erc-8176`, branch `per-function-descriptors-8176`, from `forshtat/erc8176-freshness-challenge`; not pushed): allow single-function descriptors, require a signed issue time and the embedded context binding. ERC-7730 is **not** edited; both texts assume it permits single-function descriptors.
- **This repo:** replace the revocation machinery as listed under "Removed", add `revokeFunctions`, its event, view and typehashes, rework `README.md` (§3 wallet pseudocode, §4 revocation, §5 updates, errors table) and the tests. `createAttestations` itself only loses the revoke-before-replace rule.
- **Tooling (out of scope here):** splitter/flattener and manifest builder.

## Open questions

1. **Manifest attestation format** in ERC-8176, and whether the manifest and function attestations share a format ID.
2. **Factory-bound contexts:** a revocation under the factory-kind `contextKeyId` covers every instance. Revoking one instance means the wallet must also check the contract-kind key for that address. Decide whether to define that check or accept factory-wide granularity.
3. **Batch revocation read:** the wallet issues one `getFunctionRevocationTimestamp` per function used; a multicall helper is optional.
4. **Maximum flattened descriptor size:** deferred to a separate effort.

## Plan

1. **Spec text** (outside this repo): ERC-7730 flattening and single-function context; ERC-8176 function and manifest attestations, signed issue time, and the revocation validity rule.
2. **Registry repo** (test-first):
   1. Add `revokeFunctions`, `FunctionRevoked`, `getFunctionRevocationTimestamp`, the new typehashes and `hashFunctionRevocations`.
   2. Remove the old revocation machinery listed above, including `MissingRevocation`, and update `createAttestations` to overwrite pointers.
   3. Tests: a revocation is recorded and isolated per context and per function; a repeat revocation moves the timestamp forward; relayed revocation with an ECDSA and an ERC-1271 signature consumes the nonce; `createAttestations` replaces an active pointer without any prior revocation; an end-to-end manifest registration and resolution.
   4. Update `README.md` and the errors table.
3. **Tooling** to split, flatten and build manifests, in a separate repo or task.

## Non-goals

- Changing the off-chain registry.
- Formalizing the maximum descriptor size.
- Backward compatibility with whole-contract descriptors or the old revocation interface.
