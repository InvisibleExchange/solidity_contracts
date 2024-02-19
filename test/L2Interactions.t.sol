// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

import "src/TestToken.sol";
import "src/core/Interactions.sol";
import "src/Invisible.sol";

//

// import "src/interactions/Deposit.sol";

contract InteractionsTest is Test {
    InvisibleL2 invisibleL2;
    TestToken testUsdc;
    TestToken testWbtc;

    uint256 constant EthStarkKey =
        2292025268456116477323356083246651802150462734710453904748677715907532488444;
    uint256 constant UsdcStarkKey =
        2166840471905619448909926965843998034165267473744647928190851627614183386065;

    address constant owner =
        address(0xaCEdF8742eDC7d923e1e6462852cCE136ee9Fb56);

    function setUp() public {
        vm.startPrank(owner);

        invisibleL2 = new InvisibleL2();
        invisibleL2.initialize(owner, 40231);

        testUsdc = new TestToken("testUsdc", "TT");

        testUsdc.mint(owner, 5000 * 10 ** 18);

        vm.deal(owner, 5 * 10 ** 18);

        testRegisterToken();
    }

    function testRegisterToken() public {
        address tokenAddress = address(testUsdc);

        uint32 tokenId = 2413654107;
        invisibleL2.registerToken(tokenAddress, tokenId, 6);
    }

    function testErc20Deposit() public {
        address tokenAddress = address(testUsdc);

        // ? Approve tokens to be spent by the contract
        testUsdc.approve(address(invisibleL2), 2000 * 10 ** 18);
        vm.recordLogs();
        (
            uint64 newAmountDeposited,
            uint64 depositId,
            bytes32 depositHash
        ) = invisibleL2.makeDeposit(
                tokenAddress,
                2000 * 10 ** 18,
                UsdcStarkKey
            );

        uint256 pendingDeposit = invisibleL2.getPendingDepositAmount(
            UsdcStarkKey,
            tokenAddress
        );
        console.log("pendingDeposit: ", pendingDeposit);

        // interactions.startCancelDeposit(tokenAddress, UsdcStarkKey);
    }

    function testEthDeposit() public {
        address tokenAddress = address(testUsdc);

        vm.recordLogs();
        (
            uint64 newAmountDeposited,
            uint64 depositId,
            bytes32 depositHash
        ) = invisibleL2.makeDeposit{value: 2 ether}(
                address(0),
                2 ether,
                EthStarkKey
            );

        uint256 pendingDeposit = invisibleL2.getPendingDepositAmount(
            EthStarkKey,
            address(0)
        );
        console.log("pendingDeposit: ", pendingDeposit);

        // interactions.startCancelDeposit(tokenAddress, EthStarkKey);
    }

    function testDeposits() public {
        testErc20Deposit();
        testEthDeposit();
    }

    function testUpdatingTxBatch() public {}

    function testEncode() public {
        bytes memory res = abi.encode(123, 456);

        // bytes32[] memory b_arr = bytesToBytes32Array(res);
        // console.log("res: ", uint256(b_arr[0]));
        // console.log("res: ", uint256(b_arr[1]));

        uint256 hashRes = uint256(keccak256(res));

        console.log("hashRes: ", hashRes);
    }
}

function bytesToBytes32Array(
    bytes memory data
) pure returns (bytes32[] memory) {
    // Find 32 bytes segments nb
    uint256 dataNb = data.length / 32;
    // Create an array of dataNb elements
    bytes32[] memory dataList = new bytes32[](dataNb);
    // Start array index at 0
    uint256 index = 0;
    // Loop all 32 bytes segments
    for (uint256 i = 32; i <= data.length; i = i + 32) {
        bytes32 temp;
        // Get 32 bytes from data
        assembly {
            temp := mload(add(data, i))
        }
        // Add extracted 32 bytes to list
        dataList[index] = temp;
        index++;
    }
    // Return data list
    return (dataList);
}

// function getProgramOutput() pure returns (uint256[] memory res) {
//     uint256[1] memory arr = [1];

//     res = new uint256[](arr.length);
//     for (uint256 i = 0; i < arr.length; i++) {
//         res[i] = arr[i];
//     }

//     return res;
// }
