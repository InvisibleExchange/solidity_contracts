from typing import Tuple
import os
import json
import time

from math_utils import ec_add, ec_neg, ec_mult, is_quad_residue, sqrt_mod, pi_as_string, ECPoint


ECPoint = Tuple[int, int]


N_ELEMENT_BITS_HASH = 252

PEDERSEN_HASH_POINT_FILENAME = os.path.join(
    os.path.dirname(__file__), 'pedersen_params.json')
PEDERSEN_PARAMS = json.load(open(PEDERSEN_HASH_POINT_FILENAME))

FIELD_PRIME = PEDERSEN_PARAMS['FIELD_PRIME']
ALPHA = PEDERSEN_PARAMS['ALPHA']
CONSTANT_POINTS = PEDERSEN_PARAMS['CONSTANT_POINTS']
SHIFT_POINT = CONSTANT_POINTS[0]


def pedersen_hash_as_point(elements) -> ECPoint:
    """
    Similar to pedersen_hash but also returns the y coordinate of the resulting EC point.
    This function is used for testing.
    """
    point = SHIFT_POINT
    for i, x in enumerate(elements):
        assert 0 <= x < FIELD_PRIME
        point_list = CONSTANT_POINTS[2 + i *
                                     N_ELEMENT_BITS_HASH:2 + (i + 1) * N_ELEMENT_BITS_HASH]
        assert len(point_list) == N_ELEMENT_BITS_HASH
        for pt in point_list:
            assert point[0] != pt[0], 'Unhashable input.'
            if x & 1:
                point = ec_add(point, pt, FIELD_PRIME)
            x >>= 1
        assert x == 0
    return point


def split_felt(a):
    # returns (a_high, a_low)
    res = divmod(a, 2**128)
    return res


P0 = (2089986280348253421170679821480865132823066470938446095505822317253594081284,
      1713931329540660377023406109199410414810705867260802078187082345529207694986)
P1 = (996781205833008774514500082376783249102396023663454813447423147977397232763,
      1668503676786377725805489344771023921079126552019160156920634619255970485781)
P2 = (2251563274489750535117886426533222435294046428347329203627021249169616184184,
      1798716007562728905295480679789526322175868328062420237419143593021674992973)
P3 = (2138414695194151160943305727036575959195309218611738193261179310511854807447,
      113410276730064486255102093846540133784865286929052426931474106396135072156)
P4 = (2379962749567351885752724891227938183011949129833673362440656643086021394946,
      776496453633298175483985398648758586525933812536653089401905292063708816422)

a = 32785849129042095080375743259094238589325873250793583258732952354
b = 28935787528752389598372589732349875328975987329875983725897328975
# H(a,b)=[P0+alow⋅P1+ahigh⋅P2+blow⋅P3+bhigh⋅P4]x


def pedersen_hash2(a, b):
    (a_high, a_low) = split_felt(a)
    (b_high, b_low) = split_felt(b)

    print(a_low, a_high)
    print(b_low, b_high)

    P_prod = None
    P = None
    if a_low != 0:
        P_prod = ec_mult(a_low, P1, ALPHA, FIELD_PRIME)
        P = ec_add(P0, P_prod, FIELD_PRIME)
    else:
        P = P0
    if a_high != 0:
        P_prod = ec_mult(a_high, P1, ALPHA, FIELD_PRIME)
        P = ec_add(P, P_prod, FIELD_PRIME)
    if b_low != 0:
        P_prod = ec_mult(b_low, P3, ALPHA, FIELD_PRIME)
        P = ec_add(P, P_prod, FIELD_PRIME)
    if b_high != 0:
        P_prod = ec_mult(b_high, P4, ALPHA, FIELD_PRIME)
        P = ec_add(P, P_prod, FIELD_PRIME)

    return P


# arr = [237696532, 23598236592385]
# t1 = time.time()
# hash_ = pedersen_hash_as_point(arr)[0]
# t2 = time.time()
# print(hash_, "   ",  t2 - t1)

# t1 = time.time()
# hash2 = pedersen_hash2(237696532, 23598236592385)
# t2 = time.time()
# print(hash2, "   ",  t2 - t1)
