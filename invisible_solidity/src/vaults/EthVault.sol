// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// TODO:
contract ETHVault {
    event WithdrawalEvent(
        address withdrawer,
        uint256 withdrawalAmount,
        uint256 timestamp
    );

    mapping(address => uint256) public withdrawableBalances;

    address interactionsContract; // Todo: Should this be immutable?

    constructor(address _interactionsContract) {
        interactionsContract = _interactionsContract;
    }

    modifier onlyInteractionsContract() {
        require(
            msg.sender == interactionsContract,
            "Only interactions contract"
        );
        _;
    }

    receive() external payable {}

    // ---------------------------------------------------------

    function increaseWithdrawableAmount(address depositor, uint256 amount)
        external
        onlyInteractionsContract
    {
        withdrawableBalances[depositor] += amount;
    }

    // ---------------------------------------------------------

    function makeETHVaultWithdrawal(address payable depositor)
        external
        onlyInteractionsContract
    {
        uint256 amount = withdrawableBalances[depositor];
        require(amount > 0, "No pending withdrawals");

        (bool sent, bytes memory data) = depositor.call{value: amount}("");
        require(sent, "Failed to send Ether");

        emit WithdrawalEvent(depositor, amount, block.timestamp);
    }

    // ---------------------------------------------------------

    function getWithdrawableAmount(address depositor)
        public
        view
        returns (uint256)
    {
        return withdrawableBalances[depositor];
    }
}
