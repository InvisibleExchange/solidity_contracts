// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

import "@openzeppelin/contracts/token/ERC20/presets/ERC20PresetMinterPauser.sol";
import "src/interactions/Interactions.sol";

// import "src/interactions/Deposit.sol";

contract InteractionsTest is Test {
    Interactions interactions;

    ERC20PresetMinterPauser testToken;

    function setUp() public {
        vm.startPrank(address(8953626958234137847422389523978938749873));

        interactions = new Interactions();
        testToken = new ERC20PresetMinterPauser("TestToken", "TT");

        testToken.mint(
            address(8953626958234137847422389523978938749873),
            5000 * 10 ** 18
        );

        vm.deal(
            address(8953626958234137847422389523978938749873),
            5 * 10 ** 18
        );
    }

    function testRegisterToken() private {
        address tokenAddress = address(testToken);

        uint32 tokenId = 55555;
        interactions.registerToken(tokenAddress, tokenId, 6);

        require(
            interactions.getETHVaultAddress() != address(0),
            "ETH vault not set"
        );
        require(
            interactions.getAssetVaultAddress(tokenAddress) != address(0),
            "Asset Vault not set"
        );
        require(interactions.getTokenId(tokenAddress) != 0, "Token ID not set");
    }

    function testErc20Deposit() public {
        address tokenAddress = address(testToken);
        // ? Register token
        uint32 tokenId = 55555;
        interactions.registerToken(tokenAddress, tokenId, 6);
        // ? Approve tokens to be spent by the contract
        testToken.approve(address(interactions), 10 ** 18);
        vm.recordLogs();
        uint256 starkKey = 883045738439352841478194533192765345509759306772397516907181243450667673002;
        uint64 newAmountDeposited = interactions.makeDeposit(
            tokenAddress,
            10 ** 18,
            starkKey
        );
        console.log("newAmountDeposited: ", newAmountDeposited);
        uint256 hash_ = uint256(
            keccak256("DepositEvent(uint256,uint64,uint64,uint256)")
        );
        console.log("hash: ", hash_);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bytes32[] memory b_arr = bytesToBytes32Array(entries[2].data);
        console.log("entries: ", uint256(b_arr[0]));
        console.log("entries: ", uint256(b_arr[1]));
        console.log("entries: ", uint256(b_arr[2]));
        console.log("entries: ", uint256(b_arr[3]));
        // interactions.startCancelDeposit(tokenAddress, starkKey);
    }

    function testEthDeposit() public {
        address tokenAddress = address(testToken);

        uint256 starkKey = 883045738439352841478194533192765345509759306772397516907181243450667673002;

        (bool sent, bytes memory data) = address(interactions).call{
            value: 1 ether
        }("");

        uint256 pendingDeposit = interactions.getPendingDepositAmount(
            starkKey,
            address(0)
        );

        console.log("newAmountDeposited: ", pendingDeposit);

        // interactions.startCancelDeposit(tokenAddress, starkKey);
    }

    function testUpdatingTxBatch() public {
        address tokenAddress = address(testToken);
        interactions.registerToken(tokenAddress, 55555, 6);

        testToken.approve(address(interactions), 2000 * 10 ** 18);

        uint256 starkKey1 = 2459783709223877114575387623877149074199685766944984049223820349308467967672;
        interactions.makeDeposit(tokenAddress, 2000 * 10 ** 18, starkKey1);

        (bool sent, bytes memory data) = address(interactions).call{
            value: 2 ether
        }("");

        uint256 pendingErcDeposit = interactions.getPendingDepositAmount(
            starkKey1,
            tokenAddress
        );
        uint256 pendingEthDeposit = interactions.getPendingDepositAmount(
            775866413365693995389455817999955458452590009573650990406301639026116962377,
            address(0)
        );
        // uint256 pendingtokenWithdrawal = interactions.getWithdrawableAmount(
        //     address(1234566790),
        //     tokenAddress
        // );
        // uint256 pendingEthWithdrawal = interactions.getWithdrawableAmount(
        //     address(1234566790),
        //     address(0)
        // );

        assert(pendingErcDeposit == 2000 ether);
        assert(pendingEthDeposit == 2 ether);
        // assert(pendingtokenWithdrawal == 0);
        // assert(pendingEthWithdrawal == 0);

        // =================================================
        uint256[] memory programOutput = getProgramOutput();

        interactions.updateStateAfterTxBatch(programOutput);

        uint256 pendingErcDeposit2 = interactions.getPendingDepositAmount(
            starkKey1,
            tokenAddress
        );
        uint256 pendingEthDeposit2 = interactions.getPendingDepositAmount(
            775866413365693995389455817999955458452590009573650990406301639026116962377,
            address(0)
        );
        uint256 pendingtokenWithdrawal2 = interactions.getWithdrawableAmount(
            address(1234566790),
            tokenAddress
        );
        uint256 pendingEthWithdrawal2 = interactions.getWithdrawableAmount(
            address(1234566790),
            address(0)
        );

        assert(pendingErcDeposit2 == 0);
        assert(pendingEthDeposit2 == 0);
        assert(pendingtokenWithdrawal2 == 0);
        assert(pendingEthWithdrawal2 == 0);

        // vm.stopPrank();
        // vm.startPrank(address(1234566790));

        // uint256 prevErc20Balance = testToken.balanceOf(address(1234566790));
        // uint256 prevEthBalance = address(1234566790).balance;

        // interactions.makeWithdrawal(tokenAddress);
        // interactions.makeWithdrawal(address(0));

        // uint256 newErc20Balance = testToken.balanceOf(address(1234566790));
        // uint256 newEthBalance = address(1234566790).balance;

        // assert(newErc20Balance == prevErc20Balance + 750 ether);
        // assert(newEthBalance == prevEthBalance + 1 ether);

        console.log("all good");
    }

    function testParsingOutput() public {}
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
    uint256[30] memory arr = [
        1234,
        2450644354998405982022115704618884006901283874365176806194200773707121413423,
        1044525760850525118001825284285477436097574189665475174859091253959006979265,
        2450644354998405982022115704618884006901283874365176806194200773707121413423,
        2450644354998405982022115704618884006901283874365176806194200773707121413423,
        32,
        32,
        1000000,
        2,
        0,
        0,
        0,
        4,
        0,
        41854731131275432030803943729043630035968,
        2459783709223877114575387623877149074199685766944984049223820349308467967672,
        41854731131275432008040661542084243341824,
        775866413365693995389455817999955458452590009573650990406301639026116962377,
        18904400986198465485309396213578752547880960,
        1988250149696710433421329553413323843519599428602598721779961439785779831659,
        659989352669679706312161156445382964319342115273494181480533346128107582885,
        18484642380480183411440568065748676380721153,
        274041165779404240379851331431573468887690028447885183061428345441162228837,
        67055171112012512305592818037275309783220345922063691138627562330974567212,
        18484782119636345144126987198758415612510210,
        2318803890409382406016585251510039616196857029763153382713871205013500218887,
        2299410017732986529954972099567931130912921914304792329906711340862300954434,
        18904588928650690853760905227666797757464579,
        2848031459761922232595855712687383486560957333800991025057858697147318478732,
        240068136509177011915819753529256036608534142097626836653921964325513418447
    ];

    uint256[] memory res = new uint256[](arr.length);
    for (uint256 i = 0; i < arr.length; i++) {
        res[i] = arr[i];
    }

    return res;
}
