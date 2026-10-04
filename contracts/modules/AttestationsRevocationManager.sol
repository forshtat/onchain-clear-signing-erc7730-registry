// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;


contract AttestationsRevocationManager {

    /// @notice The timestamp at which 'attester' revoked the 'descriptorHash' for a given 'contextKeyId'.
    /// @notice Value is 0 if attester has never revoked this 'descriptorHash'.
    /// @notice The registry does link revocations to any records and never checks that the content was ever attested.
    /// @notice Written by a 'revokeDescriptors' function.
    mapping(address attester => mapping(bytes32 contextKeyId => mapping(bytes32 descriptorHash => uint64))) private _descriptorRevokedAt;

    /// @inheritdoc IClearSigningRegistry
    function revokeDescriptors(
        address attester,
        DescriptorRevocation[] calldata revocations,
        bytes                  calldata signature
    ) external {
        if (revocations.length == 0) {
            revert EmptyRevocations();
        }
        if (msg.sender != attester) {
            uint256 nonce = _nonces[attester];
            _nonces[attester] = nonce + 1;
            _verifyDescriptorRevocationSignature(attester, revocations, nonce, signature);
        }

        uint64 timestamp = uint64(block.timestamp);
        for (uint256 revocationIndex = 0; revocationIndex < revocations.length; revocationIndex++) {
            DescriptorRevocation calldata revocation = revocations[revocationIndex];
            // Overwritten on repeat: an audit-trail timestamp only, never consulted for
            // ordering — the pair is void from the moment it is first recorded, forever.
            _descriptorRevokedAt[attester][revocation.contextKeyId][revocation.descriptorHash] = timestamp;
            emit DescriptorRevoked(attester, revocation.contextKeyId, revocation.descriptorHash, timestamp);
        }
    }

    /// @inheritdoc IClearSigningRegistry
    function getDescriptorRevocationTimestamp(address attester, bytes32 contextKeyId, bytes32 descriptorHash)
    external view returns (uint64)
    {
        return _descriptorRevokedAt[attester][contextKeyId][descriptorHash];
    }
}
