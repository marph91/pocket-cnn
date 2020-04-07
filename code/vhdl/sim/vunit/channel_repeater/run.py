"""Run the testbench of the "window_ctrl" module."""

import itertools
import os
from os.path import join, dirname
from random import randint
from vunit import VUnit


def create_stimuli(root, ksize, total_bits, channel_in,
                   channel_out, para):
    in_rand = [str(randint(0, 2 ** total_bits - 1))
               for _ in range(ksize * ksize * channel_in)]

    os.makedirs(join(root, "gen"), exist_ok=True)
    with open(join(root, "gen", f"input_{ksize}_{para}.csv"),
              "w") as outfile:
        outfile.write(", ".join(in_rand))

    with open(join(root, "gen", f"output_{ksize}_{para}.csv"),
              "w") as outfile:
        outfile.write(", ".join(in_rand * channel_out))


def create_test_suite(prj):
    root = dirname(__file__)

    prj.add_array_util()
    unittest = prj.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "*.vhd"))
    tb_channel_repeater = unittest.entity("tb_channel_repeater")

    for ksize in (1, 2, 3):
        total_bits = 8
        channel_in = randint(1, 16)
        channel_out = randint(1, 16)

        for para in (1,)*(channel_in > 1) + (channel_in,):
            generics = {"C_DATA_WIDTH": total_bits,
                        "C_CH": channel_in,
                        "C_REPEAT": channel_out,
                        "C_KSIZE": ksize,
                        "C_PARALLEL_CH": para}
            tb_channel_repeater.add_config(
                name=f"dim_{ksize}_para_{para}",
                generics=generics,
                pre_config=create_stimuli(root, ksize, total_bits,
                                          channel_in, channel_out, para))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
