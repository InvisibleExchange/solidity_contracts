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
    Invisible invisibleL1;
    TestToken testUsdc;
    TestToken testWbtc;

    uint256 constant EthStarkKey =
        2292025268456116477323356083246651802150462734710453904748677715907532488444;
    uint256 constant UsdcStarkKey =
        2166840471905619448909926965843998034165267473744647928190851627614183386065;

    address constant owner = address(8953626958234137847422389523978938749873);

    function setUp() public {
        vm.startPrank(address(8953626958234137847422389523978938749873));

        invisibleL1 = new Invisible();
        invisibleL1.initialize(
            address(8953626958234137847422389523978938749873)
        );

        testUsdc = new TestToken("testUsdc", "TT");

        testUsdc.mint(
            address(8953626958234137847422389523978938749873),
            5000 * 10 ** 18
        );

        vm.deal(
            address(8953626958234137847422389523978938749873),
            5 * 10 ** 18
        );

        // testRegisterToken();
    }

    function testRegisterToken() public {
        address tokenAddress = address(testUsdc);

        uint32 tokenId = 2413654107;
        invisibleL1.registerToken(tokenAddress, tokenId, 6);
    }

    function testErc20Deposit2() public {
        address tokenAddress = address(testUsdc);

        // ? Approve tokens to be spent by the contract
        testUsdc.approve(address(invisibleL1), 2000 * 10 ** 18);
        vm.recordLogs();
        uint64 newAmountDeposited = invisibleL1.makeDeposit(
            tokenAddress,
            2000 * 10 ** 18,
            UsdcStarkKey
        );

        // interactions.startCancelDeposit(tokenAddress, UsdcStarkKey);
    }

    function testEthDeposit2() public {
        address tokenAddress = address(testUsdc);

        vm.recordLogs();
        uint64 newAmountDeposited = invisibleL1.makeDeposit{value: 2 ether}(
            address(0),
            2 ether,
            EthStarkKey
        );

        // Vm.Log[] memory entries = vm.getRecordedLogs();
        // bytes32[] memory b_arr = bytesToBytes32Array(entries[0].data);
        // console.log("entries: ", uint256(b_arr[0]));
        // console.log("entries: ", uint256(b_arr[1]));
        // console.log("entries: ", uint256(b_arr[2]));
        // console.log("entries: ", uint256(b_arr[3]));
        // console.log("entries: ", uint256(b_arr[4]));

        // console.log("newAmountDeposited: ", newAmountDeposited);

        // uint256 pendingDeposit = invisibleL1.getPendingDepositAmount(
        //     EthStarkKey,
        //     address(0)
        // );
        // console.log("pendingDeposit: ", pendingDeposit);

        // interactions.startCancelDeposit(tokenAddress, EthStarkKey);
    }
}
