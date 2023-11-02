// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IETHVault {
    function increaseWithdrawableAmount(
        address recipient,
        uint256 amount
    ) external;

    function makeETHVaultWithdrawal(
        address payable recipient,
        uint256 _gasFee
    ) external;

    // function getWithdrawableAmount(
    //     address recipient
    // ) external view returns (uint256);
}

interface IAssetVault {
    function makeErc20VaultWithdrawal(
        address tokenAddress,
        address recipient,
        uint256 _gasFee
    ) external;

    function increaseWithdrawableAmount(
        address recipient,
        address tokenAddress,
        uint256 amount
    ) external;

    // function getWithdrawableAmount(
    //     address recipient
    // ) external view returns (uint256);
}
