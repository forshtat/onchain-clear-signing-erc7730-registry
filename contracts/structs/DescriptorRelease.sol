// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @notice One descriptor file, published for wallets that support one ERC-7730 descriptor schema MAJOR version.
struct DescriptorRelease {
    /// The declared canonical hash of the descriptor resolved by the URLs in the record's 'mirrorListId'.
    /// The value is used only to ensure immutability of the data served off-chain and is not enforced by the registry.
    bytes32 descriptorHash;
    /// The MAJOR version of the ERC-7730 descriptor schema per the descriptor's '$schema' key.
    uint64 schemaMajor;
}
