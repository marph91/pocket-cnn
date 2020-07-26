"""Utility to convert ONNX weights in a format, which can be loaded
in the VHDL design at simulation and synthesis."""

import argparse
import math

import onnx
from onnx import numpy_helper

from weights_to_files import weights_to_files


def convert_weights(model: str, output_dir: str = "weights") -> None:
    """Extract weights from model, convert them into binary fixed point and
    save to file."""
    net = onnx.load(model)

    weights_dict = {}
    for init in net.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    last_layer_name = ""
    for node in net.graph.node:
        if node.op_type == "QLinearConv":
            # only convolution layers contain weights
            kernel = weights_dict[node.input[3]]
            bias = weights_dict[node.input[8]]

            layer_name = node.input[3][:16].zfill(16)
            if last_layer_name and len(last_layer_name) != len(layer_name):
                print("Warning: Layer names have different length. "
                      "Padding to 16 chars failed.")
            last_layer_name = layer_name
            bitwidth = (
                8 - int(math.log2(weights_dict[node.input[4]])),
                int(math.log2(weights_dict[node.input[4]]))
            )
            scale = weights_dict[node.input[4]]
            weights_to_files(kernel / scale, bias / scale,
                             bitwidth, layer_name, output_dir)


if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("model", help="Path to a .onnx model")
    PARSER.add_argument(
        "--output_dir", type=str, help="Output directory of weights")
    ARGS = PARSER.parse_args()

    convert_weights(ARGS.model, ARGS.output_dir)
