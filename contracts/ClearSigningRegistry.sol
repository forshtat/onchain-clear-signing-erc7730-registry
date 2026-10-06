// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";

import "./modules/RecordsModule.sol";

import "./structs/AttestationsDetails.sol";
import "./structs/DescriptorDetails.sol";
import "./structs/RegistrationRecord.sol";

import "./ClearSigningRegistryConstants.sol";
import "./IClearSigningRegistry.sol";

/// @title  ClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of IClearSigningRegistry.
contract ClearSigningRegistry is
    RecordsModule,
    EIP712 {
    constructor() EIP712("ClearSigningRegistry", "1") {}




    /// @inheritdoc IClearSigningRegistry
    function updateMirrorLists(
        bytes32[] calldata descriptorHashes,
        bytes32 descriptorMirrorListId,
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
