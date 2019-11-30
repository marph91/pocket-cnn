import json
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

    integration_test = ui.add_library("integration_test")
    integration_test.add_source_files(join(root, "src", "tb_top.vhd"))
    tb_top = integration_test.entity("tb_top")

    test_cases = [name for name in os.listdir(join(root, "src"))
                  if isdir(join(root, "src", name))]
    for test_case in test_cases:
        if test_case.endswith("_"):
            # temporary disable some tests
            continue
        with open(join(root, "src", test_case, "cnn_parameter.json")) as infile:
            params = json.load(infile)

        weights = ["%s/W_%s.txt" % (params["weight_dir"], name)
                   for name in params["conv_names"]]
        bias = ["%s/B_%s.txt" % (params["weight_dir"], name)
                for name in params["conv_names"]]
        assert len(weights[0]) == params["len_weights"]
        assert len(bias[0]) == params["len_weights"]

        bitwidth = "; ".join([", ".join(str(item) for item in inner)
                              for inner in params["bitwidth"]])

        generics = {"C_DATA_TOTAL_BITS": params["bitwidth"][0][0],
                    "C_FOLDER": test_case,  # TODO: find a better way
                    "C_IMG_WIDTH_IN": params["input_width"],
                    "C_IMG_HEIGHT_IN": params["input_height"],
                    "C_PE": params["pe"],
                    "C_SCALE": params["scale"],
                    "C_RELU": "".join(map(str, params["relu"])),
                    "C_LEAKY_RELU": "".join(map(str, params["leaky_relu"])),
                    "C_PAD": ", ".join(map(str, params["pad"])),
                    "C_CONV_KSIZE": ", ".join(map(str, params["conv_kernel"])),
                    "C_CONV_STRIDE": ", ".join(map(str, params["conv_stride"])),
                    "C_WIN_POOL": ", ".join(map(str, params["pool_kernel"])),
                    "C_POOL_STRIDE": ", ".join(map(str, params["pool_stride"])),
                    "C_CH": ", ".join(map(str, params["channel"])),
                    "C_BITWIDTH": bitwidth,
                    "C_STR_LENGTH": params["len_weights"],
                    "STR_WEIGHTS_INIT": ", ".join(weights),
                    "STR_BIAS_INIT": ", ".join(bias),
                    }
        tb_top.add_config(name=test_case, generics=generics,
                          pre_config=create_stimuli(join(
                              root, "src", test_case)))
        tb_top.set_attribute(".integration_test", None)


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
