from os.path import join, dirname
from random import randint

import numpy as np
from vunit import VUnit

from fixfloat import v_float2fixedint
from tools_vunit import array2stream, random_fixed_array
from cnn_reference import zero_pad


def create_arrays(root, w, h, ch):
    # TODO: check: numpy size: (ch, h, w) -> 2d: (h, w*ch)
    a_rand = random_fixed_array((ch, h, w), 8, 0)
    a_in = v_float2fixedint(a_rand, 8, 0)
    np.savetxt(join(root, "src", "input.csv"),
               array2stream(a_in), delimiter=", ",
               fmt="%3d")

    a_out = v_float2fixedint(zero_pad(a_rand), 8, 0)
    np.savetxt(join(root, "src", "output.csv"),
               array2stream(a_out), delimiter=", ",
               fmt="%3d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    unittest = ui.add_library("unittest", allow_duplicate=True)
    unittest.add_source_files("../../src/zero_pad.vhd")
    unittest.add_source_files(join(root, "src", "*.vhd"))

    tb_zero_pad = unittest.entity("tb_zero_pad")
    width, height, channel = randint(1, 32), randint(1, 32), randint(1, 16)
    tb_zero_pad.add_config(name="all",
                           generics={"C_IMG_WIDTH": width,
                                     "C_IMG_HEIGHT": height,
                                     "C_IMG_DEPTH": channel},
                           pre_config=create_arrays(root, width, height,
                                                    channel))
    tb_zero_pad.set_attribute(".unittest", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
