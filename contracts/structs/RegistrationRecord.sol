// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "./AttestationDetails.sol";
import "./DescriptorDetails.sol";

/// @notice The data provided by the attester containing descriptors and attestations for a given set of 'contexts'.
struct RegistrationRecord {
    DescriptorDetails  descriptorDetails;
    AttestationDetails attestationDetails;
}
