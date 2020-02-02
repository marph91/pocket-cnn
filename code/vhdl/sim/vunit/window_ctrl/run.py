import itertools
import math
from os.path import join, dirname
from random import randint
from vunit import VUnit

import numpy as np

from fixfloat import v_float2fixedint, float2fixedint


def create_stimuli(root, ksize, stride, total_bits, channel_in, channel_out,
                   width, height):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    a_rand = np.random.randint(
        2 ** total_bits, size=(1, channel_in, height, width))

    # put the array in a stream based shape (channel > width > height)
    a_rand_stream = np.transpose(a_rand, (0, 2, 3, 1)).flatten()[None]
    np.savetxt(join(root, "src", "input_%d_%d.csv" % (ksize, stride)), a_rand_stream,
               delimiter=", ", fmt="%3d")

    # assign the outputs
    rois = []
    # - (stride - 1) to provide only outputs, where the full kernel fits
    max_height = height - (ksize - stride) - (stride - 1)
    max_width = width - (ksize - stride) - (stride - 1)
    for row in range(0, max_height, stride):
        for col in range(0, max_width, stride):
            roi = a_rand[0, :, row:row + ksize, col:col + ksize]
            rois.append(roi)
    with open(join(root, "src", "output_%d_%d.csv" % (ksize, stride)), "w") as outfile:
        for r in rois:
            # add None to get second dimension and comma separation
            # ksize * ksize > channel
            np.savetxt(outfile, r.flatten()[None], delimiter=", ", fmt="%3d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
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


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
