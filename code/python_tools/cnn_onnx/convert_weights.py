#!/usr/bin/env python3
import argparse
import math

import onnx
from onnx import numpy_helper
import tools_common as common
from weights2files import weights2files


# somehow the onnx members aren't detected properly
# pylint: disable=no-member


def convert_weights(model, mem_init=""):
    """Extract weights from model, convert them into binary fixed point and
    save to file.
    """
    # create dir
    common.create_dir(mem_init + "/")

    # load the model
    net = onnx.load(model)

    weights_dict = {}
    for init in net.graph.initializer:
        weights_dict[init.name] = numpy_helper.to_array(init)
    # TODO: similar to inference
    # extract data for every layer
    for node in net.graph.node:
        if node.op_type == "Conv":
            assert False, "Layer not supported"
        elif node.op_type == "QLinearConv":
            kernel = weights_dict[node.input[3]]
            bias = weights_dict[node.input[8]]

            layer = node.input[3].split("_", 1)[0]
            data_bits = 8
            frac_bits = int(8 - math.log2(weights_dict[node.input[4]]))

            weights2files(kernel, bias, data_bits, frac_bits, layer,
                          mem_init)


if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("model", help="Path to a .onnx model")
    PARSER.add_argument(
        "--mem_init", type=str, help="Output directory of weights")
    ARGS = PARSER.parse_args()

    convert_weights(ARGS.model, ARGS.mem_init)
