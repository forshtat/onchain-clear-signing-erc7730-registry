contract AttesterProfileManager {
    /// @notice Self-declared profile document URI per attester, an on-chain business card of the attesting entity.
    /// @notice Data provided by these links is a display-only metadata, and users should never trust this input.
    mapping(address attester => string) private _attesterProfileURIs;

    /// @inheritdoc IClearSigningRegistry
    function setAttesterProfileURI(
        address attester,
        string calldata profileURI,
        bytes  calldata signature
    ) external {
        if (msg.sender != attester) {
            uint256 nonce = _nonces[attester];
            _nonces[attester] = nonce + 1;
            _verifyProfileUpdateSignature(attester, profileURI, nonce, signature);
        }

        if (keccak256(bytes(_attesterProfileURIs[attester])) == keccak256(bytes(profileURI))) {
            return;
        }
        _attesterProfileURIs[attester] = profileURI;
        emit AttesterProfileUpdated(attester, profileURI);
    }

    /// @inheritdoc IClearSigningRegistry
    function getAttesterProfileURI(address attester) external view returns (string memory) {
        return _attesterProfileURIs[attester];
    }

}
