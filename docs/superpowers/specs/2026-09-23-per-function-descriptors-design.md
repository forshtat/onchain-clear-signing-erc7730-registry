# Per-function descriptors in the ERC-8283 registry — design

Status: implemented in this repo (`per-function-descriptors` branch); ERC-8283 updated in the `forshtat/ERCs` fork; ERC-8176 and ERC-7730 not yet touched. Date: 2026-09-23, revised 2026-10-02 (twice — see decision 9).

## Goal

Allow an ERC-7730 descriptor file to cover a **single function** (or a single EIP-712 primary type) instead of a whole contract, so that a memory-limited hardware wallet can receive, hash and verify the attestation of exactly the descriptors it uses. The proposal spans ERC-7730, ERC-8176 and this registry.

Scope: the on-chain registry only. The existing off-chain registry (`ethereum/clear-signing-erc7730-registry`) does not change. The ERC has no production deployments, so backward compatibility is not a constraint.

## Decisions

These were settled while scoping the work, in order, including two reversals made after the first revocation design proved confusing to reason about (see "History" below).

1. **One attestation per function descriptor.** No Merkle root. A device does what it does today: hash one file, verify one signature.
2. **Double-nested index.** The registry keeps its contract-level context key. It points at a *function index* that maps each function or message to its descriptor and attestations.
3. **Registration is unchanged.** `createAttestations`, `contextKeyId` and `descriptorHash` keep their meaning; the registry treats them as opaque `bytes32`.
4. **Each function descriptor is self-contained and signed.** It carries its own chain, address and selector (EIP-712: verifying contract and primary type). All `includes` are flattened into it and attested with it. The maximum flattened size will be formalized separately.
5. **Revocation is one flow, one shape, keyed by content, not by slot.** `(contextKeyId, descriptorHash)`: the attester states that this exact descriptor content is no longer correct at this context. It works identically for a whole-contract descriptor, a function index, or a single-function descriptor — the registry only ever sees an opaque content hash, never a selector or an attestation ID.
6. **Revoke-before-replace is normative for nested content the registry cannot see** (individual functions inside a function index), **but enforced and automatic for the registered `descriptorHash` itself** (see decision 9). ERC-8283 states the nested-content obligation as a MUST on attesters; the registry obligation needs no MUST, because it is not optional.
7. **The `(contextKeyId, descriptorHash)` revocation is the only revocation mechanism in ERC-8283.** The `erc8283-index-revocation-killswitch` side branch (kill switch, revocation oracle) is not the basis of this work; it was superseded by `create-erc7730-onchain-registry`, which has neither.
8. **Function index lookup keys are split by dispatch kind, not unified.** A function index has two maps: `methods` (keyed by raw `bytes4` function selector) and `messages` (keyed by the EIP-712 `typeHash` of the primary type). A wallet always knows which kind of request it's resolving before it looks anything up, so a unified `bytes32` key never bought real simplification — it only relied on selectors and type hashes never colliding (true in practice, but not true by construction).
9. **Displacing an active record auto-revokes what it displaces, atomically, inside `createAttestations` itself.** No separate `revokeDescriptors` call, no window where the attester could forget it, and a revoked `descriptorHash` can never become active again at that context (`RevokedDescriptorReused`). This restores the old design's enforced revoke-before-replace guarantee — generalized to `descriptorHash`, scoped per context instead of globally — without reintroducing its two-call dance. See "Auto-revocation on displacement" below.

### History: why decision 5 isn't the first thing shipped

The first implementation keyed revocation by `(contextKeyId, functionKey)` — `functionKey` being the selector/type-hash slot, not content — with validity decided by comparing the attestation's signed issue time against the revocation timestamp ("void if issued at or before the cutoff"). That required ERC-8176 to mandate a trustworthy signed issue time on every attestation format, and needed careful "at or before" ordering semantics that proved hard to reason about even in-conversation. It also turned out, on inspection, to have **deleted all whole-descriptor/function index-level revocation** with no replacement — `revokeFunctions` only ever covered function slots, and the registry's old `_revokedAt` (keyed by attestation-set ID) was removed outright.

Keying by `descriptorHash` instead fixes both: a correction automatically produces a different hash with zero coordination (no issue-time, no clock trust), and because a function index and a whole-contract descriptor also have their own `descriptorHash`, the exact same primitive generically revokes them too — closing the gap for free. The real trade made, knowingly: the old design could revoke one attestation *rendition* (format) within a set while leaving a sibling rendition active; `descriptorHash`-keying can't, since it doesn't see formats. The practical remedy is dropping the bad rendition from the function index on republish, with the usual staleness caveat for already-fetched copies.

## Design

### Trust chain (what the device verifies)

`function descriptor → its attestation → attester's signature`. The device checks that the descriptor's hash matches the attestation and that the signature is valid, then that the embedded context matches the transaction. It never sees the function index, and it needs no revocation logic at all — revocation and "is this the active release" are checked by the host wallet; a device cannot read chain state.

### Function descriptor

An ERC-7730 document that contains one format entry plus everything that entry needs (flattened `includes`, referenced definitions, enums, constants, metadata). Its `context` names every deployment it applies to (chain and address) and, through its single format key, the selector or EIP-712 primary type. The attestation signs these bytes, so the context binding cannot be replayed against another contract or function.

### Function index

A JSON file, one per contract release, registered on-chain as the record's descriptor.

```json
{
  "version": 1,
  "methods": {
    "0xa9059cbb": { "descriptorHash": "0x...", "descriptorUris": [...], "attestations": [{ "attestationId": "0x...", "attestationFormatId": "0x...", "uris": [...] }] }
  },
  "messages": {
    "0x8b73c3c6...": { "descriptorHash": "0x...", "descriptorUris": [...], "attestations": [...] }
  }
}
```

- `methods` keyed by the raw 4-byte selector; `messages` keyed by the EIP-712 `typeHash`. No shared/unified key — see decision 8.
- Each entry gives the function descriptor's hash, its mirror URIs, and its attestation IDs with formats.
- The function index's own hash is the `descriptorHash` in `DescriptorInfo`. It carries an ordinary attestation, because `createAttestations` requires at least one (`EmptyAttestationIds`). That attestation is an integrity marker; devices never use it.
- A function index is itself just a lookup table, not a trust root. It is superseded by registering a newer one. It is revoked exactly like any other descriptor — by its own `descriptorHash`, same call as a function.
- The wallet can tell a function index apart from a plain descriptor by its `$schema`.

Function attestations are **not** registered on-chain. They live in the function index and the attestation index.

### Keys

- `contextKeyId`: unchanged. The contract, factory, EIP-712 deployment or domain-separator key the wallet already derives for `resolveDescriptors`.
- `functionKey` (off-chain, internal to the function index only — not part of the Solidity interface): its lookup key, split into `methods` (bytes4 selector) and `messages` (EIP-712 `typeHash`). Never appears on-chain.
- `descriptorHash`: the ERC-8176 content hash, computed identically whether the descriptor is whole-contract, a function index, or a single function. This is the on-chain revocation key.

### Revocation

One write, one event, one read — generic over any descriptor, not specific to functions:

```solidity
struct DescriptorRevocation { bytes32 contextKeyId; bytes32 descriptorHash; }

function revokeDescriptors(address attester, DescriptorRevocation[] calldata revocations, bytes calldata signature) external;

event DescriptorRevoked(address indexed attester, bytes32 indexed contextKeyId, bytes32 descriptorHash, uint64 timestamp);

function getDescriptorRevocationTimestamp(address attester, bytes32 contextKeyId, bytes32 descriptorHash) external view returns (uint64);
```

Storage: `[attester][contextKeyId][descriptorHash] → uint64`.

**Validity rule.** Pure set membership: a `(contextKeyId, descriptorHash)` pair is either revoked (non-zero timestamp) or not. No comparison against anything the attestation carries — no issue time, no ordering, no clock trust anywhere in this check.

Consequences:

- A revoked pair is void **forever**. There is no un-revoke.
- A correction is automatically unaffected: different content ⇒ different `descriptorHash` ⇒ never touched by the old revocation. Nothing to coordinate, no timing requirement on the new attestation.
- Repeating a revocation of the same pair only moves its timestamp forward — an audit-trail detail, never consulted for any ordering decision.
- **Supersession is not revocation, for nested content.** Registering a newer function index auto-revokes the *old function index's own* hash (decision 9, below) — but not the hash of any individual function whose descriptor changed or was removed *inside* it, since the registry never sees function indexes' internals. ERC-8283 requires (MUST) that an attester revoke that nested `descriptorHash` explicitly; the registry cannot enforce it.
- Retiring a whole release *without* registering a replacement (an emergency stop, nothing new ready yet): revoke the function index's own `descriptorHash` at each affected context directly — the same call, no separate mechanism, and a wallet's §3-level check (below) skips the whole record without even fetching the function index.
- Authorization matches every other attester write: a direct call needs no signature; a relayed call carries an EIP-712 signature (ECDSA or ERC-1271) and consumes the shared nonce. Typehashes: `DescriptorRevocation(bytes32 contextKeyId,bytes32 descriptorHash)` and `ClearSigningDescriptorRevocationBatch(DescriptorRevocation[] revocations,uint256 nonce)`.

### Auto-revocation on displacement

`createAttestations` displacing a context's active record (registering a different `descriptorHash` than what is currently active there) auto-revokes the displaced `descriptorHash`, at that context, inside the same transaction:

- No separate `revokeDescriptors` call, no signed data beyond what `createAttestations` already commits to, no window where the attester could forget it.
- A `descriptorHash` that is revoked at a context — whether auto-revoked or explicitly — can never become active at that context again. Attempting to reverts `RevokedDescriptorReused(contextKeyId, descriptorHash)`. Closes the old "revoked IDs consumed forever" gap this redesign had also dropped.
- Re-displacing a `descriptorHash` that was already revoked (e.g. explicitly, before a later registration also displaces it) does not move its timestamp again — the write is skipped once already non-zero.
- Measured cost: **~9,300 gas per displaced context key**, on top of the existing per-context write `createAttestations` already does. Scales with contexts touched in the call, same as everything else in this design — never with how many functions a function index lists.
- This covers only the registered `descriptorHash` itself. A function index swap auto-revokes the *old function index's* hash; it does nothing for an individual function's hash that changed *inside* the new function index, since the registry never sees it. That still needs an explicit `revokeDescriptors` call — the MUST in decision 6 is exactly, and only, this remaining case.

**Removed from the registry** (the original, pre-this-feature `_revokedAt`/`revokeAttestations`, and the first per-function attempt alike):

- `revokeAttestations`, `RevocationEntry`, the old `AttestationRevoked` event and the single-argument `getRevocationTimestamp`.
- The old `MissingRevocation` error (attester-enforced, required a prior separate call) — superseded by automatic, atomic auto-revocation plus `RevokedDescriptorReused` (decision 9), not reinstated as-is.
- Pointer clearing on revocation (the old `RevocationEntry.contextKeyIds` cleanup list) — unneeded: the active pointer is simply overwritten, same as before.
- The "a revoked ID is consumed forever" rule for attestation-set IDs, specifically — restored, generalized to `descriptorHash` and scoped per context, via auto-revocation above. `AttestationIdAlreadyUsed` remains, separately, only for a reused set ID whose stored record does not match.
- `ResolvedAttestation.revokedAt`.
- The old `REVOCATION_ENTRY_TYPEHASH` / `REVOCATION_BATCH_TYPEHASH` and `hashRevocationEntries`.
- (From the first per-function attempt) the signed-issue-time validity rule, and any ERC-8176 requirement that attestation formats carry one for this purpose.

### Wallet flow

1. Derive the contract-level `contextKeyId`; call `resolveDescriptors`.
2. **Top-level check** — directly on the resolved entry, before fetching anything: `getDescriptorRevocationTimestamp(attester, entry.contextKeyId, entry.descriptorHash)`. Non-zero ⇒ skip; this covers whole-contract descriptors and function indexes alike.
3. Fetch the function index; verify its hash equals the registered `descriptorHash` (already covered by step 2 if it fails the live check, but a wallet should still verify the fetched bytes).
4. Branch on request kind: look up `methods[selector]` or `messages[typeHash]`.
5. Fetch the function descriptor and its attestation; verify per ERC-8176 — this step already computes the function descriptor's own `descriptorHash` to check it against the attestation.
6. **Function-level check**, reusing that same hash: `getDescriptorRevocationTimestamp(attester, contextKeyId, functionDescriptorHash)`.
7. Send the descriptor and attestation to the device, which verifies hash, signature and embedded context.

### Attester flow

1. **New or added function:** sign a flattened descriptor and its attestation, add it to a new function index (under `methods` or `messages` as appropriate), `publishMirrorLists`, then `createAttestations` for the function index. Reuse unchanged functions' attestations verbatim.
2. **Correcting a function:** sign the corrected descriptor and a fresh attestation (any time — no ordering constraint), add it to a new function index, publish and register it, and separately call `revokeDescriptors` for the old descriptor's hash at every affected context. Order between the correction and the revocation no longer matters, unlike the issue-time scheme.

## Cost

Measured on the current contract, 2 deployments, one EAS attestation per descriptor, gas per `createAttestations`:

| Registration model | 1 unit | 5 | 20 | 60 |
|---|---|---|---|---|
| Per-function context keys (rejected) | 255k | 1.16M | 4.54M | 13.6M |
| Function index (this design) | ≈255k regardless of function count | | | |

The function index figure follows from the on-chain data being independent of function count; it was not measured separately. A `revokeDescriptors` entry is one storage write plus an event, consistent with the `createAttestations` per-context-key cost already measured. Auto-revocation on displacement (decision 9) adds a measured ~9,300 gas per displaced context on top of a normal registration — cheaper than a separate `revokeDescriptors` transaction would have cost, since it avoids that transaction's base cost and (if relayed) its own signature verification.

## Alternatives considered

- **Per-function context keys** (`tag, chainId, address, selector`): needs no contract change, but gas and calldata grow linearly, and every upgrade must re-register every function. Caps out around 60 functions per block.
- **Merkle root over a release**: constant gas and atomic release semantics, but the device must verify a proof and ERC-8176 must sign a root. Rejected for device complexity.
- **`(contextKeyId, functionKey)` + signed-issue-time cutoff** (first implementation): see "History" above. Superseded by content-hash keying.
- **Revocation by attestation ID** (with or without a context scope): doesn't mirror what an attestation actually claims, forces the attester to track every ID ever issued, and loses the "correction auto-resolves" property that content-hash keying gets for free. Rejected.
- **Derived-ID convention** on the pre-existing attestation-ID-keyed revocation mapping: works without contract changes but keeps two revocation flows and emits opaque hashes. Rejected.
- **Unified function index lookup key** (one `bytes32` holding either a padded selector or a type hash): relies on the two never colliding rather than being correct by construction, and doesn't match ERC-7730's own separation of `context.contract` and `context.eip712`. Rejected in favor of two explicit maps (decision 8).
- **Enforced-but-manual revoke-before-replace** (re-add the old `MissingRevocation`, re-keyed to `descriptorHash`, requiring the attester to call `revokeDescriptors` before a displacing `createAttestations`): restores the same end guarantee as decision 9, but needs a separate transaction every time, costs more overall (extra tx base cost, extra signature verification if relayed), and the attester can still fail to batch the two calls atomically. Rejected in favor of automatic auto-revocation, which gets the identical guarantee for less gas with no way to get it wrong.

## Changes by component

- **ERC-7730:** permit single-function descriptors; define flattening (all `includes` inlined and attested) and the required embedded context. Not yet done.
- **ERC-8176:** attestation over a function descriptor including its context; integrity attestation over a function index. **Not touched in this pass** — the signed-issue-time requirement from the first attempt is no longer needed and should not be added.
- **ERC-8283** (worktree `~/ERCS2/.worktrees/erc-8283`, branch `per-function-descriptors-8283`, from `create-erc7730-onchain-registry`; pushed to `forshtat/ERCs`, PR #7): function indexes, the two-map lookup split, `revokeDescriptors`/`getDescriptorRevocationTimestamp`/`DescriptorRevocation`/`DescriptorRevoked` throughout, the MUST obligation, the dropped issue-time language, and (pending) auto-revocation on displacement plus `RevokedDescriptorReused`. The normative interface asset is synced with this repo.
- **This repo** (branch `per-function-descriptors`, PR #1): the contract, interface, constants and hash-lib renames (`FunctionRevocation`→`DescriptorRevocation`, `revokeFunctions`→`revokeDescriptors`, `getFunctionRevocationTimestamp`→`getDescriptorRevocationTimestamp`, `FunctionRevoked`→`DescriptorRevoked`, `_functionRevokedAt`→`_descriptorRevokedAt`); auto-revocation on displacement and the new `RevokedDescriptorReused` error in `_updateActiveAttestation`; the revocation test file (including auto-revoke, cross-context isolation, revived-hash rejection, and the already-explicitly-revoked no-op-timestamp cases); `README.md` §3 (top-level check restored), §4 (reframed as the standalone/nested-function case), §5 (no-prior-revocation-needed demonstrated), §10 (function index two-map example, strengthened top-level guarantee), and the errors table.
- **Tooling (out of scope here):** splitter/flattener and function index builder.

## Open questions

1. **Function index attestation format** in ERC-8176, and whether the function index and function attestations share a format ID.
2. **Factory-bound contexts:** a revocation under the factory-kind `contextKeyId` covers every instance. Revoking one instance means the wallet must also check the contract-kind key for that address. Decide whether to define that check or accept factory-wide granularity.
3. **Batch revocation read:** the wallet issues one `getDescriptorRevocationTimestamp` per check (two per function, including the top-level one); a multicall helper is optional.
4. **Maximum flattened descriptor size:** deferred to a separate effort.
5. **Per-rendition revocation** (kill one attestation format within a set, keep a sibling active): no on-chain primitive exists post-redesign; the function index-editing remedy has a staleness caveat for already-fetched copies. Accepted as a known limitation (see "History"). Unaffected by decision 9 — auto-revocation operates on `descriptorHash`, same granularity limit as explicit revocation.
6. **~~Enforced revoke-before-replace~~ — resolved by decision 9.**

## Plan

1. **Spec text** (outside this repo, deferred): ERC-7730 flattening and single-function context; ERC-8176 function and function index attestations.
2. **Registry repo** (test-first) — done: `revokeDescriptors`, `DescriptorRevoked`, `getDescriptorRevocationTimestamp`, the renamed typehashes and `hashDescriptorRevocations`; removal of the old revocation machinery including the old `MissingRevocation`; auto-revocation on displacement and `RevokedDescriptorReused` (decision 9); tests for per-pair isolation, the generalized whole-descriptor case, the audit-only timestamp bump, batching, relayed signing with nonce and replay rejection, auto-revoke on displacement, cross-context isolation, revived-hash rejection, and the already-revoked no-op case; `README.md` and the errors table updated.
3. **ERC-8283** — done (PR #7), pending review.
4. **Tooling** to split, flatten and build function indexes, in a separate repo or task.

## Non-goals

- Changing the off-chain registry.
- Formalizing the maximum descriptor size.
- Backward compatibility with whole-contract descriptors or the old revocation interface.
