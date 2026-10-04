// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./RootAttestationsIndexDetails.sol";
import "./RootDescriptorsIndexDetails.sol";

/// @notice The data provided by the attester to add descriptors and attestations for a provided set of 'contexts'
struct RegistrationRecord {
    RootDescriptorsIndexDetails        calldata descriptorsRootIndex;
    RootAttestationsIndexDetails       calldata attestationsRootIndex;
    bytes32[]                          contextKeyIds;
}
