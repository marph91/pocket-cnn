import os
from os.path import join, dirname
from vunit import VUnit

from random import randint
import numpy as np

from fixfloat import v_float2fixedint, float2ffloat
from tools_vunit import random_bw, random_fixed_array


def create_stimuli(root, w, h, ch, int_bits, frac_bits):
    a_rand = random_fixed_array((h, w*ch), int_bits, frac_bits)
    a_in = v_float2fixedint(a_rand, int_bits, frac_bits)
    np.savetxt(join(root, "src", "input.csv"), a_in, delimiter=", ", fmt='%3d')

    # calculate reciprocal for average manually, because else factor would be too different 
    reciprocal = float2ffloat(1./(w*h), 1, 16)
    # a_in[:, x::ch] -> start:stop:step
    a_avg = np.asarray([np.sum(a_rand[:, x::ch])*reciprocal for x in range(ch)])
    a_out = v_float2fixedint(a_avg, int_bits, frac_bits)
    np.savetxt(join(root, "src", "output.csv"), a_out, delimiter=", ", fmt='%3d')


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    lib_cmn = ui.add_library("util", allow_duplicate=True)
    lib_cmn.add_source_files(join("/home/workspace/opencnn/code/VHDL/src/util/*.vhd"))
    lib = ui.add_library("lib", allow_duplicate=True)
    lib.add_source_files(join("/home/workspace/opencnn/code/VHDL/src/pool_ave.vhd"))
    lib.add_source_files(join(root, "src", "*.vhd"))

    tb_pool_ave = lib.entity("tb_pool_ave")
    width, height, channel = randint(1, 4), randint(1, 8), randint(1, 8)
    int_bits, frac_bits = random_bw(max_bw=8)
    # print("w=%d,h=%d,ch=%d,q%d.%d" % (width, height, channel, int_bits, frac_bits))
    tb_pool_ave.add_config(name="all",
                                generics=dict(C_WIDTH=width, C_HEIGHT=height, C_POOL_CH=channel, C_INT_WIDTH=int_bits, C_FRAC_WIDTH=frac_bits),
                                pre_config=create_stimuli(root, width, height, channel, int_bits, frac_bits))

if __name__ == '__main__':
    ui = VUnit.from_argv()
    create_test_suite(ui)
    ui.main()