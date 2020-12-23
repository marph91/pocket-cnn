"""Run the testbench of the "channel_repeater" module."""

import os
from os.path import join, dirname
from random import randint


def create_stimuli(root, ksize, total_bits, channel_in, channel_out):
    in_rand = [str(randint(0, 2 ** total_bits - 1))
               for _ in range(ksize * ksize * channel_in)]

    os.makedirs(join(root, "gen"), exist_ok=True)
    with open(join(root, "gen", f"input_{ksize}_{channel_in}.csv"),
              "w") as outfile:
        outfile.write(", ".join(in_rand))

    with open(join(root, "gen", f"output_{ksize}_{channel_in}.csv"),
              "w") as outfile:
        outfile.write(", ".join(in_rand * channel_out))


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_channel_repeater = test_lib.entity("tb_channel_repeater")

    for ksize in (1, 2, 3):
        total_bits = 8
        channel_in = randint(1, 16)
        channel_out = randint(1, 16)

        # TODO: Stimuli and output files get overwritten multiple times.
        #       Parallelization doesn't affect them.
        # TODO: THe function shoulndn't be executed before passing to
        #       "pre_config". I. e. use "functools.partial".
        for para in (1,)*(channel_in > 1) + (channel_in,):
            generics = {"C_BITWIDTH": total_bits,
                        "C_CH": channel_in,
                        "C_REPEAT": channel_out,
                        "C_KERNEL_SIZE": ksize,
                        "C_PARALLEL_CH": para}
            tb_channel_repeater.add_config(
                name=f"dim_{ksize}_ch_in_{channel_in}_para_{para}",
                generics=generics,
                pre_config=create_stimuli(root, ksize, total_bits,
                                          channel_in, channel_out))

        if ksize == 1:
            channel_in = 32
            for para in (2, 4, 8, 16):
                generics["C_PARALLEL_CH"] = para
                generics["C_CH"] = channel_in
                tb_channel_repeater.add_config(
                    name=f"dim_{ksize}_ch_in_{channel_in}_para_{para}",
                    generics=generics,
                    pre_config=create_stimuli(root, ksize, total_bits,
                                              channel_in, channel_out))
