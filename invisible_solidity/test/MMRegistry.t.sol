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

        testRegisterNewMarkets();
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

    function testUpdatingTxBatch2() public {
        testRegisterMM();

        // =================================================

        bool isRegistered1 = invisibleL1.isAddressRegistered(
            3610252171009957135751225199721183378446742326108970414989791262578932735751
        );
        console.log("isRegistered: %s", isRegistered1);

        // =================================================
        uint256[] memory programOutput = getProgramOutput();

        invisibleL1.updateStateAfterTxBatch(programOutput);

        bool isRegistered2 = invisibleL1.isAddressRegistered(
            3610252171009957135751225199721183378446742326108970414989791262578932735751
        );
        console.log("isRegistered: %s", isRegistered2);
    }

    function testRegisterNewMarkets() public {
        uint32[] memory baseAssets = new uint32[](2);
        baseAssets[0] = 12345;
        baseAssets[1] = 54321;

        uint32[] memory quoteAssets = new uint32[](2);
        quoteAssets[0] = 55555;
        quoteAssets[1] = 55555;

        invisibleL1.registerNewMarkets(baseAssets, quoteAssets, baseAssets);
    }

    function testRegisterMM() public {
        vm.startPrank(address(8953626958234137847422389523978938749873));

        uint256 mmAddress = 3610252171009957135751225199721183378446742326108970414989791262578932735751;
        uint64 maxVlpSupply = 1000000 * 10 ** 6;

        uint32 baseAsset = 12345;
        uint32 quoteAsset = 55555;

        invisibleL1.approveMMRegistration(
            false,
            address(8953626958234137847422389523978938749873),
            mmAddress
        );

        invisibleL1.registerSpotMarketMaker(
            baseAsset,
            quoteAsset,
            mmAddress,
            maxVlpSupply
        );
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
    uint256[59] memory arr = [
        1681714975540286446064826179733025259025830596163312715622600677991254276136,
        1942169278408866985100966193432472349192882635042713816468080752951867678865,
        597580416694809001986,
        340282367000166625977638945029607129088,
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
        0,
        0,
        7878787,
        0,
        0,
        5656565,
        0,
        0,
        20703416456491290441237729280,
        3610252171009957135751225199721183378446742326108970414989791262578932735751,
        381910624860573789248581695129117664103119192065,
        9856732629625703539098952454285200176020062844859158785080014647278814545,
        2290920952232220448527736559373559381585407513725991428947467440279587605219,
        1361138075189787778177397299397205303297,
        25289090813440523962054569164799521261759807542017161434515644970743,
        2167668079050922025726930092564445435996017186294382461127463662289194574336,
        2504248300409688044280013972424585137451279189037418493421050935174055288734,
        3488528698316931683898207226290741495305671586547254558192171399990534171115,
        3610252171009957135751225199721183378446742326108970414989791262578932735751
    ];

    res = new uint256[](arr.length);
    for (uint256 i = 0; i < arr.length; i++) {
        res[i] = arr[i];
    }

    return res;
}
