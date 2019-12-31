import itertools
import math
import os
from os.path import join, dirname
from random import randint
from vunit import VUnit

import numpy as np

from cnn_reference import conv
from fixfloat import v_float2fixedint, float2fixedint, float2ffloat
from fixfloat import random_fixed_array
from tools_vunit import array2stream
from weights2files import weights2files


def create_stimuli(root, ksize, stride,
                   total_bits_data, frac_bits_data_in,
                   frac_bits_data_out,
                   total_bits_weight, frac_bits_weight,
                   channel_in, channel_out,
                   width, height):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    int_bits_data_in = total_bits_data - frac_bits_data_in
    int_bits_data_out = total_bits_data - frac_bits_data_out
    a_rand = random_fixed_array(
        (channel_in, height, width), int_bits_data_in, frac_bits_data_in)
    a_in = v_float2fixedint(a_rand, int_bits_data_in, frac_bits_data_in)
    np.savetxt(join(root, "gen", "input_%d_%d.csv" % (ksize, stride)),
               array2stream(a_in), delimiter=", ", fmt="%3d")

    int_bits_weight = total_bits_weight - frac_bits_weight
    a_weights_rand = random_fixed_array(
        (channel_out, channel_in, ksize, ksize),
        int_bits_weight, frac_bits_weight)
    a_bias_rand = random_fixed_array(
        (channel_out), int_bits_weight, frac_bits_weight)

    # weights and bias to txt
    weights2files(
        a_weights_rand, a_bias_rand,
        total_bits_weight, frac_bits_weight,
        "conv_%d_%d" % (ksize, stride), join(root, "gen"))

    # assign the outputs
    conv_out = v_float2fixedint(
        conv(a_rand, a_weights_rand, a_bias_rand, ksize, stride,
             int_bits_data_out, frac_bits_data_out),
        int_bits_data_out, frac_bits_data_out)
    filename = join(root, "gen", "output_%d_%d.csv" % (ksize, stride))
    with open(filename, "w") as outfile:
        np.savetxt(outfile, array2stream(conv_out), delimiter=", ", fmt="%3d")


def create_test_suite(ui):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "*.vhd"))
    tb_conv_top = unittest.entity("tb_conv_top")

    for ksize, stride in itertools.product((1, 2, 3), (1, 2, 3)):
        if stride > ksize:  # this case doesn't make sense
            continue
        total_bits_data = 8  # TODO: fix when bitwidth is parametrizable
        frac_bits_data_in = randint(0, total_bits_data-1)
        frac_bits_data_out = randint(0, total_bits_data-1)
        total_bits_weight = 8
        frac_bits_weight = randint(0, total_bits_data-1)

        # TODO: bigger values at nightly runs
        channel_in, channel_out = randint(1, 16), randint(1, 16)
        width = randint(ksize, 16)
        height = randint(ksize, 16)

        weights_file = join(os.getcwd(), root, "gen",
                            "W_conv_%d_%d.txt" % (ksize, stride))
        bias_file = join(os.getcwd(), root, "gen",
                         "B_conv_%d_%d.txt" % (ksize, stride))
        
        # TODO: add test for first stage
        #       functionality is already ensured by toplevel tests and
        #       partially by mm test
        stage = 2
        generics = {"C_FIRST_STAGE": int(stage == 1),
                    "C_DATA_TOTAL_BITS": total_bits_data,
                    "C_DATA_FRAC_BITS_IN": frac_bits_data_in,
                    "C_DATA_FRAC_BITS_OUT": frac_bits_data_out,
                    "C_WEIGHTS_TOTAL_BITS": total_bits_weight,
                    "C_WEIGHTS_FRAC_BITS": frac_bits_weight,
                    "C_CH_IN": channel_in,
                    "C_CH_OUT": channel_out,
                    "C_IMG_WIDTH": width,
                    "C_IMG_HEIGHT": height,
                    "C_KSIZE": ksize,
                    "C_STRIDE": stride,
                    "STR_WEIGHTS_INIT": weights_file,
                    "STR_BIAS_INIT": bias_file}
        tb_conv_top.add_config(name="stage=%d_dim=%d_stride=%d" % (
                                   stage, ksize, stride),
                               generics=generics,
                               pre_config=create_stimuli(root, ksize, stride,
                                                         total_bits_data,
                                                         frac_bits_data_in,
                                                         frac_bits_data_out,
                                                         total_bits_weight,
                                                         frac_bits_weight,
                                                         channel_in, channel_out,
                                                         width, height))
        tb_conv_top.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
