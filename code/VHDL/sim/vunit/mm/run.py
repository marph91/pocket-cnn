import math
from os.path import join, dirname
from vunit import VUnit

import numpy as np

from fixfloat import v_float2fixedint, float2fixedint
from tools_vunit import random_bw, random_fixed_array


def create_stimuli(root, ksize, total_bits_data, frac_bits_data,
                   total_bits_weight, frac_bits_weight):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    int_bits_data = total_bits_data - frac_bits_data
    a_rand = random_fixed_array((ksize, ksize), int_bits_data, frac_bits_data)
    a_in = v_float2fixedint(a_rand, int_bits_data, frac_bits_data)
    np.savetxt(join(root, "src", "input_data%d.csv" % ksize), a_in,
               delimiter=", ", fmt="%3d")

    int_bits_weight = total_bits_weight - frac_bits_weight
    a_weights_rand = random_fixed_array(
        (ksize, ksize), int_bits_weight, frac_bits_weight)
    a_weights_in = v_float2fixedint(
        a_weights_rand, int_bits_weight, frac_bits_weight)
    np.savetxt(join(root, "src", "input_weights%d.csv" % ksize), a_weights_in,
               delimiter=", ", fmt="%3d")

    sum_ = np.sum(np.multiply(a_rand, a_weights_rand))

    additions = 0 if ksize == 1 else int(math.log(ksize - 1, 2) * 2)
    # use atleast_1d to fulfill 1d requirement of savetxt
    a_out = np.atleast_1d(float2fixedint(
        sum_, int_bits_data + int_bits_weight + additions + 1,
        frac_bits_data+frac_bits_weight))
    np.savetxt(join(root, "src", "output%d.csv" % ksize), a_out,
               delimiter=", ", fmt="%d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    util = ui.add_library("util", allow_duplicate=True)
    util.add_source_files("../../src/util/math_pkg.vhd")
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files("../../src/mm.vhd")
    unittest.add_source_files(join(root, "src", "*.vhd"))

    tb_mm = unittest.entity("tb_mm")
    for ksize in [1, 2, 3]:
        total_bits_data, frac_bits_data = random_bw(max_bw=16)
        total_bits_weight, frac_bits_weight = random_bw(max_bw=16)
        # TODO: fix when bitwidth is parametrizable
        total_bits_data, frac_bits_data = 8, 4
        total_bits_weight, frac_bits_weight = 8, 5
        generics = {"C_DATA_TOTAL_BITS": total_bits_data,
                    "C_DATA_FRAC_BITS_IN": frac_bits_data,
                    "C_WEIGHTS_TOTAL_BITS": total_bits_weight,
                    "C_WEIGHTS_FRAC_BITS": frac_bits_weight,
                    "C_KSIZE": ksize}
        tb_mm.add_config(name="dim=%d" % (ksize),
                         generics=generics,
                         pre_config=create_stimuli(root, ksize,
                                                   total_bits_data,
                                                   frac_bits_data,
                                                   total_bits_weight,
                                                   frac_bits_weight))
        tb_mm.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
