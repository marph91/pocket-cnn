import itertools
import math
from os.path import join, dirname
from random import randint
from vunit import VUnit

import numpy as np

from fixfloat import v_float2fixedint, float2fixedint
from tools_vunit import random_bw, random_fixed_array


def create_stimuli(root, ksize, stride, total_bits, channel_in, channel_out,
                   width, height):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    a_rand = np.random.randint(2 ** total_bits, size=(channel_in, height, width))

    # put the array in a stream based shape (channel > width > height)
    a_rand_stream = np.transpose(a_rand, (1, 2, 0)).flatten()
    np.savetxt(join(root, "src", "input_%d_%d.csv" % (ksize, stride)), a_rand_stream[None],
               delimiter=", ", fmt="%3d")
    
    # assign the outputs
    rois = []
    # - (stride - 1) to provide only outputs, where the full kernel fits
    for row in range(0, height - (ksize - stride) - (stride - 1), stride):
        for col in range(0, width - (ksize - stride) - (stride - 1), stride):
            roi = a_rand[:, row:row + ksize, col:col + ksize]
            rois.append(roi)
    with open(join(root, "src", "output_%d_%d.csv" % (ksize, stride)), "w") as outfile:
        for r in rois:
            r_stream = r.flatten() # ksize * ksize > channel
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
    unittest.add_source_files(join(root, "src", "*.vhd"))

    tb_window_ctrl = unittest.entity("tb_window_ctrl")

    for ksize, stride in itertools.product((1, 2, 3), (1, 2, 3)):
        if stride > ksize:  # this case doesn't make sense
            continue

        total_bits = 8  # TODO: fix when bitwidth is parametrizable
        channel_in = randint(1, 16)  # TODO: test larger values in nightly runs
        channel_out = randint(1, 16)
        width = randint(ksize, 16)
        height = randint(ksize, 16)
        
        generics = {"C_DATA_TOTAL_BITS": total_bits,
                    "C_CH_IN": channel_in,
                    "C_CH_OUT": channel_out,
                    "C_IMG_WIDTH": width,
                    "C_IMG_HEIGHT": height,
                    "C_STRIDE": stride,
                    "C_KSIZE": ksize}
        tb_window_ctrl.add_config(name="dim=%d_stride=%d" % (ksize, stride),
                                  generics=generics,
                                  pre_config=create_stimuli(root,
                                                            ksize, stride,
                                                            total_bits,
                                                            channel_in,
                                                            channel_out,
                                                            width, height))
        tb_window_ctrl.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
