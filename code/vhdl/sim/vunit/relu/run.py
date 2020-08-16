"""Run the testbench of the "relu" module."""

from os.path import join, dirname

import numpy as np

from cnn_reference import relu, leaky_relu
from fpbinary_helper import random_fixed_array, v_to_fixedint


def create_stimuli(root, sample_cnt: int = 1):
    a_rand = random_fixed_array((sample_cnt), 4, 4)
    a_in = v_to_fixedint(a_rand)
    np.savetxt(join(root, "src", "input.csv"), a_in, delimiter=", ",
               fmt="%3d")

    a_out = v_to_fixedint(relu(a_rand))
    a_out_leaky = v_to_fixedint(leaky_relu(a_rand, 0.125))
    np.savetxt(join(root, "src", "output.csv"), a_out, delimiter=", ",
               fmt="%3d")
    np.savetxt(join(root, "src", "output_leaky.csv"), a_out_leaky, delimiter=", ",
               fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_relu = test_lib.entity("tb_relu")

    # TODO: different bitwidths
    sample_cnt = 100
    for leaky in [0, 1]:
        generics = {"sample_cnt": sample_cnt,
                    "ref_file": "output" + "_leaky" * leaky + ".csv",
                    "C_LEAKY": "'%d'" % leaky,
                    "C_TOTAL_BITS": 8, "C_FRAC_BITS": 0}
        tb_relu.add_config(name="leaky=%d_samples=%d" % (leaky, sample_cnt),
                           generics=generics,
                           pre_config=create_stimuli(root,
                                                     sample_cnt=sample_cnt))
