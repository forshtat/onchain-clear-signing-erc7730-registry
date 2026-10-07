// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "../structs/RegistrationRecord.sol";

import "../interfaces/IRecordsModule.sol";
import "./MirrorListManager.sol";

contract RecordsModule is MirrorListManager, IRecordsModule {

    /// @notice Records, stored once under the hash of their ABI-encoded content and shared by
    ///         every context that points to them. Never deleted: a record is immutable content.
    mapping(bytes32 recordId => RegistrationRecord) internal _recordsById;

    /// @notice The ID of the record currently active for the given attester and context, zero if none.
    mapping(address attester => mapping(bytes32 contextKeyId => bytes32 recordId)) internal _recordIds;

    /// @notice Write the caller's registration records, each for one or more contexts.
    ///
    ///         The attester produces the signed attestation artifacts locally and stores them off-chain.
    ///         Every record SHOULD reference at least one standard ERC-8176 EAS off-chain attestation.
    ///         The registry itself is attestation-agnostic and does not validate any attestation's
    ///         signature or content, nor the declared descriptor hash.
    ///
    ///         Each attester has at most one record per context. Writing a record replaces the
    ///         previous one at that context as a whole, including every descriptor release it held:
    ///         to update one schema MAJOR, resend the other releases too, or they stop being served.
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
        require(registrationRecords.length != 0, EmptyRecords());
        require(contextKeyIds.length == registrationRecords.length, ArrayLengthMismatch());
        for (uint256 i = 0; i < registrationRecords.length; i++) {
            _processRegistrationRecord(contextKeyIds[i], registrationRecords[i]);
        }
    }

    /// @notice Delete the caller's record at every listed context.
    ///         A context without a record does not revert, and still emits 'RecordDeleted'.
    /// @param contextKeyIds  The context IDs whose records are deleted. Must not be empty.
    function deleteRecords(bytes32[] calldata contextKeyIds) external {
        require(contextKeyIds.length != 0, EmptyContextKeyIds());
        for (uint256 i = 0; i < contextKeyIds.length; i++) {
            delete _recordIds[msg.sender][contextKeyIds[i]];
            emit RecordDeleted(msg.sender, contextKeyIds[i]);
        }
    }

    /// @dev Validates one record and stores it under every one of its contexts.
    function _processRegistrationRecord(
        bytes32[] calldata contextKeyIds,
        RegistrationRecord calldata registrationRecord
    ) private {
        require(contextKeyIds.length != 0, EmptyContextKeyIds());
        DescriptorRelease[] calldata releases = registrationRecord.descriptorDetails.releases;
        _requireValidReleases(releases);
        // Both MirrorLists must already be published using the 'publishMirrorLists' function
        _requireMirrorListPublished(registrationRecord.descriptorDetails.mirrorListId);
        _requireMirrorListPublished(registrationRecord.attestationDetails.mirrorListId);

        bytes32 recordId = keccak256(abi.encode(registrationRecord));
        if (_recordsById[recordId].descriptorDetails.releases.length == 0) {
            _recordsById[recordId] = registrationRecord;
        }

        for (uint256 i = 0; i < contextKeyIds.length; i++) {
            _recordIds[msg.sender][contextKeyIds[i]] = recordId;
            emit RecordWritten(msg.sender, contextKeyIds[i], registrationRecord);
            for (uint256 j = 0; j < releases.length; j++) {
                emit DescriptorReleased(msg.sender, contextKeyIds[i], releases[j].descriptorHash, releases[j].schemaMajor);
            }
        }
    }

    /// @dev Reverts unless there is at least one release, every release has a descriptor hash,
    ///      and the schema MAJOR versions are strictly ascending starting above zero.
    function _requireValidReleases(DescriptorRelease[] calldata releases) private pure {
        require(releases.length != 0, EmptyReleases());
        uint64 previousMajor;
        for (uint256 i = 0; i < releases.length; i++) {
            require(releases[i].descriptorHash != bytes32(0), ZeroDescriptorHash());
            require(releases[i].schemaMajor > previousMajor, SchemaMajorsNotAscending());
            previousMajor = releases[i].schemaMajor;
        }
    }
}
