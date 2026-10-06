// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../IClearSigningRegistry.sol";

contract MirrorListManager {
    /// @notice Global store of MirrorLists, each a list of URLs leading to the same off-chain contents.
    /// @notice Written once per unique URL list, so attesters can share common data between records.
    mapping(bytes32 mirrorListId => string[] urls) internal _mirrorLists;

    /// @inheritdoc IClearSigningRegistry
    function getMirrorListById(bytes32 mirrorListId) external view returns (string[] memory) {
        return _mirrorLists[mirrorListId];
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorLists(string[][] calldata uriLists) external {
        for (uint256 i = 0; i < uriLists.length; i++) {
            _publishMirrorList(uriLists[i]);
        }
    }

    /// @dev Stores 'uris' keyed by its content hash. Idempotent: a list with identical
    ///      content is stored exactly once and emits no event on repeated publication.
    function _publishMirrorList(string[] calldata uris) private {
        if (uris.length == 0) {
            revert IClearSigningRegistry.EmptyMirrorList();
        }
        bytes32 mirrorListId = keccak256(abi.encode(uris));
        string[] storage storedUris = _mirrorLists[mirrorListId];
        if (storedUris.length == 0) {
            // Element-by-element copy: a whole-array 'storedUris = uris' assignment of
            // nested calldata arrays is only supported by the IR pipeline ('via-ir').
            for (uint256 i = 0; i < uris.length; i++) {
                storedUris.push(uris[i]);
            }
            emit IClearSigningRegistry.MirrorListPublished(mirrorListId, uris);
        }
    }

    /// @dev Reverts with 'UnknownMirrorList' unless 'mirrorListId' was already published.
    function _requireMirrorListPublished(bytes32 mirrorListId) internal view {
        if (_mirrorLists[mirrorListId].length == 0) {
            revert IClearSigningRegistry.UnknownMirrorList(mirrorListId);
        }
    }
}
