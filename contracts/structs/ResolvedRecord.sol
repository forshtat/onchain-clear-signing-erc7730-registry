// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "./DescriptorRelease.sol";

/// @notice An attester's active record at a context, with its MirrorLists resolved to URLs.
struct ResolvedRecord {
    /// The attester that wrote this record.
    address attester;
    /// The context ID the record was resolved for.
    bytes32 contextKeyId;
    /// The descriptor releases of the record, one per supported schema MAJOR version, ordered by ascending 'schemaMajor'.
    DescriptorRelease[] releases;
    /// The URLs of the descriptor root index file.
    string[] descriptorUrls;
    /// The URLs of the attestations root index file.
    string[] attestationUrls;
}
