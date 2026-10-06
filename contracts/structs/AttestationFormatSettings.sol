// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

/// @notice An attestation format an attester declares to use, with its optional revocation controller.
struct AttestationFormatSettings {
    /// The declared attestation format identifier, calculated as 'keccak256("erc7730.attestation.<format>")'.
    bytes32 attestationFormatId;
    /// An optional contract implementing 'IRevocationController' that wallets MAY ask whether an attestation
    /// of this format was revoked, or address(0) for none.
    /// The registry never calls it, does not interpret the attestation identifiers it accepts, and does not
    /// check that it is a contract. The controller is chosen by the attester, so wallets that use it extend
    /// the trust they already place in that attester and nothing more.
    address revocationController;
}
