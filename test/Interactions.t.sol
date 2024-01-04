// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.22;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "forge-std/Vm.sol";

// // import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// import "src/TestToken.sol";
// import "src/core/Interactions.sol";
// import "src/Invisible.sol";

// //

// // import "src/interactions/Deposit.sol";

// contract InteractionsTest is Test {
//     Invisible invisibleL1;
//     TestToken testUsdc;
//     TestToken testWbtc;

//     uint256 constant EthStarkKey =
//         2292025268456116477323356083246651802150462734710453904748677715907532488444;
//     uint256 constant UsdcStarkKey =
//         2166840471905619448909926965843998034165267473744647928190851627614183386065;

//     address constant owner = address(8953626958234137847422389523978938749873);

//     function setUp() public {
//         vm.startPrank(address(8953626958234137847422389523978938749873));

//         invisibleL1 = new Invisible();
//         invisibleL1.initialize(
//             address(8953626958234137847422389523978938749873)
//         );

//         testUsdc = new TestToken("testUsdc", "TT");

//         testUsdc.mint(
//             address(8953626958234137847422389523978938749873),
//             5000 * 10 ** 18
//         );

//         vm.deal(
//             address(8953626958234137847422389523978938749873),
//             5 * 10 ** 18
//         );

//         testRegisterToken();
//     }

//     function testKeccak() public {
//         uint256[5] memory arr = [
//             uint256(1),
//             uint256(2),
//             uint256(3),
//             uint256(4),
//             uint256(5)
//         ];

//         bytes memory data = abi.encodePacked(
//             uint256(1),
//             uint256(2),
//             uint256(3),
//             uint256(4),
//             uint256(5)
//         );

//         bytes32 hash = keccak256(data);

//         console.log("hash: ", uint256(hash));
//     }

//     function testRegisterToken() public {
//         address tokenAddress = address(testUsdc);

//         uint32 tokenId = 2413654107;
//         invisibleL1.registerToken(tokenAddress, tokenId, 6);
//     }

//     function testErc20Deposit() public {
//         address tokenAddress = address(testUsdc);

//         // ? Approve tokens to be spent by the contract
//         testUsdc.approve(address(invisibleL1), 2000 * 10 ** 18);
//         vm.recordLogs();
//         uint64 newAmountDeposited = invisibleL1.makeDeposit(
//             tokenAddress,
//             2000 * 10 ** 18,
//             UsdcStarkKey
//         );

//         // interactions.startCancelDeposit(tokenAddress, UsdcStarkKey);
//     }

//     function testEthDeposit() public {
//         address tokenAddress = address(testUsdc);

//         vm.recordLogs();
//         uint64 newAmountDeposited = invisibleL1.makeDeposit{value: 2 ether}(
//             address(0),
//             2 ether,
//             EthStarkKey
//         );

//         // Vm.Log[] memory entries = vm.getRecordedLogs();
//         // bytes32[] memory b_arr = bytesToBytes32Array(entries[0].data);
//         // console.log("entries: ", uint256(b_arr[0]));
//         // console.log("entries: ", uint256(b_arr[1]));
//         // console.log("entries: ", uint256(b_arr[2]));
//         // console.log("entries: ", uint256(b_arr[3]));
//         // console.log("entries: ", uint256(b_arr[4]));

//         // console.log("newAmountDeposited: ", newAmountDeposited);

//         // uint256 pendingDeposit = invisibleL1.getPendingDepositAmount(
//         //     EthStarkKey,
//         //     address(0)
//         // );
//         // console.log("pendingDeposit: ", pendingDeposit);

//         // interactions.startCancelDeposit(tokenAddress, EthStarkKey);
//     }

//     function testDeposits() public {
//         testErc20Deposit();
//         testEthDeposit();
//     }

//     function testUpdatingTxBatch() public {
//         // testDeposits();

//         // address tokenAddress = address(testUsdc);

//         // uint256 pendingErcDeposit = invisibleL1.getPendingDepositAmount(
//         //     UsdcStarkKey,
//         //     tokenAddress
//         // );
//         // uint256 pendingEthDeposit = invisibleL1.getPendingDepositAmount(
//         //     EthStarkKey,
//         //     address(0)
//         // );

//         // assert(pendingErcDeposit == 2000 ether);
//         // assert(pendingEthDeposit == 2 ether);

//         // =================================================
//         uint256[] memory programOutput = getProgramOutput();

//         invisibleL1.updateStateAfterTxBatch(programOutput);

//         // address recipient = address(
//         //     uint160(649643524963080317271811968397224848924325242593)
//         // );
//         // uint256 pendingErcDeposit2 = invisibleL1.getPendingDepositAmount(
//         //     UsdcStarkKey,
//         //     tokenAddress
//         // );
//         // uint256 pendingEthDeposit2 = invisibleL1.getPendingDepositAmount(
//         //     EthStarkKey,
//         //     address(0)
//         // );

//         // assert(pendingErcDeposit2 == 0);
//         // assert(pendingEthDeposit2 == 0);
//     }

//     function testEncode() public {
//         bytes memory res = abi.encode(123, 456);

//         // bytes32[] memory b_arr = bytesToBytes32Array(res);
//         // console.log("res: ", uint256(b_arr[0]));
//         // console.log("res: ", uint256(b_arr[1]));

//         uint256 hashRes = uint256(keccak256(res));

//         console.log("hashRes: ", hashRes);
//     }
// }

// function bytesToBytes32Array(
//     bytes memory data
// ) pure returns (bytes32[] memory) {
//     // Find 32 bytes segments nb
//     uint256 dataNb = data.length / 32;
//     // Create an array of dataNb elements
//     bytes32[] memory dataList = new bytes32[](dataNb);
//     // Start array index at 0
//     uint256 index = 0;
//     // Loop all 32 bytes segments
//     for (uint256 i = 32; i <= data.length; i = i + 32) {
//         bytes32 temp;
//         // Get 32 bytes from data
//         assembly {
//             temp := mload(add(data, i))
//         }
//         // Add extracted 32 bytes to list
//         dataList[index] = temp;
//         index++;
//     }
//     // Return data list
//     return (dataList);
// }

// function getProgramOutput() pure returns (uint256[] memory res) {
//     uint256[104] memory arr = [
//         2450644354998405982022115704618884006901283874365176806194200773707121413423,
//         1779053205173089949966258235816545733462515880944861419991711009032113449712,
//         597612279996321103872,
//         18999565886792134998211121516561875277242016202752,
//         210258926710712570525957419222609112870661182717955,
//         3592681469,
//         453755560,
//         2413654107,
//         277158171,
//         3592681469,
//         453755560,
//         277158171,
//         8,
//         8,
//         6,
//         8,
//         250,
//         2500,
//         50000,
//         250000,
//         6,
//         6,
//         6,
//         50000000,
//         500000000,
//         350000000,
//         150000,
//         3000000,
//         1500000,
//         15000000,
//         100000000,
//         1000000000,
//         9090909,
//         7878787,
//         5656565,
//         874739451078007766457464989774322083649278607533249481151382481072868806602,
//         3324833730090626974525872402899302150520188025637965566623476530814354734325,
//         1839793652349538280924927302501143912227271479439798783640887258675143576352,
//         296568192680735721663075531306405401515803196637037431012739700151231900092,
//         9090909,
//         3170973507823588981294900020459345950039794773821756218581266678231594905084,
//         3372463785465611580789515646825511322259587015591807679327175773993875163942,
//         7878787,
//         0,
//         0,
//         5656565,
//         0,
//         0,
//         3093476031982862012000163619208700170948089472,
//         3225200283062039681311450510140452982672304159186741365074365564954203911314,
//         3093476031982862091228326133473037764492039808,
//         3225200283062039681311450510140452982672304159186741365074365564954203911314,
//         3093476031982862566597301219059063325845741824,
//         3225200283062039681311450510140452982672304159186741365074365564954203911314,
//         3093476031982862681979210640267612031609594112,
//         1669987464367741806901581703315727722326801619559351826421346426798401265671,
//         3093476031982862761207373154531949625153544448,
//         1669987464367741806901581703315727722326801619559351826421346426798401265671,
//         3093476031982862919663698183060624813141445120,
//         1669987464367741806901581703315727722326801619559351826421346426798401265671,
//         3093476031982863099869239214304206195344662784,
//         95386976468426923783346594028622962171518585924647255192876045839129024801,
//         3093476031982863236576348240117975186617246464,
//         1669987464367741806901581703315727722326801619559351826421346426798401265671,
//         3093476031982863315804510754382312780161196800,
//         1669987464367741806901581703315727722326801619559351826421346426798401265671,
//         3093476031982863416781889271361556569550464128,
//         95386976468426923783346594028622962171518585924647255192876045839129024801,
//         3093476031982863474260835782910987967699097472,
//         1669987464367741806901581703315727722326801619559351826421346426798401265671,
//         3093476031982863553488998297175325562493047808,
//         2642092749689377153080241311842925827947262820199074023775737174772744537106,
//         3093476031982863675791576418759789635411046528,
//         2162198863156996455528967238530366062883894408942065426562205807698555167858,
//         3093476031982863654466376814154569350152315136,
//         3048139959120501548941345689443309692590230772914574746929841975115612192513,
//         3093476031982863791173485839968338341224898816,
//         2642092749689377153080241311842925827947262820199074023775737174772744537106,
//         3093476031982863870401648354232675935668849152,
//         2642092749689377153080241311842925827947262820199074023775737174772744537106,
//         3093476031982863949629810868497013529212799488,
//         2642092749689377153080241311842925827947262820199074023775737174772744537106,
//         3093476031982864028857973382761351121856749824,
//         2642092749689377153080241311842925827947262820199074023775737174772744537106,
//         3093476031982864108086135897025688715400700160,
//         2642092749689377153080241311842925827947262820199074023775737174772744537106,
//         720256060178447889295157023191982336,
//         1168271400774823843371169417094491223346955826025,
//         720256060178447889295157023191982336,
//         1168271400774823843371169417094491223346955826025,
//         720256060178447889295157023109282336,
//         1168271400774823843371169417094491223346955826025,
//         720256060178447889295157023101982336,
//         1168271400774823843371169417094491223346955826025,
//         720256060178447889295157023141982336,
//         1168271400774823843371169417094491223346955826025,
//         720256060178447889295157023141982336,
//         1168271400774823843371169417094491223346955826025,
//         720256060178447889295157023141982336,
//         1168271400774823843371169417094491223346955826025,
//         720256081927663892010063219157299328,
//         1168271400774823843371169417094491223346955826025,
//         720256024024700982350945910892080384,
//         1168271400774823843371169417094491223346955826025
//     ];

//     res = new uint256[](arr.length);
//     for (uint256 i = 0; i < arr.length; i++) {
//         res[i] = arr[i];
//     }

//     return res;
// }
