// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @title  IRevocationController — optional third-party revocation root for attestations
/// @notice An attester MAY declare, per attestation format, a contract wallets can ask whether a given
///         attestation was revoked. The registry never calls a controller and does not interpret
///         'attestationIdentifier': its encoding is defined by the attestation format and the controller.
interface IRevocationController {
    /// @notice The timestamp at which the identified attestation was revoked, or 0 if it was not.
    /// @param attestationIdentifier  The format-specific identifier of the attestation.
    /// @return timestamp  The revocation timestamp, or 0 if not revoked.
    function getRevocationTimestamp(bytes calldata attestationIdentifier) external view returns (uint64 timestamp);
}
