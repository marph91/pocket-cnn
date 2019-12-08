from random import randint
import numpy as np


def random_bw(max_bw=16):
    bits = randint(1, max_bw)
    int_bits = randint(1, bits)
    frac_bits = bits - int_bits
    return bits, frac_bits


def random_fixed_array(size, int_bits, frac_bits):
    val_range = 2**(int_bits + frac_bits)/2
    return np.random.randint(-val_range, high=val_range-1, size=size,
                             dtype=np.int) / float(2**frac_bits)


def array2stream(array):
    """Converts an array to a stream based vector (CH > H > W)."""
    return np.transpose(array, (1, 2, 0)).flatten()[None]
