// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// TODO:
contract ETHVault {
    event WithdrawalEvent(
        address recipient,
        address aprovedProxy,
        uint256 proxyFee,
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

    function increaseWithdrawableAmount(
        address recipient,
        uint256 amount
    ) external onlyInteractionsContract {
        withdrawableBalances[recipient] += amount;
    }

    // ---------------------------------------------------------

    function makeETHVaultWithdrawal(
        address payable recipient,
        address payable approvedProxy,
        uint256 proxyFee
    ) external onlyInteractionsContract {
        // ? Get the withdrawable amount pending for the recipient
        uint256 amount = withdrawableBalances[recipient];
        require(amount > 0, "No pending withdrawals");

        // ? Reset the withdrawable amount for the recipient
        withdrawableBalances[recipient] = 0;

        // ? Transfer the fee to the proxy
        if (proxyFee > 0) {
            (bool sent, ) = approvedProxy.call{value: proxyFee}("");
            require(sent, "Failed to send Ether");
        }

        // ? Transfer the rest to the recipient
        (bool sent2, ) = recipient.call{value: amount - proxyFee}("");
        require(sent2, "Failed to send Ether");

        emit WithdrawalEvent(
            recipient,
            approvedProxy,
            proxyFee,
            amount - proxyFee,
            block.timestamp
        );
    }

    // ---------------------------------------------------------

    function getWithdrawableAmount(
        address recipient
    ) public view returns (uint256) {
        return withdrawableBalances[recipient];
    }
}
