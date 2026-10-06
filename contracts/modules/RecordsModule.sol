// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../structs/RegistrationRecord.sol";

import "./MirrorListManager.sol";

contract RecordsModule is MirrorListManager {

    /// @notice The attestations record currently **active** for the given attester and context.
    /// @notice The ClearSigningRegistry does not enforce or prioritize any attestation formats.
    mapping(address attester => mapping(bytes32 contextKeyId => RegistrationRecord)) private _records;

    function createAttestations(
        bytes32[][] calldata contextKeyIds, // todo add comment: nested array, one array per each record
        RegistrationRecord[] calldata registrationRecords
    ) external {
        if (registrationRecords.length == 0) {
            revert EmptyDescriptors(); // TODO rename errors and match the checks to the new parameters type
        }
        for (uint256 i = 0; i < registrationRecords.length; i++) {
            _processRegistrationRecord(registrationRecords[i]);
        }
    }

    function _processRegistrationRecord(
        RegistrationRecord calldata registrationRecord,
        bytes32[] calldata contextKeyIds
    ) private view {
        // Both MirrorLists must already be published using the 'publishMirrorLists' function
        _requireMirrorListPublished(registrationRecord.descriptorDetails.mirrorListId);
        _requireMirrorListPublished(registrationRecord.attestationDetails.mirrorListId);

        for (uint256 i = 0; i < contextKeyIds.length; i++) {
            _records[msg.sender][contextKeyIds[i]] = registrationRecord;
        }
    }
}
