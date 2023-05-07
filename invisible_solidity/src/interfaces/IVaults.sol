// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IETHVault {

    function increaseWithdrawableAmount(address depositor, uint256 amount)
        external;

    function makeETHVaultWithdrawal(address payable depositor) external;

    function getWithdrawableAmount(address depositor)
        external
        view
        returns (uint256);
}

interface IAssetVault {
    function makeErc20VaultWithdrawal(address depositor, address tokenAddress)
        external;

    function increaseWithdrawableAmount(
        address depositor,
        address tokenAddress,
        uint256 amount
    ) external;

    function getWithdrawableAmount(address depositor)
        external
        view
        returns (uint256);
}
