import os
from os.path import join, dirname

import numpy as np
import onnx
from vunit import VUnit

from fixfloat import v_float2fixedint

import cnn_onnx.inference
import cnn_onnx.model_zoo
import cnn_onnx.parse_param
import cnn_onnx.convert_weights
from cnn_reference import flatten
import vhdl_top_template


# somehow the onnx members aren't detected properly
# pylint: disable=no-member


def create_stimuli(root, model_name):
    model = onnx.load(join(root, model_name))
    shape = cnn_onnx.parse_param.get_input_shape(model)

    in_ = np.random.randint(256, size=shape)
    out_ = cnn_onnx.inference.numpy_inference(model, in_)

    np.savetxt(join(root, "input.csv"), flatten(in_),
               delimiter=", ", fmt="%3d")
    np.savetxt(join(root, "output.csv"), v_float2fixedint(out_, 4, 4),
               delimiter=", ", fmt="%3d")


def create_test_suite(ui):
    root = dirname(__file__)

    ui.add_array_util()
    integration_test = ui.add_library("integration_test", allow_duplicate=True)
    integration_test.add_source_files(join(root, "src", "tb_top.vhd"))
    tb_top = integration_test.entity("tb_top")

    test_cnns = [  # name in model zoo
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_leaky_relu,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_nonsquare_input,
        # cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_odd_input,  # TODO: needed?
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_colored_input,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_odd_channel,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_one_channel,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_padding,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x1, # TODO: fix (parallel)
        cnn_onnx.model_zoo.conv_3x1_1x1_max_3x1,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_3x3,
        cnn_onnx.model_zoo.conv_3x2_1x1_max_2x1,
        cnn_onnx.model_zoo.conv_2x1_1x1_max_3x2,
        cnn_onnx.model_zoo.conv_3x3_2x2_1x1,
        cnn_onnx.model_zoo.conv_4x3x1_1x1,
        cnn_onnx.model_zoo.conv_2x_3x1_1x1_max_2x2,
        cnn_onnx.model_zoo.conv_2x_3x1_1x1_max_2x2_padding,  # TODO: fix
        # cnn_onnx.model_zoo.conv_2x_3x1_1x1_max_2x2_mt  # TODO: fix
    ]
    for test_cnn in test_cnns:
        test_case_name = test_cnn.__name__
        test_case_root = join(root, "src", test_case_name)
        os.makedirs(test_case_root, exist_ok=True)

        # save arbitrary cnn model to file in onnx format
        model = test_cnn()
        onnx.save(model, join(test_case_root, "cnn_model.onnx"))

        # parse parameter
        params = cnn_onnx.parse_param.parse_param(
            join(test_case_root, "cnn_model.onnx"))
        # create some (redundant) dict entries
        params["weight_dir"] = join(test_case_root, "weights")
        params["len_weights"] = len("%s/W_%s.txt" % (
            params["weight_dir"], params["conv_names"][0]))

        # create toplevel wrapper for synthesis
        vhdl_top_template.vhdl_top_template(
            params, join(test_case_root, "top_wrapper.vhd"))

        # convert weights
        cnn_onnx.convert_weights.convert_weights(
            join(test_case_root, "cnn_model.onnx"),
            join(test_case_root, "weights"))

        # setup the test
        weights = ["%s/W_%s.txt" % (params["weight_dir"], name)
                   for name in params["conv_names"]]
        bias = ["%s/B_%s.txt" % (params["weight_dir"], name)
                for name in params["conv_names"]]
        assert len(weights[0]) == params["len_weights"]
        assert len(bias[0]) == params["len_weights"]

        bitwidth = "; ".join([", ".join(str(item) for item in inner)
                              for inner in params["bitwidth"]])

        generics = {
            "C_DATA_TOTAL_BITS": params["bitwidth"][0][0],
            "C_FOLDER": test_case_name,  # TODO: find a better way
            "C_IMG_WIDTH_IN": params["input_width"],
            "C_IMG_HEIGHT_IN": params["input_height"],
            "C_PE": params["pe"],
            "C_SCALE": params["scale"],
            "C_RELU": "".join(map(str, params["relu"])),
            "C_LEAKY_RELU": "".join(map(str, params["leaky_relu"])),
            "C_PAD": ", ".join(map(str, params["pad"])),
            "C_CONV_KSIZE": ", ".join(map(str, params["conv_kernel"])),
            "C_CONV_STRIDE": ", ".join(map(str, params["conv_stride"])),
            "C_POOL_KSIZE": ", ".join(map(str, params["pool_kernel"])),
            "C_POOL_STRIDE": ", ".join(map(str, params["pool_stride"])),
            "C_CH": ", ".join(map(str, params["channel"])),
            "C_BITWIDTH": bitwidth,
            "C_STR_LENGTH": params["len_weights"],
            "C_WEIGHTS_INIT": ", ".join(weights),
            "C_BIAS_INIT": ", ".join(bias),
        }
        tb_top.add_config(name=test_case_name, generics=generics,
                          pre_config=create_stimuli(
                              join(root, "src", test_case_name),
                              "cnn_model.onnx"))


if __name__ == "__main__":
    UI = VUnit.from_argv()
    create_test_suite(UI)
    UI.main()
