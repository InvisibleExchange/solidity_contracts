// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";

import "src/helpers/PedersenHash/PedersenHash.sol";
import "src/helpers/PedersenHash/PedersenHashNaive.sol";

import "src/interfaces/IPedersenHash.sol";

address constant PEDERSEN_HASH_ADDRESS = address(
    0x1a1eB562D2caB99959352E40a03B52C00ba7a5b1
);

contract Test1 is Test {
    function testHash() public {
        vm.startPrank(address(8953626958234137847422389523978938749873));

        // address[64] memory table = [
        //     address(0x5FbDB2315678afecb367f032d93F642f64180aa3),
        //     address(0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512),
        //     address(0xCf7Ed3AccA5a467e9e704C703E8D87F634fB0Fc9),
        //     address(0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0),
        //     address(0xDc64a140Aa3E981100a9becA4E685f962f0cF6C9),
        //     address(0x5FC8d32690cc91D4c39d9d3abcBD16989F875707),
        //     address(0x0165878A594ca255338adfa4d48449f69242Eb8F),
        //     address(0xa513E6E4b8f2a923D98304ec87F64353C4D5C853),
        //     address(0x2279B7A0a67DB372996a5FaB50D91eAA73d2eBe6),
        //     address(0x8A791620dd6260079BF849Dc5567aDC3F2FdC318),
        //     address(0x610178dA211FEF7D417bC0e6FeD39F05609AD788),
        //     address(0xB7f8BC63BbcaD18155201308C8f3540b07f84F5e),
        //     address(0xA51c1fc2f0D1a1b8494Ed1FE312d7C3a78Ed91C0),
        //     address(0x0DCd1Bf9A1b36cE34237eEaFef220932846BCD82),
        //     address(0x9A676e781A523b5d0C0e43731313A708CB607508),
        //     address(0x0B306BF915C4d645ff596e518fAf3F9669b97016),
        //     address(0x959922bE3CAee4b8Cd9a407cc3ac1C251C2007B1),
        //     address(0x3Aa5ebB10DC797CAC828524e59A333d0A371443c),
        //     address(0x9A9f2CCfdE556A7E9Ff0848998Aa4a0CFD8863AE),
        //     address(0x68B1D87F95878fE05B998F19b66F4baba5De1aed),
        //     address(0xc6e7DF5E7b4f2A278906862b61205850344D4e7d),
        //     address(0x59b670e9fA9D0A427751Af201D676719a970857b),
        //     address(0x4ed7c70F96B99c776995fB64377f0d4aB3B0e1C1),
        //     address(0x322813Fd9A801c5507c9de605d63CEA4f2CE6c44),
        //     address(0xa85233C63b9Ee964Add6F2cffe00Fd84eb32338f),
        //     address(0x4A679253410272dd5232B3Ff7cF5dbB88f295319),
        //     address(0x09635F643e140090A9A8Dcd712eD6285858ceBef),
        //     address(0x7a2088a1bFc9d81c55368AE168C2C02570cB814F),
        //     address(0xc5a5C42992dECbae36851359345FE25997F5C42d),
        //     address(0x67d269191c92Caf3cD7723F116c85e6E9bf55933),
        //     address(0xE6E340D132b5f46d1e472DebcD681B2aBc16e57E),
        //     address(0xc3e53F4d16Ae77Db1c982e75a937B9f60FE63690),
        //     address(0x84eA74d481Ee0A5332c457a4d796187F6Ba67fEB),
        //     address(0x9E545E3C0baAB3E08CdfD552C960A1050f373042),
        //     address(0xa82fF9aFd8f496c3d6ac40E2a0F282E47488CFc9),
        //     address(0x851356ae760d987E095750cCeb3bC6014560891C),
        //     address(0x1613beB3B2C4f22Ee086B2b38C1476A3cE7f78E8),
        //     address(0xf5059a5D33d5853360D16C683c16e67980206f36),
        //     address(0x95401dc811bb5740090279Ba06cfA8fcF6113778),
        //     address(0x998abeb3E57409262aE5b751f60747921B33613E),
        //     address(0x36C02dA8a0983159322a80FFE9F24b1acfF8B570),
        //     address(0x70e0bA845a1A0F2DA3359C97E0285013525FFC49),
        //     address(0x8f86403A4DE0BB5791fa46B8e795C547942fE4Cf),
        //     address(0x4826533B4897376654Bb4d4AD88B7faFD0C98528),
        //     address(0x99bbA657f2BbC93c02D617f8bA121cB8Fc104Acf),
        //     address(0x9d4454B023096f34B160D6B654540c56A1F81688),
        //     address(0x0E801D84Fa97b50751Dbf25036d067dCf18858bF),
        //     address(0x5eb3Bc0a489C5A8288765d2336659EbCA68FCd00),
        //     address(0x4c5859f0F772848b2D91F1D83E2Fe57935348029),
        //     address(0x1291Be112d480055DaFd8a610b7d1e203891C274),
        //     address(0x809d550fca64d94Bd9F66E60752A544199cfAC3D),
        //     address(0x5f3f1dBD7B74C6B46e8c44f98792A1dAf8d69154),
        //     address(0xCD8a1C3ba11CF5ECfa6267617243239504a98d90),
        //     address(0xb7278A61aa25c888815aFC32Ad3cC52fF24fE575),
        //     address(0x2bdCC0de6bE1f7D2ee689a0342D76F52E8EFABa3),
        //     address(0x82e01223d51Eb87e16A03E24687EDF0F294da6f1),
        //     address(0x7969c5eD335650692Bc04293B07F5BF2e7A673C0),
        //     address(0x7bc06c482DEAd17c0e297aFbC32f6e63d3846650),
        //     address(0xc351628EB244ec633d5f21fBD6621e1a683B1181),
        //     address(0xFD471836031dc5108809D173A067e8486B9047A3),
        //     address(0x1429859428C0aBc9C2C47C8Ee9FBaf82cFA0F20f),
        //     address(0xcbEAF3BDe82155F56486Fb5a1072cb8baAf547cc),
        //     address(0xB0D4afd8879eD9F52b28595d31B441D079B2Ca07),
        //     address(0x162A433068F51e18b7d13932F27e66a3f99E6890)
        // ];

        // PedersenHash hasher = new PedersenHash(table);

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
