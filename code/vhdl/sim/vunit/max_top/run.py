import itertools
import math
from os.path import join, dirname
from random import randint
from vunit import VUnit

import numpy as np

from cnn_reference import max_pool
from fixfloat import v_float2fixedint, v_fixedint2ffloat
from tools_vunit import array2stream


def create_stimuli(root, ksize, stride, total_bits, frac_bits, channel,
                   width, height):
    int_bits = total_bits - frac_bits
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    a_rand = np.random.randint(2 ** total_bits, size=(channel, height, width))
    np.savetxt(join(root, "src", "input_%d_%d.csv" % (ksize, stride)),
               array2stream(a_rand), delimiter=", ", fmt="%3d")

    a_rand_ffloat = v_fixedint2ffloat(a_rand, int_bits, frac_bits)

    # assign the outputs
    filename = join(root, "src", "output_%d_%d.csv" % (ksize, stride))
    max_out = v_float2fixedint(
        max_pool(a_rand_ffloat, ksize, stride),
        int_bits, frac_bits)
    with open(filename, "w") as outfile:
        np.savetxt(outfile, array2stream(max_out), delimiter=", ", fmt="%3d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "src", "*.vhd"))
    tb_max_top = unittest.entity("tb_max_top")

    for ksize, stride in itertools.product((2, 3), (1, 2, 3)):
        if stride > ksize:  # this case doesn't make sense
            continue

        total_bits = 8  # TODO: fix when bitwidth is parametrizable
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
        tb_max_top.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
