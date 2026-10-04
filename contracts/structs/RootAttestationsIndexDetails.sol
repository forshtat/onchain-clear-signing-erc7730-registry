/// @notice Attestations index metadata attesters provide to create new attestations.
struct RootAttestationsIndexDetails {
    /// All declared MAJOR versions of the included descriptors' schema.
    uint256[] descriptorSchemaMajor;
    /// All attestation formats the specified "attestation index" file contains.
    /// The format identifiers are calculated as 'keccak256("erc7730.attestation.<format>")'.
    bytes32[] attestationFormatIds;
    /// The list of URLs leading to the root attestations index file.
    bytes32 mirrorListId;
}
