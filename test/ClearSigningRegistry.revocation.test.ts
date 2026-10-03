import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodeAbiParameters, keccak256 } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const hashOf = (label: string) => keccak256(encodeAbiParameters([{ type: "string" }], [label]));

describe("ClearSigningRegistry descriptor revocation", async function () {
  const { viem, networkHelpers } = await network.create();
  const publicClient = await viem.getPublicClient();

  const contextA = hashOf("context-a");
  const contextB = hashOf("context-b");
  // Stand-ins for content hashes — e.g. a function descriptor's ERC-8176 descriptorHash, or a
  // whole-contract descriptor's / function index's own descriptorHash. The registry treats all of
  // these identically: an opaque bytes32 naming exact content.
  const oldTransferHash = hashOf("descriptor-transfer-v1");
  const approveHash = hashOf("descriptor-approve-v1");

  async function deploy() {
    const [attester, relayer] = await viem.getWalletClients();
    const registry = await viem.deployContract("ClearSigningRegistry");
    return { attester, relayer, registry };
  }

  async function registerFunctionIndex(
    registry: Awaited<ReturnType<typeof deploy>>["registry"],
    attesterAddress: `0x${string}`,
    label: string,
    contextKeyIds: `0x${string}`[],
  ) {
    const descriptorUris = [`ipfs://descriptor-${label}`];
    const attestationUris = [`ipfs://attestation-${label}`];
    await registry.write.publishMirrorLists([[descriptorUris, attestationUris]]);
    const descriptorMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [descriptorUris]));
    const attestationMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [attestationUris]));
    const descriptor = {
      descriptorHash: hashOf(`function-index-${label}`),
      descriptorSchemaMajor: 1n,
      contextKeyIds,
      attestationIds: [{ attestationId: hashOf(`att-${label}`), attestationFormatId: hashOf("erc7730.attestation.eas.offchain") }],
    };
    const hash = await registry.write.createAttestations([
      attesterAddress, [descriptor], descriptorMirrorListId, attestationMirrorListId, "0x",
    ]);
    return { descriptor, descriptorMirrorListId, attestationMirrorListId, hash };
  }

  it("records a revocation per (context, descriptorHash) and leaves every other pair untouched", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registry.write.revokeDescriptors([who, [{ contextKeyId: contextA, descriptorHash: oldTransferHash }], "0x"]);

    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([who, contextA, oldTransferHash]), 0n);
    assert.equal(await registry.read.getDescriptorRevocationTimestamp([who, contextA, approveHash]), 0n);
    assert.equal(await registry.read.getDescriptorRevocationTimestamp([who, contextB, oldTransferHash]), 0n);
  });

  it("a corrected descriptor's different hash is never affected by revoking the old one", async function () {
    // This is the whole point of keying by content: a correction naturally produces a
    // different descriptorHash, so there is nothing to coordinate — no issue-time, no
    // ordering, no second call needed to "clear" the new content.
    const { attester, registry } = await deploy();
    const who = attester.account.address;
    const newTransferHash = hashOf("descriptor-transfer-v2-corrected");

    await registry.write.revokeDescriptors([who, [{ contextKeyId: contextA, descriptorHash: oldTransferHash }], "0x"]);

    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([who, contextA, oldTransferHash]), 0n);
    assert.equal(await registry.read.getDescriptorRevocationTimestamp([who, contextA, newTransferHash]), 0n);
  });

  it("works identically for a whole-descriptor hash, not just a function's", async function () {
    // The registry never distinguishes a whole-contract descriptor, a function index, or a
    // single-function descriptor — revoking a function index's own descriptorHash uses the
    // exact same call as revoking one function within it.
    const { attester, registry } = await deploy();
    const who = attester.account.address;
    const { descriptor } = await registerFunctionIndex(registry, who, "release-1", [contextA]);

    await registry.write.revokeDescriptors([who, [{ contextKeyId: contextA, descriptorHash: descriptor.descriptorHash }], "0x"]);

    assert.notEqual(
      await registry.read.getDescriptorRevocationTimestamp([who, contextA, descriptor.descriptorHash]),
      0n,
    );
  });

  it("scopes revocations to the attester", async function () {
    const { attester, relayer, registry } = await deploy();

    await registry.write.revokeDescriptors([attester.account.address, [{ contextKeyId: contextA, descriptorHash: oldTransferHash }], "0x"]);

    assert.equal(
      await registry.read.getDescriptorRevocationTimestamp([relayer.account.address, contextA, oldTransferHash]),
      0n,
    );
  });

  it("emits DescriptorRevoked with the recorded timestamp", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    const hash = await registry.write.revokeDescriptors([who, [{ contextKeyId: contextA, descriptorHash: oldTransferHash }], "0x"]);
    await publicClient.waitForTransactionReceipt({ hash });

    const events = await registry.getEvents.DescriptorRevoked();
    assert.equal(events.length, 1);
    assert.equal(events[0].args.attester?.toLowerCase(), who.toLowerCase());
    assert.equal(events[0].args.contextKeyId, contextA);
    assert.equal(events[0].args.descriptorHash, oldTransferHash);
    assert.equal(events[0].args.timestamp, await registry.read.getDescriptorRevocationTimestamp([who, contextA, oldTransferHash]));
  });

  it("moving the audit timestamp forward on a repeat revocation changes nothing about validity", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;
    const entry = { contextKeyId: contextA, descriptorHash: oldTransferHash };

    await registry.write.revokeDescriptors([who, [entry], "0x"]);
    const first = await registry.read.getDescriptorRevocationTimestamp([who, contextA, oldTransferHash]);

    await networkHelpers.time.increase(100);
    await registry.write.revokeDescriptors([who, [entry], "0x"]);
    const second = await registry.read.getDescriptorRevocationTimestamp([who, contextA, oldTransferHash]);

    // The timestamp moves (audit trail), but there is no "un-revoke" and no consumer-side
    // ordering rule depends on this value beyond non-zero.
    assert.ok(second > first);
  });

  it("revokes a batch of pairs in one call", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registry.write.revokeDescriptors([
      who,
      [
        { contextKeyId: contextA, descriptorHash: oldTransferHash },
        { contextKeyId: contextB, descriptorHash: approveHash },
      ],
      "0x",
    ]);

    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([who, contextA, oldTransferHash]), 0n);
    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([who, contextB, approveHash]), 0n);
  });

  it("reverts on an empty batch", async function () {
    const { attester, registry } = await deploy();
    await assert.rejects(registry.write.revokeDescriptors([attester.account.address, [], "0x"]), /EmptyRevocations/);
  });

  it("rejects a relayed revocation without a valid attester signature", async function () {
    const { attester, relayer, registry } = await deploy();
    const relayed = await viem.getContractAt("ClearSigningRegistry", registry.address, { client: { wallet: relayer } });

    await assert.rejects(
      relayed.write.revokeDescriptors([attester.account.address, [{ contextKeyId: contextA, descriptorHash: oldTransferHash }], "0x"]),
      /InvalidRegistrationSignature/,
    );
    assert.equal(await registry.read.getDescriptorRevocationTimestamp([attester.account.address, contextA, oldTransferHash]), 0n);
  });

  it("accepts a relayed revocation signed by the attester, consumes the nonce, and rejects replay", async function () {
    const { relayer, registry } = await deploy();
    const attester = privateKeyToAccount("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
    const relayed = await viem.getContractAt("ClearSigningRegistry", registry.address, { client: { wallet: relayer } });
    const chainId = await publicClient.getChainId();

    const revocations = [{ contextKeyId: contextA, descriptorHash: oldTransferHash }];
    const nonce = await registry.read.getNonce([attester.address]);
    const signature = await attester.signTypedData({
      domain: { name: "ClearSigningRegistry", version: "1", chainId, verifyingContract: registry.address },
      types: {
        ClearSigningDescriptorRevocationBatch: [
          { name: "revocations", type: "DescriptorRevocation[]" },
          { name: "nonce", type: "uint256" },
        ],
        DescriptorRevocation: [
          { name: "contextKeyId", type: "bytes32" },
          { name: "descriptorHash", type: "bytes32" },
        ],
      },
      primaryType: "ClearSigningDescriptorRevocationBatch",
      message: { revocations, nonce },
    });

    await relayed.write.revokeDescriptors([attester.address, revocations, signature]);

    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([attester.address, contextA, oldTransferHash]), 0n);
    assert.equal(await registry.read.getNonce([attester.address]), nonce + 1n);
    await assert.rejects(relayed.write.revokeDescriptors([attester.address, revocations, signature]), /InvalidRegistrationSignature/);
  });

  it("lets createAttestations replace an active record without any prior revocation", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registerFunctionIndex(registry, who, "v1", [contextA]);
    const v2 = await registerFunctionIndex(registry, who, "v2", [contextA]);

    const [resolved] = await registry.read.resolveDescriptors([[who], [contextA], [1n], [], []]);
    assert.equal(resolved.descriptorHash, v2.descriptor.descriptorHash);
  });

  it("resolveDescriptors reports revocation inline, with no separate call needed", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    const v1 = await registerFunctionIndex(registry, who, "v1", [contextA]);

    const [freshResolved] = await registry.read.resolveDescriptors([[who], [contextA], [1n], [], []]);
    assert.equal(freshResolved.revokedAt, 0n);

    // Auto-revoked by displacement: resolving the NEW active record should show it clean...
    const v2 = await registerFunctionIndex(registry, who, "v2", [contextA]);
    const [v2Resolved] = await registry.read.resolveDescriptors([[who], [contextA], [1n], [], []]);
    assert.equal(v2Resolved.descriptorHash, v2.descriptor.descriptorHash);
    assert.equal(v2Resolved.revokedAt, 0n);

    // ...while the OLD hash is now provably dead, confirmed the same way resolveDescriptors
    // would report it if it were still the active record (it's displaced, so we check the
    // underlying mapping directly here, same value resolveDescriptors would have inlined).
    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([who, contextA, v1.descriptor.descriptorHash]), 0n);

    // Now revoke the CURRENTLY active v2 record explicitly (no replacement registered) and
    // confirm resolveDescriptors itself reflects it without any extra call.
    await registry.write.revokeDescriptors([who, [{ contextKeyId: contextA, descriptorHash: v2.descriptor.descriptorHash }], "0x"]);
    const [v2AfterRevoke] = await registry.read.resolveDescriptors([[who], [contextA], [1n], [], []]);
    assert.notEqual(v2AfterRevoke.revokedAt, 0n);
  });

  it("auto-revokes the displaced descriptorHash atomically, with no separate call", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    const v1 = await registerFunctionIndex(registry, who, "v1", [contextA]);
    assert.equal(await registry.read.getDescriptorRevocationTimestamp([who, contextA, v1.descriptor.descriptorHash]), 0n);

    const v2 = await registerFunctionIndex(registry, who, "v2", [contextA]);
    await publicClient.waitForTransactionReceipt({ hash: v2.hash });

    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([who, contextA, v1.descriptor.descriptorHash]), 0n);
    const events = await registry.getEvents.DescriptorRevoked();
    assert.equal(events.length, 1);
    assert.equal(events[0].args.contextKeyId, contextA);
    assert.equal(events[0].args.descriptorHash, v1.descriptor.descriptorHash);
  });

  it("does not touch other contexts sharing the attester when displacing one", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registerFunctionIndex(registry, who, "shared-v1", [contextA, contextB]);
    await registerFunctionIndex(registry, who, "shared-v2", [contextA]); // only displaces contextA

    const v1Hash = hashOf("function-index-shared-v1");
    assert.notEqual(await registry.read.getDescriptorRevocationTimestamp([who, contextA, v1Hash]), 0n);
    assert.equal(await registry.read.getDescriptorRevocationTimestamp([who, contextB, v1Hash]), 0n);

    const [resolvedB] = await registry.read.resolveDescriptors([[who], [contextB], [1n], [], []]);
    assert.equal(resolvedB.descriptorHash, v1Hash); // untouched: still active at contextB
  });

  it("reverts RevokedDescriptorReused when registering an already-revoked descriptorHash at that context", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registerFunctionIndex(registry, who, "v1", [contextA]);
    await registerFunctionIndex(registry, who, "v2", [contextA]); // auto-revokes v1's hash at contextA

    // Trying to bring v1's exact content back, at the same context, must fail.
    const descriptorUris = ["ipfs://descriptor-v1-revival"];
    const attestationUris = ["ipfs://attestation-v1-revival"];
    await registry.write.publishMirrorLists([[descriptorUris, attestationUris]]);
    const descriptorMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [descriptorUris]));
    const attestationMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [attestationUris]));

    await assert.rejects(
      registry.write.createAttestations([
        who,
        [{
          descriptorHash: hashOf("function-index-v1"),
          descriptorSchemaMajor: 1n,
          contextKeyIds: [contextA],
          attestationIds: [{ attestationId: hashOf("att-v1-revival"), attestationFormatId: hashOf("erc7730.attestation.eas.offchain") }],
        }],
        descriptorMirrorListId, attestationMirrorListId, "0x",
      ]),
      /RevokedDescriptorReused/,
    );
  });

  it("blocks a revoked descriptorHash even on first-time activation of a fresh context", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    // Pre-emptively revoke content that was never registered anywhere.
    const neverRegisteredHash = hashOf("never-registered");
    await registry.write.revokeDescriptors([who, [{ contextKeyId: contextA, descriptorHash: neverRegisteredHash }], "0x"]);

    const descriptorUris = ["ipfs://descriptor-fresh"];
    const attestationUris = ["ipfs://attestation-fresh"];
    await registry.write.publishMirrorLists([[descriptorUris, attestationUris]]);
    const descriptorMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [descriptorUris]));
    const attestationMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [attestationUris]));

    await assert.rejects(
      registry.write.createAttestations([
        who,
        [{
          descriptorHash: neverRegisteredHash,
          descriptorSchemaMajor: 1n,
          contextKeyIds: [contextA], // contextA has never had any active record
          attestationIds: [{ attestationId: hashOf("att-fresh"), attestationFormatId: hashOf("erc7730.attestation.eas.offchain") }],
        }],
        descriptorMirrorListId, attestationMirrorListId, "0x",
      ]),
      /RevokedDescriptorReused/,
    );
  });

  it("does not move the timestamp of an already-explicitly-revoked hash when it is later displaced", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    const v1 = await registerFunctionIndex(registry, who, "v1", [contextA]);
    await registry.write.revokeDescriptors([who, [{ contextKeyId: contextA, descriptorHash: v1.descriptor.descriptorHash }], "0x"]);
    const explicitTimestamp = await registry.read.getDescriptorRevocationTimestamp([who, contextA, v1.descriptor.descriptorHash]);

    await networkHelpers.time.increase(100);
    // v1 is still (surprisingly, but validly) the active record — explicit revocation does
    // not clear the active pointer — so this still counts as a displacement.
    await registerFunctionIndex(registry, who, "v2", [contextA]);

    assert.equal(
      await registry.read.getDescriptorRevocationTimestamp([who, contextA, v1.descriptor.descriptorHash]),
      explicitTimestamp,
    );
  });

  it("does not expose the removed attestation-ID revocation interface", async function () {
    const { registry } = await deploy();
    const functionNames = registry.abi.filter((item) => item.type === "function").map((item) => item.name);
    assert.ok(!functionNames.includes("getRevocationTimestamp"));
    const errorNames = registry.abi.filter((item) => item.type === "error").map((item) => item.name);
    assert.ok(!errorNames.includes("MissingRevocation"));
  });
});
