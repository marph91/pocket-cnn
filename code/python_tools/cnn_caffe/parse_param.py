#!/usr/bin/env python3

import argparse
import math
import ast

from google.protobuf import text_format
from caffe.proto import caffe_pb2

import cnn_caffe.tools as tools
from vhdl_top_template import vhdl_top_template


def check_pool(net, pool_kernel, pool_stride, index):
    if net.layer[index].type == "Pooling":
        if net.layer[index].pooling_param.pool == 0:
            # pooling_param.pool: 0 - max, 1 average
            pool_kernel.append(
                net.layer[index].pooling_param.kernel_size)
            if net.layer[index].pooling_param.stride:
                pool_stride.append(
                    net.layer[index].pooling_param.stride)
            else:
                pool_stride.append(1)


def parse_param(deploy_file):
    # pylint: disable=E1101
    # open caffe prototxt file and parse parameter
    net = caffe_pb2.NetParameter()
    with open(deploy_file) as infile:
        text_format.Merge(infile.read(), net)

    if net.input_shape:
        if net.input_shape[0].dim[0] != 1:
            print("Warning: Batch size should be 1 (single image forwarding)")
        channel = [net.input_shape[0].dim[1]]
        input_height = net.input_shape[0].dim[2]
        input_width = net.input_shape[0].dim[3]
    else:
        if net.layer[0].input_param.shape[0].dim[0] != 1:
            print("Warning: Batch size should be 1 (single image forwarding)")
        channel = [net.layer[0].input_param.shape[0].dim[1]]
        input_height = net.layer[0].input_param.shape[0].dim[2]
        input_width = net.layer[0].input_param.shape[0].dim[3]

    if net.layer[0].type == "Power":
        scale = int(1/net.layer[0].power_param.scale)
    elif net.layer[1].type == "Power":
        scale = int(1/net.layer[1].power_param.scale)
    else:
        print("Warning: No Power layer found")

    if not math.log(scale, 2).is_integer():
        print("Warning: Just scaling with 2^-x values supported")

    # maximum input value for 8 bit is 2**8 / scale
    max_val_scale = 2**8 / scale

    # get first conv layer for checking input integer widths
    for i, layer in enumerate(net.layer):
        if layer.type == "ConvolutionRistretto":
            max_val_in = 2**(layer.quantization_param.bw_layer_in - 1 -
                             2**-layer.quantization_param.fl_layer_in -
                             layer.quantization_param.fl_layer_in)
            break

    # input: 8 bit gray -> max=256, scaling: 1/64 -> max = 4
    if max_val_scale > max_val_in:
        print("Warning: Scaling factor is in conflict with input integer width"
              " (number could be still too big after scaling)")

    relu, leaky_relu = [], []
    pad = []
    conv_names, conv_kernel, conv_stride = [], [], []
    pool_kernel, pool_stride = [], []
    bitwidth = []

    for i, layer in enumerate(net.layer):
        if layer.type == "Convolution":
            print("Warning: Layer should be ConvolutionRistretto instead of "
                  "Convolution")
        elif layer.type == "ConvolutionRistretto":
            # padding
            if layer.convolution_param.pad:
                if layer.convolution_param.pad[0] == 1:
                    pad.append(layer.convolution_param.pad[0])
                else:
                    print("Warning: Only padding of 1 supported")
            else:
                pad.append(0)

            # convolution
            conv_names.append(layer.name)
            channel.append(layer.convolution_param.num_output)
            conv_kernel.append(layer.convolution_param.kernel_size[0])
            if layer.convolution_param.stride:
                conv_stride.append(layer.convolution_param.stride[0])
            else:
                conv_stride.append(1)

            # convolution bitwidth
            bitwidth_tmp = []
            bitwidth_tmp.append(layer.quantization_param.bw_layer_in)
            # bw_layer_out == bw_layer_in, so its redundant
            bitwidth_tmp.append(layer.quantization_param.fl_layer_in)
            bitwidth_tmp.append(layer.quantization_param.fl_layer_out)
            bitwidth_tmp.append(layer.quantization_param.bw_params)
            bitwidth_tmp.append(layer.quantization_param.fl_params)
            if bitwidth:
                if bitwidth[-1][2] != bitwidth_tmp[1]:
                    print("Warning: int_width and frac_width shouldnt change "
                          "between conv layers")
            bitwidth.append(bitwidth_tmp)

            # relu and pooling
            if net.layer[i+1].type == "ReLU":
                relu.append(1)
                if net.layer[i+1].relu_param.negative_slope == 0.125:
                    leaky_relu.append(1)
                elif net.layer[i+1].relu_param.negative_slope != 0:
                    print("Warning: LeakyReLU should have slope of -0.125")
                else:
                    leaky_relu.append(0)
                check_pool(net, pool_kernel, pool_stride, i+2)
            elif (net.layer[i+1].type == "Python" and
                  net.layer[i+1].python_param.layer == "QuantizedRelu"):
                relu.append(1)
                # use ast instead of dict, because it's an string to parse
                neg_slope = ast.literal_eval(
                    net.layer[i+1].python_param.param_str)["negative_slope"]
                if neg_slope == 0.125:
                    leaky_relu.append(1)
                elif neg_slope != 0:
                    print("Warning: LeakyReLU should have slope of -0.125")
                else:
                    leaky_relu.append(0)
                check_pool(net, pool_kernel, pool_stride, i+2)
            else:
                relu.append(0)
                check_pool(net, pool_kernel, pool_stride, i+1)
            if len(conv_kernel) > len(pool_kernel):
                pool_kernel.append(0)
            if len(conv_stride) > len(pool_stride):
                pool_stride.append(0)

            # check if fractional bitwidths fit in the constraints
            if bitwidth_tmp[0] <= bitwidth_tmp[1] or \
                    bitwidth_tmp[0] <= bitwidth_tmp[2] or \
                    bitwidth_tmp[3] <= bitwidth_tmp[4]:
                print("Warning: fractional width is equal bitwidth "
                      "-> no sign bit at layer %d" % (i))
            if bitwidth_tmp[1] < 0 or \
                    bitwidth_tmp[2] < 0 or \
                    bitwidth_tmp[4] < 0:
                print("Warning: fractional width < 0 not supported "
                      "(layer %d)" % (i))

    # check fractional width of last layer
    if bitwidth[-1][2] < 2:
        print("Warning: Output accuracy may be too low (currently %d bits -> "
            "2^-bits/2 = %d)" % (bitwidth[-1][2], 2**-bitwidth[-1][2]/2.0))

    # last layers (global average pooling and softmax)
    if (net.layer[-2].type != "Pooling" and
            net.layer[-2].python_param.layer !=
            "QuantizedAveragePooling"):
        print("Warning: Second last layer should be an average pooling layer")
    if net.layer[-1].type != "Softmax":
        print("Warning: Last layer should be a softmax layer")

    # pe == number of conv layers
    pe = len(conv_kernel)
    param_dict = {
        "channel": channel,
        "input_height": input_height,
        "input_width": input_width,
        "scale": scale,
        "relu": relu,
        "leaky_relu": leaky_relu,
        "pad": pad,
        "conv_names": conv_names,
        "conv_kernel": conv_kernel,
        "conv_stride": conv_stride,
        "pool_kernel": pool_kernel,
        "pool_stride": pool_stride,
        "bitwidth": bitwidth,
        "pe": pe}
    return param_dict

if __name__ == "__main__":
    # pylint: disable=C0103
    parser = argparse.ArgumentParser()
    parser.add_argument("train_file", type=str, help="Path to deploy file")
    parser.add_argument("weight_dir", type=str, help="Directory of weights")
    parser.add_argument("param_file", type=str,
                        help="Output directory and filename of toplevel")
    args = parser.parse_args()

    deploy_file = tools.deploy_filename(args.train_file)
    tools.train2deploy(args.train_file, deploy_file)

    param_dict = parse_param(deploy_file)
    vhdl_top_template(param_dict, args.weight_dir, args.param_file)
