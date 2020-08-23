"""Run the testbench of the "zero_pad" module."""

from os.path import join, dirname
from random import randint

import numpy as np

from cnn_reference import flatten, zero_pad
from fp_helper import random_fixed_array, v_to_fixedint, Bitwidth


def create_arrays(root, shape):
    id_ = "one" if shape[1] == 1 else "multiple"

    a_rand = random_fixed_array(shape, Bitwidth(int_bits=8, frac_bits=0))
    a_in = v_to_fixedint(a_rand)
    np.savetxt(join(root, "src", "input_%s.csv" % id_),
               flatten(a_in), delimiter=", ", fmt="%3d")
    a_out = v_to_fixedint(zero_pad(a_rand))
    np.savetxt(join(root, "src", "output_%s.csv" % id_),
               flatten(a_out), delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_zero_pad = test_lib.entity("tb_zero_pad")

    config_multiple_ch = randint(1, 32), randint(1, 32), randint(2, 16)
    config_one_ch = randint(1, 32), randint(1, 32), 1
    for width, height, channel in (config_one_ch, config_multiple_ch):
        id_ = "one" if channel == 1 else "multiple"
        tb_zero_pad.add_config(
            name="%s_channel" % id_,
            generics={
                "id": id_,
                "C_IMG_WIDTH": width,
                "C_IMG_HEIGHT": height,
                "C_IMG_DEPTH": channel,
            },
            pre_config=create_arrays(root, (1, channel, height, width)))
