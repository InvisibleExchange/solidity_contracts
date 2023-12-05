// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "forge-std/Vm.sol";

// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "src/TestToken.sol";
import "src/core/Interactions.sol";
import "src/core/EscapeVerifier.sol";
import "src/Invisible.sol";

import "src/libraries/StructHasher.sol";
import "src/interfaces/IStructHasher.sol";
import "src/interfaces/IPedersenHash.sol";

//

// import "src/interactions/Deposit.sol";

contract EscapeVerifierTest is Test {
    EscapeVerifier escapeVerifier;
    Invisible invisibleL1;
    StructHasher structHasher;
    TestToken testUsdc;
    TestToken testWbtc;

    uint256 constant EthStarkKey =
        2292025268456116477323356083246651802150462734710453904748677715907532488444;
    uint256 constant UsdcStarkKey =
        2166840471905619448909926965843998034165267473744647928190851627614183386065;

    address constant owner = address(8953626958234137847422389523978938749873);

    function setUp() public {
        vm.startPrank(owner);

        invisibleL1 = new Invisible();
        escapeVerifier = new EscapeVerifier();
        structHasher = new StructHasher();

        invisibleL1.initialize(owner);
        invisibleL1.setEscapeVerifier(address(escapeVerifier));

        escapeVerifier.initialize(owner);
        escapeVerifier.setInvisibleAddress(address(invisibleL1));

        escapeVerifier.setStructHasher(address(structHasher));

        testUsdc = new TestToken("testUsdc", "TT");
        // testUsdc.mint(owner, 5000 * 10 ** 18);
        testUsdc.mint(address(invisibleL1), 15000 * 10 ** 18);

        vm.deal(owner, 5 * 10 ** 18);
        vm.deal(address(invisibleL1), 15 * 10 ** 18);

        testRegisterToken();
    }

    function testRegisterToken() public {
        address tokenAddress = address(testUsdc);

        uint32 tokenId = 55555;
        invisibleL1.registerToken(tokenAddress, tokenId, 6);
    }

    function testNoteEscapes() public {
        Note[] memory notes;
        uint256[2] memory signature;
        (notes, signature) = getNoteEscapes();

        // vm.recordLogs();
        // Vm.Log[] memory entries = vm.getRecordedLogs();

        // Valid escape
        escapeVerifier.startNoteEscape(notes, signature, 2);

        // // Invalid escape
        // uint256[2] memory dummySig;
        // dummySig[0] = 0;
        // dummySig[1] = 0;
        // escapeVerifier.startNoteEscape(notes, dummySig, 1);
    }

    function testTabEscapes() public {
        OrderTab memory orderTab;
        uint256[2] memory signature;
        (orderTab, signature) = getTabEscapes();

        // Valid escape
        escapeVerifier.startOrderTabEscape(orderTab, signature, 11);

        // // Invalid escape
        // uint256[2] memory dummySig;
        // dummySig[0] = 0;
        // dummySig[1] = 0;
        // escapeVerifier.startOrderTabEscape(orderTab, dummySig, 12);
    }

    function testPositionEscapes() public {
        Position memory position_a;
        uint64 closePrice;
        OpenOrderFields memory openOrderFields_b;
        uint256[2] memory signature_a;
        uint256[2] memory signature_b;
        (
            position_a,
            closePrice,
            openOrderFields_b,
            signature_a,
            signature_b
        ) = getPositionEscape();

        // Valid escape
        escapeVerifier.startPositionEscape(
            position_a,
            closePrice,
            openOrderFields_b,
            signature_a,
            signature_b,
            128
        );

        // // Invalid escape
        // uint256[2] memory dummySig;
        // dummySig[0] = 0;
        // dummySig[1] = 0;
        // escapeVerifier.startPositionEscape(
        //     position_a,
        //     closePrice,
        //     openOrderFields_b,
        //     dummySig,
        //     dummySig,
        //     135
        // );
    }

    function testProcessBatch() public {
        // testPositionEscapes();

        testNoteEscapes();
        testTabEscapes();

        uint256[] memory arr = getProgramOutput2();

        invisibleL1.updateStateAfterTxBatch(arr);
    }

    function testEscapeWithdrawal() public {
        testProcessBatch();

        uint32 escapeId = 128;
        uint32 tokenId = 55555;

        console.log(
            "escapeAmount",
            escapeVerifier.s_escapeAmounts(escapeId, tokenId)
        );
        console.log(
            "successfulEscape",
            escapeVerifier.s_successfulEscapes(owner, escapeId)
        );
        console.log("successfulEscape", testUsdc.balanceOf(owner));

        escapeVerifier.withdrawForcedEscape(escapeId, tokenId);

        console.log(
            "\nescapeAmount after",
            escapeVerifier.s_escapeAmounts(escapeId, tokenId)
        );
        console.log(
            "successfulEscape after",
            escapeVerifier.s_successfulEscapes(owner, escapeId)
        );
        console.log("successfulEscape after", testUsdc.balanceOf(owner));
    }

    function testEscapeWithdrawal2() public {
        testProcessBatch();

        uint32 escapeId1 = 2;
        uint32 escapeId2 = 11;
        uint32 tokenId = 55555;
        uint32 tokenId2 = 54321;

        uint256 usdcBalBefore = testUsdc.balanceOf(address(invisibleL1));
        uint256 ethBalBefore = address(invisibleL1).balance;

        uint256 userUsdcBalBefore = testUsdc.balanceOf(owner);
        uint256 userEthBalBefore = owner.balance;

        escapeVerifier.withdrawForcedEscape(escapeId1, tokenId);
        escapeVerifier.withdrawForcedEscape(escapeId1, tokenId2);
        escapeVerifier.withdrawForcedEscape(escapeId2, tokenId);
        escapeVerifier.withdrawForcedEscape(escapeId2, tokenId2);

        uint256 usdcBalAfter = testUsdc.balanceOf(address(invisibleL1));
        uint256 ethBalAfter = address(invisibleL1).balance;

        uint256 userUsdcBalAfter = testUsdc.balanceOf(owner);
        uint256 userEthBalAfter = owner.balance;

        console.log("exchnage udsc delta ", usdcBalBefore - usdcBalAfter);
        console.log("exchnage eth delta ", ethBalBefore - ethBalAfter);
        console.log("user udsc delta ", userUsdcBalAfter - userUsdcBalBefore);
        console.log("user eth delta ", userEthBalAfter - userEthBalBefore);
    }
}

function getNoteEscapes()
    returns (Note[] memory notes, uint256[2] memory signature)
{
    notes = new Note[](2);

    notes[0] = Note(
        2,
        404195628429038392188208777949968973248122674610497347828958236477912896160,
        54321,
        100000000,
        267099241270533436751542004607467725098598013714151929202417715155313090803
    );
    notes[1] = Note(
        4,
        3555460070581968613174898250885756456206639550925936234900081415721610948181,
        55555,
        2000000000,
        2647343803609648239060205890773562780556225239840078433450021563841495818385
    );

    signature[
        0
    ] = 71218852872710562685948556608356987067604398663999840021704691522925938193;
    signature[
        1
    ] = 3312928004899280475275572939772407233356242663055849505912917278591783590297;
}

function getTabEscapes()
    returns (OrderTab memory orderTab, uint256[2] memory signature)
{
    orderTab = OrderTab(
        1,
        false,
        54321,
        55555,
        1506299164746246972807630085093885627889496031779636518987325331094514970909,
        3141641782898669383782770282059196445935874790589431572295052393080268261516,
        0,
        0,
        2656972640952053007590492392225463985200045050692828167171404173303799535149,
        100000000,
        2000000000,
        0
    );

    signature[
        0
    ] = 2059662861923825985307624166720394890620508623970283737300715245850278412005;
    signature[
        1
    ] = 3065615451086776348232224285225080735822068978619482185419787293220013243789;
}

function getPositionEscape()
    returns (
        Position memory position_a,
        uint64 closePrice,
        OpenOrderFields memory openOrderFields_b,
        uint256[2] memory signature_a,
        uint256[2] memory signature_b
    )
{
    position_a = Position(
        4,
        54321,
        3113660463485591058176034749662446744199622491875270729576957500309999901525,
        true,
        0,
        0,
        true,
        10000000,
        1999897500,
        2050000000,
        0,
        0,
        0,
        0
    );
    closePrice = 2050000000;

    Note[] memory notesIn = new Note[](2);
    notesIn[0] = Note(
        2,
        2207967086721787679515270206530804916408422883045111940920983890278196523945,
        55555,
        800000000,
        174568016950627946672405112124573552548388530886499109909432292811001004399
    );
    notesIn[1] = Note(
        1,
        1242672241837870290401213389203460597352553592046666588022209436288799492426,
        55555,
        1200000000,
        693311616868382840349832188270476326740589429789678786317593894902116608877
    );

    openOrderFields_b = OpenOrderFields(
        2000000000,
        55555,
        notesIn,
        Note(0, 0, 0, 0, 0),
        3113660463485591058176034749662446744199622491875270729576957500309999901525,
        true
    );

    signature_a = [
        2651819154866219199329708825311842448024917060827918357965091526530166682386,
        1836740464041228003945148257823321353116550100122108445651506149978680032576
    ];
    signature_b = [
        2143470646128778979261373597404820211414957594370359336163266730947408207744,
        3481279488422189619488402586022624027019365142695955553763098725577418910018
    ];
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
    uint256[85] memory arr = [
        2450644354998405982022115704618884006901283874365176806194200773707121413423,
        1477479647017246745902113942625728486274926676366053133907271462431119959473,
        597604491575640981504,
        5846006549323611672814739330920472310853448761344,
        237684487542793012780631851010,
        4839524406068408503119694702759214384341319683,
        12345,
        54321,
        55555,
        66666,
        12345,
        54321,
        66666,
        8,
        8,
        6,
        8,
        250,
        2500,
        50000,
        250000,
        6,
        6,
        6,
        50000000,
        500000000,
        350000000,
        150000,
        3000000,
        1500000,
        15000000,
        100000000,
        1000000000,
        9090909,
        7878787,
        5656565,
        874739451078007766457464989774322083649278607533249481151382481072868806602,
        3324833730090626974525872402899302150520188025637965566623476530814354734325,
        1839793652349538280924927302501143912227271479439798783640887258675143576352,
        296568192680735721663075531306405401515803196637037431012739700151231900092,
        9090909,
        1916955978945301341620395067648885526978986210947901045277915393320945744693,
        0,
        7878787,
        1536374069007233984544513184582763446994413226934374324309183509264711945525,
        0,
        5656565,
        0,
        0,
        2681012288826897986174311721013788427095758336,
        74901839598575695933198600747477116051910698073949569800895908963417866925,
        3093476031983839916840789305451873349190128640,
        2630218654585085177461306357329914251088104560233472914416495399589555053568,
        3093476031983839916840789305451873347990128640,
        12388412551322563046938301055460190568676903087755960114816012945396558209,
        3093476031983839916840789305451873348390128640,
        12388412551322563046938301055460190568676903087755960114816012945396558209,
        34560,
        816227615319284438340660495765833546330618534197173018518808756346610353951,
        3293483627263123063316656338064814625882420644164415338987616119720689526640,
        2999150648993495593882136590815773365883532250312798078797997680179691538406,
        3561195741880087369063329350652044250747117819311758034746673391222096895221,
        2940866901871978015751821018926679377740026981616539436128011541712024755452,
        2198797855668305952769,
        1453569843345417594979525465524174435057739828550332058810694205229325558992,
        2651819154866219199329708825311842448024917060827918357965091526530166682386,
        1836740464041228003945148257823321353116550100122108445651506149978680032576,
        2143470646128778979261373597404820211414957594370359336163266730947408207744,
        3481279488422189619488402586022624027019365142695955553763098725577418910018,
        18904488656604366991914239636993321082028032,
        2789208382745512472824365666070929850196696713493035170893709941556120634090,
        744961808157708231482903768766879719646159149052813110535796042797801728402,
        18904488656604549433660456156953644328026115,
        868956032582342156597685557982096725347388228236225672717882653375104209960,
        744961808157708231482903768766879719646159149052813110535796042797801728402,
        18904488656604362436288614319371692825116678,
        2237923086101874614042507548059951638123844445636264047729735425427020783169,
        744961808157708231482903768766879719646159149052813110535796042797801728402,
        31385588067163845271157159140027272705097623391735199563776,
        11984313426113403930531712584725170852943835908136822112257,
        984935119886124645086441620844852851238293707965663463054997145584753410360,
        43939791537937206798828737986442605537302334280663268589568,
        11984313426113403929270215628273520761178646852403200000003,
        3113660463485591058176034749662446744199622491875270729576957500309999901525,
        340282366920938463500268095579187314692
    ];

    res = new uint256[](arr.length);
    for (uint256 i = 0; i < arr.length; i++) {
        res[i] = arr[i];
    }

    return res;
}

function getProgramOutput2() pure returns (uint256[] memory res) {
    uint256[74] memory arr = [
        1477479647017246745902113942625728486274926676366053133907271462431119959473,
        1477479647017246745902113942625728486274926676366053133907271462431119959473,
        597604836714917920769,
        5846006549323611672814739330865132078623730171904,
        237684487579686500936640888832,
        4839524406068408503119694702759214384341319683,
        12345,
        54321,
        55555,
        66666,
        12345,
        54321,
        66666,
        8,
        8,
        6,
        8,
        250,
        2500,
        50000,
        250000,
        6,
        6,
        6,
        50000000,
        500000000,
        350000000,
        150000,
        3000000,
        1500000,
        15000000,
        100000000,
        1000000000,
        9090909,
        7878787,
        5656565,
        874739451078007766457464989774322083649278607533249481151382481072868806602,
        3324833730090626974525872402899302150520188025637965566623476530814354734325,
        1839793652349538280924927302501143912227271479439798783640887258675143576352,
        296568192680735721663075531306405401515803196637037431012739700151231900092,
        9090909,
        1384184243467829103459057795077699966494146250334031582869785281675311809205,
        0,
        7878787,
        0,
        0,
        5656565,
        0,
        0,
        3093476031983839916840789305451873349190128640,
        605032940248148603226818117499285003015866267782214362325633837150586080673,
        3093476031983839916840766542169686389703434496,
        346227976992452892649865346377387200102523200360340159260261220761824009441,
        3093476031983839916840789305451873349190128640,
        1144106206871706778375321326690338349315613075659839363014266530016811517342,
        3093476031983839916840766542169686389703434496,
        3355421662757205439159457587087020577167741707913178860940872600581754893083,
        65536,
        394058465685679731058653150948393046660244084198846383263290060203961576965,
        0,
        0,
        131328,
        2459159232680021945321534902198820090984542568261038574749656678105742502576,
        71218852872710562685948556608356987067604398663999840021704691522925938193,
        3312928004899280475275572939772407233356242663055849505912917278591783590297,
        655361,
        105982949478042635395815802523683267751994373235322492192728410177470893461,
        0,
        0,
        721153,
        2278212098280562982903168565182196225865280053127025380531754145270673423516,
        2059662861923825985307624166720394890620508623970283737300715245850278412005,
        3065615451086776348232224285225080735822068978619482185419787293220013243789,
        340282366920938463500268095579187314692
    ];

    res = new uint256[](arr.length);
    for (uint256 i = 0; i < arr.length; i++) {
        res[i] = arr[i];
    }

    return res;
}
