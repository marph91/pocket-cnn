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
    np.savetxt(join(root, "src", "input_%d_%d.csv" % (ksize, stride)), a_rand_stream[None],
               delimiter=", ", fmt="%3d")
    
    # assign the outputs
    # TODO: check numpy.lib.stride_tricks.as_strided +
    #       scipy.ndimage.maximum_filter / scipy.ndimage.convolve
    rois = []
    ## get rois
    # - (stride - 1) to provide only outputs, where the full kernel fits
    a_rand_ffloat = v_fixedint2ffloat(a_rand, int_bits, frac_bits)
    for row in range(0, height - (ksize - stride) - (stride - 1), stride):
        for col in range(0, width - (ksize - stride) - (stride - 1), stride):
            roi = a_rand_ffloat[:, row:row + ksize, col:col + ksize]
            rois.append(roi)

    ## get max for each channel of each roi
    rois_max = []
    for r in rois:
        rois_max.append(
            block_reduce(r, block_size=(1, ksize, ksize), func=np.max))

    with open(join(root, "src", "output_%d_%d.csv" % (ksize, stride)), "w") as outfile:
        for r in rois_max:
            r_stream = v_float2fixedint(r, int_bits, frac_bits).flatten()
            # add None to get second dimension and comma separation
            np.savetxt(outfile, r_stream[None], delimiter=", ", fmt="%3d")


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
