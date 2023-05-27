use std::sync::Arc;

use invisible_backend::utils::{
    firestore::{create_session, start_delete_position_thread},
    storage::BackupStorage,
};
use parking_lot::Mutex;

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    //

    // 1684502386098572560865500250041581148646578677955444760400258625865572888023

    let backup = BackupStorage::new();
    let session = create_session();

    let handle = start_delete_position_thread(
        &Arc::new(Mutex::new(session)),
        &Arc::new(Mutex::new(backup)),
        "1684502386098572560865500250041581148646578677955444760400258625865572888023".to_string(),
        "1".to_string(),
    );

    handle.join().unwrap();

    Ok(())
}





// state tree: [22217562064919415645720771779791517643910475989309364334651704122073222196, 3394835667512580550907237285418943371380969074850047644490801525760422637375]
// pos2 : PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 27500, margin: 29999999975, entry_price: 1090909090, liquidation_price: 0, bankruptcy_price: 0, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 3394835667512580550907237285418943371380969074850047644490801525760422637375, index: 1 }
// Perpetual swap executed successfully in the backend engine


//  state tree: [1248196891688283047003753526749225239322198947586242154698557657348469090155, 1409961263007387335691293679407306332274707847427201567138607816914581667581]
// pos_: PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 1000000000, margin: 29999087501, entry_price: 1824979811, liquidation_price: 0, bankruptcy_price: 0, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 1409961263007387335691293679407306332274707847427201567138607816914581667581, index: 1 }

//  state tree: [1248196891688283047003753526749225239322198947586242154698557657348469090155, 1409961263007387335691293679407306332274707847427201567138607816914581667581]
// pos2 : PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 1000000000, margin: 1824999999, entry_price: 1824999998, liquidation_price: 3509615381, bankruptcy_price: 3649999997, allow_partial_liquidations: true, position_address: 2231630657657086781901359565951925022142325676190353267305456562683567895802, last_funding_idx: 0, hash: 1248196891688283047003753526749225239322198947586242154698557657348469090155, index: 0 }
// Perpetual swap executed successfully in the backend engine

// =================
// margin before: 1818616853
// margin after: 1622616853
// state before: [1156244909064316922886948362487677695224376545770021698171874639314427367798, 2985297819591067522934403239287795965649821576678758321047481498701701284068]
// new position hash: 1157202095815931800144151419881928485379609418707627524444698672464767439699
// position index: 0
// state after: [1157202095815931800144151419881928485379609418707627524444698672464767439699, 2985297819591067522934403239287795965649821576678758321047481498701701284068]
// Margin change response: true

//  state tree: [1157202095815931800144151419881928485379609418707627524444698672464767439699, 2985297819591067522934403239287795965649821576678758321047481498701701284068]
// pos2 : PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 7989900000, margin: 1622616853, entry_price: 1826217201, liquidation_price: 1951250673, bankruptcy_price: 2029300700, allow_partial_liquidations: true, position_address: 2231630657657086781901359565951925022142325676190353267305456562683567895802, last_funding_idx: 0, hash: 1157202095815931800144151419881928485379609418707627524444698672464767439699, index: 0 }

//  state tree: [1157202095815931800144151419881928485379609418707627524444698672464767439699, 2985297819591067522934403239287795965649821576678758321047481498701701284068]
// pos_: PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 7989900000, margin: 29999087501, entry_price: 1826214674, liquidation_price: 0, bankruptcy_price: 0, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 2985297819591067522934403239287795965649821576678758321047481498701701284068, index: 1 }
// Perpetual swap executed successfully in the backend engine


//  state tree: [0, 3042556850923743421511246193140339829638344844435660707320373922610709670611]
// pos_: PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 0, margin: 30015099140, entry_price: 1828218659, liquidation_price: 1000000000000000, bankruptcy_price: 1000000000000000, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 3042556850923743421511246193140339829638344844435660707320373922610709670611, index: 1 }
// Perpetual swap executed successfully in the backend engine


//  state tree: [284059255760693531946165206731573575448921809306630285161170790299519338032, 2033942421751128046986957020196554835867406875385339016247240746375516896723]
// pos_: PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 781067303, margin: 30015099140, entry_price: 1828548819, liquidation_price: 38708521406, bankruptcy_price: 40256862262, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 2033942421751128046986957020196554835867406875385339016247240746375516896723, index: 1 }
// Perpetual swap executed successfully in the backend engine


//  state tree: [1113120292236811322167308262678004021624257279664976582689911355076133601582, 2182953237627976546409332772814742827008811839208615212663978388419375038406]
// pos2 : PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 1000000000, margin: 588537342, entry_price: 1828515636, liquidation_price: 1291644057, bankruptcy_price: 1239978294, allow_partial_liquidations: true, position_address: 293210719561074849100019532881273931002006922526671719385635380011942391630, last_funding_idx: 0, hash: 1113120292236811322167308262678004021624257279664976582689911355076133601582, index: 0 }

//  state tree: [1113120292236811322167308262678004021624257279664976582689911355076133601582, 2182953237627976546409332772814742827008811839208615212663978388419375038406]
// pos_: PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 1000000000, margin: 30015099140, entry_price: 1828515963, liquidation_price: 30618860675, bankruptcy_price: 31843615103, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 2182953237627976546409332772814742827008811839208615212663978388419375038406, index: 1 }
// Perpetual swap executed successfully in the backend engine

// =================
// margin before: 585918253
// margin after: 1085918253
// state before: [3290583001742863312928690282306508060054878310821523653027160282561461191584, 1641052193613485563228986733901667280824468597663555290654197938492177669144]
// state after: [1972587183536352368724482488000556272418787901830738551512987531480708865287, 1641052193613485563228986733901667280824468597663555290654197938492177669144]
// Margin change response: true

//  state tree: [1972587183536352368724482488000556272418787901830738551512987531480708865287, 1641052193613485563228986733901667280824468597663555290654197938492177669144]
// pos_: PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 3864900000, margin: 30015099140, entry_price: 1828429076, liquidation_price: 9225483661, bankruptcy_price: 9594503008, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 1641052193613485563228986733901667280824468597663555290654197938492177669144, index: 1 }

//  state tree: [1972587183536352368724482488000556272418787901830738551512987531480708865287, 1641052193613485563228986733901667280824468597663555290654197938492177669144]
// pos2 : PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 3864900000, margin: 1085918253, entry_price: 1828428992, liquidation_price: 1611937178, bankruptcy_price: 1547459691, allow_partial_liquidations: true, position_address: 293210719561074849100019532881273931002006922526671719385635380011942391630, last_funding_idx: 0, hash: 1972587183536352368724482488000556272418787901830738551512987531480708865287, index: 0 }
// Perpetual swap executed successfully in the backend engine


//  state tree: [357220403309732167326166553420544240475986622036186558516097713868890244748, 2085644274237307252472822937073591399575697779338605470983826768697861536576]
// pos_: PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 2952653322, margin: 30016930837, entry_price: 1828429076, liquidation_price: 11533188627, bankruptcy_price: 11994516172, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 2085644274237307252472822937073591399575697779338605470983826768697861536576, index: 1 }

//  state tree: [357220403309732167326166553420544240475986622036186558516097713868890244748, 2085644274237307252472822937073591399575697779338605470983826768697861536576]
// pos_: PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 2952653322, margin: 1083253560, entry_price: 1828428992, liquidation_price: 1522452473, bankruptcy_price: 1461554374, allow_partial_liquidations: true, position_address: 293210719561074849100019532881273931002006922526671719385635380011942391630, last_funding_idx: 0, hash: 357220403309732167326166553420544240475986622036186558516097713868890244748, index: 0 }
// Perpetual swap executed successfully in the backend engine

// =================
// margin before: 1082646835
// margin after: 900646835
// state before: [1609014429859402918471740116337365966180234356630782666638845348070385996470, 2340233815350908137709776621907379726425080718768874761833319112527952257881]
// new position hash: 2111879101170447983885271261936484999656775240173198097866718895497316723655
// position index: 0
// state after: [2111879101170447983885271261936484999656775240173198097866718895497316723655, 2340233815350908137709776621907379726425080718768874761833319112527952257881]
// Margin change response: true

//  state tree: [2111879101170447983885271261936484999656775240173198097866718895497316723655, 2340233815350908137709776621907379726425080718768874761833319112527952257881]
// pos_: PerpPosition { order_side: Short, synthetic_token: 54321, collateral_token: 55555, position_size: 2733700000, margin: 30017337614, entry_price: 1828429076, liquidation_price: 12316258529, bankruptcy_price: 12808908870, allow_partial_liquidations: true, position_address: 1684502386098572560865500250041581148646578677955444760400258625865572888023, last_funding_idx: 0, hash: 2340233815350908137709776621907379726425080718768874761833319112527952257881, index: 1 }

//  state tree: [2111879101170447983885271261936484999656775240173198097866718895497316723655, 2340233815350908137709776621907379726425080718768874761833319112527952257881]
// pos_: PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 2733700000, margin: 1082646835, entry_price: 1828428992, liquidation_price: 1492074806, bankruptcy_price: 1432391814,
//  allow_partial_liquidations: true, position_address: 293210719561074849100019532881273931002006922526671719385635380011942391630, last_funding_idx: 0, hash: 1609014429859402918471740116337365966180234356630782666638845348070385996470, index: 0 }
// pos: PerpPosition { order_side: Long, synthetic_token: 54321, collateral_token: 55555, position_size: 2733700000, margin: 900646835, entry_price: 1828428992, liquidation_price: 1561425259, bankruptcy_price: 1498968249, 
    // allow_partial_liquidations: true, position_address: 293210719561074849100019532881273931002006922526671719385635380011942391630, last_funding_idx: 0, hash: 2111879101170447983885271261936484999656775240173198097866718895497316723655, index: 0 }
// Perpetual swap executed successfully in the backend engine
