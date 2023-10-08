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

contract InteractionsTest is Test {
    InvisibleL1 invisibleL1;
    ERC20PresetMinterPauser testToken;

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

        testToken = new ERC20PresetMinterPauser("TestToken", "TT");

        testToken.mint(
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
        address tokenAddress = address(testToken);

        uint32 tokenId = 55555;
        invisibleL1.registerToken(tokenAddress, tokenId, 6);

        require(
            invisibleL1.getETHVaultAddress() != address(0),
            "ETH vault not set"
        );
        require(
            invisibleL1.getAssetVaultAddress(tokenAddress) != address(0),
            "Asset Vault not set"
        );
        require(invisibleL1.getTokenId(tokenAddress) != 0, "Token ID not set");
    }

    function testErc20Deposit() public {
        address tokenAddress = address(testToken);

        // ? Approve tokens to be spent by the contract
        testToken.approve(address(invisibleL1), 2000 * 10 ** 18);
        vm.recordLogs();
        uint64 newAmountDeposited = invisibleL1.makeDeposit(
            tokenAddress,
            2000 * 10 ** 18,
            UsdcStarkKey
        );

        // Vm.Log[] memory entries = vm.getRecordedLogs();
        // bytes32[] memory b_arr = bytesToBytes32Array(entries[2].data);
        // console.log("entries: ", uint256(b_arr[0]));
        // console.log("entries: ", uint256(b_arr[1]));
        // console.log("entries: ", uint256(b_arr[2]));
        // console.log("entries: ", uint256(b_arr[3]));
        // console.log("entries: ", uint256(b_arr[4]));

        // interactions.startCancelDeposit(tokenAddress, UsdcStarkKey);
    }

    function testEthDeposit() public {
        address tokenAddress = address(testToken);

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

        address tokenAddress = address(testToken);

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

    function testWithdawals() public {
        testUpdatingTxBatch();

        address tokenAddress = address(testToken);

        vm.stopPrank();
        vm.startPrank(
            address(649643524963080317271811968397224848924325242593)
        );

        uint256 prevErc20Balance = testToken.balanceOf(
            address(649643524963080317271811968397224848924325242593)
        );
        uint256 prevEthBalance = address(
            649643524963080317271811968397224848924325242593
        ).balance;

        assert(prevErc20Balance == 0);
        assert(prevEthBalance == 0);

        invisibleL1.makeWithdrawal(
            tokenAddress,
            address(649643524963080317271811968397224848924325242593),
            address(0),
            0,
            0,
            bytes32(""),
            bytes32("")
        );
        invisibleL1.makeETHWithdrawal(
            address(649643524963080317271811968397224848924325242593),
            address(0),
            0,
            0,
            bytes32(""),
            bytes32("")
        );

        uint256 newErc20Balance = testToken.balanceOf(
            address(649643524963080317271811968397224848924325242593)
        );
        uint256 newEthBalance = address(
            649643524963080317271811968397224848924325242593
        ).balance;

        console.log("newErc20Balance: ", newErc20Balance);
        console.log("newEthBalance: ", newEthBalance);
    }

    function testDelegatedWithdawals() public {
        testUpdatingTxBatch();

        address tokenAddress = address(testToken); //0x99F2226cf67E3270701C8eF16349E8e4F398dB2e

        vm.startPrank(
            address(845977816346026234456067308737012157398485141494)
        );

        invisibleL1.makeWithdrawal(
            tokenAddress,
            address(649643524963080317271811968397224848924325242593),
            address(845977816346026234456067308737012157398485141494),
            10000000000000000000,
            27,
            bytes32(
                0xeaee5268fc6984140aea5671a7476e4d2eeb36e7f771b4dd50103cbc15816aa4
            ),
            bytes32(
                0x70410f00f7d1956abab42d07bb3cee2b103d6374444e96196e11a49b09d8ebef
            )
        );
        invisibleL1.makeETHWithdrawal(
            address(649643524963080317271811968397224848924325242593),
            address(845977816346026234456067308737012157398485141494),
            10000000000000000,
            28,
            bytes32(
                0x2be5c5919f810768302f87c44e865dc1c3aa458982d60a41163d458553517304
            ),
            bytes32(
                0x255a831b08fe04ce9204bb59f9b3a6baad63ab344056ab41cf6d441895aca292
            )
        );

        uint256 newErc20Balance = testToken.balanceOf(
            address(649643524963080317271811968397224848924325242593)
        );
        uint256 newEthBalance = address(
            649643524963080317271811968397224848924325242593
        ).balance;

        console.log("recipient newErc20Balance: ", newErc20Balance);
        console.log("recipient newEthBalance: ", newEthBalance);
        // -- -- -- -- -- -- -- -- -- -- --
        uint256 newErc20Balance2 = testToken.balanceOf(
            address(845977816346026234456067308737012157398485141494)
        );
        uint256 newEthBalance2 = address(
            845977816346026234456067308737012157398485141494
        ).balance;

        console.log("proxy newErc20Balance: ", newErc20Balance2);
        console.log("proxy newEthBalance: ", newEthBalance2);
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

function getProgramOutput() pure returns (uint256[] memory res) {
    uint256[57] memory arr = [
        2450644354998405982022115704618884006901283874365176806194200773707121413423,
        2450644354998405982022115704618884006901283874365176806194200773707121413423,
        597579297039784607745,
        12554203473696364802333384682822702497637276928239934111746,
        4839524406068408503119694702759214384341319683,
        12345,
        54321,
        55555,
        66666,
        12345,
        54321,
        66666,
        9,
        9,
        6,
        0,
        2500,
        25000,
        50000,
        50000,
        6,
        6,
        10,
        50000000,
        500000000,
        350000000,
        150000,
        3000000,
        1500000,
        15000000,
        100000000000000,
        14000000204800000,
        9090909,
        7878787,
        5656565,
        874739451078007766457464989774322083649278607533249481151382481072868806602,
        3324833730090626974525872402899302150520188025637965566623476530814354734325,
        1839793652349538280924927302501143912227271479439798783640887258675143576352,
        296568192680735721663075531306405401515803196637037431012739700151231900092,
        9090909,
        953615528603744311503903171090925833574271533835808503650182590398151916787,
        1879460325315574557858341378868312245118849894900773666272893829174307676334,
        7878787,
        0,
        0,
        5656565,
        0,
        0,
        3093476031982861765946388197939943455579280384,
        2166840471905619448909926965843998034165267473744647928190851627614183386065,
        3093476031982861845174527948922094091536536576,
        2292025268456116477323356083246651802150462734710453904748677715907532488444,
        720256015655390340593015018558428160,
        649643524963080317271811968397224848924325242593,
        720256015655413103875201976145122304,
        649643524963080317271811968397224848924325242593,
        1
    ];

    res = new uint256[](arr.length);
    for (uint256 i = 0; i < arr.length; i++) {
        res[i] = arr[i];
    }

    return res;
}
