"""Run the testbench of the "relu" module."""

from os.path import join, dirname

import numpy as np
from vunit import VUnit

import fixfloat


def relu(val, leaky=0):
    out = val if val >= 0 else val * leaky * 0.125
    # convert to int, because only int is supported at image2d.get
    return str(int(fixfloat.float2fixed(out, 8, 0), 2))


def create_stimuli(root, sample_cnt: int = 1):
    a_in = np.random.randint(-128, high=127, size=(sample_cnt), dtype=np.int8)
    np.savetxt(join(root, "src", "input.csv"), a_in, delimiter=", ",
               fmt="%3d")

    a_out = []
    a_out_leaky = []
    for val in a_in:
        a_out.append(relu(val, leaky=0))
        a_out_leaky.append(relu(val, leaky=1))
    with open(join(root, "src", "output.csv"), "w") as outfile:
        outfile.write("\n".join(a_out))
    with open(join(root, "src", "output_leaky.csv"), "w") as outfile:
        outfile.write("\n".join(a_out_leaky))


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_relu = test_lib.entity("tb_relu")

    sample_cnt = 100
    for leaky in [0, 1]:
        generics = {"sample_cnt": sample_cnt,
                    "ref_file": "output" + "_leaky" * leaky + ".csv",
                    "C_LEAKY": "'%d'" % leaky,
                    "C_TOTAL_BITS": 8, "C_FRAC_BITS": 0}
        tb_relu.add_config(name="leaky=%d_samples=%d" % (leaky, sample_cnt),
                           generics=generics,
                           pre_config=create_stimuli(root,
                                                     sample_cnt=sample_cnt))
