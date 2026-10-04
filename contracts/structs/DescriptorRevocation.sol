/// @notice One individual descriptor at one context being revoked - a single function or signature typehash.
///         The attester states that this exact descriptor content is no longer correct at this context.
///         The wallet MUST check the state of the descriptor's revocation before showing it to the users.
struct DescriptorRevocation {
    /// The context key ID the descriptor is attested under.
    bytes32 contextKeyId;
    /// The ERC-8176 descriptor hash of the exact descriptor content being revoked.
    bytes32 descriptorHash;
}
