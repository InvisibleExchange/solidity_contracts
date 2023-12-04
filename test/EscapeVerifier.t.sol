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
        testUsdc.mint(owner, 5000 * 10 ** 18);

        vm.deal(owner, 5 * 10 ** 18);

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

        // Invalid escape
        uint256[2] memory dummySig;
        dummySig[0] = 0;
        dummySig[1] = 0;
        escapeVerifier.startNoteEscape(notes, dummySig, 1);
    }

    function testTabEscapes() public {
        OrderTab memory orderTab;
        uint256[2] memory signature;
        (orderTab, signature) = getTabEscapes();

        // Valid escape
        escapeVerifier.startOrderTabEscape(orderTab, signature, 11);

        // Invalid escape
        uint256[2] memory dummySig;
        dummySig[0] = 0;
        dummySig[1] = 0;
        escapeVerifier.startOrderTabEscape(orderTab, dummySig, 12);
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
        testPositionEscapes();

        uint256[] memory arr = getProgramOutput();

        invisibleL1.updateStateAfterTxBatch(arr);
    }
}

function getNoteEscapes()
    returns (Note[] memory notes, uint256[2] memory signature)
{
    notes = new Note[](2);

    notes[0] = Note(
        4,
        1566649712665696531788041517182951585822871732316111647199855847902683588922,
        54321,
        100000000,
        3077944611448657135417618404032464794885121022945641600596482300654575716231
    );
    notes[1] = Note(
        2,
        2308714436020853974060851796422740060650374107781040578195850229297286767214,
        55555,
        2000000000,
        1942578072023419285550860063766381096823539324610824321940965229908364081309
    );

    signature[
        0
    ] = 2861535764498299283870654044280045782816540908919423994923068738223180046309;
    signature[
        1
    ] = 288356048781751418183996651126403732399405042351973422504188385278111294405;
}

function getTabEscapes()
    returns (OrderTab memory orderTab, uint256[2] memory signature)
{
    orderTab = OrderTab(
        5,
        false,
        54321,
        55555,
        2000660698553400490147504740372837209093413281195576032906054274807429670977,
        1729569490107074610318404565916036019883355374308326012519540800891046909686,
        0,
        0,
        776399882889269650293515514341602162847486819293749570082701017732057556930,
        100000000,
        2000000000,
        0
    );

    signature[
        0
    ] = 3565496895177901663471971135972802006453968348112690703457963586442270598103;
    signature[
        1
    ] = 3231114911266323906490916427266703583537258402440179137373440868283042129464;
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
