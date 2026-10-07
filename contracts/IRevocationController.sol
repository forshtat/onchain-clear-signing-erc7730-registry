// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @title  IRevocationController — optional third-party revocation root for attestations
/// @notice An attester MAY declare, per attestation format, a contract wallets can ask whether a given
///         attestation was revoked. The registry never calls a controller and does not interpret
///         'data': its meaning is defined by the attestation format.
///         Revocation is the attestation format's job. A format other than the EAS off-chain one
///         must define what 'data' means and where revocation is answered. The controller is an
///         optional hint. Without one, the attestation is unrevocable. Removing or replacing a record
///         is not revocation.
///         The signature deliberately matches 'getRevokeOffchain' of the Ethereum Attestation Service,
///         so the canonical EAS contract itself is a valid controller for the EAS off-chain format.
interface IRevocationController {
    /// @notice The timestamp at which 'revoker' revoked the identified attestation, or 0 if it did not.
    /// @param revoker  The account whose revocation counts: the attester that issued the attestation.
    /// @param data     The format-specific identifier of the attestation. For the EAS off-chain format,
    ///                 the attestation UID.
    /// @return timestamp  The revocation timestamp, or 0 if not revoked.
    function getRevokeOffchain(address revoker, bytes32 data) external view returns (uint64 timestamp);
}
