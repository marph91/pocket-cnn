"""Run the testbench of the "conv_top" module."""

import itertools
import os
from os.path import join, dirname
from random import randint

import numpy as np

from cnn_reference import conv, flatten
from fp_helper import random_fixed_array, v_to_fixedint, Bitwidth
from weights_to_files import weights_to_files


def create_stimuli(root, ksize, stride,
                   bitwidth_data_in, bitwidth_data_out, bitwidth_weights,
                   channel_in, channel_out,
                   width, height):
    a_rand = random_fixed_array((1, channel_in, height, width), bitwidth_data_in)
    a_in = v_to_fixedint(a_rand)
    np.savetxt(join(root, "gen", f"input_{ksize}_{stride}_{channel_in}.csv"),
               flatten(a_in), delimiter=", ", fmt="%3d")

    a_weights_rand = random_fixed_array(
        (channel_out, channel_in, ksize, ksize), bitwidth_weights)
    a_bias_rand = random_fixed_array((channel_out,), bitwidth_weights)

    # weights and bias to txt
    weights_to_files(
        a_weights_rand, a_bias_rand,
        f"conv_{ksize}_{stride}_{channel_in}", join(root, "gen"))

    # assign the outputs
    conv_out = v_to_fixedint(conv(
        a_rand, a_weights_rand, a_bias_rand, (ksize, stride),
        bitwidth_data_out.as_tuple))
    filename = join(root, "gen", f"output_{ksize}_{stride}_{channel_in}.csv")
    with open(filename, "w") as outfile:
        np.savetxt(outfile, flatten(conv_out), delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)
    os.makedirs(join(root, "gen"), exist_ok=True)

    tb_conv_top = test_lib.entity("tb_conv_top")

    for ksize, stride in itertools.product((1, 2, 3, 5), (1, 2, 3)):
        if stride > ksize:  # this case doesn't make sense
            continue

        total_bits_data = 8
        total_bits_weight = 8
        bitwidth_data_in = Bitwidth(total_bits=total_bits_data)
        bitwidth_data_out = Bitwidth(total_bits=total_bits_data)
        bitwidth_weights = Bitwidth(total_bits=total_bits_weight)

        # TODO: resolve the bug with ch_in>1 and ch_out=1
        #       reference values seem to be calculated correctly
        channel_in, channel_out = randint(1, 16), randint(2, 16)
        width = randint(ksize, 16)
        height = randint(ksize, 16)

        weights_file = join(os.getcwd(), root, "gen",
                            f"W_conv_{ksize}_{stride}_{channel_in}.txt")
        bias_file = join(os.getcwd(), root, "gen",
                         f"B_conv_{ksize}_{stride}_{channel_in}.txt")

        for channel_para in (1,) * (channel_in > 1) + (channel_in,):
            # TODO: add test for first stage
            #       functionality is already ensured by toplevel tests and
            #       partially by mm test
            stage = 2
            generics = {
                "C_FIRST_STAGE": int(stage == 1),
                "C_DATA_TOTAL_BITS": total_bits_data,
                "C_DATA_FRAC_BITS_IN": bitwidth_data_in.frac_bits,
                "C_DATA_FRAC_BITS_OUT": bitwidth_data_out.frac_bits,
                "C_WEIGHTS_TOTAL_BITS": bitwidth_weights.total_bits,
                "C_WEIGHTS_FRAC_BITS": bitwidth_weights.frac_bits,
                "C_CH_IN": channel_in,
                "C_CH_OUT": channel_out,
                "C_IMG_WIDTH": width,
                "C_IMG_HEIGHT": height,
                "C_KSIZE": ksize,
                "C_STRIDE": stride,
                "C_WEIGHTS_INIT": weights_file,
                "C_BIAS_INIT": bias_file,
                "C_PARALLEL_CH": channel_para,
            }

            # Only create new stimuli if the config changes. Changes in the
            # parallelization don't affect the calculations.
            pre_config = create_stimuli(
                root, ksize, stride,
                bitwidth_data_in, bitwidth_data_out, bitwidth_weights,
                channel_in, channel_out,
                width, height) if channel_para == 1 else None
            tb_conv_top.add_config(
                name=(f"stage_{stage}_dim_{ksize}_stride_{stride}" +
                      f"_ch_in_{channel_in}_para_{channel_para}"),
                generics=generics,
                pre_config=pre_config)

        channel_in = 32
        if ksize == 1 and stride == 1:
            weights_file = join(os.getcwd(), root, "gen",
                                f"W_conv_{ksize}_{stride}_{channel_in}.txt")
            bias_file = join(os.getcwd(), root, "gen",
                             f"B_conv_{ksize}_{stride}_{channel_in}.txt")
            for channel_para in (2, 4, 8, 16):
                generics.update({
                    "C_CH_IN": channel_in,
                    "C_WEIGHTS_INIT": weights_file,
                    "C_BIAS_INIT": bias_file,
                    "C_PARALLEL_CH": channel_para,
                })
                pre_config = create_stimuli(
                    root, ksize, stride,
                    bitwidth_data_in, bitwidth_data_out, bitwidth_weights,
                    channel_in, channel_out,
                    width, height) if channel_para == 2 else None
                tb_conv_top.add_config(
                    name=(f"stage={stage}_dim_{ksize}_stride_{stride}" +
                          f"_ch_in_{channel_in}_para_{channel_para}"),
                    generics=generics,
                    pre_config=pre_config)
