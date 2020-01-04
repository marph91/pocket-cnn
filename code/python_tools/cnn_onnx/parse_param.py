"""Utilities to parse data from an ONNX model."""

import argparse
import json
import math
from typing import List, Optional, Tuple

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


class ProcessingElement:
    """Represents a processing element (PE) in the hardware design.
    Each PE has to contain exactly one convolution with optional
    activation function and maximum pooling."""
    def __init__(self, param):
        self.relu = 0
        self.leaky_relu = 0
        self.pool_param = (0, 0)
        self.param = param

    def set_activation(self, type_):
        """Set the activation function of the PE. Possible only once."""
        assert self.relu == 0 and self.leaky_relu == 0
        self.relu = 1
        if type_ == "LeakyRelu":
            self.leaky_relu = 1

    def set_max_pool(self, ksize, stride):
        """Set the maximum pooling parameter of the PE. Possible only once."""
        assert self.pool_param == (0, 0)
        self.pool_param = (ksize, stride)

    def get_param(self):
        """Get all parameter of the PE as dict."""
        self.param.update({
            "relu": self.relu,
            "leaky_relu": self.leaky_relu,
            "pool_kernel": self.pool_param[0],
            "pool_stride": self.pool_param[1],
        })
        return self.param


def parse_param(model: str) -> dict:
    """Parse an ONNX model into a python dictionary."""
    net = onnx.load(model)

    input_shape = get_input_shape(net)
    assert input_shape[0] in [1, 3]
    param_dict = {
        "channel": [input_shape[0]],
        "input_height": input_shape[1],
        "input_width": input_shape[2],
        "relu": [],
        "leaky_relu": [],
        "pad": [],
        "conv_names": [],
        "conv_kernel": [],
        "conv_stride": [],
        "pool_kernel": [],
        "pool_stride": [],
        "bitwidth": [],
    }

    pes: List[Optional[ProcessingElement]] = []
    pelem: Optional[ProcessingElement] = None

    weights_dict = {}
    for init in net.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    for node in net.graph.node:
        params = parse_node_params(node)

        if node.op_type == "QuantizeLinear":
            param_dict["scale"] = int(weights_dict[node.input[1]])
        elif node.op_type == "QLinearConv":
            if pelem:
                pes.append(pelem)

            conv_param = {
                "conv_names": node.input[3].split("_", 1)[0],
                "conv_kernel": get_kernel_params(params)[0],
                "conv_stride": get_kernel_params(params)[1],
                "channel": weights_dict[node.input[3]].shape[0],
                "bitwidth": [  # data, frac in, frac out, weight, weight frac
                    8,
                    int(8 - math.log2(weights_dict[node.input[1]])),
                    int(8 - math.log2(weights_dict[node.input[6]])),
                    8,
                    int(8 - math.log2(weights_dict[node.input[4]])),
                ],
                "pad": get_pad(params),
            }
            pelem = ProcessingElement(conv_param)
        elif node.op_type == "GlobalAveragePool":
            pes.append(pelem)
        elif node.op_type == "MaxPool":
            assert pelem is not None
            pelem.set_max_pool(*get_kernel_params(params))
        elif node.op_type in ["Relu", "LeakyRelu"]:
            assert pelem is not None
            pelem.set_activation(node.op_type)
        else:
            raise ValueError(
                "Unknown or unsupported layer type %s" % node.op_type)

    # update param dict with data of all pes
    param_dict["pe"] = len(pes)
    for current_pe in pes:
        assert current_pe is not None
        for key, val in current_pe.get_param().items():
            param_dict[key].append(val)
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
