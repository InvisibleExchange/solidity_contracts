// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "../libraries/StructHasher.sol";

interface IStructHasher {
    function hashNote(Note calldata note) external view returns (uint256);

    function hashPosition(
        Position memory position
    ) external view returns (uint256);

    function hashOrderTab(
        OrderTab memory orderTab
    ) external view returns (uint256);

    function hashOpenOrderFields(
        OpenOrderFields calldata openOrderFields
    ) external view returns (uint256);

    function hashArr(uint256[] memory arr) external view returns (uint256);

    function hash2(uint256 a, uint256 b) external view returns (uint256);
}
