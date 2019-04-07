import os
from os.path import join, dirname
from vunit import VUnit

from random import randint
import numpy as np

import fixfloat


def relu(x, leaky=0):
    out = x if x >= 0 else x * leaky * 0.125
    # convert to int, because only int is supported at image2d.get
    return str(int(fixfloat.float2fixed(out, 8, 0), 2))


def create_stimuli(root, sample_cnt=1):
    a_in = np.random.randint(-128, high=127, size=(sample_cnt), dtype=np.int8)
    np.savetxt(join(root, "src", "input.csv"), a_in, delimiter=", ", fmt='%3d')

    a_out = []
    a_out_leaky = []
    for val in a_in:
        a_out.append(relu(val, leaky=0))
        a_out_leaky.append(relu(val, leaky=1))
    with open(join(root, "src", "output.csv"), "w") as outfile:
        outfile.write("\n".join(a_out))
    with open(join(root, "src", "output_leaky.csv"), "w") as outfile:
        outfile.write("\n".join(a_out_leaky))


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    lib = ui.add_library("lib", allow_duplicate=True)
    lib.add_source_files(join("/home/workspace/opencnn/code/VHDL/src/relu.vhd"))
    lib.add_source_files(join(root, "src", "*.vhd"))

    tb_relu = lib.entity("tb_relu")
    sample_cnt = 10
    for leaky in [0, 1]:
        tb_relu.add_config(name="leaky=%d,samples=%d" % (leaky, sample_cnt),
                            generics=dict(sample_cnt=10, ref_file="output" + "_leaky"*leaky + ".csv", C_LEAKY="'" + str(leaky) + "'", C_INT_WIDTH=8, C_FRAC_WIDTH=0),
                            pre_config=create_stimuli(root, sample_cnt=sample_cnt))

if __name__ == '__main__':
    ui = VUnit.from_argv()
    create_test_suite(ui)
    ui.main()
