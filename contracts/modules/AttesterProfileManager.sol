// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../IClearSigningRegistry.sol";

contract AttesterProfileManager {
    /// @notice Self-declared profile document URI per attester, an on-chain business card of the attesting entity.
    /// @notice Data provided by these links is a display-only metadata, and users should never trust this input.
    mapping(address attester => string) private _attesterProfileURIs;

    /// @inheritdoc IClearSigningRegistry
    function setAttesterProfileURI(string calldata profileURI) external {
        _attesterProfileURIs[msg.sender] = profileURI;
        emit IClearSigningRegistry.AttesterProfileUpdated(msg.sender, profileURI);
    }

    /// @inheritdoc IClearSigningRegistry
    function getAttesterProfileURI(address attester) external view returns (string memory) {
        return _attesterProfileURIs[attester];
    }
}
