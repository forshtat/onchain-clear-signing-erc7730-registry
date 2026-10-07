// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @notice One descriptor file, published for wallets that support one ERC-7730 descriptor schema MAJOR version.
struct DescriptorRelease {
    /// The declared canonical hash of the descriptor resolved by the URLs in the record's 'mirrorListId',
    /// computed as in ERC-8176 "Descriptor Hash Computation": 'includes' resolved, RFC 8785 serialized, Keccak-256.
    /// A URL serves either the fully resolved descriptor, or one whose relative 'includes' resolve against that URL;
    /// a URL that cannot resolve them (such as a bare IPFS file CID) must serve the resolved file.
    /// The value is used only to ensure immutability of the data served off-chain and is not enforced by the registry.
    bytes32 descriptorHash;
    /// The MAJOR version of the ERC-7730 descriptor schema per the descriptor's '$schema' key.
    uint64 schemaMajor;
}
