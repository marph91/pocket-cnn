"""Calculate the inference of a CNN model in ONNX format with the self defined
functions."""

import math

import numpy as np
import onnx
from onnx import numpy_helper

import cnn_reference
from cnn_onnx import model_zoo, parse_param


def numpy_inference(onnx_model, input_):
    """Calculate the inference of a given input with a given model."""
    weights_dict = {}
    for init in onnx_model.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    next_input = input_
    first_layer = True  # first layer is unsigned
    for node in onnx_model.graph.node:
        params = parse_param.parse_node_attributes(node)

        if node.op_type == "Conv":
            assert False, "Layer not supported"
        elif node.op_type == "QLinearConv":
            pad = parse_param.get_pad(params)
            if pad:
                next_input = cnn_reference.zero_pad(next_input, pad)

            ksize, stride = parse_param.get_kernel_params(params)
            weights = weights_dict[node.input[3]]
            bias = weights_dict[node.input[8]]

            # bitwidths: int in, frac in, int out, frac out,
            #            int weights, frac weights
            bitwidth_next = (
                8 - int(math.log2(weights_dict[node.input[6]])),
                int(math.log2(weights_dict[node.input[6]])),
            )
            bitwidth = (
                8 + int(first_layer) -
                int(math.log2(weights_dict[node.input[1]])),
                int(math.log2(weights_dict[node.input[1]])),
                *bitwidth_next,
                8 - int(math.log2(weights_dict[node.input[4]])),
                int(math.log2(weights_dict[node.input[4]])),
            )

            next_input = cnn_reference.conv(
                next_input, weights, bias, (ksize, stride), bitwidth)
            first_layer = False
        elif node.op_type == "MaxPool":
            ksize, stride = parse_param.get_kernel_params(params)
            next_input = cnn_reference.max_pool(
                next_input, ksize, stride, bitwidth_next)
        elif node.op_type == "GlobalAveragePool":
            next_input = cnn_reference.avg_pool(next_input, bitwidth_next)
        elif node.op_type == "Relu":
            next_input = cnn_reference.relu(next_input, bitwidth_next)
        elif node.op_type == "LeakyRelu":
            next_input = cnn_reference.leaky_relu(
                next_input, 0.125, bitwidth_next)
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
