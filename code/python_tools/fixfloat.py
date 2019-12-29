import math
import numpy as np


def py3round(val):
    """get rounding behaviour of python3 in python2 (round to nearest even)"""
    if abs(round(val)-val) == 0.5:
        return 2.0*round(val/2.0)
    return round(val)


def float2fixed(number, int_bits, frac_bits):
    """converts float number to binary fixed string"""
    if number < 0:
        if number < -2**(int_bits-1):
            return "1" + "0"*(int_bits+frac_bits-1)
        fixed_nr = bin(int(
            2**(int_bits+frac_bits)-py3round(abs(number) * 2**frac_bits)))
        return fixed_nr[-(int_bits+frac_bits):].zfill(int_bits+frac_bits)
    else:
        if number > 2**(int_bits-1)-2**-frac_bits:
            return "0" + "1"*(int_bits+frac_bits-1)
        return bin(int(
            py3round(number * 2**frac_bits)))[2:].zfill(int_bits+frac_bits)


def float2fixedint(number, int_bits, frac_bits):
    """converts float to fixed. the representation of the fixed number is an
    unsigned integer of the binary value. useful if there are only integers as
    input allowed.
    """
    return int(float2fixed(number, int_bits, frac_bits), 2)


def v_float2fixedint(array, int_bits, frac_bits):
    """vectorized float2fixedint function"""
    vector_float2fixedint = np.vectorize(float2fixedint, otypes=[np.int])
    return vector_float2fixedint(array, int_bits, frac_bits)


def fixedint2ffloat(number, int_bits, frac_bits):
    return fixed2float(bin(int(number))[2:].zfill(int_bits + frac_bits), int_bits, frac_bits)


def v_fixedint2ffloat(array, int_bits, frac_bits):
    """vectorized fixedint2ffloat function"""
    vector_fixedint2ffloat = np.vectorize(fixedint2ffloat, otypes=[np.float])
    return vector_fixedint2ffloat(array, int_bits, frac_bits)


def fixed2float(number, int_bits, frac_bits):
    """converts binary signed fixed point to floating point number"""
    if number[0] == "1":
        return -1.0*(2**(int_bits+frac_bits)-int(number, 2))*2**-frac_bits
    return int(number, 2)*2**-frac_bits


def float2ffloat_alt(number, int_bits, frac_bits):
    """converts floating point to fixed point number, but stored as float"""
    if number > 2**(int_bits-1) - 2**-frac_bits:
        # max value
        return 2**(int_bits-1) - 2**-frac_bits
    elif number < -2**(int_bits-1):
        # min value
        return -2**(int_bits-1)
    return py3round(number*2**frac_bits)/2**frac_bits


def float2ffloat(number, int_bits, frac_bits):
    """converts floating point to fixed point number, but stored as float"""
    return max(min(py3round(
        number*2**frac_bits)/2**frac_bits, 2**(int_bits-1) - 2**-frac_bits),
               -2**(int_bits-1))


def float2pow2(number, min_exp, max_exp):
    """converts floating point to power-of-two number, but stored as float"""
    if number == 0:
        exp_rounded = min_exp
    else:
        exp = math.log(abs(number), 2)
        exp_rounded = int(max(min(py3round(exp), max_exp), min_exp))

    sign = "1" if number < 0 else "0"
    return sign + bin(abs(exp_rounded)-1)[2:].zfill(3)


def random_fixed_array(size, int_bits, frac_bits):
    arr = np.random.randint(2 ** (int_bits + frac_bits),
                            size=size, dtype=np.int)
    return v_fixedint2ffloat(arr, int_bits, frac_bits)
