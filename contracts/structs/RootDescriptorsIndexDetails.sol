/// @notice Function index metadata provided to the 'createAttestations' function for new descriptors.
struct RootDescriptorsIndexDetails {
    /// The MAJOR version of the ERC-7730 descriptor schema per its '$schema' key.
    uint256 descriptorSchemaMajor;
    /// The list of URLs leading to the root descriptors index file.
    bytes32 mirrorListId;
}
