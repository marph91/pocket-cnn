import os
from os.path import join, dirname, isdir

import numpy as np
from vunit import VUnit


def create_stimuli(root):
    # TODO: convert image to csv
    # TODO: process cnn and add output to csv
    # TODO: extract weights
    pass


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    lib_sim = ui.add_library("sim", allow_duplicate=True)
    lib_sim.add_source_files("common.vhd")
    lib_cmn = ui.add_library("util", allow_duplicate=True)
    lib_cmn.add_source_files("../../src/util/*.vhd")

    cnn_lib = ui.add_library("cnn_lib", allow_duplicate=True)
    cnn_lib.add_source_files("../../src/*.vhd")

    test_cases = [name for name in os.listdir(join(root, "src"))
                  if isdir(join(root, "src", name))]
    for test_case in test_cases:
        if test_case.endswith("_"):
            # temporary disable some tests
            continue
        param_lib = ui.add_library(f"integration_{test_case}")
        param_lib.add_source_files(join(root, "src", "tb_top.vhd"))
        param_lib.add_source_files("../../src/top.vhd")
        param_lib.add_source_files(
            join(root, "src", test_case, "cnn_parameter.vhd"))
        tb_top = param_lib.entity("tb_top")
        generics = {"C_DATA_WIDTH": 8,
                    "C_FOLDER": test_case}  # TODO: find a better way
        tb_top.add_config(name=test_case, generics=generics,
                          pre_config=create_stimuli(join(
                              root, "src", test_case)))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
