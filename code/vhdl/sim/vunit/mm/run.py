import itertools
import math
from os.path import join, dirname
import random

import numpy as np
from vunit import VUnit

from fixfloat import v_float2fixedint, float2fixedint
from fixfloat import random_fixed_array
from tools_vunit import random_bw


def create_stimuli(root, stage, ksize, total_bits_data, frac_bits_data,
                   total_bits_weight, frac_bits_weight):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    int_bits_data = total_bits_data - frac_bits_data
    a_rand = random_fixed_array(
        (ksize, ksize), int_bits_data, frac_bits_data, signed=stage != 1)
    # manually extend the bitwidth to implicitly create unsigned values
    sign_bit = 1 if stage == 1 else 0
    a_in = v_float2fixedint(a_rand, int_bits_data + sign_bit, frac_bits_data)
    name = "input_data%s.csv" % ("_stage1" if stage == 1 else str(ksize))
    np.savetxt(join(root, "src", name), a_in, delimiter=", ", fmt="%3d")

    int_bits_weight = total_bits_weight - frac_bits_weight
    a_weights_rand = random_fixed_array(
        (ksize, ksize), int_bits_weight, frac_bits_weight)
    a_weights_in = v_float2fixedint(
        a_weights_rand, int_bits_weight, frac_bits_weight)
    name = "input_weights%s.csv" % ("_stage1" if stage == 1 else str(ksize))
    np.savetxt(join(root, "src", name), a_weights_in,
               delimiter=", ", fmt="%3d")

    sum_ = np.sum(a_rand * a_weights_rand)

    additions = 0 if ksize == 1 else int(math.log2(ksize - 1) * 2)
    # use atleast_1d to fulfill 1d requirement of savetxt
    a_out = np.atleast_1d(float2fixedint(
        sum_, int_bits_data + int_bits_weight + additions + 1 + sign_bit,
        frac_bits_data+frac_bits_weight))
    name = "output%s.csv" % ("_stage1" if stage == 1 else str(ksize))
    np.savetxt(join(root, "src", name), a_out, delimiter=", ", fmt="%d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "src", "*.vhd"))
    tb_mm = unittest.entity("tb_mm")

    for stage, ksize in itertools.product((1, 2), (1, 2, 3)):
        if ksize != 3 and stage == 1:
            # only test both stage possibilities for ksize = 3
            continue
        total_bits_data, frac_bits_data = random_bw(max_bw=16)
        total_bits_weight, frac_bits_weight = random_bw(max_bw=16)
        # TODO: fix when bitwidth is parametrizable
        total_bits_data, frac_bits_data = 8, 4
        total_bits_weight, frac_bits_weight = 8, 5
        generics = {"C_FIRST_STAGE": int(stage == 1),
                    "C_DATA_TOTAL_BITS": total_bits_data,
                    "C_DATA_FRAC_BITS_IN": frac_bits_data,
                    "C_WEIGHTS_TOTAL_BITS": total_bits_weight,
                    "C_WEIGHTS_FRAC_BITS": frac_bits_weight,
                    "C_KSIZE": ksize}
        tb_mm.add_config(name="stage=%d_dim=%d" % (stage, ksize),
                         generics=generics,
                         pre_config=create_stimuli(root, stage, ksize,
                                                   total_bits_data,
                                                   frac_bits_data,
                                                   total_bits_weight,
                                                   frac_bits_weight))
        tb_mm.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
