// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../IClearSigningRegistry.sol";

contract AttesterSettingsManager {
    /// @notice Self-declared profile document URI per attester, an on-chain business card of the attesting entity.
    /// @notice Data provided by these links is a display-only metadata, and users should never trust this input.
    mapping(address attester => string) private _attesterProfileURIs;

    /// @notice The revocation controller (see IRevocationController) an attester declares per attestation format.
    /// @notice Value is address(0) if the attester declared none. The registry never calls a controller.
    mapping(address attester => mapping(bytes32 attestationFormatId => address)) private _revocationControllers;

    /// @notice The attestation formats an attester declares to use consistently across all of its records.
    /// @notice A declaration only: records are not checked against it and wallets may act on it as a hint.
    mapping(address attester => bytes32[]) private _attestationFormatIds;

    /// @inheritdoc IClearSigningRegistry
    function setAttesterProfileURI(string calldata profileURI) external {
        _attesterProfileURIs[msg.sender] = profileURI;
        emit IClearSigningRegistry.AttesterProfileUpdated(msg.sender, profileURI);
    }

    /// @inheritdoc IClearSigningRegistry
    function getAttesterProfileURI(address attester) external view returns (string memory) {
        return _attesterProfileURIs[attester];
    }

    /// @inheritdoc IClearSigningRegistry
    function setAttestationFormatIds(bytes32[] calldata attestationFormatIds) external {
        _attestationFormatIds[msg.sender] = attestationFormatIds;
        emit IClearSigningRegistry.AttestationFormatIdsUpdated(msg.sender, attestationFormatIds);
    }

    /// @inheritdoc IClearSigningRegistry
    function getAttestationFormatIds(address attester) external view returns (bytes32[] memory) {
        return _attestationFormatIds[attester];
    }

    /// @inheritdoc IClearSigningRegistry
    function setRevocationController(bytes32 attestationFormatId, address controller) external {
        _revocationControllers[msg.sender][attestationFormatId] = controller;
        emit IClearSigningRegistry.RevocationControllerUpdated(msg.sender, attestationFormatId, controller);
    }

    /// @inheritdoc IClearSigningRegistry
    function getRevocationController(address attester, bytes32 attestationFormatId) external view returns (address) {
        return _revocationControllers[attester][attestationFormatId];
    }
}
