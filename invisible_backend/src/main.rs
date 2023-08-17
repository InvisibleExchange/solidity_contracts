use invisible_backend::utils::cairo_output::parse_cairo_output;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let output = vec![
        "809462073105307194568174908831137243225467841397696340230018464868208458923",
        "-1368601406475461696042510434695152656225836987778616560801060915033600417202",
        "47343875582106985482326929951097633274529727907026",
        "2923003274661805836961966803069309890618386808833",
        "4839525086633142265768459096797347580624240643",
        "4200785819638985332457405113573155123812611",
        "227725055589944414753841",
        "3062541302288446171336392163549299867654",
        "850705917302346159119605120422159319090000",
        "110680464442257309702",
        "922337203685477581300000000",
        "51042355038140769574846423335893886567900000",
        "15000000",
        "3093476031982861766090701356473198376492879861",
        "874739451078007766457464989774322083649278607533249481151382481072868806602",
        "-293669058575504239171450380195767955102919189693631133349615525321517286156",
        "-1778709136316592932772395480593926193395835735891797916332204797460728444129",
        "296568192680735721663075531306405401515803196637037431012739700151231900092",
        "9090909",
        "-1753358767859572410611515585931006220593502354773990967283812246693405533276",
        "0",
        "7878787",
        "0",
        "0",
        "5656565",
        "0",
        "0",
        "3093476031983839916840789305451873497190128640",
        "-177331404620015310851975491018035141725863651076706787145747726336649488080",
        "3093476031983839916839992221640448363464801280",
        "1781680244087554366832788416412381161256137382830776789312042489557606934118",
        "18904442314288113493001772276035176802287616",
        "-983652385802901076821227278181204597179955011089424386667882052323910263073",
        "-1174899896738903036029035642936122198392451315804469906207800907598066111653",
        "18904627373871817345458946846496130953379841",
        "-378133945149157086789123165549310737142841717099277621374812729540242808240",
        "224963859903117103870317922590516013819333744400665472090160618163386726897",
        "18904472420352245514712676384723377101733890",
        "1458074355722769701340051700979396865277337095387087218765913710848597907734",
        "-643797768152988419097931793795965797788641471751641114394484359286673486758",
        "4200869274379989838169724760993234377768965",
        "692094535093204409369461170302616420868281205268632476143178381165306453248",
        "574186873028250617021342983084740637408850321488926356688246687511517829671",
        "18904433035839827655050530358743722495049734",
        "-1552159266985673964942824107430130037530342850245205019302198959768139563828",
        "1489645825998796912367754156144843107217956291817609069432297363566702176425",
        "18904679075710087160694765861707570575573002",
        "896016856997122891626033938172768775106489173622675876233640186130944116905",
        "859929205627068363494222092431919185513491410689035114813574608750482925310",
        "4200847747770700186439880478721023259181067",
        "-38335161387921724064904387936989751607886460758144068485016618709450450847",
        "205013182326565388736535847245719340112629735288533895594383592724633156657",
        "36346092933933036542317243039547393",
        "2308420265154110881552827842408988278784",
        "-1399650829940553815026288744308213113769111367768665950288597531717172851547",
        "41538389792467864170847739368767745",
        "2308420265154110875354491125806372225024",
        "-1563786254596458974364326810376704140067207348130182560928432452363624578736",
        "75325292993591096184389126854667472303575790411969366652236",
        "948888522792902503954517531791946303208432119048954446284171173915037404277",
        "683339387779852063148511713376838541206819197955846204978302997241640762799",
        "-518096491600404316808235574659721165607065944555320394409867667053140637693",
        "9",
    ];

    let program_output = parse_cairo_output(output);

    println!("{:#?}", program_output);

    Ok(())
}




