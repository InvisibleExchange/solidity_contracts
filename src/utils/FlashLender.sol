// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";

contract FlashLender is IERC3156FlashLender {
    bytes32 public constant CALLBACK_SUCCESS =
        keccak256("ERC3156FlashBorrower.onFlashLoan");

    uint256 public constant feePercent = 0; //  1 == 0.01 %.

    /**
     * @dev Loan `amount` tokens to `receiver`, and takes it back plus a `flashFee` after the callback.
     * @param receiver The contract receiving the tokens, needs to implement the `onFlashLoan(address user, uint256 amount, uint256 fee, bytes calldata)` interface.
     * @param token The loan currency.
     * @param amount The amount of tokens lent.
     * @param data A data parameter to be passed on to the `receiver` for any custom use.
     */
    function flashLoan(
        IERC3156FlashBorrower receiver,
        address token,
        uint256 amount,
        bytes calldata data
    ) external override returns (bool) {
        require(
            maxFlashLoan(token) >= amount,
            "FlashLender: Insufficient funds for flash loan"
        );
        require(
            IERC20(token).transfer(address(receiver), amount),
            "FlashLender: Transfer failed"
        );

        uint256 fee = _flashFee(amount);
        require(
            receiver.onFlashLoan(msg.sender, token, amount, fee, data) ==
                CALLBACK_SUCCESS,
            "FlashLender: Callback failed"
        );
        require(
            IERC20(token).transferFrom(
                address(receiver),
                address(this),
                amount + fee
            ),
            "FlashLender: Repay failed"
        );
        return true;
    }

    /**
     * @dev The amount of currency available to be lent.
     * @return The amount of `token` that can be borrowed.
     */
    function maxFlashLoan(
        address token
    ) public view override returns (uint256) {
        return IERC20(token).balanceOf(address(this));
    }

    /**
     * @dev The fee to be charged for a given loan
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function flashFee(
        address token,
        uint256 amount
    ) external pure override returns (uint256) {
        return _flashFee(amount);
    }

    /**
     * @dev The fee to be charged for a given loan. Internal function with no checks.
     * @param amount The amount of tokens lent.
     * @return The amount of `token` to be charged for the loan, on top of the returned principal.
     */
    function _flashFee(uint256 amount) internal pure returns (uint256) {
        return (amount * feePercent) / 10000;
    }
}
