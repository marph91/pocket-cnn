"""Reference implementation for basic CNN functions. This allows to verify the
CNN implementation in hardware without installing a big CNN framework
Furthermore the fixed point functionality is implemented."""

from typing import Tuple

import numpy as np

from fixfloat import float2fixedint, v_float2fixedint
from fixfloat import float2ffloat, v_fixedint2ffloat


def avg_pool(array_in, bitwidth: Tuple[int, int]):
    """Global average pooling layer."""
    _, width, height = array_in.shape

    array_in_float = v_fixedint2ffloat(array_in, *bitwidth)
    # calculate reciprocal for average manually, because else factor would
    # be too different
    reciprocal = float2ffloat(1. / (width * height), 1, 16)
    return v_float2fixedint(
        np.sum(np.sum(array_in_float, axis=1), axis=1) * reciprocal,
        *bitwidth)


def max_pool(array_in, ksize: int, stride: int, bitwidth: Tuple[int, int]):
    """Local maximum pooling layer."""
    # pylint: disable=too-many-locals
    channel, height, width = array_in.shape
    array_in_flt = v_fixedint2ffloat(array_in, *bitwidth)
    out = np.zeros((channel, int((height - ksize) / stride) + 1,
                    int((width - ksize) / stride) + 1), dtype=np.uint8)
    # - (stride - 1) to provide only outputs, where the full kernel fits
    max_height = height - (ksize - stride) - (stride - 1)
    max_width = width - (ksize - stride) - (stride - 1)
    for row_out, row_in in enumerate(range(0, max_height, stride)):
        for col_out, col_in in enumerate(range(0, max_width, stride)):
            roi = array_in_flt[:, row_in:row_in + ksize, col_in:col_in + ksize]
            out[:, row_out, col_out] = v_float2fixedint(np.amax(
                roi.reshape(channel, -1), axis=1), *bitwidth)
    return out


def conv(array_in, weights, bias, param: Tuple[int, int],
         bitwidth: Tuple[int, int, int, int, int, int]):
    """Convolution layer."""
    # used more locals for better readability
    # pylint: disable=too-many-locals
    ksize, stride = param
    channel_in, height, width = array_in.shape
    channel_out, channel_in_w, ksize_w1, ksize_w2 = weights.shape
    assert channel_in == channel_in_w, "input channel don't fit"
    assert channel_out == bias.shape[0], "output channel don't fit"
    assert ksize_w1 == ksize_w2 == ksize, "kernel size doesn't fit"

    array_in_flt = v_fixedint2ffloat(array_in, *bitwidth[:2])
    weights_flt = v_fixedint2ffloat(weights, *bitwidth[4:])
    bias_flt = v_fixedint2ffloat(bias, *bitwidth[4:])

    out = np.zeros((channel_out, int((height - ksize) / stride) + 1,
                    int((width - ksize) / stride) + 1), dtype=np.uint8)
    # - (stride - 1) to provide only outputs, where the full kernel fits
    max_height = height - (ksize - stride) - (stride - 1)
    max_width = width - (ksize - stride) - (stride - 1)
    for row_out, row_in in enumerate(range(0, max_height, stride)):
        for col_out, col_in in enumerate(range(0, max_width, stride)):
            roi = array_in_flt[:, row_in:row_in + ksize, col_in:col_in + ksize]
            for ch_out in range(channel_out):
                result = np.sum(roi * weights_flt[ch_out]) + bias_flt[ch_out]
                # float2ffloat only to saturate the values
                out[ch_out, row_out, col_out] = float2fixedint(
                    result, *bitwidth[2:4])
    return out


def zero_pad(array_in, size: int = 1):
    """Zero padding with same padding at each edge."""
    return np.pad(array_in, ((0, 0), (size, size), (size, size)),
                  "constant", constant_values=0)


def relu(array_in, bitwidth: Tuple[int, int]):
    """Rectified linear unit activation."""
    array_in_float = v_fixedint2ffloat(array_in, *bitwidth)
    return v_float2fixedint(np.maximum(array_in_float, 0), *bitwidth)


def leaky_relu(array_in, alpha: float, bitwidth: Tuple[int, int]):
    """Leaky rectified linear unit activation."""
    array_in_float = v_fixedint2ffloat(array_in, *bitwidth)
    return np.where(
        array_in_float > 0, array_in,
        v_float2fixedint(array_in_float * alpha, *bitwidth))


def flatten(array_in):
    """Converts an array to a stream based vector (CH > H > W)."""
    return np.transpose(array_in, (1, 2, 0)).flatten()[None]
