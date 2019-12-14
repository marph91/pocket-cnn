from os.path import join, dirname
from random import randint

import numpy as np
from vunit import VUnit

from cnn_reference import avg_pool
from fixfloat import v_float2fixedint, float2ffloat
from tools_vunit import array2stream, random_fixed_array


def create_stimuli(root, w, h, ch, total_bits, frac_bits):
    int_bits = total_bits - frac_bits
    a_rand = random_fixed_array((ch, h, w), int_bits, frac_bits)
    a_in = v_float2fixedint(a_rand, int_bits, frac_bits)
    np.savetxt(join(root, "src", "input.csv"), array2stream(a_in), delimiter=", ",
               fmt="%3d")

    a_out = v_float2fixedint(avg_pool(a_rand), int_bits, frac_bits)
    np.savetxt(join(root, "src", "output.csv"), a_out[None], delimiter=", ",
               fmt="%3d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files(join(root, "src", "*.vhd"))
    tb_pool_ave = unittest.entity("tb_pool_ave")

    width, height, channel = randint(1, 4), randint(1, 8), randint(1, 8)
    total_bits = 8
    frac_bits = randint(0, total_bits-1)
    generics = {"C_IMG_WIDTH": width,
                "C_IMG_HEIGHT": height,
                "C_IMG_DEPTH": channel,
                "C_TOTAL_BITS": total_bits,
                "C_FRAC_BITS": frac_bits}
    tb_pool_ave.add_config(name="all", generics=generics,
                           pre_config=create_stimuli(root, width, height,
                                                     channel, total_bits,
                                                     frac_bits))
    tb_pool_ave.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
