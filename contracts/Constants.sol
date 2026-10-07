// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @title  Constants — Namespacing tags and attestation format IDs
/// @notice Pure constant values with no state or logic, kept in their own file so
///         ClearSigningRegistry.sol stays focused on registry behavior. The context
///         tags and the attestation format ID are reference values for off-chain use
///         (wallets derive context IDs and format IDs locally per the formulas here)
///         and are never read by the registry.
library Constants {
    /// contextKeyId = keccak256(abi.encode(CONTEXT_TAG_CONTRACT, uint256 chainId, address contractAddress))
    bytes32 internal constant CONTEXT_TAG_CONTRACT   = keccak256("erc7730.context.contract");

    /// contextKeyId = keccak256(abi.encode(CONTEXT_TAG_FACTORY, uint256 chainId, address factory, bytes32 deployEventTopic0))
    /// 'deployEventTopic0' is the topic0 of the factory's deploy event: the keccak256 of its canonical signature.
    /// Finding the factory of a given contract is up to the wallet.
    bytes32 internal constant CONTEXT_TAG_FACTORY    = keccak256("erc7730.context.factory");

    /// contextKeyId = keccak256(abi.encode(CONTEXT_TAG_EIP712_DEP, uint256 chainId, address verifyingContract, bytes32 typeHash))
    /// 'typeHash' is the EIP-712 type hash of the message's primary type, 'keccak256(encodeType(primaryType))'.
    bytes32 internal constant CONTEXT_TAG_EIP712_DEP = keccak256("erc7730.context.eip712.deployment");

    /// contextKeyId = keccak256(abi.encode(CONTEXT_TAG_EIP712_DS, bytes32 domainSeparator, bytes32 typeHash))
    /// 'typeHash' as for 'CONTEXT_TAG_EIP712_DEP'.
    bytes32 internal constant CONTEXT_TAG_EIP712_DS  = keccak256("erc7730.context.eip712.domainseparator");

    bytes32 internal constant ATTESTATION_FORMAT_EAS_OFFCHAIN = keccak256("erc7730.attestation.eas.offchain");

    /// Example vendor format for a post-quantum-signed attestation rendition (ML-DSA).
    /// The format namespace is open-ended and the registry has no opinion on attestations actual contents or encoding.
    bytes32 internal constant ATTESTATION_FORMAT_ML_DSA = keccak256("erc7730.attestation.mldsa");
}
