"""Reference implementation for basic CNN functions. This allows to verify the
CNN implementation in hardware without installing a big CNN framework
Furthermore the fixed point functionality is implemented."""

from typing import Tuple

from fpbinary import FpBinary, OverflowEnum, RoundingEnum
import numpy as np

from common import InconsistencyError, NotSupportedError
from fp_helper import to_fixed_point_array


def avg_pool(array_in):
    """Global average pooling layer."""
    _, _, width, height = array_in.shape
    sample = array_in.item(0)

    # calculate reciprocal for average manually, because else factor would
    # be too different
    reciprocal = to_fixed_point_array(
        np.array(1. / (width * height)), int_bits=1, frac_bits=16,
        signed=False)
    array_out = np.sum(np.sum(array_in, axis=2), axis=2) * reciprocal
    # TODO: replace for loop
    for value in np.nditer(array_out, flags=["refs_ok"]):
        value.item().resize(
            sample.format, OverflowEnum.sat, RoundingEnum.near_even)
    return array_out


def max_pool(array_in, ksize: int, stride: int):
    """Local maximum pooling layer."""
    # pylint: disable=too-many-locals
    batch, channel, height, width = array_in.shape

    if batch != 1:
        raise NotSupportedError(f"Batch size != 1 not supported. Got {batch}.")
    array_out = np.empty((1, channel, int((height - ksize) / stride) + 1,
                          int((width - ksize) / stride) + 1), dtype=object)
    # - (stride - 1) to provide only outputs, where the full kernel fits
    max_height = height - (ksize - stride) - (stride - 1)
    max_width = width - (ksize - stride) - (stride - 1)
    for row_out, row_in in enumerate(range(0, max_height, stride)):
        for col_out, col_in in enumerate(range(0, max_width, stride)):
            roi = array_in[0, :, row_in:row_in+ksize, col_in:col_in+ksize]
            array_out[0, :, row_out, col_out] = np.amax(
                roi.reshape(channel, -1), axis=1)
    return array_out


def conv(array_in, weights, bias, param: Tuple[int, int],
         bitwidth_out: Tuple[int, int]):
    """Convolution layer."""
    # used more locals for better readability
    # pylint: disable=too-many-locals
    ksize, stride = param
    batch, channel_in, height, width = array_in.shape
    channel_out, channel_in_w, ksize_w1, ksize_w2 = weights.shape
    if channel_in != channel_in_w:
        raise InconsistencyError(
            f"Input channel don't fit. {channel_in} != {channel_in_w}")
    if channel_out != bias.shape[0]:
        raise InconsistencyError(
            f"Output channel don't fit. {channel_out} != {bias.shape[0]}")
    if not ksize_w1 == ksize_w2 == ksize:
        raise InconsistencyError(
            f"Kernel size doesn't fit. !({ksize_w1} == {ksize_w2} == {ksize}.")
    if batch != 1:
        raise NotSupportedError(f"Batch size != 1 not supported. Got {batch}.")

    array_out = np.empty((1, channel_out, int((height - ksize) / stride) + 1,
                          int((width - ksize) / stride) + 1), dtype=object)
    # - (stride - 1) to provide only outputs, where the full kernel fits
    max_height = height - (ksize - stride) - (stride - 1)
    max_width = width - (ksize - stride) - (stride - 1)
    for row_out, row_in in enumerate(range(0, max_height, stride)):
        for col_out, col_in in enumerate(range(0, max_width, stride)):
            roi = array_in[0, :, row_in:row_in+ksize, col_in:col_in+ksize]
            for ch_out in range(channel_out):
                array_out[0, ch_out, row_out, col_out] = (
                    np.sum(roi * weights[ch_out]) + bias[ch_out])

    # TODO: replace for loop
    for value in np.nditer(array_out, flags=["refs_ok"]):
        value.item().resize(
            bitwidth_out, OverflowEnum.sat, RoundingEnum.near_even)
    return array_out


def zero_pad(array_in, size: int = 1):
    """Zero padding with same padding at each edge."""
    sample = array_in.item(0)
    # TODO: figure out why np.pad doesn't work
    # c = np.pad(array_in, ((0, 0), (0, 0), (size, size), (size, size)),
    #            "constant", constant_values=FpBinary(...))
    shape_out = (array_in.shape[0], array_in.shape[1],
                 array_in.shape[2] + 2*size, array_in.shape[3] + 2*size)
    array_out = to_fixed_point_array(
        np.zeros(shape_out), format_inst=sample, signed=sample.is_signed)
    array_out[:, :, size:-size, size:-size] = array_in
    return array_out


def relu(array_in):
    """Rectified linear unit activation."""
    sample = array_in.item(0)
    array_out = to_fixed_point_array(
        np.zeros(array_in.shape), format_inst=sample,
        signed=sample.is_signed)
    return np.where(array_in > 0, array_in, array_out)


def leaky_relu(array_in, alpha: FpBinary):
    """Leaky rectified linear unit activation."""
    sample = array_in.item(0)

    # TODO: look for a simpler conversion
    # https://github.com/smlgit/fpbinary/issues/9
    array_out = np.empty((np.product(array_in.shape),), dtype=object)
    list_out = []
    for value in array_in.flat:
        if value < 0:
            value_leaky = value * alpha
            value_leaky.resize(
                sample.format, OverflowEnum.sat, RoundingEnum.near_even)
        else:
            value_leaky = value
        list_out.append(value_leaky)
    array_out[:] = list_out
    return array_out.reshape(array_in.shape)


def flatten(array_in):
    """Converts an array to a stream based vector (B > CH > H > W)."""
    return np.transpose(array_in, (0, 2, 3, 1)).flatten()[None]
