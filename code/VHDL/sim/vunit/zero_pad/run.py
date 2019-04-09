from os.path import join, dirname
from vunit import VUnit

from random import randint
import numpy as np

from fixfloat import v_float2fixedint
from tools_vunit import random_fixed_array


def create_arrays(root, w, h, ch):
    a_rand = random_fixed_array((h, w*ch), 8, 0)
    a_in = v_float2fixedint(a_rand, 8, 0)
    np.savetxt(join(root, "src", "input.csv"), a_in, delimiter=", ", fmt='%3d')

    a_out = np.pad(a_in, ((1, 1), (ch, ch)), 'constant', constant_values=0)
    np.savetxt(join(root, "src", "output.csv"), a_out, delimiter=", ", fmt='%3d')


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    lib = ui.add_library("lib", allow_duplicate=True)
    # TODO: remove absolute path -> problem when running single test vs al tests
    lib.add_source_files(join("/home/workspace/opencnn/code/VHDL/src/zero_pad.vhd"))
    lib.add_source_files(join(root, "src", "*.vhd"))

    tb_zero_pad = lib.entity("tb_zero_pad")
    width, height, channel = randint(1, 32), randint(1, 32), randint(1, 16)
    # print("w=%d,h=%d,ch=%d" % (width, height, channel))
    tb_zero_pad.add_config(name="all",
                            generics=dict(C_WIDTH=width, C_HEIGHT=height, C_CH=channel),
                            pre_config=create_arrays(root, width, height, channel))

if __name__ == '__main__':
    ui = VUnit.from_argv()
    create_test_suite(ui)
    ui.main()