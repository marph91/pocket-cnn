"""Run the testbench of the "pool_max" module."""

from os.path import join, dirname

import numpy as np

from fp_helper import random_fixed_array, to_fixedint, v_to_fixedint, Bitwidth


def create_stimuli(root, pool_dim, bitwidth):
    a_rand = random_fixed_array((pool_dim, pool_dim), bitwidth)
    a_in = v_to_fixedint(a_rand)
    np.savetxt(join(root, "src", "input%d.csv" % pool_dim), a_in,
               delimiter=", ", fmt="%3d")

    # use atleast_1d to fulfill 1d requirement of savetxt
    a_out = np.atleast_1d(to_fixedint(np.max(a_rand)))
    np.savetxt(join(root, "src", "output%d.csv" % pool_dim), a_out,
               delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_pool_max = test_lib.entity("tb_pool_max")

    for pool_dim in [2, 3]:
        bitwidth = Bitwidth(total_bits=8)
        generics = {
            "C_KSIZE": pool_dim,
            "C_TOTAL_BITS": bitwidth.total_bits,
            "C_FRAC_BITS": bitwidth.frac_bits,
        }
        tb_pool_max.add_config(
            name="dim=%d" % (pool_dim), generics=generics,
            pre_config=create_stimuli(root, pool_dim, bitwidth))
