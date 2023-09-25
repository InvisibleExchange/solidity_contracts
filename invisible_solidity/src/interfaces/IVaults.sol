// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IETHVault {
    function increaseWithdrawableAmount(
        address recipient,
        uint256 amount
    ) external;

    function makeETHVaultWithdrawal(
        address payable recipient,
        address payable _approvedProxy,
        uint256 _proxyFee
    ) external;

    function getWithdrawableAmount(
        address recipient
    ) external view returns (uint256);
}

interface IAssetVault {
    function makeErc20VaultWithdrawal(
        address tokenAddress,
        address recipient,
        address _approvedProxy,
        uint256 _proxyFee
    ) external;

    function increaseWithdrawableAmount(
        address recipient,
        address tokenAddress,
        uint256 amount
    ) external;

    function getWithdrawableAmount(
        address recipient
    ) external view returns (uint256);
}
