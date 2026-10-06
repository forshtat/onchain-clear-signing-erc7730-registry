// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice Attestation metadata an attester provides in a registration record.
/// @notice Unlike DescriptorDetails it carries no content hash, so the attestation files may change while they remain valid.
struct AttestationDetails {
    /// The ID of an already-published MirrorList of URLs leading to the attestations index file.
    bytes32 mirrorListId;
}
