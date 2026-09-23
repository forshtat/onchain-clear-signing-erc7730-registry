import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodeAbiParameters, keccak256 } from "viem";
import { privateKeyToAccount } from "viem/accounts";

const hashOf = (label: string) => keccak256(encodeAbiParameters([{ type: "string" }], [label]));

// A 4-byte selector left-aligned in a bytes32, the same value as a Solidity bytes4-to-bytes32 cast.
const selectorKey = (selector: `0x${string}`) => `${selector}${"00".repeat(28)}` as `0x${string}`;

describe("ClearSigningRegistry function revocation", async function () {
  const { viem, networkHelpers } = await network.create();
  const publicClient = await viem.getPublicClient();

  const contextA = hashOf("context-a");
  const contextB = hashOf("context-b");
  const transferKey = selectorKey("0xa9059cbb");
  const approveKey = selectorKey("0x095ea7b3");

  async function deploy() {
    const [attester, relayer] = await viem.getWalletClients();
    const registry = await viem.deployContract("ClearSigningRegistry");
    return { attester, relayer, registry };
  }

  async function registerManifest(
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
      descriptorHash: hashOf(`manifest-${label}`),
      descriptorSchemaMajor: 1n,
      contextKeyIds,
      attestationIds: [{ attestationId: hashOf(`att-${label}`), attestationFormatId: hashOf("erc7730.attestation.eas.offchain") }],
    };
    await registry.write.createAttestations([
      attesterAddress, [descriptor], descriptorMirrorListId, attestationMirrorListId, "0x",
    ]);
    return { descriptor, descriptorMirrorListId, attestationMirrorListId };
  }

  it("records a revocation per (context, function) and leaves every other tuple untouched", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registry.write.revokeFunctions([who, [{ contextKeyId: contextA, functionKey: transferKey }], "0x"]);

    assert.notEqual(await registry.read.getFunctionRevocationTimestamp([who, contextA, transferKey]), 0n);
    assert.equal(await registry.read.getFunctionRevocationTimestamp([who, contextA, approveKey]), 0n);
    assert.equal(await registry.read.getFunctionRevocationTimestamp([who, contextB, transferKey]), 0n);
  });

  it("scopes revocations to the attester", async function () {
    const { attester, relayer, registry } = await deploy();

    await registry.write.revokeFunctions([attester.account.address, [{ contextKeyId: contextA, functionKey: transferKey }], "0x"]);

    assert.equal(
      await registry.read.getFunctionRevocationTimestamp([relayer.account.address, contextA, transferKey]),
      0n,
    );
  });

  it("emits FunctionRevoked with the recorded timestamp", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    const hash = await registry.write.revokeFunctions([who, [{ contextKeyId: contextA, functionKey: transferKey }], "0x"]);
    await publicClient.waitForTransactionReceipt({ hash });

    const events = await registry.getEvents.FunctionRevoked();
    assert.equal(events.length, 1);
    assert.equal(events[0].args.attester?.toLowerCase(), who.toLowerCase());
    assert.equal(events[0].args.contextKeyId, contextA);
    assert.equal(events[0].args.functionKey, transferKey);
    assert.equal(events[0].args.timestamp, await registry.read.getFunctionRevocationTimestamp([who, contextA, transferKey]));
  });

  it("moves the timestamp forward when the same tuple is revoked again", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;
    const entry = { contextKeyId: contextA, functionKey: transferKey };

    await registry.write.revokeFunctions([who, [entry], "0x"]);
    const first = await registry.read.getFunctionRevocationTimestamp([who, contextA, transferKey]);

    await networkHelpers.time.increase(100);
    await registry.write.revokeFunctions([who, [entry], "0x"]);
    const second = await registry.read.getFunctionRevocationTimestamp([who, contextA, transferKey]);

    assert.ok(second > first);
  });

  it("revokes a batch of tuples in one call", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registry.write.revokeFunctions([
      who,
      [
        { contextKeyId: contextA, functionKey: transferKey },
        { contextKeyId: contextB, functionKey: approveKey },
      ],
      "0x",
    ]);

    assert.notEqual(await registry.read.getFunctionRevocationTimestamp([who, contextA, transferKey]), 0n);
    assert.notEqual(await registry.read.getFunctionRevocationTimestamp([who, contextB, approveKey]), 0n);
  });

  it("reverts on an empty batch", async function () {
    const { attester, registry } = await deploy();
    await assert.rejects(registry.write.revokeFunctions([attester.account.address, [], "0x"]), /EmptyRevocations/);
  });

  it("rejects a relayed revocation without a valid attester signature", async function () {
    const { attester, relayer, registry } = await deploy();
    const relayed = await viem.getContractAt("ClearSigningRegistry", registry.address, { client: { wallet: relayer } });

    await assert.rejects(
      relayed.write.revokeFunctions([attester.account.address, [{ contextKeyId: contextA, functionKey: transferKey }], "0x"]),
      /InvalidRegistrationSignature/,
    );
    assert.equal(await registry.read.getFunctionRevocationTimestamp([attester.account.address, contextA, transferKey]), 0n);
  });

  it("accepts a relayed revocation signed by the attester, consumes the nonce, and rejects replay", async function () {
    const { relayer, registry } = await deploy();
    const attester = privateKeyToAccount("0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80");
    const relayed = await viem.getContractAt("ClearSigningRegistry", registry.address, { client: { wallet: relayer } });
    const chainId = await publicClient.getChainId();

    const revocations = [{ contextKeyId: contextA, functionKey: transferKey }];
    const nonce = await registry.read.getNonce([attester.address]);
    const signature = await attester.signTypedData({
      domain: { name: "ClearSigningRegistry", version: "1", chainId, verifyingContract: registry.address },
      types: {
        ClearSigningFunctionRevocationBatch: [
          { name: "revocations", type: "FunctionRevocation[]" },
          { name: "nonce", type: "uint256" },
        ],
        FunctionRevocation: [
          { name: "contextKeyId", type: "bytes32" },
          { name: "functionKey", type: "bytes32" },
        ],
      },
      primaryType: "ClearSigningFunctionRevocationBatch",
      message: { revocations, nonce },
    });

    await relayed.write.revokeFunctions([attester.address, revocations, signature]);

    assert.notEqual(await registry.read.getFunctionRevocationTimestamp([attester.address, contextA, transferKey]), 0n);
    assert.equal(await registry.read.getNonce([attester.address]), nonce + 1n);
    await assert.rejects(relayed.write.revokeFunctions([attester.address, revocations, signature]), /InvalidRegistrationSignature/);
  });

  it("lets createAttestations replace an active record without any prior revocation", async function () {
    const { attester, registry } = await deploy();
    const who = attester.account.address;

    await registerManifest(registry, who, "v1", [contextA]);
    const v2 = await registerManifest(registry, who, "v2", [contextA]);

    const [resolved] = await registry.read.resolveDescriptors([[who], [contextA], [1n], [], []]);
    assert.equal(resolved.descriptorHash, v2.descriptor.descriptorHash);
  });

  it("does not expose the removed attestation-ID revocation interface", async function () {
    const { registry } = await deploy();
    const functionNames = registry.abi.filter((item) => item.type === "function").map((item) => item.name);
    assert.ok(!functionNames.includes("getRevocationTimestamp"));
    const errorNames = registry.abi.filter((item) => item.type === "error").map((item) => item.name);
    assert.ok(!errorNames.includes("MissingRevocation"));
  });
});
