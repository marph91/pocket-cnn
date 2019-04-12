import os
from os.path import join, dirname
from vunit import VUnit

from random import randint
import numpy as np

from fixfloat import v_float2fixedint
from tools_vunit import random_bw, random_fixed_array


def create_stimuli(root, pool_dim, int_bits, frac_bits):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to the corresponding integer values.
    a_rand = random_fixed_array((pool_dim, pool_dim), int_bits, frac_bits)
    a_in = v_float2fixedint(a_rand, int_bits, frac_bits)
    np.savetxt(join(root, "src", "input%d.csv" % pool_dim), a_in, delimiter=", ", fmt='%3d')

    # use atleast_1d to fulfill 1d requirement of savetxt
    a_out = np.atleast_1d(v_float2fixedint(np.max(a_rand), int_bits, frac_bits))
    np.savetxt(join(root, "src", "output%d.csv" % pool_dim), a_out, delimiter=", ", fmt='%3d')


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    util = ui.add_library("util", allow_duplicate=True)
    util.add_source_files("/home/workspace/opencnn/code/VHDL/src/util/math.vhd")
    lib = ui.add_library("lib", allow_duplicate=True)
    lib.add_source_files("/home/workspace/opencnn/code/VHDL/src/pool_max.vhd")
    lib.add_source_files(join("src", "*.vhd"))

    tb_pool_max = lib.entity("tb_pool_max")
    for pool_dim in [2, 3]:
        int_bits, frac_bits = random_bw(max_bw=16)
        # print("dim=%d,q%d.%d" % (pool_dim, int_bits, frac_bits))
        tb_pool_max.add_config(name="dim=%d" % (pool_dim),
                                generics=dict(C_POOL_DIM=pool_dim, C_INT_WIDTH=int_bits, C_FRAC_WIDTH=frac_bits),
                                pre_config=create_stimuli(root, pool_dim, int_bits, frac_bits))


if __name__ == '__main__':
    ui = VUnit.from_argv()
    create_test_suite(ui)
    ui.main()
