// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "../helpers/FlashLender.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

// todo: if the function receives funds it forwards them to the vault

// TODO: Add possibility to lock/pause the vault (maybe on a user specific level)

contract AssetVault is FlashLender {
    event DepositEvent(
        address depositor,
        address tokenAddress,
        uint256 depositAmount,
        uint256 timestamp
    );

    event WithdrawalEvent(
        address tokenAddress,
        address recipient,
        address aprovedProxy,
        uint256 proxyFee,
        uint256 withdrawalAmount,
        uint256 timestamp
    );

    address public immutable tokenAddr;
    address public immutable interactionsContract;

    mapping(address => uint256) public withdrawableBalances;

    constructor(address _tokenAddress, address _interactionsContract) {
        tokenAddr = _tokenAddress;
        interactionsContract = _interactionsContract;
    }

    modifier onlyInteractionsContract() {
        // TODO:
        // require(
        //     msg.sender == interactionsContract,
        //     "Only interactions contract"
        // );
        _;
    }

    modifier onlyVaultToken(address tokenAddress) {
        require(tokenAddress == tokenAddr, "token missmatch in asset vault");
        _;
    }

    function makeErc20VaultWithdrawal(
        address tokenAddress,
        address recipient,
        address approvedProxy,
        uint256 proxyFee
    ) external onlyInteractionsContract onlyVaultToken(tokenAddress) {
        // ? Get the withdrawable amount pending for the recipient
        uint256 amount = withdrawableBalances[recipient];
        require(amount > 0, "No pending withdrawals");

        // ? Reset the withdrawable amount for the recipient
        withdrawableBalances[recipient] = 0;

        IERC20 token = IERC20(tokenAddress);

        // ? Transfer the fee to the proxy
        if (proxyFee > 0) {
            bool success = token.transfer(approvedProxy, proxyFee);
            require(success, "Transfer failed");
        }

        // ? Transfer the rest to the recipient
        uint256 withdrawalAmount = amount - proxyFee;

        bool success2 = token.transfer(recipient, withdrawalAmount);
        require(success2, "Transfer failed");

        // ? Emit an event
        emit WithdrawalEvent(
            tokenAddress,
            recipient,
            approvedProxy,
            proxyFee,
            withdrawalAmount,
            block.timestamp
        );
    }

    // ----------------------------------

    function increaseWithdrawableAmount(
        address recipient,
        address tokenAddress,
        uint256 amount
    ) external onlyInteractionsContract onlyVaultToken(tokenAddress) {
        withdrawableBalances[recipient] += amount;
    }

    // ----------------------------------

    // todo
    function changeInteractionsContractAddress(address newAddress) public {}

    // ----------------------------------

    function getWithdrawableAmount(
        address depositor
    ) public view returns (uint256) {
        return withdrawableBalances[depositor];
    }
}
