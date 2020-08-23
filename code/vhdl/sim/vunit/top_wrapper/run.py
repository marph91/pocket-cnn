"""Run the testbench of the "top_wrapper"."""

import os
from os.path import join, dirname

import numpy as np
import onnx

import cnn_onnx.inference
import cnn_onnx.model_zoo
import cnn_onnx.parse_param
import cnn_onnx.convert_weights
from cnn_reference import flatten
from fp_helper import random_fixed_array, v_to_fixedint, Bitwidth
import vhdl_top_template


def create_stimuli(root, model_name):
    model = onnx.load(join(root, model_name))
    shape = cnn_onnx.parse_param.get_input_shape(model)

    a_rand = random_fixed_array(shape, Bitwidth(8, 8, 0), signed=False)
    a_in = v_to_fixedint(a_rand)
    a_out = v_to_fixedint(cnn_onnx.inference.numpy_inference(model, a_rand))

    np.savetxt(join(root, "input.csv"), flatten(a_in),
               delimiter=", ", fmt="%3d")
    np.savetxt(join(root, "output.csv"), a_out, delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_top_wrapper = test_lib.entity("tb_top_wrapper")

    test_cnns = [  # name in model zoo
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2,
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

        # TODO: This doesn't work with multiple CNN. Create one
        #       CNN architecture with a variety of layers/features.
        test_lib.add_source_files(
            join(test_case_root, "top_wrapper.vhd"))

        # convert weights
        cnn_onnx.convert_weights.convert_weights(
            join(test_case_root, "cnn_model.onnx"),
            join(test_case_root, "weights"))

        # setup the test
        generics = {
            "C_FOLDER": test_case_name,  # TODO: find a better way
            "C_IMG_WIDTH_IN": params["input_width"],
            "C_IMG_HEIGHT_IN": params["input_height"],
            "C_IMG_DEPTH_IN": params["channel"][0],
            "C_CLASSES": params["channel"][-1],
        }
        tb_top_wrapper.add_config(name=test_case_name, generics=generics,
                                  pre_config=create_stimuli(
                                      join(root, "src", test_case_name),
                                      "cnn_model.onnx"))
