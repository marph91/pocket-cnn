import numpy as np

from fixfloat import float2ffloat, v_float2ffloat


def scale(array_in, factor):
    return array_in / factor


def avg_pool(array_in):
    _, width, height = array_in.shape
    # calculate reciprocal for average manually, because else factor would
    # be too different
    reciprocal = float2ffloat(1. / (width * height), 1, 16)
    return np.sum(np.sum(array_in, axis=1), axis=1) * reciprocal


def max_pool(array_in, ksize, stride):
    channel, height, width = array_in.shape
    out = np.zeros((channel, int((height - (ksize - stride)) / stride),
                    int((width - (ksize - stride)) / stride)))
    # - (stride - 1) to provide only outputs, where the full kernel fits
    max_height = height - (ksize - stride) - (stride - 1)
    max_width = width - (ksize - stride) - (stride - 1)
    for row_out, row_in in enumerate(range(0, max_height, stride)):
        for col_out, col_in in enumerate(range(0, max_width, stride)):
            roi = array_in[:, row_in:row_in+ksize, col_in:col_in+ksize]
            out[:, row_out, col_out] = np.amax(
                roi.reshape(channel, -1), axis=1)
    return out


def conv(array_in, weights, bias, ksize, stride, int_bits_out, frac_bits_out):
    channel_in, height, width = array_in.shape
    channel_out, channel_in_w, ksize_w1, ksize_w2 = weights.shape
    assert channel_in == channel_in_w
    assert channel_out == bias.shape[0]
    assert ksize_w1 == ksize_w2 == ksize

    out = np.zeros((channel_out, int((height - (ksize - stride)) / stride),
                    int((width - (ksize - stride)) / stride)))
    # - (stride - 1) to provide only outputs, where the full kernel fits
    max_height = height - (ksize - stride) - (stride - 1)
    max_width = width - (ksize - stride) - (stride - 1)
    for row_out, row_in in enumerate(range(0, max_height, stride)):
        for col_out, col_in in enumerate(range(0, max_width, stride)):
            roi = array_in[:, row_in:row_in + ksize, col_in:col_in + ksize]
            for ch_out in range(channel_out):
                mm = np.sum(roi * weights[ch_out]) + bias[ch_out]
                # float2ffloat only to saturate the values
                out[ch_out, row_out, col_out] = float2ffloat(
                    mm, int_bits_out, frac_bits_out)
    return out


def zero_pad(array_in):
    return np.pad(array_in, ((0, 0), (1, 1), (1, 1)),
                  "constant", constant_values=0)


def relu(array_in):
    return np.maximum(array_in, 0)


def leaky_relu(array_in, alpha, int_bits_out, frac_bits_out):
    return np.where(
        array_in > 0, array_in,
        v_float2ffloat(array_in*alpha, int_bits_out, frac_bits_out))
