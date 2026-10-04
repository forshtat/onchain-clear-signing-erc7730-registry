// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../structs/MirrorList.sol";

contract MirrorListManager {

    /// @notice Global store of MirrorLists regardless of the contents type.
    /// @notice Mirror lists allow sharing common off-chain data with identifier written once per unique URI set.
    mapping(bytes32 mirrorListId => MirrorList) private _mirrorLists;

    /// @inheritdoc IClearSigningRegistry
    function getMirrorListById(bytes32 mirrorListId, string[] calldata allowedPrefixes)
    external view returns (string[] memory)
    {
        return _mirrorLists[mirrorListId].filter(allowedPrefixes);
    }

    /// @inheritdoc IClearSigningRegistry
    function publishMirrorLists(string[][] calldata uriLists) external {
        uint256 listCount = uriLists.length;
        for (uint256 listIndex = 0; listIndex < listCount; listIndex++) {
            _publishMirrorList(uriLists[listIndex]);
        }
    }

    /// @dev Stores 'uris' keyed by its content hash. Idempotent: a list with identical
    ///      content is stored exactly once and emits no event on repeated publication.
    function _publishMirrorList(string[] calldata uris) private returns (bytes32 mirrorListId) {
        if (uris.length == 0) {
            revert EmptyMirrorList();
        }
        mirrorListId = keccak256(abi.encode(uris));
        string[] storage storedUris = _mirrorLists[mirrorListId];
        if (storedUris.length == 0) {
            // Element-by-element copy: a whole-array 'storedUris = uris' assignment of
            // nested calldata arrays is only supported by the IR pipeline ('via-ir').
            for (uint256 uriIndex = 0; uriIndex < uris.length; uriIndex++) {
                storedUris.push(uris[uriIndex]);
            }
            emit MirrorListPublished(mirrorListId, uris);
        }
    }
}
