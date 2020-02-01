"""Utility to convert ONNX weights in a format, which can be loaded
in the VHDL design at simulation and synthesis."""

import argparse
import math

import onnx
from onnx import numpy_helper

from weights2files import weights2files
from fixfloat import v_fixedint2ffloat


# somehow the onnx members aren't detected properly
# pylint: disable=no-member


def convert_weights(model: str, output_dir: str = "weights") -> None:
    """Extract weights from model, convert them into binary fixed point and
    save to file."""
    net = onnx.load(model)

    weights_dict = {}
    for init in net.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    for node in net.graph.node:
        if node.op_type == "QLinearConv":
            # only convolution layers contain weights
            kernel = weights_dict[node.input[3]]
            bias = weights_dict[node.input[8]]

            layer_name = node.input[3].split("_", 1)[0]
            bitwidth = (
                8 - int(math.log2(weights_dict[node.input[4]])),
                int(math.log2(weights_dict[node.input[4]]))
            )
            kernel_flt = v_fixedint2ffloat(kernel, *bitwidth)
            bias_flt = v_fixedint2ffloat(bias, *bitwidth)
            weights2files(kernel_flt, bias_flt,
                          bitwidth, layer_name, output_dir)


if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("model", help="Path to a .onnx model")
    PARSER.add_argument(
        "--output_dir", type=str, help="Output directory of weights")
    ARGS = PARSER.parse_args()

    convert_weights(ARGS.model, ARGS.output_dir)
