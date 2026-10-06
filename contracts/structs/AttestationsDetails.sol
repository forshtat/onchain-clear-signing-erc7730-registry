// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;


/// @notice Attestations metadata attesters provide to create new attestations.
/// @notice Unlike the DescriptorDetails does not contain the file hash allowing mutable data if it remains valid.
struct AttestationDetails {
    /// All attestation formats the specified "attestation" file contains.
    /// The format identifiers are calculated as 'keccak256("erc7730.attestation.<format>")'.
    bytes32[] attestationFormatIds;
    /// The list of URLs leading to the attestation file.
    bytes32 mirrorListId;
}
