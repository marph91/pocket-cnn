"""Run the testbench of the "pool_ave" module."""


from os.path import join, dirname
from random import randint

import numpy as np
from vunit import VUnit

from cnn_reference import avg_pool, flatten


def create_stimuli(root, w, h, ch, total_bits, frac_bits):
    int_bits = total_bits - frac_bits
    a_rand = np.random.randint(256, size=(1, ch, h, w), dtype=np.uint8)
    np.savetxt(join(root, "src", "input.csv"), flatten(a_rand),
               delimiter=", ", fmt="%3d")

    a_out = avg_pool(a_rand, (int_bits, frac_bits))
    np.savetxt(join(root, "src", "output.csv"), a_out, delimiter=", ",
               fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_pool_ave = test_lib.entity("tb_pool_ave")

    width, height, channel = randint(1, 4), randint(1, 8), randint(1, 8)
    total_bits = 8
    frac_bits = randint(0, total_bits-1)
    generics = {"C_IMG_WIDTH": width,
                "C_IMG_HEIGHT": height,
                "C_IMG_DEPTH": channel,
                "C_TOTAL_BITS": total_bits,
                "C_FRAC_BITS": frac_bits}
    tb_pool_ave.add_config(name="all", generics=generics,
                           pre_config=create_stimuli(root, width, height,
                                                     channel, total_bits,
                                                     frac_bits))
