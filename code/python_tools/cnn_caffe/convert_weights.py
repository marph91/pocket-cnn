#!/usr/bin/env python3
import argparse

import cnn_caffe.tools as tools
import tools_common as common
from weights2files import weights2files


def convert_weights(caffemodel, deploy_file, mem_init=""):
    """Extract weights from model, convert them into binary fixed point and
    save to file.
    """
    # create dir
    common.create_dir(mem_init + "/")

    # load the model
    net = tools.get_net(caffemodel, deploy_file)

    # pylint: disable=E1101
    # load the quantization parameters (from ristretto)
    net_quant = tools.load_net(deploy_file)

    # extract data for every layer
    for layer in net.params:
        # get properties of layer
        kernel = net.params[layer][0].data
        bias = net.params[layer][1].data

        # get the quantization parameter of the layers weights
        index = 0
        while layer != net_quant.layer[index].name:
            index += 1

        if net_quant.layer[index].quantization_param.precision == 0:
            data_bits = net_quant.layer[index].quantization_param.bw_params
            frac_bits = net_quant.layer[index].quantization_param.fl_params
        else:
            print("Error: quantization type not supported")
            return

        weights2files(kernel, bias, data_bits, frac_bits, layer,
                      mem_init)

if __name__ == "__main__":
    # pylint: disable=C0103
    parser = argparse.ArgumentParser(description="Classification with DIGITS")
    parser.add_argument("caffemodel", help="Path to a .caffemodel")
    parser.add_argument("train_file", help="Path to the deploy file")
    parser.add_argument(
        "--mem_init", type=str, help="Output directory of weights")
    args = parser.parse_args()

    deploy_file = tools.deploy_filename(args.train_file)
    tools.train2deploy(args.train_file, deploy_file)

    convert_weights(args.caffemodel, deploy_file, args.mem_init)
