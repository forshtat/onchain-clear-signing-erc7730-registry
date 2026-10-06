// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../structs/RegistrationRecord.sol";

import "./MirrorListManager.sol";

contract RecordsModule is MirrorListManager {

    /// @notice The record currently active for the given attester and context.
    /// @notice The ClearSigningRegistry does not enforce or prioritize any attestation formats.
    mapping(address attester => mapping(bytes32 contextKeyId => RegistrationRecord)) internal _records;

    /// @notice Writes the caller's record for every listed context, replacing any previous record there.
    /// @param contextKeyIds  One array of context IDs per record: 'registrationRecords[i]' is written for every ID in 'contextKeyIds[i]'.
    function writeRecords(
        bytes32[][] calldata contextKeyIds,
        RegistrationRecord[] calldata registrationRecords
    ) external {
        if (registrationRecords.length == 0) {
            revert IClearSigningRegistry.EmptyRecords();
        }
        if (contextKeyIds.length != registrationRecords.length) {
            revert IClearSigningRegistry.ArrayLengthMismatch();
        }
        for (uint256 i = 0; i < registrationRecords.length; i++) {
            _processRegistrationRecord(contextKeyIds[i], registrationRecords[i]);
        }
    }

    /// @notice Deletes the caller's record at every listed context. A context without a record is skipped silently.
    function deleteRecords(bytes32[] calldata contextKeyIds) external {
        if (contextKeyIds.length == 0) {
            revert IClearSigningRegistry.EmptyContextKeyIds();
        }
        for (uint256 i = 0; i < contextKeyIds.length; i++) {
            delete _records[msg.sender][contextKeyIds[i]];
            emit IClearSigningRegistry.RecordDeleted(msg.sender, contextKeyIds[i]);
        }
    }

    /// @dev Validates one record and stores it under every one of its contexts.
    function _processRegistrationRecord(
        bytes32[] calldata contextKeyIds,
        RegistrationRecord calldata registrationRecord
    ) private {
        if (contextKeyIds.length == 0) {
            revert IClearSigningRegistry.EmptyContextKeyIds();
        }
        if (registrationRecord.descriptorDetails.descriptorHash == bytes32(0)) {
            revert IClearSigningRegistry.ZeroDescriptorHash();
        }
        if (registrationRecord.descriptorDetails.descriptorSchemaMajors.length == 0) {
            revert IClearSigningRegistry.EmptyDescriptorSchemaMajors();
        }
        if (registrationRecord.attestationDetails.attestationFormatIds.length == 0) {
            revert IClearSigningRegistry.EmptyAttestationFormatIds();
        }
        // Both MirrorLists must already be published using the 'publishMirrorLists' function
        _requireMirrorListPublished(registrationRecord.descriptorDetails.mirrorListId);
        _requireMirrorListPublished(registrationRecord.attestationDetails.mirrorListId);

        for (uint256 i = 0; i < contextKeyIds.length; i++) {
            _records[msg.sender][contextKeyIds[i]] = registrationRecord;
            emit IClearSigningRegistry.RecordWritten(msg.sender, contextKeyIds[i], registrationRecord);
        }
    }
}
