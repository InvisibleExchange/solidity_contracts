%builtins output pedersen range_check ecdsa

from starkware.cairo.common.cairo_builtins import HashBuiltin, SignatureBuiltin
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.hash import hash2
from starkware.cairo.common.registers import get_fp_and_pc
from starkware.cairo.common.dict import dict_new, dict_write, dict_update, dict_squash
from starkware.cairo.common.dict_access import DictAccess
from starkware.cairo.common.ec import ec_add
from starkware.cairo.common.signature import verify_ecdsa_signature
from starkware.cairo.common.ec_point import EcPoint
from starkware.cairo.common.merkle_multi_update import merkle_multi_update
from starkware.cairo.common.uint256 import Uint256
from starkware.cairo.common.hash_state import (
    hash_init,
    hash_finalize,
    hash_update,
    hash_update_single,
)

const CURVE_ALPHA = 1;
const CURVE_BETA = 0x6f21413efbe40de150e596d72f7a8c5609ad26c15c915c1f4cdfcb99cee9e89;

func main{output_ptr, pedersen_ptr: HashBuiltin*, range_check_ptr, ecdsa_ptr: SignatureBuiltin*}() {
    alloc_locals;

    let p1: EcPoint = EcPoint(
        x=874739451078007766457464989774322083649278607533249481151382481072868806602,
        y=152666792071518830868575557812948353041420400780739481342941381225525861407,
    );
    let p2: EcPoint = EcPoint(
        x=3324833730090626974525872402899302150520188025637965566623476530814354734325,
        y=3147007486456030910661996439995670279305852583596209647900952752170983517249,
    );

    let p1_new: EcPoint = EcPoint(
        x=874739451078007766457464989774322083649278607533249481151382481072868806602,
        y=2019986263031222785962853459147043596451554493288928645915240243787718625390,
    );

    assert_on_curve(p1);

    // verify_ecdsa_signature(
    //     message=1234,
    //     public_key=p3.x,
    //     signature_r=2025343413376321494602191974019293925947609136906997937578124455889402646333,
    //     signature_s=1759666001440452222859085476391482068746159906863342159929368891538851883922,
    // )

    return ();
}

func assert_on_curve(p: EcPoint) {
    // Because the curve order is odd, there is no point (except (0, 0), which represents the point
    // at infinity) with y = 0.
    if (p.y == 0) {
        assert p.x = 0;
        return ();
    }
    tempvar rhs = (p.x * p.x + CURVE_ALPHA) * p.x + CURVE_BETA;
    %{ print("rhs: " , ids.rhs) %}

    assert p.y * p.y = rhs;
    return ();
}
