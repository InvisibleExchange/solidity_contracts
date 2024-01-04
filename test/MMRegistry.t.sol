// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.22;

// import "forge-std/Test.sol";
// import "forge-std/console.sol";
// import "forge-std/Vm.sol";

// // import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
// import "src/TestToken.sol";
// import "src/core/Interactions.sol";
// import "src/Invisible.sol";

// import "../src/storage/MMRegistryStorage.sol";

// //

// // import "src/interactions/Deposit.sol";

// contract MMRegistryTest is Test {
//     Invisible invisibleL1;
//     TestToken testUsdc;
//     TestToken testWbtc;

//     uint256 constant EthStarkKey =
//         2292025268456116477323356083246651802150462734710453904748677715907532488444;
//     uint256 constant UsdcStarkKey =
//         2166840471905619448909926965843998034165267473744647928190851627614183386065;

//     address constant owner = address(8953626958234137847422389523978938749873);
//     address constant depositor =
//         address(61872278164781256322784325782984327823785);

//     function setUp() public {
//         vm.startPrank(owner);

//         invisibleL1 = new Invisible();

//         invisibleL1.initialize(owner);

//         testUsdc = new TestToken("testUsdc", "TT");
//         // testUsdc.mint(owner, 5000 * 10 ** 18);
//         testUsdc.mint(address(invisibleL1), 15000 * 10 ** 18);
//         testUsdc.mint(depositor, 10000 * 10 ** 18);

//         vm.deal(owner, 5 * 10 ** 18);
//         vm.deal(address(invisibleL1), 15 * 10 ** 18);
//         vm.deal(depositor, 1 * 10 ** 18);

//         testRegisterToken();

//         testRegisterMM();
//     }

//     function testRegisterToken() public {
//         address tokenAddress = address(testUsdc);

//         uint32 tokenId = 2413654107;
//         invisibleL1.registerToken(tokenAddress, tokenId, 6);

//         uint32[] memory syntheticTokens = new uint32[](2);
//         syntheticTokens[0] = 3592681469;
//         syntheticTokens[1] = 453755560;
//         invisibleL1.registerNewMarkets(syntheticTokens);
//     }

//     function testRegisterMM() public {
//         uint256 mmAddress = 2555939808869746381652107679103753944317105711864612294672051588088957237575;
//         uint64 maxVlpSupply = 1000000000000;
//         uint32 syntheticAsset = 3592681469;

//         invisibleL1.approveMMRegistration(owner, mmAddress);

//         vm.recordLogs();
//         invisibleL1.registerPerpMarketMaker(
//             syntheticAsset,
//             mmAddress,
//             maxVlpSupply
//         );
//         Vm.Log[] memory entries = vm.getRecordedLogs();

//         // for (uint i = 0; i < entries[0].topics.length; i++) {
//         //     console.log(uint256(entries[0].topics[i]));
//         // }
//     }

//     function testAddLiquidity() public {
//         vm.startPrank(depositor);

//         uint256 mmAddress = 2555939808869746381652107679103753944317105711864612294672051588088957237575;
//         uint32 syntheticAsset = 3592681469;

//         vm.recordLogs();
//         testUsdc.approve(address(invisibleL1), 2000 * 10 ** 18);
//         invisibleL1.provideLiquidity(
//             syntheticAsset,
//             mmAddress,
//             2000 * 10 ** 18
//         );
//         Vm.Log[] memory entries = vm.getRecordedLogs();

//         // for (uint i = 0; i < entries[0].topics.length; i++) {
//         //     console.log(uint256(entries[0].topics[i]));
//         // }
//     }

//     function testCancelAddLiquidity() public {
//         vm.startPrank(owner);
//         testUsdc.mint(
//             address(111111111111111111111111111111111),
//             10000 * 10 ** 18
//         );

//         vm.startPrank(address(111111111111111111111111111111111));

//         uint256 mmAddress = 2555939808869746381652107679103753944317105711864612294672051588088957237575;
//         uint32 syntheticAsset = 3592681469;

//         testUsdc.approve(address(invisibleL1), 4000 * 10 ** 18);
//         invisibleL1.provideLiquidity(
//             syntheticAsset,
//             mmAddress,
//             2000 * 10 ** 18
//         );
//         invisibleL1.provideLiquidity(
//             syntheticAsset,
//             mmAddress,
//             2000 * 10 ** 18
//         );

//         invisibleL1.tryCancelAddLiquidity(mmAddress);
//     }

//     function testRemoveLiquidity() public {
//         vm.startPrank(depositor);

//         uint256 mmAddress = 2555939808869746381652107679103753944317105711864612294672051588088957237575;
//         uint32 syntheticAsset = 3592681469;

//         vm.recordLogs();
//         invisibleL1.removeLiquidity(syntheticAsset, mmAddress);
//         Vm.Log[] memory entries = vm.getRecordedLogs();

//         // for (uint i = 0; i < entries[0].topics.length; i++) {
//         //     console.log(uint256(entries[0].topics[i]));
//         // }
//     }

//     function testCloseMM() public {
//         vm.startPrank(owner);

//         uint256 mmAddress = 2555939808869746381652107679103753944317105711864612294672051588088957237575;

//         vm.recordLogs();
//         invisibleL1.closePerpMarketMaker(mmAddress);
//         Vm.Log[] memory entries = vm.getRecordedLogs();

//         // for (uint i = 0; i < entries[0].topics.length; i++) {
//         //     console.log(uint256(entries[0].topics[i]));
//         // }
//     }

//     function testMMRegiterUpdateBatch() public {
//         // =================================================

//         bool isRegistered1 = invisibleL1.isAddressRegistered(
//             2555939808869746381652107679103753944317105711864612294672051588088957237575
//         );
//         console.log("isRegistered: %s", isRegistered1);

//         // =================================================
//         uint256[] memory programOutput = getProgramOutput();

//         vm.startPrank(owner);
//         invisibleL1.updateStateAfterTxBatch(programOutput);

//         bool isRegistered2 = invisibleL1.isAddressRegistered(
//             2555939808869746381652107679103753944317105711864612294672051588088957237575
//         );
//         console.log("isRegistered: %s", isRegistered2);
//     }

//     function testMMRegiterUpdateBatch2() public {
//         testMMRegiterUpdateBatch();

//         // =================================================
//         testAddLiquidity();
//         testAddLiquidity();
//         testAddLiquidity();

//         testCancelAddLiquidity();

//         // =================================================
//         uint256[] memory programOutput = getProgramOutput();

//         vm.startPrank(owner);
//         // invisibleL1.updateStateAfterTxBatch2(programOutput);
//     }

//     function testMMRegiterUpdateBatch3() public {
//         testMMRegiterUpdateBatch2();

//         // =================================================
//         testRemoveLiquidity();
//         testRemoveLiquidity();

//         (uint64 initialValue, uint64 vlpAmount) = invisibleL1.s_activeLiqudity(
//             depositor,
//             2555939808869746381652107679103753944317105711864612294672051588088957237575
//         );
//         console.log("-->vlpAmount: %s", vlpAmount);

//         // =================================================
//         uint256[] memory programOutput = getProgramOutput();

//         // invisibleL1.updateStateAfterTxBatch3(programOutput);

//         (uint64 initialValue2, uint64 vlpAmount2) = invisibleL1
//             .s_activeLiqudity(
//                 depositor,
//                 2555939808869746381652107679103753944317105711864612294672051588088957237575
//             );
//         console.log("vlpAmount: %s", vlpAmount2);
//     }

//     function testMMRegiterUpdateBatch4() public {
//         testMMRegiterUpdateBatch3();

//         // =================================================
//         testCloseMM();

//         (uint64 vlpAmountSum, uint64 returnCollateral) = invisibleL1
//             .s_closedPositionLiqudity(
//                 2555939808869746381652107679103753944317105711864612294672051588088957237575
//             );
//         console.log("-->returnCollateral: %s", returnCollateral);

//         // =================================================
//         uint256[] memory programOutput = getProgramOutput();

//         // invisibleL1.updateStateAfterTxBatch4(programOutput);

//         (uint64 vlpAmountSum2, uint64 returnCollateral2) = invisibleL1
//             .s_closedPositionLiqudity(
//                 2555939808869746381652107679103753944317105711864612294672051588088957237575
//             );
//         console.log("-->returnCollateral: %s", returnCollateral2);

//         testRemoveLiquidity();

//         uint256 pendingWithdrawal = invisibleL1.s_pendingWithdrawals(depositor);
//         console.log("-->pendingWithdrawal: %s", pendingWithdrawal);

//         vm.startPrank(depositor);
//         invisibleL1.withdrawalLiquidity();

//         uint256 pendingWithdrawal2 = invisibleL1.s_pendingWithdrawals(
//             depositor
//         );
//         console.log("-->pendingWithdrawal2: %s", pendingWithdrawal2);
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
//     uint256[86] memory arr = [
//         2450644354998405982022115704618884006901283874365176806194200773707121413423,
//         3142695053653597095586708733570803848021265084277238215438641777587575625287,
//         597606316000438910976,
//         2923047876152202897812111479749281210805151334400,
//         4839524406068408503119694702759214384341319683,
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
//         1166260320567678569074286927415518331832071223798029965790371363666066427203,
//         0,
//         7878787,
//         985387061409897285031411378697247401257340098622853134207444831726099316521,
//         0,
//         5656565,
//         0,
//         0,
//         2681012288826897986174311721013788427095758336,
//         1155560327560595810277547796632773459017238673296569489024397323316334105299,
//         3093476031983839916840789305451873367190128640,
//         1959539234350891128453293007249544042004006583703848438236600344801093982078,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         0,
//         1182897730672094755697375576558587019100422400,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         61872278164781256322784325782984327823785,
//         9444732965739290427904000000001,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         61872278164781256322784325782984327823785,
//         174224571863520493302692531970804614693376000000002,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         61872278164781256322784325782984327823785,
//         9444732965739290427904000000001,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         61872278164781256322784325782984327823785,
//         174224571863520493302692531970804614693376000000002,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         61872278164781256322784325782984327823785,
//         9444732965739290427904000000001,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         0,
//         174224571863520493302692531970804614693376000000003,
//         18904435007848367023936622422249802341285890,
//         2420567746039753872347707779858556187693979327293525121346425299860792850911,
//         885386392038643549624427689518434212767149919132657342127470828943773935401,
//         18904435007848598848320947164437737461776389,
//         2363656273888911179077967994623956970132158940719838918180884037242340125903,
//         885386392038643549624427689518434212767149919132657342127470828943773935401,
//         18831384596390483743485184152799368555499912079055450551563,
//         13562735194430779080930195247607106422407053998817280000003,
//         2555939808869746381652107679103753944317105711864612294672051588088957237575,
//         25108486331777164507320973576007034967307300227519485050880,
//         13738115390910487432560743694746788568019920645985952333825,
//         1571518249481932923260906299462758204245944960281784438868661894750375958570,
//         1
//     ];

//     res = new uint256[](arr.length);
//     for (uint256 i = 0; i < arr.length; i++) {
//         res[i] = arr[i];
//     }

//     return res;
// }
