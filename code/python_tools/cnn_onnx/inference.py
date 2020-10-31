"""Calculate the inference of a CNN model in ONNX format with the self defined
functions."""

import math

from fpbinary import FpBinary
import numpy as np
import onnx
from onnx import numpy_helper

from common import NotSupportedError
import cnn_reference
from cnn_onnx import model_zoo, parse_param
from fp_helper import to_fixed_point_array


def numpy_inference(onnx_model, input_):
    """Calculate the inference of a given input with a given model."""
    weights_dict = {}
    for init in onnx_model.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    next_input = input_
    for node in onnx_model.graph.node:
        params = parse_param.parse_node_attributes(node)

        if node.op_type == "Conv":
            raise NotSupportedError(f"Layer {node.op_type} not supported.")
        if node.op_type == "QLinearConv":
            pad = parse_param.get_pad(params)
            if pad:
                next_input = cnn_reference.zero_pad(next_input, pad)

            ksize, stride = parse_param.get_kernel_params(params)

            int_bits_weights = 8 - int(math.log2(weights_dict[node.input[4]]))
            frac_bits_weights = int(math.log2(weights_dict[node.input[4]]))
            weights = to_fixed_point_array(
                weights_dict[node.input[3]], int_bits=int_bits_weights,
                frac_bits=frac_bits_weights)
            bias = to_fixed_point_array(
                weights_dict[node.input[8]], int_bits=int_bits_weights,
                frac_bits=frac_bits_weights)

            bitwidth_out = (
                8 - int(math.log2(weights_dict[node.input[6]])),
                int(math.log2(weights_dict[node.input[6]])),
            )
            next_input = cnn_reference.conv(
                next_input, weights, bias, (ksize, stride), bitwidth_out)
        elif node.op_type == "MaxPool":
            ksize, stride = parse_param.get_kernel_params(params)
            next_input = cnn_reference.max_pool(next_input, ksize, stride)
        elif node.op_type == "GlobalAveragePool":
            next_input = cnn_reference.avg_pool(next_input)
        elif node.op_type == "Relu":
            next_input = cnn_reference.relu(next_input)
        elif node.op_type == "LeakyRelu":
            next_input = cnn_reference.leaky_relu(
                next_input, FpBinary(int_bits=0, frac_bits=3, value=0.125))
    return next_input


if __name__ == "__main__":
    # save arbitrary cnn model to file in onnx format
    MODEL_DEF = model_zoo.conv_3x1_1x1_max_2x2()
    onnx.save(MODEL_DEF, MODEL_DEF.graph.name + ".onnx")

    # load model and calculate inference
    MODEL = onnx.load(MODEL_DEF.graph.name + ".onnx")
    onnx.checker.check_model(MODEL)
    SHAPE = parse_param.parse_param(MODEL)
    OUTPUT = numpy_inference(
        MODEL, np.random.randint(256, size=SHAPE).astype(np.uint8))
