// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "./modules/AttesterSettingsManager.sol";
import "./modules/RecordsResolver.sol";

/// @title  ClearSigningRegistry — On-Chain Registry for ERC-7730 Clear Signing Descriptors
/// @notice Reference implementation of ERC-8283, an on-chain registry mapping contexts to attested
///         ERC-7730 Clear Signing descriptors, composed of its modules.
contract ClearSigningRegistry is RecordsResolver, AttesterSettingsManager {
    string public constant version = "0.0.1";
}
