// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../structs/AttesterSettings.sol";

import "../IAttesterSettingsManager.sol";

contract AttesterSettingsManager is IAttesterSettingsManager {
    /// @notice The settings each attester declared. Empty if the attester never set any.
    mapping(address attester => AttesterSettings) private _attesterSettings;

    /// @notice Replace the caller's settings: its profile URI and its declared attestation formats.
    ///
    ///         The profile is display-only metadata and MUST NOT be used as trust input, while the declared
    ///         formats and their revocation controllers are functional hints wallets MAY act on.
    ///         The registry checks nothing here and never calls a revocation controller.
    ///         See 'AttesterSettings' for the meaning of each field.
    ///
    /// @param settings  The new settings. Replaces all previous settings, empty fields clear them.
    function updateAttesterSettings(AttesterSettings calldata settings) external {
        AttesterSettings storage stored = _attesterSettings[msg.sender];
        stored.profileURI = settings.profileURI;
        delete stored.attestationFormats;
        for (uint256 i = 0; i < settings.attestationFormats.length; i++) {
            stored.attestationFormats.push(settings.attestationFormats[i]);
        }
        emit AttesterSettingsUpdated(msg.sender, settings);
    }

    /// @notice The attester's current settings, or empty settings if it never set any.
    /// @param attester  The queried attester address.
    /// @return settings  The attester's settings.
    function getAttesterSettings(address attester) external view returns (AttesterSettings memory settings) {
        return _attesterSettings[attester];
    }
}
