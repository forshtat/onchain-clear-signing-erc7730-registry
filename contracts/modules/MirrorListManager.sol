// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

import "../IMirrorListManager.sol";

contract MirrorListManager is IMirrorListManager {
    /// @notice Global store of MirrorLists, each a list of URLs leading to the same off-chain contents.
    /// @notice Written once per unique URL list, so attesters can share common data between records.
    mapping(bytes32 mirrorListId => string[] urls) internal _mirrorLists;

    /// @notice Return the URI list for a given MirrorList ID, or an empty array if it was never published.
    /// @param mirrorListId  The MirrorList content hash.
    /// @return uris  The full URI list.
    function getMirrorListById(bytes32 mirrorListId) external view returns (string[] memory uris) {
        return _mirrorLists[mirrorListId];
    }

    /// @notice Publish a batch of MirrorLists on-chain.
    /// @param uriLists  The URI lists to publish. No list may be empty.
    function publishMirrorLists(string[][] calldata uriLists) external {
        for (uint256 i = 0; i < uriLists.length; i++) {
            _publishMirrorList(uriLists[i]);
        }
    }

    /// @dev Stores 'uris' keyed by its content hash. Idempotent: a list with identical
    ///      content is stored exactly once and emits no event on repeated publication.
    function _publishMirrorList(string[] calldata uris) private {
        require(uris.length != 0, EmptyMirrorList());
        bytes32 mirrorListId = keccak256(abi.encode(uris));
        if (_mirrorLists[mirrorListId].length == 0) {
            _mirrorLists[mirrorListId] = uris;
            emit MirrorListPublished(mirrorListId, uris);
        }
    }

    /// @dev Reverts with 'UnknownMirrorList' unless 'mirrorListId' was already published.
    function _requireMirrorListPublished(bytes32 mirrorListId) internal view {
        require(_mirrorLists[mirrorListId].length != 0, UnknownMirrorList(mirrorListId));
    }
}
