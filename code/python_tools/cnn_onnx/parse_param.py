"""Utilities to parse data from an ONNX model."""

import argparse
import json
import math
from typing import List, Tuple

import onnx
from onnx import numpy_helper

from vhdl_top_template import vhdl_top_template


# somehow the onnx members aren't detected properly
# pylint: disable=no-member


def parse_node_params(node) -> dict:
    """Parse the parameter of a specific node."""
    params = {}
    for attribute in node.attribute:
        if attribute.name in ["strides", "pads", "kernel_shape"]:
            params[attribute.name] = attribute.ints
        else:
            params[attribute.name] = attribute.i
    return params


def get_kernel_params(node_params: dict) -> Tuple[int, int]:
    """Obtain and validate the kernel parameter."""
    ksize = node_params["kernel_shape"][0]
    for ksize_ in node_params["kernel_shape"]:
        assert ksize == ksize_
    stride = node_params["strides"][0]
    for stride_ in node_params["strides"]:
        assert stride == stride_
    return ksize, stride


def get_pad(node_params: dict) -> int:
    """Obtain and validate the padding size."""
    pad = node_params["pads"][0]
    assert pad in [0, 1]
    for pad_ in node_params["pads"]:
        assert pad == pad_
    return pad


def get_input_shape(net) -> list:
    """Obtain the input shape in a processable format."""
    return [s.dim_value for s in net.graph.input[0].type.tensor_type.shape.dim]


def parse_param(model: str) -> dict:
    """Parse an ONNX model into a python dictionary."""
    net = onnx.load(model)

    relu: List[int] = []
    leaky_relu: List[int] = []
    padding: List[int] = []
    conv_names: List[str] = []
    conv_kernel: List[int] = []
    conv_stride: List[int] = []
    pool_kernel: List[int] = []
    pool_stride: List[int] = []
    bitwidth: List[List[int]] = []
    channel: List[int] = []

    weights_dict = {}
    for init in net.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    pool_possible = False  # TODO: improve check for missing maxpool

    nodes = net.graph.node
    for node in nodes:
        params = parse_node_params(node)

        if node.op_type == "QuantizeLinear":
            scale = int(weights_dict[node.input[1]])
        elif node.op_type == "Conv":
            assert False, "Layer not supported"
        elif node.op_type == "QLinearConv":
            pad = get_pad(params)
            padding.append(pad)

            conv_names.append(node.input[3].split("_", 1)[0])

            data_bits = 8
            frac_bits_in, frac_bits_out = (
                int(data_bits - math.log2(weights_dict[node.input[1]])),
                int(data_bits - math.log2(weights_dict[node.input[6]])))
            data_bits_weights = 8
            frac_bits_weights = (
                int(data_bits - math.log2(weights_dict[node.input[4]])))
            bitwidth.append([data_bits, frac_bits_in, frac_bits_out,
                             data_bits_weights, frac_bits_weights])

            shape = weights_dict[node.input[3]].shape
            if not channel:
                # first input channel
                assert shape[1] in [1, 3]
                channel.append(shape[1])
            channel.append(shape[0])

            if pool_possible:
                assert len(pool_kernel) == len(conv_kernel) - 1, \
                    "%d %d" % (len(pool_kernel), len(conv_kernel))
                assert len(pool_stride) == len(conv_stride) - 1, \
                    "%d %d" % (len(pool_stride), len(conv_stride))
                pool_kernel.append(0)
                pool_stride.append(0)
            else:
                pool_possible = True
            ksize, stride = get_kernel_params(params)
            conv_kernel.append(ksize)
            conv_stride.append(stride)
        elif node.op_type == "GlobalAveragePool":
            if pool_possible and len(pool_kernel) != len(conv_kernel):
                assert len(pool_kernel) == len(conv_kernel) - 1
                assert len(pool_stride) == len(conv_stride) - 1
                pool_kernel.append(0)
                pool_stride.append(0)
            pool_possible = False
        elif node.op_type == "MaxPool":
            ksize, stride = get_kernel_params(params)
            pool_kernel.append(ksize)
            pool_stride.append(stride)
            pool_possible = False
        elif node.op_type == "Relu":
            # TODO: after every Conv layer an activation layer is expected
            relu.append(1)
            leaky_relu.append(0)
        elif node.op_type == "LeakyRelu":
            relu.append(1)
            leaky_relu.append(1)

    # pe == number of conv layers
    pelem = len(conv_kernel)
    _, input_height, input_width = get_input_shape(net)
    param_dict = {
        "channel": channel,
        "input_height": input_height,
        "input_width": input_width,
        "scale": scale,
        "relu": relu,
        "leaky_relu": leaky_relu,
        "pad": padding,
        "conv_names": conv_names,
        "conv_kernel": conv_kernel,
        "conv_stride": conv_stride,
        "pool_kernel": pool_kernel,
        "pool_stride": pool_stride,
        "bitwidth": bitwidth,
        "pe": pelem}
    return param_dict


if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("model", type=str, help="Path to the model")
    PARSER.add_argument("weight_dir", type=str, help="Directory of weights")
    PARSER.add_argument("output_file", type=str,
                        help="Output directory and filename of toplevel")
    ARGS = PARSER.parse_args()

    PARAMS = parse_param(ARGS.model)
    # create some (redundant) dict entries
    PARAMS["weight_dir"] = ARGS.weight_dir
    PARAMS["len_weights"] = len("%s/W_%s.txt" % (
        PARAMS["weight_dir"], PARAMS["conv_names"][0]))
    vhdl_top_template(PARAMS, ARGS.output_file)

    with open("cnn_parameter.json", "w") as outfile:
        json.dump(PARAMS, outfile, indent=2)
