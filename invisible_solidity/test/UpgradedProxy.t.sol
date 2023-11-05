// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "src/interactions/Interactions.sol";
import "src/InvisibleL1.sol";

//

// import "src/interactions/Deposit.sol";

contract UpgradeProxyTest is Test {
    InvisibleL1 invisibleL1;
    ERC20PresetMinterPauser testUsdc;
    ERC20PresetMinterPauser testWbtc;

    uint256 constant EthStarkKey =
        2292025268456116477323356083246651802150462734710453904748677715907532488444;
    uint256 constant UsdcStarkKey =
        2166840471905619448909926965843998034165267473744647928190851627614183386065;

    function setUp() public {
        vm.startPrank(address(8953626958234137847422389523978938749873));

        invisibleL1 = new InvisibleL1(
            address(8953626958234137847422389523978938749873),
            address(8953626958234137847422389523978938749873)
        );

        testUsdc = new ERC20PresetMinterPauser("testUsdc", "TT");

        testUsdc.mint(
            address(8953626958234137847422389523978938749873),
            5000 * 10 ** 18
        );

        vm.deal(
            address(8953626958234137847422389523978938749873),
            5 * 10 ** 18
        );

        testRegisterToken();
    }

    function testRegisterToken() public {
        address tokenAddress = address(testUsdc);

        uint32 tokenId = 55555;
        invisibleL1.registerToken(tokenAddress, tokenId, 6);
    }

    function testErc20Deposit() public {
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

    function testEthDeposit() public {
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

    function testDeposits() public {
        testErc20Deposit();
        testEthDeposit();
    }

    function testUpdatingTxBatch() public {
        testDeposits();

        address tokenAddress = address(testUsdc);

        uint256 pendingErcDeposit = invisibleL1.getPendingDepositAmount(
            UsdcStarkKey,
            tokenAddress
        );
        uint256 pendingEthDeposit = invisibleL1.getPendingDepositAmount(
            EthStarkKey,
            address(0)
        );

        assert(pendingErcDeposit == 2000 ether);
        assert(pendingEthDeposit == 2 ether);

        // =================================================
        uint256[] memory programOutput = getProgramOutput();

        invisibleL1.updateStateAfterTxBatch(programOutput);

        address recipient = address(
            uint160(649643524963080317271811968397224848924325242593)
        );
        uint256 pendingErcDeposit2 = invisibleL1.getPendingDepositAmount(
            UsdcStarkKey,
            tokenAddress
        );
        uint256 pendingEthDeposit2 = invisibleL1.getPendingDepositAmount(
            EthStarkKey,
            address(0)
        );
        uint256 pendingtokenWithdrawal = invisibleL1.getWithdrawableAmount(
            recipient,
            tokenAddress
        );
        uint256 pendingEthWithdrawal = invisibleL1.getETHWithdrawableAmount(
            recipient
        );

        assert(pendingErcDeposit2 == 0);
        assert(pendingEthDeposit2 == 0);
        // assert(pendingtokenWithdrawal == 0);
        // assert(pendingEthWithdrawal == 0);
        console.log("pendingtokenWithdrawal: ", pendingtokenWithdrawal);
        console.log("pendingEthWithdrawal: ", pendingEthWithdrawal);
    }

}