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
        address withdrawer,
        address tokenAddress,
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

    function makeErc20VaultWithdrawal(address depositor, address tokenAddress)
        external
        onlyInteractionsContract
        onlyVaultToken(tokenAddress)
    {
        uint256 amount = withdrawableBalances[depositor];
        require(amount > 0, "No pending withdrawals");

        withdrawableBalances[depositor] = 0;

        IERC20 token = IERC20(tokenAddress);
        bool success = token.transfer(depositor, amount);

        require(success, "Transfer failed");

        emit WithdrawalEvent(depositor, tokenAddress, amount, block.timestamp);
    }

    // ----------------------------------

    function increaseWithdrawableAmount(
        address depositor,
        address tokenAddress,
        uint256 amount
    ) external onlyInteractionsContract onlyVaultToken(tokenAddress) {
        withdrawableBalances[depositor] += amount;
    }

    // ----------------------------------

    // todo
    function changeDepositContractAddress(address newAddress) public {}

    // ----------------------------------

    function getWithdrawableAmount(address depositor)
        public
        view
        returns (uint256)
    {
        return withdrawableBalances[depositor];
    }
}
