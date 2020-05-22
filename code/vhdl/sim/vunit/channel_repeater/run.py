"""Run the testbench of the "channel_repeater" module."""

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


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_channel_repeater = test_lib.entity("tb_channel_repeater")

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
                name=f"dim_{ksize}_ch_in_{channel_in}_para_{para}",
                generics=generics,
                pre_config=create_stimuli(root, ksize, total_bits,
                                          channel_in, channel_out, para))

        if ksize == 1:
            channel_in = 32
            for para in (2, 4, 8, 16):
                generics["C_PARALLEL_CH"] = para
                generics["C_CH"] = channel_in
                tb_channel_repeater.add_config(
                    name=f"dim_{ksize}_ch_in_{channel_in}_para_{para}",
                    generics=generics,
                    pre_config=create_stimuli(root, ksize, total_bits,
                                              channel_in, channel_out, para))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
