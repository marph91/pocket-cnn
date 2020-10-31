"""Utilities to parse data from an ONNX model."""

import argparse
import json
import math
from typing import List, Optional, Tuple
import warnings

import onnx
from onnx import numpy_helper

from common import CnnArchitectureError, InconsistencyError, NotSupportedError

# https://github.com/onnx/onnx/blob/master/onnx/onnx.proto
TYPE_TO_STR = {
    key + 1: val for key, val in enumerate([
        "f", "i", "s", "t", "g",
        "floats", "ints", "strings", "tensors", "graphs",
        ])
}


def parse_node_attributes(node) -> dict:
    """Parse the parameter of a specific node."""
    node_attr = {}
    for attribute in node.attribute:
        node_attr[attribute.name] = getattr(attribute,
                                            TYPE_TO_STR[attribute.type])
    return node_attr


def get_kernel_params(node_params: dict) -> Tuple[int, int]:
    """Obtain and validate the kernel parameter."""
    ksize = node_params["kernel_shape"][0]
    for ksize_ in node_params["kernel_shape"]:
        if ksize != ksize_:
            raise InconsistencyError(
                f"Kernel shapes don't fit. {ksize} != {ksize_}")
    stride = node_params["strides"][0]
    for stride_ in node_params["strides"]:
        if stride != stride_:
            raise InconsistencyError(
                f"Stride doesn't fit. {stride} != {stride_}")
    return ksize, stride


def get_pad(node_params: dict) -> int:
    """Obtain and validate the padding size."""
    pad = node_params["pads"][0]
    if pad not in [0, 1]:
        raise NotSupportedError(
            f"Only padding of 0 or 1 pixel is supported. Got {pad}.")
    for pad_ in node_params["pads"]:
        if pad != pad_:
            raise InconsistencyError(f"Padding doesn't fit. {pad} != {pad_}")
    return pad


def get_input_shape(net) -> list:
    """Obtain the input shape in a processable format."""
    return [s.dim_value for s in net.graph.input[0].type.tensor_type.shape.dim]


class ProcessingElement:
    """Represents a processing element (PE) in the hardware design.
    Each PE has to contain exactly one convolution with optional
    activation function and maximum pooling."""
    def __init__(self, param: dict) -> None:
        self.relu = 0
        self.leaky_relu = 0
        self.pool_param = (0, 0)
        self.param = param

    def set_activation(self, type_: str):
        """Set the activation function of the PE. Possible only once."""
        if self.relu != 0 or self.leaky_relu != 0:
            raise CnnArchitectureError("Relu can only be set once.")
        self.relu = 1
        if type_ == "LeakyRelu":
            self.leaky_relu = 1

    def set_max_pool(self, ksize: int, stride: int):
        """Set the maximum pooling parameter of the PE. Possible only once."""
        if self.pool_param != (0, 0):
            raise CnnArchitectureError("Pooling can only be set once.")
        self.pool_param = (ksize, stride)

    def get_param(self) -> dict:
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
    # pylint: disable=too-many-branches
    net = onnx.load(model)

    input_shape = get_input_shape(net)
    if input_shape[1] not in [1, 3]:
        raise NotSupportedError(
            f"Only one or three input channel supported. "
            f"Got {input_shape[1]}.")
    param_dict = {
        "channel": [input_shape[1]],
        "input_height": input_shape[2],
        "input_width": input_shape[3],
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
        params = parse_node_attributes(node)

        if node.op_type in ["QuantizeLinear", "DequantizeLinear"]:
            pass  # these layers are only used for ONNX internally
        elif node.op_type == "QLinearConv":
            if pelem:
                pes.append(pelem)

            conv_param = {
                "conv_names": node.input[3][:16].zfill(16),
                "conv_kernel": get_kernel_params(params)[0],
                "conv_stride": get_kernel_params(params)[1],
                "channel": weights_dict[node.input[3]].shape[0],
                "bitwidth": [  # data, frac in, frac out, weight, weight frac
                    8,
                    int(math.log2(weights_dict[node.input[1]])),
                    int(math.log2(weights_dict[node.input[6]])),
                    8,
                    int(math.log2(weights_dict[node.input[4]])),
                ],
                "pad": get_pad(params),
            }
            pelem = ProcessingElement(conv_param)
        elif node.op_type in ["AveragePool", "GlobalAveragePool"]:
            pes.append(pelem)
        elif node.op_type == "MaxPool":
            if pelem is None:
                raise CnnArchitectureError(
                    "Pooling can be only used inside a PE.")
            pelem.set_max_pool(*get_kernel_params(params))
        elif node.op_type in ["Relu", "LeakyRelu"]:
            if pelem is None:
                raise CnnArchitectureError(
                    "Relu can be only used inside a PE.")
            pelem.set_activation(node.op_type)
        else:
            warnings.warn(f"Unsupported layer {node.op_type} will be ignored.")

    # update param dict with data of all pes
    param_dict["pe"] = len(pes)
    for current_pe in pes:
        if current_pe is None:
            raise CnnArchitectureError("PE can't be empty.")
        for key, val in current_pe.get_param().items():
            param_dict[key].append(val)
    return param_dict


def main():
    """Main function to demonstrate the usage."""
    parser = argparse.ArgumentParser()
    parser.add_argument("model", type=str, help="Path to the model.")
    parser.add_argument("output_file", type=str,
                        help="Output directory and filename (json).")
    args = parser.parse_args()

    params = parse_param(args.model)
    with open(args.output_file, "w") as outfile:
        json.dump(params, outfile, indent=2)


if __name__ == "__main__":
    main()
