// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "../structs/RegistrationRecord.sol";

/// @notice Events and errors of the attester records store.
interface IRecordsModule {
    /// @notice Emitted when an attester writes the record for a context, replacing any previous one.
    /// @param attester       The attester whose record was written.
    /// @param contextKeyId   The context ID affected.
    /// @param record         The newly active record.
    event RecordWritten(address indexed attester, bytes32 indexed contextKeyId, RegistrationRecord record);

    /// @notice Emitted right after 'RecordWritten', once per descriptor release of the written record,
    ///         so a descriptor hash can be searched for by its topic.
    /// @param attester        The attester whose record was written.
    /// @param contextKeyId    The context ID affected.
    /// @param descriptorHash  The descriptor hash of the release.
    /// @param schemaMajor     The schema MAJOR version of the release.
    event DescriptorReleased(
        address indexed attester,
        bytes32 indexed contextKeyId,
        bytes32 indexed descriptorHash,
        uint64          schemaMajor
    );

    /// @notice Emitted when an attester deletes the record for a context.
    /// @param attester       The attester whose record was deleted.
    /// @param contextKeyId   The context ID affected.
    event RecordDeleted(address indexed attester, bytes32 indexed contextKeyId);

    /// @notice Thrown when no registration records are passed.
    error EmptyRecords();

    /// @notice Thrown when 'contextKeyIds' and 'registrationRecords' differ in length.
    error ArrayLengthMismatch();

    /// @notice Thrown when a record or a deletion lists no context IDs.
    error EmptyContextKeyIds();

    /// @notice Thrown when a release declares a zero descriptor hash.
    error ZeroDescriptorHash();

    /// @notice Thrown when a record declares no descriptor releases.
    error EmptyReleases();

    /// @notice Thrown when the releases' schema MAJOR versions are not strictly ascending from a value above zero.
    error SchemaMajorsNotAscending();
}
