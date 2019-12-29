# https://github.com/onnx/onnx/blob/477a9b87715d614f8b7540a69c144b177275baa2/docs/PythonAPIOverview.md
# https://stackoverflow.com/questions/52402448/how-to-read-individual-layers-weight-bias-values-from-onnx-model

import math

import numpy as np
import onnx
from onnx import numpy_helper

import cnn_reference
import cnn_onnx.model_zoo


# somehow the onnx members aren't detected properly
# pylint: disable=no-member


def numpy_inference(onnx_model, input_):
    weights_dict = {}
    for init in onnx_model.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    next_input = input_
    for node in onnx_model.graph.node:
        params = {}
        for attribute in node.attribute:
            if attribute.name in ["strides", "pads", "kernel_shape"]:
                params[attribute.name] = attribute.ints
            else:
                params[attribute.name] = attribute.i

        def get_kernel_params(params):
            ksize = params["kernel_shape"][0]
            for ksize_ in params["kernel_shape"]:
                assert ksize == ksize_
            stride = params["strides"][0]
            for stride_ in params["strides"]:
                assert stride == stride_
            return ksize, stride

        if node.op_type == "Conv":
            assert False, "Layer not supported"
        elif node.op_type == "QLinearConv":
            pad = params["pads"][0]
            assert pad in [0, 1]
            for pad_ in params["pads"]:
                assert pad == pad_
            if pad == 1:
                next_input = cnn_reference.zero_pad(next_input)

            ksize, stride = get_kernel_params(params)
            weights = weights_dict[node.input[3]]
            bias = weights_dict[node.input[8]]

            frac_bits_out = int(math.log2(weights_dict[node.input[4]]))
            int_bits_out = 8 - frac_bits_out

            next_input = cnn_reference.conv(
                next_input, weights, bias, ksize, stride,
                int_bits_out, frac_bits_out)
        elif node.op_type == "QuantizeLinear":
            next_input = cnn_reference.scale(
                next_input, weights_dict[node.input[1]])
        elif node.op_type == "MaxPool":
            ksize, stride = get_kernel_params(params)
            next_input = cnn_reference.max_pool(next_input, ksize, stride)
        elif node.op_type == "GlobalAveragePool":
            next_input = cnn_reference.avg_pool(next_input)
        elif node.op_type == "Relu":
            next_input = cnn_reference.relu(next_input)
        elif node.op_type == "LeakyRelu":
            next_input = cnn_reference.leaky_relu(next_input, alpha=0.125)
    return next_input


if __name__ == "__main__":
    # save arbitrary cnn model to file in onnx format
    MODEL_DEF = cnn_onnx.model_zoo.cnn1()
    onnx.save(MODEL_DEF, MODEL_DEF.graph.name + ".onnx")

    # load model and calculate inference
    MODEL = onnx.load(MODEL_DEF.graph.name + ".onnx")
    onnx.checker.check_model(MODEL)
    # TODO: get input shape of the model
    OUTPUT = numpy_inference(
        MODEL, np.random.randint(256, size=(1, 6, 6)).astype(np.float))
