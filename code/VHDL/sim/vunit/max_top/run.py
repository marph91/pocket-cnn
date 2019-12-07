import itertools
import math
from os.path import join, dirname
from random import randint
from vunit import VUnit

import numpy as np

from fixfloat import v_float2fixedint, v_fixedint2ffloat
from tools_vunit import random_bw, random_fixed_array

from skimage.measure import block_reduce


def create_stimuli(root, ksize, stride, total_bits, frac_bits, channel,
                   width, height):
    int_bits = total_bits - frac_bits
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    a_rand = np.random.randint(2 ** total_bits, size=(channel, height, width))

    # put the array in a stream based shape (channel > width > height)
    a_rand_stream = np.transpose(a_rand, (1, 2, 0)).flatten()
    np.savetxt(join(root, "src", "input_%d_%d.csv" % (ksize, stride)),
               a_rand_stream[None], delimiter=", ", fmt="%3d")

    a_rand_ffloat = v_fixedint2ffloat(a_rand, int_bits, frac_bits)

    # assign the outputs
    # TODO: put in own cnn operations file
    def max_pool(array_in):
        out = np.zeros((channel, int((height - (ksize - stride)) / stride),
                        int((width - (ksize - stride)) / stride)))
        # - (stride - 1) to provide only outputs, where the full kernel fits
        max_height = height - (ksize - stride) - (stride - 1)
        max_width = width - (ksize - stride) - (stride - 1)
        for row_out, row_in in enumerate(range(0, max_height, stride)):
            for col_out, col_in in enumerate(range(0, max_width, stride)):
                roi = array_in[:, row_in:row_in+ksize, col_in:col_in+ksize]
                out[:, row_out, col_out] = np.amax(
                    roi.reshape(channel, -1), axis=1)
        return out

    filename = join(root, "src", "output_%d_%d.csv" % (ksize, stride))
    with open(filename, "w") as outfile:
        out_stream = np.transpose(
            v_float2fixedint(
                max_pool(a_rand_ffloat), int_bits, frac_bits),
                (1, 2, 0)).flatten()
        np.savetxt(outfile, out_stream[None], delimiter=", ", fmt="%3d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    util = ui.add_library("util", allow_duplicate=True)
    util.add_source_files("../../src/util/cnn_pkg.vhd")
    util.add_source_files("../../src/util/math_pkg.vhd")
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files("../../src/bram.vhd")
    unittest.add_source_files("../../src/line_buffer.vhd")
    unittest.add_source_files("../../src/window_buffer.vhd")
    unittest.add_source_files("../../src/channel_buffer.vhd")
    unittest.add_source_files("../../src/window_ctrl.vhd")
    unittest.add_source_files("../../src/pool_max.vhd")
    unittest.add_source_files("../../src/max_top.vhd")
    unittest.add_source_files(join(root, "src", "*.vhd"))

    tb_max_top = unittest.entity("tb_max_top")

    for ksize, stride in itertools.product((2, 3), (1, 2, 3)):
        if stride > ksize:  # this case doesn't make sense
            continue

        total_bits = 8  # TODO: fix when bitwidth is parametrizable
        frac_bits = 4
        channel = randint(2, 16)  # TODO: test larger values in nightly runs
        width = randint(ksize, 16)
        height = randint(ksize, 16)
        
        generics = {"C_TOTAL_BITS": total_bits,
                    "C_FRAC_BITS": frac_bits,
                    "C_CH": channel,
                    "C_IMG_WIDTH": width,
                    "C_IMG_HEIGHT": height,
                    "C_STRIDE": stride,
                    "C_KSIZE": ksize}
        tb_max_top.add_config(name="dim=%d,stride=%d" % (ksize, stride),
                                  generics=generics,
                                  pre_config=create_stimuli(root,
                                                            ksize, stride,
                                                            total_bits,
                                                            frac_bits,
                                                            channel,
                                                            width, height))
        tb_max_top.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
