"""Run the testbench of the "pool_max" module."""

from os.path import join, dirname
from random import randint

import numpy as np
from vunit import VUnit

from fixfloat import v_float2fixedint
from fixfloat import random_fixed_array


def create_stimuli(root, pool_dim, total_bits, frac_bits):
    # vunit import from csv can only handle datatype integer.
    # Therefore the random fixed point values have to be converted to
    # corresponding integer values.
    int_bits = total_bits - frac_bits
    a_rand = random_fixed_array((pool_dim, pool_dim), int_bits, frac_bits)
    a_in = v_float2fixedint(a_rand, int_bits, frac_bits)
    np.savetxt(join(root, "src", "input%d.csv" % pool_dim), a_in,
               delimiter=", ", fmt="%3d")

    # use atleast_1d to fulfill 1d requirement of savetxt
    a_out = np.atleast_1d(v_float2fixedint(
        np.max(a_rand), int_bits, frac_bits))
    np.savetxt(join(root, "src", "output%d.csv" % pool_dim), a_out,
               delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_pool_max = test_lib.entity("tb_pool_max")

    for pool_dim in [2, 3]:
        total_bits = 8
        frac_bits = randint(0, total_bits - 1)

        generics = {"C_KSIZE": pool_dim, "C_TOTAL_BITS": total_bits,
                    "C_FRAC_BITS": frac_bits}
        tb_pool_max.add_config(name="dim=%d" % (pool_dim),
                               generics=generics,
                               pre_config=create_stimuli(root, pool_dim,
                                                         total_bits, frac_bits))
