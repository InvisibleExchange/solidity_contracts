// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;


interface IL2Interactions {
    function makeDeposit(
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    ) external payable returns (uint64 newAmountDeposited,
            uint64 depositId,
            bytes32 depositHash);

    function handleExtensionDeposit(
        uint32 _srcChainId,
        address tokenAddress,
        uint256 amount,
        uint256 starkKey
    )
        external
        payable
        returns (
            uint64 newAmountDeposited,
            uint64 depositId,
            bytes32 depositHash
        );
}

 


