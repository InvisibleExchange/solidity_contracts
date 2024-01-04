// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

// import "src/interactions/Deposit.sol";

contract InteractionsTest is Test {
    function testEncode() public view {
        bytes memory res = abi.encodePacked(uint256(1), uint256(1));

        // bytes32[] memory b_arr = bytesToBytes32Array(res);
        // console.log("res: ", uint256(b_arr[0]));
        // console.log("res: ", uint256(b_arr[1]));

        uint256 hashRes = uint256(keccak256(res));

        console.log("hashRes: ", hashRes);
    }
}
