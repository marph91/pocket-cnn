#!/usr/bin/env python3
import numpy as np
import argparse

import tools
import tools_common as common
from weights2files import weights2files

import models
import quant


def convert_weights(model, mem_init=""):
    """Extract weights from model, convert them into binary fixed point and
    save to file.
    """
    # create dir
    common.create_dir(mem_init + "/")

    # load the model
    net = tools.load_model(model)

    # extract data for every layer
    bitwidths = []
    for part in net.children():
        for layer in part.children():
            if isinstance(layer, quant.LinearQuant):
                if layer.bw_params and layer.fl_params:
                    bitwidths.append([layer.bw_params,
                                      layer.fl_params])

    state_dict = net.state_dict()
    bw_cnt = 0
    # alternatively: for name, param in self.named_parameters():
    for k, v in state_dict.items():
        if any(x in k for x in ["features", "classifier"]):
            if "weight" in k:
                data_bits = int(bitwidths[bw_cnt][0])
                frac_bits = int(bitwidths[bw_cnt][1])
                kernel = v.numpy()
                layer = "conv" + str(bw_cnt + 1)
            if "bias" in k:
                bias = v.numpy()
                bw_cnt += 1
                weights2files(kernel, bias, data_bits, frac_bits, layer,
                              mem_init)

if __name__ == "__main__":
    # pylint: disable=C0103
    parser = argparse.ArgumentParser(description="Classification with DIGITS")
    parser.add_argument("weights", help="Path to a file with cnn weights")
    parser.add_argument("net", help="Path to a file which describes the net")
    parser.add_argument(
        "--mem_init", type=str, help="Output directory of weights")
    args = parser.parse_args()

    # parse weights and net only for caffe compatibility
    convert_weights(args.weights, args.mem_init)
