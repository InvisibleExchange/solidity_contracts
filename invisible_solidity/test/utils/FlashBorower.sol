// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/console.sol";

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashLender.sol";
import "@openzeppelin/contracts/interfaces/IERC3156FlashBorrower.sol";

contract FlashBorrower is IERC3156FlashBorrower {
    enum Action {
        NORMAL,
        OTHER
    }

    IERC3156FlashLender lender;

    constructor(address lender_) {
        lender = IERC3156FlashLender(lender_);
    }

    /// @dev ERC-3156 Flash loan callback
    function onFlashLoan(
        address initiator,
        address token,
        uint256 amount,
        uint256 fee,
        bytes calldata data
    ) external override returns (bytes32) {
        require(
            msg.sender == address(lender),
            "FlashBorrower: Untrusted lender"
        );
        require(
            initiator == address(this),
            "FlashBorrower: Untrusted loan initiator"
        );
        Action action = abi.decode(data, (Action));
        if (action == Action.NORMAL) {
            // do one thing
        } else if (action == Action.OTHER) {
            // do another
        }

        uint256 _allowance = IERC20(token).allowance(
            address(this),
            address(lender)
        );
        uint256 _repayment = amount + fee;
        IERC20(token).approve(address(lender), _allowance + _repayment);


        return keccak256("ERC3156FlashBorrower.onFlashLoan");
    }

    /// @dev Initiate a flash loan
    function flashBorrow(address token, uint256 amount) public {
        bytes memory data = abi.encode(Action.NORMAL);

        lender.flashLoan(this, token, amount, data);
    }
}
