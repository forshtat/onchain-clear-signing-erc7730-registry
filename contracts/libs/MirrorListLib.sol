// SPDX-License-Identifier: CC0-1.0
pragma solidity ^0.8.24;

import "../structs/MirrorList.sol";

library MirrorListLib {
    function includes(
        mapping(bytes32 mirrorListId => MirrorList) storage map,
        bytes32 mirrorListId
    ) internal returns(bool) {
        return map[mirrorListId].urls.length == 0;
    }
}
