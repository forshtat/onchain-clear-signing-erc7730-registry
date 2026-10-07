// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @title  Constants — Namespacing tags and attestation format IDs
/// @notice Pure constant values with no state or logic, kept in their own file so
///         ClearSigningRegistry.sol stays focused on registry behavior. The context
///         tags and the attestation format ID are reference values for off-chain use
///         (wallets derive context IDs and format IDs locally per the formulas here)
///         and are never read by the registry.
library Constants {
    bytes32 internal constant CONTEXT_TAG_CONTRACT   = keccak256("erc7730.context.contract");

    bytes32 internal constant CONTEXT_TAG_FACTORY    = keccak256("erc7730.context.factory");

    bytes32 internal constant CONTEXT_TAG_EIP712_DEP = keccak256("erc7730.context.eip712.deployment");

    bytes32 internal constant CONTEXT_TAG_EIP712_DS  = keccak256("erc7730.context.eip712.domainseparator");

    bytes32 internal constant ATTESTATION_FORMAT_EAS_OFFCHAIN = keccak256("erc7730.attestation.eas.offchain");

    /// Example vendor format for a post-quantum-signed attestation rendition (ML-DSA).
    /// The format namespace is open-ended and the registry has no opinion on attestations actual contents or encoding.
    bytes32 internal constant ATTESTATION_FORMAT_ML_DSA = keccak256("erc7730.attestation.mldsa");
}
