#!/usr/bin/env python3
import argparse
import quant
import torch
import torch.nn as nn
import torch.nn.functional as F
from collections import OrderedDict

import tools
import tools_common as common


def quantize_net(net, n_sample, param_bits, bn_bits, fwd_bits, overflow_rate):
    # quantize parameters
    bw_param = []
    if param_bits < 32:
        state_dict = net.state_dict()
        state_dict_quant = OrderedDict()
        for k, v in state_dict.items():
            if "running" in k:
                if bn_bits >= 32:
                    print("Ignoring {}".format(k))
                    state_dict_quant[k] = v
                    continue
                else:
                    bits = bn_bits
            else:
                bits = param_bits

            if "weight" in k:
                # apply the same quantization for weights and bias
                # TODO: take also bias in account for computing integral part
                # limit fractional width to bits - 1 (sign)
                sf = bits - 1 - quant.compute_integral_part(
                    v, overflow_rate=overflow_rate)
                sf = max(0, min(bits-1, sf))
                bw_param.append([bits, sf])

            # print(sf, k, frac)
            v_quant = quant.linear_quantize(v, sf, bits=bits)
            state_dict_quant[k] = v_quant
        net.load_state_dict(state_dict_quant)
    # print(bw_param)

    # quantize activation
    if fwd_bits < 32:
        net = quant.duplicate_model_with_quant(
            net, bw_param, bits=fwd_bits, overflow_rate=overflow_rate,
            counter=n_sample)

        # remove unnecessary quant layer (only need one at begin)
        net.classifier = nn.Sequential(*list(net.classifier.children())[1:])

        # run quantization for n_sample to find good fixed point representation
        for _ in range(n_sample):
            # TODO: forward different images to get better sf values
            tools.forward_image(net, "../../../test_images/adam_s_000725.png")
            tools.forward_image(net, "../../../test_images/bed_s_000009.png")

        # set bitwidth of last layer manually (else it would be different)
        # -> this is caused by caffe compatibility
        net.classifier[-1].fl_layer = net.classifier[-4].fl_layer

    # print(net)
    return net


if __name__ == "__main__":
    tools.detect_device()
    tools.set_fractional_digits(8)

    parser = argparse.ArgumentParser()
    # parser.add_argument(
    #     '--model_root', default='~/.torch/models/',
    #     help='folder to save the model')
    # parser.add_argument(
    #     '--data_root', default='/tmp/public_dataset/pytorch/',
    #     help='folder to save the model')
    parser.add_argument(
        '--n_sample', type=int, default=200,
        help='number of samples to infer the scaling factor')
    parser.add_argument(
        '--param_bits', type=int, default=8, help='bit-width for parameters')
    parser.add_argument(
        '--bn_bits', type=int, default=32, help='bit-width for batchnorm')
    parser.add_argument(
        '--fwd_bits', type=int, default=8, help='bit-width for layer output')
    parser.add_argument(
        '--overflow_rate', type=float, default=0.0, help='overflow rate')
    args = parser.parse_args()

    common.print_args(args)
    net = tools.load_model("data/train.pt")
    net = quantize_net(net, args.n_sample, args.param_bits, args.bn_bits,
                       args.fwd_bits, args.overflow_rate)
    tools.save_model(net, "data/quant.pt")

    net = net.eval()
    a = tools.forward_image(net, "../../../test_images/adam_s_000725.png")
