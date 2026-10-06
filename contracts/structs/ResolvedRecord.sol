// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice An attester's active record at a context, with its MirrorLists resolved to URLs.
struct ResolvedRecord {
    /// The attester that wrote this record.
    address attester;
    /// The context ID the record was resolved for.
    bytes32 contextKeyId;
    /// The declared canonical hash of the descriptor root index file.
    bytes32 descriptorHash;
    /// All declared schema MAJOR versions of the descriptors in the root index.
    uint256[] descriptorSchemaMajors;
    /// The URLs of the descriptor root index file.
    string[] descriptorUrls;
    /// The URLs of the attestations root index file.
    string[] attestationUrls;
}
