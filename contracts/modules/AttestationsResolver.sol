// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./TbdAttestationsModule.sol";

contract AttestationResolver is AttestationsModule {

    /// @inheritdoc IClearSigningRegistry
    function resolveDescriptors(
        address[] calldata attesters,
        bytes32[] calldata contextKeyIds,
        uint256[] calldata descriptorSchemaMajors,
        bytes32[] calldata attestationFormatIds,
        string[]  calldata allowedPrefixes
    ) external view returns (ResolvedDescriptor[] memory resolved) {
        uint256 activeRecordCount = _countActiveRecords(attesters, contextKeyIds, descriptorSchemaMajors);
        resolved = new ResolvedDescriptor[](activeRecordCount);
        _collectResolvedDescriptors(attesters, contextKeyIds, descriptorSchemaMajors, attestationFormatIds, allowedPrefixes, resolved);
    }

    /// @dev Counts the active records among the queried (attester, contextKeyId, descriptorSchemaMajor)
    ///      keys, used to size the 'resolveDescriptors' result array.
    function _countActiveRecords(
        address[] calldata attesters,
        bytes32[] calldata contextKeyIds,
        uint256[] calldata descriptorSchemaMajors
    ) private view returns (uint256 activeRecordCount) {
        for (uint256 attesterIndex = 0; attesterIndex < attesters.length; attesterIndex++) {
            address attester = attesters[attesterIndex];
            for (uint256 contextKeyIndex = 0; contextKeyIndex < contextKeyIds.length; contextKeyIndex++) {
                bytes32 contextKeyId = contextKeyIds[contextKeyIndex];
                for (uint256 majorIndex = 0; majorIndex < descriptorSchemaMajors.length; majorIndex++) {
                    if (_activeAttestationSetIds[attester][contextKeyId][descriptorSchemaMajors[majorIndex]] != bytes32(0)) {
                        ++activeRecordCount;
                    }
                }
            }
        }
    }

    /// @dev Fills 'resolved' with one entry per active (attester, contextKeyId, descriptorSchemaMajor) record.
    function _collectResolvedDescriptors(
        address[]            calldata attesters,
        bytes32[]            calldata contextKeyIds,
        uint256[]            calldata descriptorSchemaMajors,
        bytes32[]            calldata attestationFormatIds,
        string[]             calldata allowedPrefixes,
        ResolvedDescriptor[]   memory resolved
    ) private view {
        uint256 resolvedIndex;
        for (uint256 attesterIndex = 0; attesterIndex < attesters.length; attesterIndex++) {
            for (uint256 contextKeyIndex = 0; contextKeyIndex < contextKeyIds.length; contextKeyIndex++) {
                resolvedIndex = _resolveRecordsForContext(
                    attesters[attesterIndex], contextKeyIds[contextKeyIndex],
                    descriptorSchemaMajors, attestationFormatIds, allowedPrefixes, resolved, resolvedIndex
                );
            }
        }
    }

    /// @dev Resolves every schema MAJOR with an active record for one (attester, contextKeyId)
    ///      pair into 'resolved' starting at 'resolvedIndex', returning the index after the
    ///      last write.
    function _resolveRecordsForContext(
        address attester,
        bytes32 contextKeyId,
        uint256[]   calldata descriptorSchemaMajors,
        bytes32[]   calldata attestationFormatIds,
        string[]    calldata allowedPrefixes,
        ResolvedDescriptor[] memory resolved,
        uint256 resolvedIndex
    ) private view returns (uint256) {
        for (uint256 majorIndex = 0; majorIndex < descriptorSchemaMajors.length; majorIndex++) {
            uint256 descriptorSchemaMajor = descriptorSchemaMajors[majorIndex];
            bytes32 attestationSetId = _activeAttestationSetIds[attester][contextKeyId][descriptorSchemaMajor];
            if (attestationSetId != bytes32(0)) {
                resolved[resolvedIndex++] = _resolveActiveRecord(
                    attester, contextKeyId, descriptorSchemaMajor, attestationSetId, attestationFormatIds, allowedPrefixes
                );
            }
        }
        return resolvedIndex;
    }

    /// @dev Resolves one active attestation set into a ResolvedDescriptor.
    function _resolveActiveRecord(
        address attester,
        bytes32 contextKeyId,
        uint256 descriptorSchemaMajor,
        bytes32 attestationSetId,
        bytes32[] calldata attestationFormatIds,
        string[]  calldata allowedPrefixes
    ) private view returns (ResolvedDescriptor memory) {
        AttestationSetDetails storage details = _attestationSetDetails[attester][attestationSetId];
        bytes32 descriptorMirrorListId = _descriptorMirrorListIds[attester][details.functionIndexHash];
        bytes32 attestationMirrorListId = _attestationMirrorListIds[attester][attestationSetId];

        return ResolvedDescriptor({
            descriptorHash: details.functionIndexHash,
            contextKeyId: contextKeyId,
            descriptorSchemaMajor: descriptorSchemaMajor,
            attestationSetId: attestationSetId,
            revokedAt: _descriptorRevokedAt[attester][contextKeyId][details.functionIndexHash],
            descriptorMirrorListUris: _mirrorLists[descriptorMirrorListId].filter(allowedPrefixes),
            attestationMirrorListUris: _mirrorLists[attestationMirrorListId].filter(allowedPrefixes),
            attestations: _resolveAttestations(attester, attestationSetId, attestationFormatIds)
        });
    }

    /// @dev Builds the format-filtered ResolvedAttestation array of one attestation set.
    function _resolveAttestations(
        address attester,
        bytes32 attestationSetId,
        bytes32[] calldata attestationFormatIds
    ) private view returns (ResolvedAttestation[] memory attestations) {
        AttestationIdentifier[] storage contents = _attestationSetContents[attester][attestationSetId];

        uint256 matchCount;
        for (uint256 entryIndex = 0; entryIndex < contents.length; entryIndex++) {
            if (_matchesFormatFilter(contents[entryIndex].attestationFormatId, attestationFormatIds)) {
                ++matchCount;
            }
        }

        attestations = new ResolvedAttestation[](matchCount);
        uint256 outIndex;
        for (uint256 entryIndex = 0; entryIndex < contents.length; entryIndex++) {
            AttestationIdentifier storage entry = contents[entryIndex];
            if (!_matchesFormatFilter(entry.attestationFormatId, attestationFormatIds)) {
                continue;
            }
            attestations[outIndex++] = ResolvedAttestation({
                attester: attester,
                attestationId: entry.attestationId,
                attestationFormatId: entry.attestationFormatId
            });
        }
    }

    /// @dev Whether 'attestationFormatId' passes the 'attestationFormatIds' request filter; an empty filter passes all.
    function _matchesFormatFilter(bytes32 attestationFormatId, bytes32[] calldata attestationFormatIds) private pure returns (bool) {
        if (attestationFormatIds.length == 0) {
            return true;
        }
        for (uint256 filterIndex = 0; filterIndex < attestationFormatIds.length; filterIndex++) {
            if (attestationFormatIds[filterIndex] == attestationFormatId) {
                return true;
            }
        }
        return false;
    }
}
