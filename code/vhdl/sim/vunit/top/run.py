"""Run the testbench of the "top" module."""

import itertools
import os
from os.path import join, dirname

import numpy as np
import onnx
# import onnxruntime as rt

from common import InconsistencyError
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

    # ONNX runtime prediction, TODO: doesn't work right now
    # https://github.com/microsoft/onnxruntime/issues/2964
    # sess = rt.InferenceSession(join(root, model_name))
    # input_name = sess.get_inputs()[0].name
    # pred_onnx = sess.run(None, {input_name: in_.astype(np.float32)})[0]
    # print(pred_onnx)

    np.savetxt(join(root, "input.csv"), flatten(a_in),
               delimiter=", ", fmt="%3d")
    np.savetxt(join(root, "output.csv"), a_out,
               delimiter=", ", fmt="%3d")


def create_test_suite(test_lib):
    root = dirname(__file__)

    tb_top = test_lib.entity("tb_top")

    # TODO: fix the failing models
    test_cnns = (  # name in model zoo
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_leaky_relu,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_no_relu,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_nonsquare_input,
        # cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_odd_input,  # TODO: needed?
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_colored_input,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_odd_channel,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_one_channel,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_2x2_padding,
        # cnn_onnx.model_zoo.conv_3x1_1x1_max_2x1,
        # cnn_onnx.model_zoo.conv_3x1_1x1_max_3x1,
        cnn_onnx.model_zoo.conv_3x1_1x1_max_3x3,
        cnn_onnx.model_zoo.conv_3x2_1x1_max_2x1,
        # cnn_onnx.model_zoo.conv_3x2_1x1_max_2x1_padding,
        cnn_onnx.model_zoo.conv_2x1_1x1_max_3x2,
        cnn_onnx.model_zoo.conv_3x3_2x2_1x1,
        cnn_onnx.model_zoo.conv_5x1_1x1_max_2x2,
        cnn_onnx.model_zoo.conv_4x3x1_1x1,
        cnn_onnx.model_zoo.conv_2x_3x1_1x1_max_2x2,
        # cnn_onnx.model_zoo.conv_2x_3x1_1x1_max_2x2_padding,
        # cnn_onnx.model_zoo.conv_2x_3x1_1x1_max_2x2_mt
    )
    for test_cnn, para_full in itertools.product(test_cnns, (0, 1)):
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
        if len(weights[0]) != params["len_weights"]:
            raise InconsistencyError(
                f"Size of weights doesn't fit. "
                f"{len(weights[0])} != {params['len_weights']}.")
        if len(bias[0]) != params["len_weights"]:
            raise InconsistencyError(
                f"Size of bias doesn't fit. "
                f"{len(bias[0])} != {params['len_weights']}.")

        bitwidth = "; ".join([", ".join(str(item) for item in inner)
                              for inner in params["bitwidth"]])

        # parallelization is always corresponding to input channels
        para_per_pe = [str(ch * para_full + 1 - para_full)
                       for ch in params["channel"][:-1]]

        generics = {
            "C_DATA_TOTAL_BITS": params["bitwidth"][0][0],
            "C_FOLDER": test_case_name,  # TODO: find a better way
            "C_IMG_WIDTH_IN": params["input_width"],
            "C_IMG_HEIGHT_IN": params["input_height"],
            "C_PE": params["pe"],
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
            "C_PARALLEL_CH": ", ".join(para_per_pe),
        }
        tb_top.add_config(name=test_case_name + "_para_full" * para_full,
                          generics=generics,
                          pre_config=create_stimuli(
                              join(root, "src", test_case_name),
                              "cnn_model.onnx"))

        # add an extra parallelization test for the baseline model
        if test_case_name == "conv_3x1_1x1_max_2x2" and para_full == 0:
            generics["C_PARALLEL_CH"] = "1, 2"
            tb_top.add_config(
                name=test_case_name + "_para_half",
                generics=generics,
                pre_config=create_stimuli(
                    join(root, "src", test_case_name), "cnn_model.onnx"))
