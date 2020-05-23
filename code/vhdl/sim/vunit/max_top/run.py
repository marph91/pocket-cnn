"""Run the testbench of the "max_top" module."""

import itertools
from os.path import join, dirname
from random import randint

import numpy as np

from cnn_reference import flatten, max_pool


def create_stimuli(root, ksize, stride, total_bits, frac_bits, channel,
                   width, height):
    int_bits = total_bits - frac_bits

    a_rand = np.random.randint(2 ** total_bits,
                               size=(1, channel, height, width))
    np.savetxt(join(root, "src", "input_%d_%d.csv" % (ksize, stride)),
               flatten(a_rand), delimiter=", ", fmt="%3d")

    # assign the outputs
    filename = join(root, "src", "output_%d_%d.csv" % (ksize, stride))
    max_out = max_pool(a_rand, ksize, stride, (int_bits, frac_bits))
    with open(filename, "w") as outfile:
        np.savetxt(outfile, flatten(max_out), delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_max_top = test_lib.entity("tb_max_top")

    for ksize, stride in itertools.product((2, 3), (1, 2, 3)):
        if stride > ksize:  # this case doesn't make sense
            continue

        total_bits = 8
        frac_bits = randint(0, total_bits-1)
        channel = randint(1, 16)  # TODO: test larger values in nightly runs
        width = randint(ksize, 16)
        height = randint(ksize, 16)

        generics = {"C_TOTAL_BITS": total_bits,
                    "C_FRAC_BITS": frac_bits,
                    "C_CH": channel,
                    "C_IMG_WIDTH": width,
                    "C_IMG_HEIGHT": height,
                    "C_STRIDE": stride,
                    "C_KSIZE": ksize}
        tb_max_top.add_config(name="ksize=%d_stride=%d" % (ksize, stride),
                              generics=generics,
                              pre_config=create_stimuli(root, ksize, stride,
                                                        total_bits, frac_bits,
                                                        channel,
                                                        width, height))
