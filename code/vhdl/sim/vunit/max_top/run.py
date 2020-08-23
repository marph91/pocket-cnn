"""Run the testbench of the "max_top" module."""

import itertools
from os.path import join, dirname
from random import randint

import numpy as np

from cnn_reference import flatten, max_pool
from fp_helper import random_fixed_array, v_to_fixedint, Bitwidth


def create_stimuli(root, ksize, stride, bitwidth, shape):
    a_rand = random_fixed_array(shape, bitwidth)
    a_in = v_to_fixedint(a_rand)
    np.savetxt(join(root, "src", "input_%d_%d.csv" % (ksize, stride)),
               flatten(a_in), delimiter=", ", fmt="%3d")

    # assign the outputs
    filename = join(root, "src", "output_%d_%d.csv" % (ksize, stride))
    max_out = v_to_fixedint(max_pool(a_rand, ksize, stride))
    with open(filename, "w") as outfile:
        np.savetxt(outfile, flatten(max_out), delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_max_top = test_lib.entity("tb_max_top")

    for ksize, stride in itertools.product((2, 3), (1, 2, 3)):
        if stride > ksize:  # this case doesn't make sense
            continue

        bitwidth = Bitwidth(total_bits=8)
        channel = randint(1, 16)
        width = randint(ksize, 16)
        height = randint(ksize, 16)

        generics = {
            "C_TOTAL_BITS": bitwidth.total_bits,
            "C_FRAC_BITS": bitwidth.frac_bits,
            "C_CH": channel,
            "C_IMG_WIDTH": width,
            "C_IMG_HEIGHT": height,
            "C_STRIDE": stride,
            "C_KSIZE": ksize,
        }
        tb_max_top.add_config(
            name="ksize=%d_stride=%d" % (ksize, stride),
            generics=generics,
            pre_config=create_stimuli(
                root, ksize, stride, bitwidth, (1, channel, height, width)))
