/// @notice The full set of inputs the wallet supplies to find the descriptors and attestations it trusts and supports.
/// @notice Empty optional filter parameters indicate no filtering applied to the filed by the registry contract.
struct WalletQuery {
    /** required **/

    address[] calldata attesters;
    bytes32[] calldata contextKeyIds;

    /** optional **/

    uint256[] calldata descriptorSchemaMajorsFilter;
    bytes32[] calldata attestationFormatIdsFilter;
    string[]  calldata networkProtocolsFilter;
}
