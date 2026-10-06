// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Descriptor metadata provided to the 'createAttestations' function for new descriptors.
struct DescriptorDetails {
    /// The declared canonical hash of the descriptor resolved by the URLs in the 'mirrorListId'.
    /// The value is used only to ensure immutability of the data served off-chain and is not enforced by the registry.
    bytes32 descriptorHashes;
    /// All declared MAJOR versions of the supplied ERC-7730 descriptor schemas per its '$schema' key.
    uint256[] descriptorSchemaMajors;
    /// The list of URLs leading to the root descriptors index file.
    bytes32 mirrorListId;
}
