# ERC-8283 Clear Signing Registry

Reference implementation of [ERC-8283](https://ethereum-magicians.org/t/erc-8283-on-chain-registry-for-erc-7730-clear-signing-descriptors/28717), an on-chain registry for [ERC-7730](https://eips.ethereum.org/EIPS/eip-7730) Clear Signing descriptors.

This implementation is **not audited** and is intended for specification clarity only; production contracts will undergo an independent security review before deployment.

```bash
npm install
npm run compile
npm test
```

## `IClearSigningRegistry` walkthrough

**Attester Signer Entity** (the attester)

**IPFS Mirror Operator** (an independent mirror operator)

**Relayer Service** (relays authorized actions on the attester's behalf)

**Wallet Client** (the user)

## Constants

```TypeScript
import {
  createPublicClient,
  createWalletClient,
  http,
  getContract,
  keccak256,
  toHex,
  encodeAbiParameters,
  parseEventLogs,
  type Address,
  type Hex,
} from "viem";
import { mainnet } from "viem/chains";
import { privateKeyToAccount } from "viem/accounts";
import { IClearSigningRegistryAbi } from "./abi"; // the compiled contract's ABI JSON

const REGISTRY_ADDRESS: Address = "0xREGISTRY0000000000000000000000000000000";

const publicClient = createPublicClient({ chain: mainnet, transport: http() });

const attesterAccount = privateKeyToAccount(ATTESTER_PRIVATE_KEY);
const relayerAccount = privateKeyToAccount(RELAYER_PRIVATE_KEY);
const ipfsPinnerAccount = privateKeyToAccount(PINNING_PRIVATE_KEY); // independent IPFS mirror operator

const attesterClient = createWalletClient({ account: attesterAccount, chain: mainnet, transport: http() });
const relayerClient = createWalletClient({ account: relayerAccount, chain: mainnet, transport: http() });
const ipfsPinnerClient = createWalletClient({ account: ipfsPinnerAccount, chain: mainnet, transport: http() });

// Binds the registry ABI to a given wallet client, so every call below reads
// as "<role> calls <function>" the same way `registry.connect(signer)` did.
function registryAs(walletClient: typeof attesterClient) {
  return getContract({ address: REGISTRY_ADDRESS, abi: IClearSigningRegistryAbi, client: { public: publicClient, wallet: walletClient } });
}
const registryRead = getContract({ address: REGISTRY_ADDRESS, abi: IClearSigningRegistryAbi, client: publicClient });

const mainnetChainId = 1n;
const optimismChainId = 10n;

const ATTESTATION_FORMAT_EAS_OFFCHAIN = keccak256(toHex("erc7730.attestation.eas.offchain"));

const eip712Domain = { name: "ClearSigningRegistry", version: "1", chainId: 1, verifyingContract: REGISTRY_ADDRESS } as const;
```


```TypeScript
function deriveContextKeyId(chainId: bigint, contractAddress: Address): Hex {
  const CONTEXT_TAG_CONTRACT = keccak256(toHex("erc7730.context.contract"));
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }],
      [CONTEXT_TAG_CONTRACT, chainId, contractAddress],
    ),
  );
}

function deriveFactoryContextKeyId(chainId: bigint, factoryAddress: Address, deployEventSignature: string): Hex {
  const CONTEXT_TAG_FACTORY = keccak256(toHex("erc7730.context.factory"));
  const deployEventTopic = keccak256(toHex(deployEventSignature)); // topic0 = hash of the event signature string
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }, { type: "bytes32" }],
      [CONTEXT_TAG_FACTORY, chainId, factoryAddress, deployEventTopic],
    ),
  );
}

function deriveEip712DeploymentContextKeyId(chainId: bigint, verifyingContract: Address): Hex {
  const CONTEXT_TAG_EIP712_DEP = keccak256(toHex("erc7730.context.eip712.deployment"));
  return keccak256(
    encodeAbiParameters(
      [{ type: "bytes32" }, { type: "uint256" }, { type: "address" }],
      [CONTEXT_TAG_EIP712_DEP, chainId, verifyingContract],
    ),
  );
}

function deriveDomainSeparatorContextKeyId(domainSeparator: Hex): Hex {
  const CONTEXT_TAG_EIP712_DS = keccak256(toHex("erc7730.context.eip712.domainseparator"));
  return keccak256(
    encodeAbiParameters([{ type: "bytes32" }, { type: "bytes32" }], [CONTEXT_TAG_EIP712_DS, domainSeparator]),
  );
}
```

## 1. `publishMirrorLists` — **IPFS Mirror Operator** publishes retrieval URIs

Descriptor JSON and signed attestation blobs are published the same way — the registry never distinguishes the two, only the caller's later references do. A single list itself may carry several URIs — redundant mirrors of the exact same content. `createAttestations` below only ever takes an *already-published* MirrorList id — it has no way to publish one itself — so both lists it will need are published here first, in one batch:

```TypeScript
const releaseDescriptorIndexUris = [
  "ipfs://bafybeigd.../vault-and-staking-descriptors-index.json",
  "ar://vault-and-staking-descriptors-index-mirror",
];
const releaseAttestationIndexUris = ["ipfs://bafybeigd.../release-attestations-index.json"];

const publishHash = await registryAs(ipfsPinnerClient).write.publishMirrorLists([[releaseDescriptorIndexUris, releaseAttestationIndexUris]]);
const publishReceipt = await publicClient.waitForTransactionReceipt({ hash: publishHash });
const [
  { args: { mirrorListId: descriptorMirrorListId } },
  { args: { mirrorListId: attestationMirrorListId } },
] = parseEventLogs({ abi: IClearSigningRegistryAbi, eventName: "MirrorListPublished", logs: publishReceipt.logs });

console.log(descriptorMirrorListId); // keccak256(abi.encode(releaseDescriptorIndexUris)) — callers can precompute this offline
```

## 2. `createAttestations` — the first batched registration

Every field that accepts multiple elements as inputs is supplied with two elements. Let's say there are two contracts in the project: `Vault` and `Staking`. The `Vault` is deployed on Mainnet and Optimism.

```TypeScript
const vaultMainnetAddress: Address = "0xAcmeVaultMainnet00000000000000000000000000";
const vaultOptimismAddress: Address = "0xAcmeVaultOptimism0000000000000000000000000";
const stakingContractAddress: Address = "0xAcmeStaking000000000000000000000000000000";

// The attester produces its off-chain EAS attestations following the ERC-8176 rules — out of scope
const descriptorHash: Hex = "0x7c3a1e2b...5d6e7f";
const attestationId: Hex = "0x4f0eaa11...8091a2";
const stakingDescriptorHash: Hex = "0x1a2b3c4d5e...d6e7f80";
const stakingEasAttestationId: Hex = "0x2233445566...889900aabb";
const stakingDeviceAttestationId: Hex = "0x334455667...9900aabbcc";
const VENDOR_FORMAT_CUSTOM = keccak256(toHex("erc7730.attestation.vendor.custom"));

const descriptorSchemaMajor = 3n; // MAJOR version of the descriptor's schema

// Contract #1 - Vault
const vaultDescriptor = {
  descriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [
    deriveContextKeyId(mainnetChainId, vaultMainnetAddress),    // mainnet deployment
    deriveContextKeyId(optimismChainId, vaultOptimismAddress),  // an L2 deployment
  ],
  attestationIds: [{ attestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};

// Contract #2 - Staking
const stakingDescriptor = {
  descriptorHash: stakingDescriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [deriveContextKeyId(mainnetChainId, stakingContractAddress)],
  attestationIds: [
    // There is no canonical attestation ID or file format;
    // An attester can issue different attestations for the same contract:
    { attestationId: stakingEasAttestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN },
    { attestationId: stakingDeviceAttestationId, attestationFormatId: VENDOR_FORMAT_CUSTOM },
  ],
};

// Both MirrorLists (published together in step 1) resolve to an index.json file —
// 'descriptorMirrorListId' keyed by 'descriptorHash', 'attestationMirrorListId' by 'attestationSetId'.

// The attester submits directly without a relay
const createHash = await registryAs(attesterClient).write.createAttestations([
  attesterAccount.address,
  [vaultDescriptor, stakingDescriptor], // batched — one transaction, two descriptors, four contexts
  descriptorMirrorListId,
  attestationMirrorListId,
  "0x", // signature — not needed, the attester is msg.sender
]);
const createReceipt = await publicClient.waitForTransactionReceipt({ hash: createHash });
const [{ args: vaultRegistered }, { args: stakingRegistered }] = parseEventLogs({
  abi: IClearSigningRegistryAbi, eventName: "AttestationRegistered", logs: createReceipt.logs,
});
const vaultAttestationSetId = vaultRegistered.attestationSetId; // === attestationId (single-member set)
const stakingSetId = stakingRegistered.attestationSetId; // content-derived (two members)
```

## 3. `resolveDescriptors` and `getRevocationTimestamp` — the wallet fetches registry data before rendering

Every parameter here acts as a filter or a lookup key set.
A real wallet passes its whole trust list, every candidate context, and every schema MAJOR version, and the attestation format it supports in one call:

```TypeScript
const trustedAttesterOne: Address = "0xTrustedAttester1000000000000000000000000";
const trustedAttesterTwo: Address = "0xTrustedAttester2000000000000000000000000";

const resolved = await registryRead.read.resolveDescriptors([
  /* this wallet's full list of trusted attesters */
  [trustedAttesterOne, trustedAttesterTwo],
  /* contracts the wallet is interacting with, as their contextKeyIds */
  [deriveContextKeyId(mainnetChainId, vaultMainnetAddress), deriveContextKeyId(optimismChainId, vaultOptimismAddress)],
  /* this wallet's firmware understands these schema major versions */
  [1n, 2n, 3n],
  /* this wallet only verifies the EAS attestations */
  [ATTESTATION_FORMAT_EAS_OFFCHAIN],
  /* this wallet only supports these two protocols */
  ["ipfs:", "https:"],
]);
```

Returned array — one entry per active `(attester, contextKeyId, descriptorSchemaMajor)` record, ordered `attesters` first, then `contextKeyIds`, then `descriptorSchemaMajors`. Both of the vault's deployments resolve here, sharing the same descriptor and mirrors but under different context key IDs:

```json
[
  {
    "descriptorHash": "0x7c3a...d6e7f",
    "contextKeyId": "0x8b41...c209",
    "descriptorSchemaMajor": "1",
    "attestationSetId": "0x4f0e...d6e7f",
    "descriptorMirrorListUris": ["ipfs://bafybeigd.../vault-and-staking-descriptors-index.json", "ar://vault-and-staking-descriptors-index-mirror"],
    "attestationMirrorListUris": ["ipfs://bafybeigd.../release-attestations-index.json"],
    "attestations": [
      { "attester": "0xAttester0000000000000000000000000000000", "attestationId": "0x4f0e...d6e7f", "attestationFormatId": "0x9b2c...eas0f", "revokedAt": "0" }
    ]
  },
  {
    "descriptorHash": "0x7c3a...d6e7f",
    "contextKeyId": "0x2f19...ab77",
    "descriptorSchemaMajor": "1",
    "attestationSetId": "0x4f0e...d6e7f",
    "descriptorMirrorListUris": ["ipfs://bafybeigd.../vault-and-staking-descriptors-index.json", "ar://vault-and-staking-descriptors-index-mirror"],
    "attestationMirrorListUris": ["ipfs://bafybeigd.../release-attestations-index.json"],
    "attestations": [
      { "attester": "0xAttester0000000000000000000000000000000", "attestationId": "0x4f0e...d6e7f", "attestationFormatId": "0x9b2c...eas0f", "revokedAt": "0" }
    ]
  }
]
```

The wallet validates every candidate entry, checking for availability, validity, and revocations (pseudocode):

```TypeScript
for (const entry of resolved) {
  // A stale active record can still point at an already-revoked set
  const setRevokedAt = await registryRead.read.getRevocationTimestamp([attesterAccount.address, entry.attestationSetId]);
  if (setRevokedAt !== 0n) continue;

  const descriptorBytes = await fetch(entry.descriptorMirrorListUris[0]).then((r) => r.arrayBuffer());
  if (!isValidDescriptor(descriptorBytes)) continue;

  const easAttestationEntry = entry.attestations.find((a) => a.attestationFormatId === ATTESTATION_FORMAT_EAS_OFFCHAIN);
  if (!isValidEasAttesation(easAttestationEntry)) continue;

  renderClearSigningPrompt(JSON.parse(new TextDecoder().decode(descriptorBytes)));
  break; // no need to check the rest - this candidate matched - we can render the transaction signing request
}
throw new Error("Valid entry not found")
```

## 4. `revokeAttestations` — batching a whole set with an individual member

`createAttestations` never revokes anything itself, so retiring the Vault's v1 attestation set — ahead of registering v2 in the next section — has to happen here, as its own call. The same call also batches in an unrelated cleanup: dropping just the Staking descriptor's vendor rendition. Two different `RevocationEntry` shapes side by side:
* a set id withdraws the whole release
* a single attestation id flags only that one rendition while the rest of the set stays active

```TypeScript
await registryAs(attesterClient).write.revokeAttestations([
  attesterAccount.address,
  [
    { attestationId: vaultAttestationSetId, contextKeyIds: [deriveContextKeyId(mainnetChainId, vaultMainnetAddress), deriveContextKeyId(optimismChainId, vaultOptimismAddress)] },
    { attestationId: stakingDeviceAttestationId, contextKeyIds: [] },
  ],
  "0x", // signature
]);
```

The `revokeAttestations` function can also be invoked with an EIP-712 signature similar to `createAttestations`.

## 5. Using `createAttestations` for updates & relayed transactions

In this example we are issuing an update to the previously registered `Vault` contract.
This is a legitimate and common operation - the contract may be upgradeable and changed its behaviour.
The old attestation set (`vaultAttestationSetId`) was already revoked in the previous section — `createAttestations` requires that precondition to already hold and never revokes anything itself.
We will also use a relayer address instead of making the registry call directly from the attester's EOA address.

```TypeScript
const nonce = await registryRead.read.getNonce([attesterAccount.address]);

const newDescriptorHash: Hex = "0x99aa88b...44556677";
const newAttestationId: Hex = "0x55ee44...bccddee";
const mainnetContextKeyId = deriveContextKeyId(mainnetChainId, vaultMainnetAddress);
const optimismContextKeyId = deriveContextKeyId(optimismChainId, vaultOptimismAddress);

const newDescriptor = {
  descriptorHash: newDescriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [mainnetContextKeyId, optimismContextKeyId], // assuming both deployments updated together
  attestationIds: [{ attestationId: newAttestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};
const newAttestationSetId = newAttestationId; // a small quirk: single-member set can reuse its sole member's own id

// The new attestation blob lives at a new location, so its MirrorList has to be
// published (again, as its own prior step) before it can be referenced below.
const republishHash = await registryAs(ipfsPinnerClient).write.publishMirrorLists([[["ipfs://bafybeigd.../vault-attestation-v2.json"]]]);
const republishReceipt = await publicClient.waitForTransactionReceipt({ hash: republishHash });
const [{ args: { mirrorListId: newAttestationMirrorListId } }] = parseEventLogs({
  abi: IClearSigningRegistryAbi, eventName: "MirrorListPublished", logs: republishReceipt.logs,
});

const registrationTypes = { /* ... normal EIP-712 boilerplate types declaration, matching the typehashes in the ERC */ } as const;

const signature = await attesterClient.signTypedData({
  account: attesterAccount,
  domain: eip712Domain,
  types: registrationTypes,
  primaryType: "ClearSigningRegistrationBatch",
  message: {
    descriptors: [newDescriptor],
    descriptorMirrorListId, // URLs can remain unchanged
    attestationMirrorListId: newAttestationMirrorListId,
    nonce,
  },
});

// a relayer is the address making the actual transaction
await registryAs(relayerClient).write.createAttestations([
  attesterAccount.address, [newDescriptor], descriptorMirrorListId, newAttestationMirrorListId, signature,
]);
```

## 6. `updateDescriptorMirrorList` — rotating descriptor storage for several descriptors at once

Republishing both a **new descriptor** index and a **new attestation** index in one transaction.
Index files store mappings from ID to actual data.

```TypeScript
const republished2Hash = await registryAs(ipfsPinnerClient).write.publishMirrorLists([[
  ["ipfs://bafybeiNEW.../release-descriptors-index-v2.json"],
  ["ipfs://bafybeiNEW.../release-attestations-index-v2.json", "ar://release-attestations-index-v2-mirror"],
]]);
const republished2Receipt = await publicClient.waitForTransactionReceipt({ hash: republished2Hash });
const [
  { args: { mirrorListId: newDescriptorMirrorListId } },
  { args: { mirrorListId: rotatedAttestationMirrorListId } },
] = parseEventLogs({ abi: IClearSigningRegistryAbi, eventName: "MirrorListPublished", logs: republished2Receipt.logs });

// Rotate both the current vault descriptor and the staking descriptor together:
const descriptorHashes = [newDescriptorHash, stakingDescriptorHash];

// self-submitted transaction
await registryAs(attesterClient).write.updateDescriptorMirrorList([
  attesterAccount.address, descriptorHashes, newDescriptorMirrorListId, "0x",
]);
```

## 7. `updateAttestationMirrorList` — rotating attestation blob storage for several sets at once

Reuses the attestation index published in the previous section, rotating both attestation sets registered so far to point at it in one call:

```TypeScript
const attestationSetIds = [newAttestationSetId, stakingSetId];

await registryAs(attesterClient).write.updateAttestationMirrorList([
  attesterAccount.address, attestationSetIds, rotatedAttestationMirrorListId, "0x",
]);
```

## 8. `setAttesterProfileURI` and `getAttesterProfileURI`

```TypeScript
// The profile JSON itself lives off-chain in the following format:
//   {
//     "version": 1,
//     "attesters": ["0xAttester0000000000000000000000000000000", "0xAttesterHotWallet00000000000000000000000"],
//     "name": "Example Attester Inc.",
//     "securityContact": "mailto:security@attester.example.com"
//   }

await registryAs(attesterClient).write.setAttesterProfileURI([
  attesterAccount.address, "ipfs://bafybeigd.../attester-profile.json", "0x",
]);

const profileURI = await registryRead.read.getAttesterProfileURI([attesterAccount.address]);
```

A consumer that already trusts `attesterAccount.address` renders the profile only after checking the back-reference:

```TypeScript
const profile = await fetch(profileURI).then((r) => r.json());
if (profile.version !== 1) throw new Error("unsupported profile version");
if (!profile.attesters.some((a: string) => a.toLowerCase() === attesterAccount.address.toLowerCase())) {
  throw new Error("profile does not name the trusted attester — do not render it");
}
renderAttesterCard(profile.name);
```

## 9. Non-deployment context types — factory, EIP-712 deployments, and domain separators

`contextKeyIds` is a flat `bytes32[]` — nothing about an entry reveals which ERC-7730 binding type produced it. A single descriptor can mix every derivation rule freely:

```TypeScript
const vaultFactoryAddress: Address = "0xAcmeVaultFactory000000000000000000000000";
const deployEventSignature = "VaultCreated(address,address)"; // matches the descriptor's `context.contract.factory.deployEvent`
const permitRouterAddress: Address = "0xAcmePermitRouter00000000000000000000000";
const legacyDomainSeparator: Hex = "0xdeadbeef00000000000000000000000000000000000000000000000000cafebabe"; // precomputed off-chain per EIP-712

const factoryDescriptorHash: Hex = "0xaa11bb22...ee33ff44";
const factoryAttestationId: Hex = "0xbb22cc33...ff445566";

const factoryDescriptor = {
  descriptorHash: factoryDescriptorHash,
  descriptorSchemaMajor,
  contextKeyIds: [
    deriveFactoryContextKeyId(mainnetChainId, vaultFactoryAddress, deployEventSignature),   // any contract this factory deploys
    deriveEip712DeploymentContextKeyId(mainnetChainId, permitRouterAddress),                // an EIP-712 verifyingContract
    deriveDomainSeparatorContextKeyId(legacyDomainSeparator),                                // a precomputed domain separator
  ],
  attestationIds: [{ attestationId: factoryAttestationId, attestationFormatId: ATTESTATION_FORMAT_EAS_OFFCHAIN }],
};

// Reuses the release indexes already published in step 1 — no new MirrorList needed.
await registryAs(attesterClient).write.createAttestations([
  attesterAccount.address,
  [factoryDescriptor],
  descriptorMirrorListId,
  attestationMirrorListId,
  "0x", // signature
]);

const resolvedFactory = await registryRead.read.resolveDescriptors([
  [attesterAccount.address],
  factoryDescriptor.contextKeyIds,
  [descriptorSchemaMajor],
  [ATTESTATION_FORMAT_EAS_OFFCHAIN],
  ["ipfs:", "https:"],
]);
// shape identical to §3's output — one entry per contextKeyId, same fields
```

## Errors at a glance

| Error | Raised when | See |
|---|---|---|
| `EmptyDescriptors` | `descriptors` is empty in `createAttestations` | §2 |
| `ZeroDescriptorHash` | a descriptor's `descriptorHash` is `bytes32(0)` | §2 |
| `ZeroDescriptorSchemaMajor` | a descriptor's `descriptorSchemaMajor` is `0` | §2 |
| `EmptyContextKeyIds` | a descriptor's `contextKeyIds` is empty | §2 |
| `EmptyAttestationIds` | a descriptor's `attestationIds` is empty | §2 |
| `ZeroAttestationId` | an `attestationIds`/`RevocationEntry` entry's `attestationId` is `bytes32(0)` | §2, §4 |
| `ZeroAttestationFormat` | an `attestationIds` entry's `attestationFormatId` is `bytes32(0)` | §2 |
| `DuplicateAttestationFormat` | two entries in the same descriptor share an `attestationFormatId` | §2 |
| `AttestationIdAlreadyUsed` | an attestation or set id was already revoked, or a reused set id doesn't match the stored record | §2 |
| `EmptyMirrorList` | `publishMirrorLists` is given an empty URI list | §1 |
| `UnknownMirrorList` | a `descriptorMirrorListId`/`attestationMirrorListId` was never published via `publishMirrorLists` | §2 |
| `UnknownDescriptor` | `updateDescriptorMirrorList` names a descriptor hash the attester never registered | §6 |
| `UnknownAttestationSet` | `updateAttestationMirrorList` names a set id the attester never registered | §7 |
| `EmptyRevocations` | `revokeAttestations` is called with an empty `revocations` array | §4 |
| `EmptyKeys` | `updateDescriptorMirrorList`/`updateAttestationMirrorList` is given an empty key array | §6 |
| `MissingRevocation` | a descriptor in `createAttestations` displaces an active record whose set id isn't recorded as revoked yet — see §4/§5 for the required revoke-then-register order | §5 |
| `InvalidRegistrationSignature` | any relayed `signature` fails to verify for the named attester | §5 |
