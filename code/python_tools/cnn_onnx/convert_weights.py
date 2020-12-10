"""Utility to convert ONNX weights in a format, which can be loaded
in the VHDL design at simulation and synthesis."""

import argparse
import math

import onnx
from onnx import numpy_helper

from common import InconsistencyError
from fp_helper import to_fixed_point_array
from weights_to_files import weights_to_files


def convert_weights(model: str, output_dir: str = "weights",
                    aggressive: bool = False) -> None:
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
                raise InconsistencyError(
                    f"Layer names have different length. "
                    f"{len(last_layer_name)} != {len(layer_name)}. "
                    f"Padding to 16 chars failed.")
            last_layer_name = layer_name

            int_bits = 8 - int(math.log2(weights_dict[node.input[4]]))
            frac_bits = int(math.log2(weights_dict[node.input[4]]))

            kernel = to_fixed_point_array(
                kernel, int_bits=int_bits, frac_bits=frac_bits,
                aggressive=aggressive)
            bias = to_fixed_point_array(
                bias, int_bits=int_bits, frac_bits=frac_bits,
                aggressive=aggressive)
            weights_to_files(kernel, bias, layer_name, output_dir)


if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("model", help="Path to a .onnx model")
    PARSER.add_argument(
        "--output-dir", type=str, help="Output directory of weights")
    ARGS = PARSER.parse_args()

    convert_weights(ARGS.model, ARGS.output_dir)
