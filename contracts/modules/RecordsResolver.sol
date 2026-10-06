// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../structs/ResolvedRecord.sol";

import "../IClearSigningRegistry.sol";
import "./RecordsModule.sol";

contract RecordsResolver is RecordsModule {

    /// @inheritdoc IClearSigningRegistry
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

    /// @dev A record is active when its descriptor hash is set: written records always have one, deleted or never-written ones do not.
    function _isActive(address attester, bytes32 contextKeyId) private view returns (bool) {
        return _records[attester][contextKeyId].descriptorDetails.descriptorHash != bytes32(0);
    }

    /// @dev Reads one active record and resolves its MirrorList IDs to URLs.
    function _resolveRecord(address attester, bytes32 contextKeyId) private view returns (ResolvedRecord memory) {
        RegistrationRecord storage record = _records[attester][contextKeyId];
        return ResolvedRecord({
            attester: attester,
            contextKeyId: contextKeyId,
            descriptorHash: record.descriptorDetails.descriptorHash,
            descriptorSchemaMajors: record.descriptorDetails.descriptorSchemaMajors,
            descriptorUrls: _mirrorLists[record.descriptorDetails.mirrorListId],
            attestationUrls: _mirrorLists[record.attestationDetails.mirrorListId]
        });
    }
}
