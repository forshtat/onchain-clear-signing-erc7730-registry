// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../structs/RegistrationRecord.sol";

import "../IRecordsModule.sol";
import "./MirrorListManager.sol";

contract RecordsModule is MirrorListManager, IRecordsModule {

    /// @notice The record currently active for the given attester and context.
    /// @notice The ClearSigningRegistry does not enforce or prioritize any attestation formats.
    mapping(address attester => mapping(bytes32 contextKeyId => RegistrationRecord)) internal _records;

    /// @notice Write the caller's registration records, each for one or more contexts.
    ///
    ///         The attester produces the signed attestation artifacts locally and stores them off-chain.
    ///         Every record SHOULD reference at least one standard ERC-8176 EAS off-chain attestation.
    ///         The registry itself is attestation-agnostic and does not validate any attestation's
    ///         signature or content, nor the declared descriptor hash.
    ///
    ///         Each attester has at most one record per context. Writing a record replaces the
    ///         previous one at that context, for every descriptor schema MAJOR it declared.
    ///         To stop serving a record without a replacement, see 'deleteRecords'.
    ///
    ///         Both MirrorLists referenced by a record must already be published, see 'publishMirrorLists'.
    ///
    /// @param contextKeyIds        One array of context IDs per record: 'registrationRecords[i]'
    ///                             is written for every ID in 'contextKeyIds[i]'.
    /// @param registrationRecords  The records to write. Must be the same length as 'contextKeyIds'.
    function writeRecords(
        bytes32[][] calldata contextKeyIds,
        RegistrationRecord[] calldata registrationRecords
    ) external {
        if (registrationRecords.length == 0) {
            revert EmptyRecords();
        }
        if (contextKeyIds.length != registrationRecords.length) {
            revert ArrayLengthMismatch();
        }
        for (uint256 i = 0; i < registrationRecords.length; i++) {
            _processRegistrationRecord(contextKeyIds[i], registrationRecords[i]);
        }
    }

    /// @notice Delete the caller's record at every listed context.
    ///         A context without a record is skipped silently, and still emits 'RecordDeleted'.
    /// @param contextKeyIds  The context IDs whose records are deleted. Must not be empty.
    function deleteRecords(bytes32[] calldata contextKeyIds) external {
        if (contextKeyIds.length == 0) {
            revert EmptyContextKeyIds();
        }
        for (uint256 i = 0; i < contextKeyIds.length; i++) {
            delete _records[msg.sender][contextKeyIds[i]];
            emit RecordDeleted(msg.sender, contextKeyIds[i]);
        }
    }

    /// @dev Validates one record and stores it under every one of its contexts.
    function _processRegistrationRecord(
        bytes32[] calldata contextKeyIds,
        RegistrationRecord calldata registrationRecord
    ) private {
        if (contextKeyIds.length == 0) {
            revert EmptyContextKeyIds();
        }
        if (registrationRecord.descriptorDetails.descriptorHash == bytes32(0)) {
            revert ZeroDescriptorHash();
        }
        if (registrationRecord.descriptorDetails.descriptorSchemaMajors.length == 0) {
            revert EmptyDescriptorSchemaMajors();
        }
        // Both MirrorLists must already be published using the 'publishMirrorLists' function
        _requireMirrorListPublished(registrationRecord.descriptorDetails.mirrorListId);
        _requireMirrorListPublished(registrationRecord.attestationDetails.mirrorListId);

        for (uint256 i = 0; i < contextKeyIds.length; i++) {
            _records[msg.sender][contextKeyIds[i]] = registrationRecord;
            emit RecordWritten(msg.sender, contextKeyIds[i], registrationRecord);
        }
    }
}
