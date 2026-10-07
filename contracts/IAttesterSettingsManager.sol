// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "./structs/AttesterSettings.sol";

/// @notice Events of the attester settings store.
interface IAttesterSettingsManager {
    /// @notice Emitted when an attester replaces its settings.
    /// @param attester  The attester whose settings changed.
    /// @param settings  The new settings.
    event AttesterSettingsUpdated(address indexed attester, AttesterSettings settings);
}
