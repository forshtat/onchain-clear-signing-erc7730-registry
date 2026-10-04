// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "./structs/RegistrationRecord.sol";
import "./structs/RootAttestationsIndexDetails.sol";
import "./structs/RootDescriptorsIndexDetails.sol";

import "./ClearSigningRegistryConstants.sol";
import "./IClearSigningRegistry.sol";

/// @title  ClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of IClearSigningRegistry.
contract ClearSigningRegistry is IClearSigningRegistry, EIP712 {
    constructor() EIP712("ClearSigningRegistry", "1") {}

    /// @notice The attestation index root currently **active** for the given attester, context, and schema MAJOR.
    /// @notice The attestations in the index set should cover the same set of descriptors represented by a corresponding '_activeDescriptors'.
    /// @notice The individual attestations in the set are created for different 'attestation formats': ERC-8176, ECDSA signatures, or others.
    /// @notice The ClearSigningRegistry does not enforce or prioritize any attestation formats.
    mapping(address attester => mapping(bytes32 contextKeyId => mapping(uint256 descriptorSchemaMajor => RootAttestationsIndexDetails))) private _activeAttestations;

    /// @notice The descriptors index root currently **active** for the given attester, context, and schema MAJOR.
    /// @notice The descriptors in the index set should be cover the set of attestations represented by a corresponding '_activeAttestations'.
    mapping(address attester => mapping(bytes32 contextKeyId => mapping(uint256 descriptorSchemaMajor => RootDescriptorsIndexDetails))) private _activeDescriptors;

    /// @inheritdoc IClearSigningRegistry
    function createAttestations(RegistrationRecord[] calldata registrationRecords) external {
        if (registrationRecords.length == 0) {
            revert EmptyDescriptors(); // TODO rename errors
        }

        for (uint256 i = 0; i < registrationRecords.length; i++) {
            // TODO: use MirrorListLib::includes instead
            // Both MirrorLists must already be published using the 'publishMirrorLists' function
            _requireMirrorListPublished(registrationRecords[i].descriptorsRootIndex.mirrorListId);
            _requireMirrorListPublished(registrationRecords[i].attestationsRootIndex.mirrorListId);

            // TODO: this is the core registration loop - split up into inner functions and refactor
            for (uint256 j = 0; i < registrationRecords[i].contextKeyIds.length; j++) {
                bytes32 ckid = registrationRecords[i].contextKeyIds;
                uint256 major = registrationRecords[i].descriptorsRootIndex.descriptorSchemaMajor;
                _activeAttestations[ckid][major] = registrationRecords[i].attestationsRootIndex.mirrorListId;
                _activeDescriptors[ckid][major] = registrationRecords[i].descriptorsRootIndex.descriptorSchemaMajor;
            }
        }
    }

    function _processRegistrationRecord(RegistrationRecord calldata registrationRecords) private view {

    }

    function _processContextKeyId(RegistrationRecord calldata registrationRecords, bytes32 ckid) private view {

    }

    /// @dev Reverts with 'UnknownMirrorList' unless 'mirrorListId' was already published.
    function _requireMirrorListPublished(bytes32 mirrorListId) private view {
        if (_mirrorLists[mirrorListId].length == 0) {
            revert UnknownMirrorList(mirrorListId);
        }
    }

    /// @dev Updates the active record for each (contextKeyId, descriptorSchemaMajor) key of a
    ///      descriptor. Records of other schema MAJORs are untouched.
    ///
    ///      Displacing a context's active record auto-revokes the descriptor hash it displaces,
    ///      at that context — atomically, in this same call, with no separate 'revokeDescriptors'
    ///      step required and no way for the attester to forget it. A descriptor hash that was
    ///      ever revoked at a context — whether by this auto-revoke or by an explicit call — can
    ///      never become active at that context again, reverting with 'RevokedDescriptorReused'.
    function _updateActiveAttestation(
        address attester,
        DescriptorInfo calldata descriptor,
        bytes32 attestationSetId
    ) private {
        bytes32[] calldata contextKeyIds = descriptor.contextKeyIds;
        uint256 descriptorSchemaMajor = descriptor.descriptorSchemaMajor;
        bytes32 descriptorHash = descriptor.descriptorHash;
        uint64 timestamp = uint64(block.timestamp);

        for (uint256 contextKeyIndex = 0; contextKeyIndex < contextKeyIds.length; contextKeyIndex++) {
            bytes32 contextKeyId = contextKeyIds[contextKeyIndex];
            bytes32 previousAttestationSetId = _activeAttestationSetIds[attester][contextKeyId][descriptorSchemaMajor];

            // A record already pointing at this set — a re-activation batch listing existing
            // context IDs alongside new ones — is left untouched rather than displaced.
            if (previousAttestationSetId == attestationSetId) {
                continue;
            }

            if (previousAttestationSetId != bytes32(0)) {
                bytes32 previousDescriptorHash =
                                        _attestationSetDetails[attester][previousAttestationSetId].functionIndexHash;
                if (_descriptorRevokedAt[attester][contextKeyId][previousDescriptorHash] == 0) {
                    _descriptorRevokedAt[attester][contextKeyId][previousDescriptorHash] = timestamp;
                    emit DescriptorRevoked(attester, contextKeyId, previousDescriptorHash, timestamp);
                }
            }

            if (_descriptorRevokedAt[attester][contextKeyId][descriptorHash] != 0) {
                revert RevokedDescriptorReused(contextKeyId, descriptorHash);
            }

            _activeAttestationSetIds[attester][contextKeyId][descriptorSchemaMajor] = attestationSetId;
            emit AttestationUpdated(
                attester, contextKeyId, attestationSetId, previousAttestationSetId,
                descriptorHash, descriptorSchemaMajor
            );
        }
    }



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


    // TODO: reconsider if still necessary - seems convoluted?
    /// @inheritdoc IClearSigningRegistry
    function updateDescriptorMirrorList(
        address attester,
        bytes32[] calldata descriptorHashes,
        bytes32 descriptorMirrorListId,
        bytes calldata signature
    ) external {
        if (descriptorHashes.length == 0) {
            revert EmptyKeys();
        }
        _requireMirrorListPublished(descriptorMirrorListId);
        _authorizeMirrorListUpdate(
            attester, descriptorHashes, descriptorMirrorListId,
            ClearSigningRegistryConstants.DESCRIPTOR_MIRROR_UPDATE_TYPEHASH, signature
        );

        for (uint256 i = 0; i < descriptorHashes.length; i++) {
            bytes32 descriptorHash = descriptorHashes[i];
            // Registration always sets a non-zero descriptor MirrorList pointer, so a zero
            // pointer means the attester never registered this descriptor hash.
            if (_descriptorMirrorListIds[attester][descriptorHash] == bytes32(0)) {
                revert UnknownDescriptor(descriptorHash);
            }
            _setDescriptorMirrorList(attester, descriptorHash, descriptorMirrorListId);
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function updateAttestationMirrorList(
        address attester,
        bytes32[] calldata attestationSetIds,
        bytes32 attestationMirrorListId,
        bytes calldata signature
    ) external {
        if (attestationSetIds.length == 0) {
            revert EmptyKeys();
        }
        _requireMirrorListPublished(attestationMirrorListId);
        _authorizeMirrorListUpdate(
            attester, attestationSetIds, attestationMirrorListId,
            ClearSigningRegistryConstants.ATTESTATION_MIRROR_UPDATE_TYPEHASH, signature
        );

        for (uint256 i = 0; i < attestationSetIds.length; i++) {
            bytes32 attestationSetId = attestationSetIds[i];
            if (_attestationSetDetails[attester][attestationSetId].functionIndexHash == bytes32(0)) {
                revert UnknownAttestationSet(attestationSetId);
            }
            _setAttestationMirrorList(attester, attestationSetId, attestationMirrorListId);
        }
    }

    /// @dev Points 'attester''s MirrorList for 'descriptorHash' at 'mirrorListId',
    ///      emitting an event only when the pointer actually changes.
    function _setDescriptorMirrorList(address attester, bytes32 descriptorHash, bytes32 mirrorListId) private {
        if (_descriptorMirrorListIds[attester][descriptorHash] == mirrorListId) {
            return;
        }
        _descriptorMirrorListIds[attester][descriptorHash] = mirrorListId;
        emit DescriptorMirrorListUpdated(attester, descriptorHash, mirrorListId);
    }

    /// @dev Points 'attester''s MirrorList for 'attestationSetId' at 'mirrorListId',
    ///      emitting an event only when the pointer actually changes.
    function _setAttestationMirrorList(address attester, bytes32 attestationSetId, bytes32 mirrorListId) private {
        if (_attestationMirrorListIds[attester][attestationSetId] == mirrorListId) {
            return;
        }
        _attestationMirrorListIds[attester][attestationSetId] = mirrorListId;
        emit AttestationMirrorListUpdated(attester, attestationSetId, mirrorListId);
    }

    /// @dev Validates one descriptor's fields and every entry of its attestation set.
    function _validateDescriptor(FunctionIndexInfo calldata functionIndex) private pure {
        if (functionIndex.hash == bytes32(0)) {
            revert ZeroDescriptorHash(); // TODO rename errors
        }
        if (functionIndex.descriptorSchemaMajor == 0) {
            revert ZeroDescriptorSchemaMajor();
        }
        if (functionIndex.contextKeyIds.length == 0) {
            revert EmptyContextKeyIds();
        }
        AttestationIdentifier[] calldata attestationIds = descriptor.attestationIds;
        if (attestationIds.length == 0) {
            revert EmptyAttestationIds();
        }
        for (uint256 entryIndex = 0; entryIndex < attestationIds.length; entryIndex++) {
            AttestationIdentifier calldata entry = attestationIds[entryIndex];
            if (entry.attestationId == bytes32(0)) {
                revert ZeroAttestationId();
            }
            if (entry.attestationFormatId == bytes32(0)) {
                revert ZeroAttestationFormat();
            }
            // One attestation per format per descriptor, so the index file's
            // format-to-attestation map stays unambiguous.
            for (uint256 earlierIndex = 0; earlierIndex < entryIndex; earlierIndex++) {
                if (attestationIds[earlierIndex].attestationFormatId == entry.attestationFormatId) {
                    revert DuplicateAttestationFormat(entry.attestationFormatId);
                }
            }
        }
    }
}
