// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import "src/interfaces/IPedersenHash.sol";

address constant PEDERSEN_HASH_ADDRESS = address(
    0x1a1eB562D2caB99959352E40a03B52C00ba7a5b1
);

contract Test1 is Test {
    function testHash() public {
        vm.startPrank(address(8953626958234137847422389523978938749873));

        uint256[] memory arr = new uint256[](2);
        arr[0] = 1;
        arr[1] = 2;

        bytes memory hashInput = abi.encodePacked(arr);

        uint256[] memory res = IPedersenHash(PEDERSEN_HASH_ADDRESS).hash(
            hashInput
        );

        console.log("res", res[0]);
    }

    function testEncode() public {
        address _tokenAddress = address(
            uint160(149118583348991840656470636803218188963536151985)
        );
        address _approvedProxy = address(
            uint160(149118583348991840656470636803218188963536151985)
        );
        uint256 _proxyFee = 1000000000000;

        bytes memory res = abi.encode(_tokenAddress, _approvedProxy, _proxyFee);

        uint256 res2 = uint256(bytes32(res));

        console.log("res", res2);
    }
}
