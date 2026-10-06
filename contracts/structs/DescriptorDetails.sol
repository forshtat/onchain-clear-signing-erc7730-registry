// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Descriptor metadata an attester provides in a registration record.
struct DescriptorDetails {
    /// The declared canonical hash of the descriptor resolved by the URLs in the 'mirrorListId'.
    /// The value is used only to ensure immutability of the data served off-chain and is not enforced by the registry.
    bytes32 descriptorHash;
    /// All declared MAJOR versions of the supplied ERC-7730 descriptor schemas per its '$schema' key.
    uint256[] descriptorSchemaMajors;
    /// The ID of an already-published MirrorList of URLs leading to the root descriptors index file.
    bytes32 mirrorListId;
}
