// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./MirrorList.sol";

struct ResolvedDescriptorRootIndex {
    /// The context ID the descriptor root index was resolved for.
    bytes32 contextKeyId;
    /// The schema MAJOR version of the descriptors in the provided root index.
    uint256 descriptorSchemaMajor;
    /// The list of URLs that resolve to the descriptor root index file regardless of the network protocol.
    MirrorList mirrorList;
}
