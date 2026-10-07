// SPDX-License-Identifier: CC0-1.0
pragma solidity 0.8.37;

/// @notice Events and errors of the MirrorList store.
interface IMirrorListManager {
    /// @notice Emitted the first time a MirrorList is stored on-chain, carrying its full URI contents.
    /// @param mirrorListId  The content hash of the published MirrorList.
    /// @param uris          The published URI list.
    event MirrorListPublished(bytes32 indexed mirrorListId, string[] uris);

    /// @notice Thrown when an empty URI list is passed to 'publishMirrorLists'.
    error EmptyMirrorList();

    /// @notice Thrown when a MirrorList id was never published via 'publishMirrorLists'.
    error UnknownMirrorList(bytes32 mirrorListId);
}
