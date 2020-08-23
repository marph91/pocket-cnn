"""Run the testbench of the "pool_ave" module."""


from os.path import join, dirname
from random import randint

import numpy as np

from cnn_reference import avg_pool, flatten

from fp_helper import random_fixed_array, v_to_fixedint, Bitwidth


def create_stimuli(root, shape, bitwidth):
    a_rand = random_fixed_array(shape, bitwidth)
    a_in = v_to_fixedint(a_rand)
    np.savetxt(join(root, "src", "input.csv"), flatten(a_in),
               delimiter=", ", fmt="%3d")

    a_out = v_to_fixedint(avg_pool(a_rand))
    np.savetxt(join(root, "src", "output.csv"), a_out, delimiter=", ",
               fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_pool_ave = test_lib.entity("tb_pool_ave")

    width, height, channel = randint(1, 4), randint(1, 8), randint(1, 8)
    bitwidth = Bitwidth(total_bits=8)
    generics = {
        "C_IMG_WIDTH": width,
        "C_IMG_HEIGHT": height,
        "C_IMG_DEPTH": channel,
        "C_TOTAL_BITS": bitwidth.total_bits,
        "C_FRAC_BITS": bitwidth.frac_bits,
    }
    tb_pool_ave.add_config(
        name="all", generics=generics,
        pre_config=create_stimuli(root, (1, channel, height, width), bitwidth),
    )
