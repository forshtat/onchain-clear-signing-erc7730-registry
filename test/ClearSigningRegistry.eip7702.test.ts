import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodeAbiParameters, keccak256 } from "viem";
import { privateKeyToAccount } from "viem/accounts";

// Reproduces a review finding: a code-bearing EOA (e.g. one that delegated
// via EIP-7702) must still be able to authorize a relayed registration with
// a plain ECDSA signature, exactly as a plain EOA does. `hardhat_setCode`
// gives the attester's own address non-empty code, the same externally
// observable effect an EIP-7702 delegation has, without needing a real
// type-4 transaction.
describe("ClearSigningRegistry EIP-7702-style attester", async function () {
  const { viem } = await network.create();

  it("verifies a relayed ECDSA signature from a code-bearing attester address", async function () {
    const [, relayer] = await viem.getWalletClients();
    const publicClient = await viem.getPublicClient();
    const registry = await viem.deployContract("ClearSigningRegistry");

    const attester = privateKeyToAccount(
      "0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80",
    );
    // Simulate an EIP-7702 delegation: the attester's own EOA address now has
    // non-empty code (a delegation designator in the real protocol; any
    // non-empty bytecode reproduces the `code.length > 0` branch here).
    await publicClient.request({
      method: "hardhat_setCode" as any,
      params: [attester.address, "0x00"] as any,
    });

    const descriptorUris = ["ipfs://descriptor"];
    const attestationUris = ["ipfs://attestation"];
    await registry.write.publishMirrorLists([[descriptorUris, attestationUris]]);
    const descriptorMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [descriptorUris]));
    const attestationMirrorListId = keccak256(encodeAbiParameters([{ type: "string[]" }], [attestationUris]));

    const contextKeyId = keccak256(encodeAbiParameters([{ type: "string" }], ["ctx"]));
    const attestationId = keccak256(encodeAbiParameters([{ type: "string" }], ["att"]));
    const attestationFormatId = keccak256(encodeAbiParameters([{ type: "string" }], ["fmt"]));
    const descriptorHash = keccak256(encodeAbiParameters([{ type: "string" }], ["descriptor"]));

    const descriptor = {
      descriptorHash,
      descriptorSchemaMajor: 1n,
      contextKeyIds: [contextKeyId],
      attestationIds: [{ attestationId, attestationFormatId }],
    };

    const nonce = await registry.read.getNonce([attester.address]);
    const chainId = await publicClient.getChainId();

    const signature = await attester.signTypedData({
      domain: { name: "ClearSigningRegistry", version: "1", chainId, verifyingContract: registry.address },
      types: {
        ClearSigningRegistrationBatch: [
          { name: "descriptors", type: "DescriptorInfo[]" },
          { name: "descriptorMirrorListId", type: "bytes32" },
          { name: "attestationMirrorListId", type: "bytes32" },
          { name: "nonce", type: "uint256" },
        ],
        AttestationIdentifier: [
          { name: "attestationId", type: "bytes32" },
          { name: "attestationFormatId", type: "bytes32" },
        ],
        DescriptorInfo: [
          { name: "descriptorHash", type: "bytes32" },
          { name: "descriptorSchemaMajor", type: "uint256" },
          { name: "contextKeyIds", type: "bytes32[]" },
          { name: "attestationIds", type: "AttestationIdentifier[]" },
        ],
      },
      primaryType: "ClearSigningRegistrationBatch",
      message: {
        descriptors: [descriptor],
        descriptorMirrorListId,
        attestationMirrorListId,
        nonce,
      },
    });

    // Relayed: msg.sender (relayer) !== attester, so the registry must verify
    // `signature` via SignatureChecker.isValidSignatureNow(attester, ...).
    const relayedRegistry = await viem.getContractAt("ClearSigningRegistry", registry.address, {
      client: { wallet: relayer },
    });

    await relayedRegistry.write.createAttestations([
      attester.address,
      [descriptor],
      descriptorMirrorListId,
      attestationMirrorListId,
      signature,
    ]);

    const [resolved] = await registry.read.resolveDescriptors([
      [attester.address],
      [contextKeyId],
      [1n],
      [],
      [],
    ]);
    assert.equal(resolved.descriptorHash, descriptorHash);
  });
});
