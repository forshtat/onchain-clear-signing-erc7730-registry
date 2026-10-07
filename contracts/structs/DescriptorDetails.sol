// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "./DescriptorRelease.sol";

/// @notice Descriptor metadata an attester provides in a registration record.
struct DescriptorDetails {
    /// One release per supported schema MAJOR version, ordered by strictly ascending 'schemaMajor'.
    /// A wallet picks the release matching the schema MAJOR version it supports.
    DescriptorRelease[] releases;
    /// The ID of an already-published MirrorList of URLs leading to the root descriptors index file.
    /// The index file is shared by all releases and is keyed by their descriptor hashes.
    bytes32 mirrorListId;
}
