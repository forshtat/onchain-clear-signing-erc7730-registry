import assert from "node:assert/strict";
import { describe, it } from "node:test";

import { network } from "hardhat";
import { encodeAbiParameters, keccak256, zeroAddress } from "viem";

const hashOf = (label: string) => keccak256(encodeAbiParameters([{ type: "string" }], [label]));
const mirrorListIdOf = (uris: string[]) => keccak256(encodeAbiParameters([{ type: "string[]" }], [uris]));

describe("ClearSigningRegistry", async function () {
  const { viem } = await network.create();
  const publicClient = await viem.getPublicClient();

  const contextA = hashOf("context-a");
  const contextB = hashOf("context-b");
  const contextUnset = hashOf("context-unset");
  const descriptorUris = ["ipfs://descriptor", "https://example.com/descriptor"];
  const attestationUris = ["ipfs://attestation"];
  const descriptorMirrorListId = mirrorListIdOf(descriptorUris);
  const attestationMirrorListId = mirrorListIdOf(attestationUris);

  const recordOf = (label: string, majors: bigint[] = [1n]) => ({
    descriptorDetails: {
      releases: majors.map((major) => ({ descriptorHash: hashOf(`${label}-${major}`), schemaMajor: major })),
      mirrorListId: descriptorMirrorListId,
    },
    attestationDetails: { mirrorListId: attestationMirrorListId },
  });

  async function deploy() {
    const [attesterClient, other] = await viem.getWalletClients();
    const registry = await viem.deployContract("ClearSigningRegistry");
    await registry.write.publishMirrorLists([[descriptorUris, attestationUris]]);
    return { registry, attester: attesterClient.account.address, other, otherAddress: other.account.address };
  }

  async function logCount(txHash: `0x${string}`) {
    return (await publicClient.getTransactionReceipt({ hash: txHash })).logs.length;
  }

  describe("mirror lists", function () {
    it("stores a list under its content hash and does not emit again when republished", async function () {
      const { registry } = await deploy();
      assert.deepEqual(await registry.read.getMirrorListById([descriptorMirrorListId]), descriptorUris);

      const republish = await registry.write.publishMirrorLists([[descriptorUris]]);
      assert.equal(await logCount(republish), 0);
    });

    it("returns an empty list for an unknown id and rejects publishing an empty list", async function () {
      const { registry } = await deploy();
      assert.deepEqual(await registry.read.getMirrorListById([hashOf("unknown")]), []);
      await viem.assertions.revertWithCustomError(registry.write.publishMirrorLists([[[]]]), registry, "EmptyMirrorList");
    });
  });

  describe("records", function () {
    it("writes one record to several contexts and resolves it, skipping contexts without one", async function () {
      const { registry, attester } = await deploy();
      const record = recordOf("descriptor-1", [1n, 2n]);

      const txHash = await registry.write.writeRecords([[[contextA, contextB]], [record]]);
      // per context: one 'RecordWritten' plus one 'DescriptorReleased' per release
      assert.equal(await logCount(txHash), 2 * (1 + 2));

      const resolved = await registry.read.resolveRecords([[attester], [contextA, contextUnset, contextB]]);
      assert.equal(resolved.length, 2);
      assert.deepEqual(resolved.map((r) => r.contextKeyId), [contextA, contextB]);
      for (const r of resolved) {
        assert.equal(r.attester.toLowerCase(), attester.toLowerCase());
        assert.deepEqual(r.releases, record.descriptorDetails.releases);
        assert.deepEqual(r.descriptorUrls, descriptorUris);
        assert.deepEqual(r.attestationUrls, attestationUris);
      }
    });

    it("keeps a distinct descriptor hash per schema major", async function () {
      const { registry, attester } = await deploy();
      await registry.write.writeRecords([[[contextA]], [recordOf("multi", [1n, 3n])]]);

      const [resolved] = await registry.read.resolveRecords([[attester], [contextA]]);
      assert.deepEqual(resolved.releases.map((r) => r.schemaMajor), [1n, 3n]);
      assert.deepEqual(resolved.releases.map((r) => r.descriptorHash), [hashOf("multi-1"), hashOf("multi-3")]);
    });

    it("emits an indexed 'DescriptorReleased' per release so a descriptor hash can be searched", async function () {
      const { registry, attester } = await deploy();
      await registry.write.writeRecords([[[contextA, contextB]], [recordOf("search", [1n, 3n])]]);

      const events = await registry.getEvents.DescriptorReleased({ descriptorHash: hashOf("search-3") });
      assert.deepEqual(events.map((e) => e.args.contextKeyId), [contextA, contextB]);
      assert.deepEqual(events.map((e) => e.args.schemaMajor), [3n, 3n]);
      assert.equal(events[0].args.attester?.toLowerCase(), attester.toLowerCase());
    });

    it("keeps contexts that share a record independent when one is overwritten or deleted", async function () {
      const { registry, attester } = await deploy();
      await registry.write.writeRecords([[[contextA, contextB]], [recordOf("shared")]]);

      await registry.write.writeRecords([[[contextA]], [recordOf("other", [2n])]]);
      const afterOverwrite = await registry.read.resolveRecords([[attester], [contextA, contextB]]);
      assert.deepEqual(afterOverwrite.map((r) => r.releases), [
        recordOf("other", [2n]).descriptorDetails.releases,
        recordOf("shared").descriptorDetails.releases,
      ]);

      await registry.write.deleteRecords([[contextB]]);
      const afterDelete = await registry.read.resolveRecords([[attester], [contextA, contextB]]);
      assert.deepEqual(afterDelete.map((r) => r.contextKeyId), [contextA]);

      await registry.write.writeRecords([[[contextB]], [recordOf("shared")]]);
      const [restored] = await registry.read.resolveRecords([[attester], [contextB]]);
      assert.deepEqual(restored.releases, recordOf("shared").descriptorDetails.releases);
    });

    it("replaces the previous record at a context", async function () {
      const { registry, attester } = await deploy();
      await registry.write.writeRecords([[[contextA]], [recordOf("old", [1n, 2n, 3n])]]);
      await registry.write.writeRecords([[[contextA]], [recordOf("new", [4n])]]);

      const [resolved] = await registry.read.resolveRecords([[attester], [contextA]]);
      assert.deepEqual(resolved.releases, recordOf("new", [4n]).descriptorDetails.releases);
    });

    it("keeps records per attester", async function () {
      const { registry, attester, other, otherAddress } = await deploy();
      await registry.write.writeRecords([[[contextA]], [recordOf("by-attester")]]);
      await registry.write.writeRecords([[[contextA]], [recordOf("by-other")]], { account: other.account });

      const onlyAttester = await registry.read.resolveRecords([[attester], [contextA]]);
      assert.deepEqual(onlyAttester.map((r) => r.releases), [recordOf("by-attester").descriptorDetails.releases]);

      const both = await registry.read.resolveRecords([[attester, otherAddress], [contextA]]);
      assert.deepEqual(both.map((r) => r.releases), [
        recordOf("by-attester").descriptorDetails.releases,
        recordOf("by-other").descriptorDetails.releases,
      ]);
    });

    it("rejects invalid input", async function () {
      const { registry } = await deploy();
      const write = (contexts: `0x${string}`[][], records: ReturnType<typeof recordOf>[]) =>
        registry.write.writeRecords([contexts, records]);

      await viem.assertions.revertWithCustomError(write([], []), registry, "EmptyRecords");
      await viem.assertions.revertWithCustomError(write([[contextA], [contextB]], [recordOf("a")]), registry, "ArrayLengthMismatch");
      await viem.assertions.revertWithCustomError(write([[]], [recordOf("a")]), registry, "EmptyContextKeyIds");

      await viem.assertions.revertWithCustomError(write([[contextA]], [recordOf("a", [])]), registry, "EmptyReleases");

      const zeroHash = recordOf("a", [1n, 2n]);
      zeroHash.descriptorDetails.releases[1].descriptorHash = `0x${"00".repeat(32)}`;
      await viem.assertions.revertWithCustomError(write([[contextA]], [zeroHash]), registry, "ZeroDescriptorHash");

      for (const majors of [[0n], [1n, 1n], [2n, 1n]]) {
        await viem.assertions.revertWithCustomError(write([[contextA]], [recordOf("a", majors)]), registry, "SchemaMajorsNotAscending");
      }

      const unpublished = hashOf("unpublished");
      const unpublishedDescriptor = recordOf("a");
      unpublishedDescriptor.descriptorDetails.mirrorListId = unpublished;
      await viem.assertions.revertWithCustomErrorWithArgs(write([[contextA]], [unpublishedDescriptor]), registry, "UnknownMirrorList", [unpublished]);

      const unpublishedAttestation = recordOf("a");
      unpublishedAttestation.attestationDetails.mirrorListId = unpublished;
      await viem.assertions.revertWithCustomErrorWithArgs(write([[contextA]], [unpublishedAttestation]), registry, "UnknownMirrorList", [unpublished]);
    });

    it("deletes records, tolerating contexts that have none", async function () {
      const { registry, attester } = await deploy();
      await registry.write.writeRecords([[[contextA, contextB]], [recordOf("a")]]);

      const txHash = await registry.write.deleteRecords([[contextA, contextUnset]]);
      assert.equal(await logCount(txHash), 2);

      const resolved = await registry.read.resolveRecords([[attester], [contextA, contextB, contextUnset]]);
      assert.deepEqual(resolved.map((r) => r.contextKeyId), [contextB]);

      await viem.assertions.revertWithCustomError(registry.write.deleteRecords([[]]), registry, "EmptyContextKeyIds");
    });

    it("resolves nothing for empty queries", async function () {
      const { registry, attester } = await deploy();
      await registry.write.writeRecords([[[contextA]], [recordOf("a")]]);
      assert.deepEqual(await registry.read.resolveRecords([[], [contextA]]), []);
      assert.deepEqual(await registry.read.resolveRecords([[attester], []]), []);
    });
  });

  describe("attester settings", function () {
    it("starts empty, replaces wholesale and clears", async function () {
      const { registry, attester } = await deploy();
      const empty = await registry.read.getAttesterSettings([attester]);
      assert.equal(empty.profileURI, "");
      assert.deepEqual(empty.attestationFormats, []);

      const controller = "0x000000000000000000000000000000000000dEaD";
      const easFormat = hashOf("erc7730.attestation.eas.offchain");
      const mlDsaFormat = hashOf("erc7730.attestation.mldsa");
      await registry.write.updateAttesterSettings([
        {
          profileURI: "ipfs://profile",
          attestationFormats: [
            { attestationFormatId: easFormat, revocationController: controller },
            { attestationFormatId: mlDsaFormat, revocationController: zeroAddress },
          ],
        },
      ]);

      const set = await registry.read.getAttesterSettings([attester]);
      assert.equal(set.profileURI, "ipfs://profile");
      assert.equal(set.attestationFormats.length, 2);
      assert.equal(set.attestationFormats[0].attestationFormatId, easFormat);
      assert.equal(set.attestationFormats[0].revocationController.toLowerCase(), controller.toLowerCase());
      assert.equal(set.attestationFormats[1].attestationFormatId, mlDsaFormat);
      assert.equal(set.attestationFormats[1].revocationController, zeroAddress);

      await registry.write.updateAttesterSettings([
        { profileURI: "", attestationFormats: [{ attestationFormatId: easFormat, revocationController: zeroAddress }] },
      ]);
      const replaced = await registry.read.getAttesterSettings([attester]);
      assert.equal(replaced.profileURI, "");
      assert.equal(replaced.attestationFormats.length, 1);

      await registry.write.updateAttesterSettings([{ profileURI: "", attestationFormats: [] }]);
      assert.deepEqual((await registry.read.getAttesterSettings([attester])).attestationFormats, []);
    });

    it("keeps settings per attester", async function () {
      const { registry, attester, other, otherAddress } = await deploy();
      await registry.write.updateAttesterSettings([{ profileURI: "ipfs://mine", attestationFormats: [] }]);
      await registry.write.updateAttesterSettings([{ profileURI: "ipfs://theirs", attestationFormats: [] }], { account: other.account });

      assert.equal((await registry.read.getAttesterSettings([attester])).profileURI, "ipfs://mine");
      assert.equal((await registry.read.getAttesterSettings([otherAddress])).profileURI, "ipfs://theirs");
    });
  });
});
