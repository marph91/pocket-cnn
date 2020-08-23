"""Run the testbench of the "relu" module."""

from os.path import join, dirname

import numpy as np

from cnn_reference import relu, leaky_relu
from fpbinary import FpBinary
from fp_helper import random_fixed_array, v_to_fixedint, Bitwidth


def create_stimuli(root, bitwidth, leaky, sample_cnt: int = 1):
    a_rand = random_fixed_array((sample_cnt), bitwidth)
    a_in = v_to_fixedint(a_rand)
    np.savetxt(join(root, "src", "input_" + "leaky" * leaky + ".csv"),
               a_in, delimiter=", ", fmt="%3d")

    a_out = (
        relu(a_rand) if not leaky else
        leaky_relu(a_rand, FpBinary(int_bits=0, frac_bits=3, value=0.125)))
    np.savetxt(join(root, "src", "output_" + "leaky" * leaky + ".csv"),
               v_to_fixedint(a_out), delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_relu = test_lib.entity("tb_relu")

    sample_cnt = 100
    for leaky in [0, 1]:
        bitwidth = Bitwidth(total_bits=8)
        generics = {
            "sample_cnt": sample_cnt,
            "leaky_string": "_leaky" if leaky else "_",
            "C_LEAKY": "'%d'" % leaky,
            "C_TOTAL_BITS": bitwidth.total_bits,
            "C_FRAC_BITS": bitwidth.frac_bits,
        }
        tb_relu.add_config(
            name="leaky=%d_samples=%d" % (leaky, sample_cnt),
            generics=generics,
            pre_config=create_stimuli(
                root, bitwidth, leaky, sample_cnt=sample_cnt))
