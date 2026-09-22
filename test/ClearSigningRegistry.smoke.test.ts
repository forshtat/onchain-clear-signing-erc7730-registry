import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodeAbiParameters, keccak256 } from "viem";

describe("ClearSigningRegistry smoke test", async function () {
  const { viem } = await network.create();

  it("registers a descriptor as a self-attester and resolves it back", async function () {
    const [attester] = await viem.getWalletClients();
    const registry = await viem.deployContract("ClearSigningRegistry");

    const descriptorUris = ["ipfs://descriptor"];
    const attestationUris = ["ipfs://attestation"];
    await registry.write.publishMirrorLists([[descriptorUris, attestationUris]]);

    const descriptorMirrorListId = keccak256(
      encodeAbiParameters([{ type: "string[]" }], [descriptorUris]),
    );
    const attestationMirrorListId = keccak256(
      encodeAbiParameters([{ type: "string[]" }], [attestationUris]),
    );

    const contextKeyId = keccak256(encodeAbiParameters([{ type: "string" }], ["ctx"]));
    const attestationId = keccak256(encodeAbiParameters([{ type: "string" }], ["att"]));
    const attestationFormatId = keccak256(
      encodeAbiParameters([{ type: "string" }], ["erc7730.attestation.eas.offchain"]),
    );
    const descriptorHash = keccak256(encodeAbiParameters([{ type: "string" }], ["descriptor"]));

    await registry.write.createAttestations([
      attester.account.address,
      [
        {
          descriptorHash,
          descriptorSchemaMajor: 1n,
          contextKeyIds: [contextKeyId],
          attestationIds: [{ attestationId, attestationFormatId }],
        },
      ],
      descriptorMirrorListId,
      attestationMirrorListId,
      "0x",
    ]);

    const [resolved] = await registry.read.resolveDescriptors([
      [attester.account.address],
      [contextKeyId],
      [1n],
      [],
      [],
    ]);

    assert.equal(resolved.descriptorHash, descriptorHash);
    assert.equal(resolved.attestationSetId, attestationId);
    assert.deepEqual(resolved.descriptorMirrorListUris, descriptorUris);
    assert.deepEqual(resolved.attestationMirrorListUris, attestationUris);
    assert.equal(resolved.attestations.length, 1);
    assert.equal(resolved.attestations[0].attestationId, attestationId);
  });
});
