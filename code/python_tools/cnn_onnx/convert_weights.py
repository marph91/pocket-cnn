#!/usr/bin/env python3
import argparse
import math

import onnx
from onnx import numpy_helper
from weights2files import weights2files


# somehow the onnx members aren't detected properly
# pylint: disable=no-member


def convert_weights(model: str, output_dir: str="weights") -> None:
    """Extract weights from model, convert them into binary fixed point and
    save to file.
    """
    net = onnx.load(model)

    weights_dict = {}
    for init in net.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)

    for node in net.graph.node:
        if node.op_type == "QLinearConv":
            # only convolution layers contain weights
            kernel = weights_dict[node.input[3]]
            bias = weights_dict[node.input[8]]

            layer = node.input[3].split("_", 1)[0]
            data_bits = 8
            frac_bits = int(
                data_bits - math.log2(weights_dict[node.input[4]]))

            weights2files(kernel, bias, data_bits, frac_bits, layer,
                          output_dir)


if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("model", help="Path to a .onnx model")
    PARSER.add_argument(
        "--output_dir", type=str, help="Output directory of weights")
    ARGS = PARSER.parse_args()

    convert_weights(ARGS.model, ARGS.output_dir)
