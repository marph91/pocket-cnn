from torch.autograd import Variable
import torch
from torch import nn
from collections import OrderedDict
import math

from fixfloat import float2ffloat
import numpy as np


def compute_integral_part(input, overflow_rate):
    abs_value = input.abs().view(-1)
    sorted_value = abs_value.sort(dim=0, descending=True)[0]
    split_idx = int(overflow_rate * len(sorted_value))
    v = sorted_value[split_idx]
    if isinstance(v, Variable):
        v = v.data.cpu().numpy()
    sf = math.ceil(math.log(v+1e-12, 2))
    return sf


def linear_quantize(input, sf, bits):
    assert bits >= 1, bits
    if bits == 1:
        return torch.sign(input) - 1
    delta = math.pow(2.0, -sf)
    bound = math.pow(2.0, bits-1)
    min_val = - bound
    max_val = bound - 1
    rounded = torch.floor(input / delta + 0.5)
    clipped_value = torch.clamp(rounded, min_val, max_val) * delta
    vf2ff = np.vectorize(float2ffloat, otypes=[float])
    tmp = vf2ff(input.data.numpy(), bits-sf, sf)
    output = torch.from_numpy(tmp).float()
    # print(clipped_value == output)
    # print(type(output), type(clipped_value))
    return output
    # return clipped_value


class LinearQuant(nn.Module):
    def __init__(self, name, bw_params, bw_layer, fl_layer=None, overflow_rate=0.0, counter=10):
        super(LinearQuant, self).__init__()
        self.name = name
        self._counter = counter

        self.bw_layer = bw_layer
        self.fl_layer = fl_layer
        self.bw_params = bw_params[0]
        self.fl_params = bw_params[1]
        self.overflow_rate = overflow_rate

    @property
    def counter(self):
        return self._counter

    def forward(self, input):
        if self._counter > 0:
            self._counter -= 1
            sf_new = self.bw_layer - 1 - compute_integral_part(input, self.overflow_rate)
            sf_new = max(0, min(self.bw_layer-1, sf_new))
            self.fl_layer = min(self.fl_layer, sf_new) if self.fl_layer is not None else sf_new
            return input
        else:
            output = linear_quantize(input, self.fl_layer, self.bw_layer)
            return output

    def __repr__(self):
        return "{}(bw_layer={}, fl_layer={}, bw_params={}, fl_params={}, overflow_rate={:.3f}, counter={})".format(
            self.__class__.__name__, self.bw_layer, self.fl_layer, self.bw_params, self.fl_params, self.overflow_rate, self.counter)


def duplicate_model_with_quant(model, bw_param, bits, overflow_rate=0.0, counter=10):
    # assert type is "linear"
    if isinstance(model, nn.Sequential):
        l = OrderedDict()
        # TODO: find better way than add layer and then remove it
        # add quantization of scaled values as first layer
        quant_layer = LinearQuant("0_prepr_quant", [None, None], bw_layer=bits, fl_layer=bits-3, counter=0)
        l["0_prepr_quant"] = quant_layer
        for k, v in model._modules.items():
            if isinstance(v, nn.Conv2d):
                l[k] = v
                quant_layer = LinearQuant("{}_quant".format(k), bw_param.pop(), bw_layer=bits, overflow_rate=overflow_rate, counter=counter)
                l["{}_quant".format(k)] = quant_layer
            elif isinstance(v, nn.AdaptiveAvgPool2d):
                # TODO: add quantization layer after nn.AdaptiveAvgPool2d with same bitwidths as last conv layer
                # not possible, because fl gets calculated later -> difference to caffe
                l[k] = v
                quant_layer = LinearQuant("{}_quant".format(k), [None, None], bw_layer=bits, overflow_rate=overflow_rate, counter=counter)
                l["{}_quant".format(k)] = quant_layer
            else:
                l[k] = duplicate_model_with_quant(v, bw_param, bits, overflow_rate, counter)
        m = nn.Sequential(l)
        return m
    else:
        for k, v in model._modules.items():
            model._modules[k] = duplicate_model_with_quant(v, bw_param, bits, overflow_rate, counter)
        return model
