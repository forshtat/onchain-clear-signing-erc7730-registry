// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "../structs/ResolvedRecord.sol";

import "./RecordsModule.sol";

contract RecordsResolver is RecordsModule {

    /// @notice Resolve the records of the given attesters at the given contexts.
    ///
    ///         Returns one entry per '(attester, contextKeyId)' pair that currently has a record, ordered by
    ///         attester and then by context. Both parameters are lookup keys: an empty array yields no results.
    ///
    ///         The registry applies no filters. A wallet picks the schema MAJOR versions it supports from
    ///         'descriptorSchemaMajors', and may use the attester's declared formats and revocation
    ///         controllers (see 'getAttesterSettings').
    ///
    /// @param attesters      Attester addresses trusted by the wallet.
    /// @param contextKeyIds  Candidate context IDs to look up.
    /// @return resolved  The records found.
    function resolveRecords(address[] calldata attesters, bytes32[] calldata contextKeyIds)
    external view returns (ResolvedRecord[] memory resolved)
    {
        uint256 count;
        for (uint256 i = 0; i < attesters.length; i++) {
            for (uint256 j = 0; j < contextKeyIds.length; j++) {
                if (_isActive(attesters[i], contextKeyIds[j])) {
                    ++count;
                }
            }
        }

        resolved = new ResolvedRecord[](count);
        uint256 k;
        for (uint256 i = 0; i < attesters.length; i++) {
            for (uint256 j = 0; j < contextKeyIds.length; j++) {
                if (_isActive(attesters[i], contextKeyIds[j])) {
                    resolved[k++] = _resolveRecord(attesters[i], contextKeyIds[j]);
                }
            }
        }
    }

    /// @dev A record is active when it has at least one release: written records always do, deleted or never-written ones do not.
    function _isActive(address attester, bytes32 contextKeyId) private view returns (bool) {
        return _records[attester][contextKeyId].descriptorDetails.releases.length != 0;
    }

    /// @dev Reads one active record and resolves its MirrorList IDs to URLs.
    function _resolveRecord(address attester, bytes32 contextKeyId) private view returns (ResolvedRecord memory) {
        RegistrationRecord storage record = _records[attester][contextKeyId];
        return ResolvedRecord({
            attester: attester,
            contextKeyId: contextKeyId,
            releases: record.descriptorDetails.releases,
            descriptorUrls: _mirrorLists[record.descriptorDetails.mirrorListId],
            attestationUrls: _mirrorLists[record.attestationDetails.mirrorListId]
        });
    }
}
