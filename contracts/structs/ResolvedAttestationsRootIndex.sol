// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "./MirrorList.sol";

struct ResolvedAttestationRootIndex {
    /// The attester that issued this particular attestation.
    address attester;
    /// The context ID the attestations root index was resolved for.
    bytes32 contextKeyId;
    /// A format identifiers calculated as keccak256("erc7730.attestation.<format>") used in these attestations.
    bytes32[] attestationFormatId;
    /// The list of URLs that resolve to the attestations root index file regardless of the network protocol.
    MirrorList mirrorList;
}
