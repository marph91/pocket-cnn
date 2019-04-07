#!/usr/bin/env python3

import argparse

import torch.nn as nn

import cnn_pytorch.tools as tools
from vhdl_top_template import vhdl_top_template


def parse_param(net_file):
    """Parse pytorch net description and return parameter."""
    net = tools.load_model(net_file)

    relu, leaky_relu = [], []
    pad = []
    conv_names, conv_kernel, conv_stride = [], [], []
    pool_kernel, pool_stride = [], []
    bitwidth = []

    channel = [net.features[1].in_channels]
    input_height = 32  # TODO: parse
    input_width = 32  # TODO: parse
    scale = 2**7  # TODO: parse

    last_fl_layer = None
    not_relu = False
    not_pool = False
    for part in net.children():
        layers = list(part.children())
        # first layer must be quantization layer
        if not last_fl_layer: last_fl_layer = layers[0].fl_layer
        for i, layer in enumerate(layers):
            if isinstance(layer, nn.Conv2d):
                channel.append(layer.out_channels)
                conv_kernel.append(layer.kernel_size[0])
                conv_names.append("conv%d" % (len(conv_kernel)))
                conv_stride.append(layer.stride[0])
                pad.append(layer.padding[0])
                # quant layer must follow after conv layer
                # so quant doesn't have to be imported in this module
                q_layer = layers[i+1]
                bitwidth.append([q_layer.bw_layer, last_fl_layer,
                                 q_layer.fl_layer, q_layer.bw_params,
                                 q_layer.fl_params])
                last_fl_layer = q_layer.fl_layer
                if not_relu:
                    relu.append(0)
                    leaky_relu.append(0)
                if not_pool:
                    pool_kernel.append(0)
                    pool_stride.append(0)
                not_relu = True
                not_pool = True
            elif isinstance(layer, nn.ReLU):
                relu.append(1)
                leaky_relu.append(0)
                not_relu = False
            elif isinstance(layer, nn.MaxPool2d):
                pool_kernel.append(layer.kernel_size)
                pool_stride.append(layer.stride)
                not_pool = False

    if not_relu:
        relu.append(0)
        leaky_relu.append(0)
    if not_pool:
        pool_kernel.append(0)
        pool_stride.append(0)

    param_dict = {
        "input_height": input_height,
        "input_width": input_width,
        "scale": scale,
        "relu": relu,
        "leaky_relu": leaky_relu,
        "pad": pad,
        "channel": channel,
        "conv_names": conv_names,
        "conv_kernel": conv_kernel,
        "conv_stride": conv_stride,
        "pool_kernel": pool_kernel,
        "pool_stride": pool_stride,
        "bitwidth": [[int(bw) for bw in l] for l in bitwidth],
        "pe": len(conv_kernel)
        }
    return param_dict

if __name__ == "__main__":
    # pylint: disable=C0103
    parser = argparse.ArgumentParser()
    parser.add_argument("net_file", type=str, help="Path to deploy file")
    parser.add_argument("weight_dir", type=str, help="Directory of weights")
    parser.add_argument("param_file", type=str,
                        help="Output directory and filename of toplevel")
    args = parser.parse_args()

    param_dict = parse_param(args.net_file)
    vhdl_top_template(param_dict, args.weight_dir, args.param_file)
