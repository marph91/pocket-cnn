"""Run the testbench of the "mm" module."""


import itertools
import math
from os.path import join, dirname

import numpy as np

from fpbinary import OverflowEnum
from fp_helper import random_fixed_array, to_fixedint, v_to_fixedint, Bitwidth


def create_stimuli(root, stage, ksize, bitwidth_data, bitwidth_weights):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    a_rand = random_fixed_array((ksize,) * 2, bitwidth_data, signed=stage != 1)
    # manually extend the bitwidth to implicitly create unsigned values
    sign_bit = 1 if stage == 1 else 0
    a_in = v_to_fixedint(a_rand)
    name = "input_data%s.csv" % ("_stage1" if stage == 1 else str(ksize))
    np.savetxt(join(root, "src", name), a_in, delimiter=", ", fmt="%3d")

    a_weights_rand = random_fixed_array((ksize, ksize), bitwidth_weights)
    a_weights_in = v_to_fixedint(a_weights_rand)
    name = "input_weights%s.csv" % ("_stage1" if stage == 1 else str(ksize))
    np.savetxt(join(root, "src", name), a_weights_in,
               delimiter=", ", fmt="%3d")

    product = a_rand * a_weights_rand
    additions = 0 if ksize == 1 else int(math.log2(ksize - 1) * 2)
    # TODO: replace for loop
    for value in product.flat:
        # No rounding needed for resize.
        # The range is covered by "additions + 1 + sign_bit"
        value.resize(
            (value.format[0] + additions + 1 + sign_bit, value.format[1]),
            OverflowEnum.excep)
    sum_ = np.sum(product)

    # use atleast_1d to fulfill 1d requirement of savetxt
    a_out = np.atleast_1d(to_fixedint(sum_))
    name = "output%s.csv" % ("_stage1" if stage == 1 else str(ksize))
    np.savetxt(join(root, "src", name), a_out, delimiter=", ", fmt="%d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_mm = test_lib.entity("tb_mm")

    for stage, ksize in itertools.product((1, 2), (1, 2, 3)):
        if ksize != 3 and stage == 1:
            # only test both stage possibilities for ksize = 3
            continue
        bitwidth_data = Bitwidth(total_bits=8)
        bitwidth_weights = Bitwidth(total_bits=8)
        generics = {
            "C_FIRST_STAGE": int(stage == 1),
            "C_DATA_TOTAL_BITS": bitwidth_data.total_bits,
            "C_DATA_FRAC_BITS_IN": bitwidth_data.frac_bits,
            "C_WEIGHTS_TOTAL_BITS": bitwidth_weights.total_bits,
            "C_WEIGHTS_FRAC_BITS": bitwidth_weights.frac_bits,
            "C_KSIZE": ksize,
        }
        tb_mm.add_config(
            name="stage=%d_dim=%d" % (stage, ksize), generics=generics,
            pre_config=create_stimuli(
                root, stage, ksize, bitwidth_data, bitwidth_weights))
