"""Fixed point helper functions. This includes convenience functions
for fpbinary as well as general functions."""

from dataclasses import dataclass
import math
from random import randint
from typing import Optional, Tuple, Union

import numpy as np

from fpbinary import FpBinary


@dataclass
class Bitwidth:
    """
    >>> Bitwidth(total_bits=8)  # doctest:+ELLIPSIS
    Bitwidth(total_bits=8, ...)

    >>> Bitwidth(total_bits=8, int_bits=4)
    Bitwidth(total_bits=8, int_bits=4, frac_bits=4)

    >>> Bitwidth(int_bits=4, frac_bits=4)
    Bitwidth(total_bits=8, int_bits=4, frac_bits=4)

    >>> Bitwidth(8, 1, 7)
    Bitwidth(total_bits=8, int_bits=1, frac_bits=7)

    >>> Bitwidth()
    Traceback (most recent call last):
        ...
    Exception: Invalid initialization. Please provide int and frac bits.
    """
    total_bits: Optional[int] = None
    int_bits: Optional[int] = None
    frac_bits: Optional[int] = None

    def __post_init__(self):
        if self.total_bits is None:
            if None in (self.int_bits, self.frac_bits):
                raise Exception("Invalid initialization. "
                                "Please provide int and frac bits.")
            self.total_bits = self.int_bits + self.frac_bits
        else:
            if self.int_bits is None:
                self.int_bits = randint(1, self.total_bits)
            self.frac_bits = self.total_bits - self.int_bits
        if self.int_bits < 1:
            raise Exception("Invalid initialization. "
                            "At least one int bit required.")

    @property
    def as_tuple(self) -> Tuple[int, int]:
        """Get a tuple representation (int_bits, frac_bits) of the bitwidth."""
        if self.int_bits is None or self.frac_bits is None:
            raise Exception("Int and frac bits should be defined.")
        return (self.int_bits, self.frac_bits)


def to_binary_string(number: FpBinary):
    """Convert a float number to binary fixed string."""
    return bin(number)[2:].zfill(sum(number.format))


def to_fixedint(number: FpBinary):
    """Convert float to fixed. The representation of the fixed number is an
    unsigned integer of the binary value. Useful if there are only integers as
    input allowed."""
    return int(to_binary_string(number), 2)


def v_to_fixedint(array):
    """Vectorized float2fixedint function for usage on numpy arrays."""
    vector_float2fixedint = np.vectorize(to_fixedint, otypes=[np.int32])
    return vector_float2fixedint(array)


def to_fixed_point(number: str, **kwargs):
    """Convert a binary fixed point string to a fixed point object."""
    return FpBinary(**kwargs, bit_field=int(number, 2))


def to_fixed_point_array(array_in, from_value: bool = True,
                         aggressive: bool = False, **kwargs):
    """Convert an arbitrary array to an array of fixed point objects."""
    def fp_gen(value):
        if from_value:
            return FpBinary(**kwargs, value=value)
        return FpBinary(**kwargs, bit_field=int(value))

    # TODO: v_fp_gen = np.vectorize(fp_gen)
    # see also: https://github.com/smlgit/fpbinary/issues/9
    array_out = np.empty((array_in.size,), dtype=object)
    array_out[:] = (
        [fp_gen(element) for element in v_power_of_two(array_in).flat]
        if aggressive else
        [fp_gen(element) for element in array_in.flat]
    )
    return array_out.reshape(array_in.shape)


def is_power_of_two(val: Union[int, float]) -> bool:
    """Check whether a number is a power of two.

    >>> is_power_of_two(-1)
    True
    >>> is_power_of_two(-0.125)
    True
    >>> is_power_of_two(0)
    False
    >>> is_power_of_two(0.25)
    True
    >>> is_power_of_two(1)
    True
    >>> is_power_of_two(2)
    True
    >>> is_power_of_two(5)
    False
    >>> is_power_of_two(2048)
    True
    >>> is_power_of_two(2049)
    False
    """
    if not val:
        return False
    bits = math.log2(abs(val))
    return int(bits) == bits


def v_is_power_of_two(val: Union[int, float]):
    """Vectorized version of "is_power_of_two()"."""
    vector_is_power_of_two = np.vectorize(is_power_of_two, otypes=[np.int32])
    return vector_is_power_of_two(val)


def power_of_two(value: int, bitwidth: int = 8) -> int:
    """Obtain the closest power of 2 of a given number.
    Also check whether it's whithin the range.

    >>> power_of_two(127)
    64
    >>> power_of_two(64)
    64
    >>> power_of_two(63)
    64
    >>> power_of_two(5)
    4
    >>> power_of_two(3)
    4
    >>> power_of_two(2)
    2
    >>> power_of_two(1)
    1
    >>> power_of_two(0)
    0
    >>> power_of_two(-1)
    -1
    >>> power_of_two(-2)
    -2
    >>> power_of_two(-3)
    -4
    >>> power_of_two(-127)
    -128
    >>> power_of_two(-129)
    Traceback (most recent call last):
        ...
    ValueError: Value -129 is out of range.
    >>> power_of_two(1000)
    Traceback (most recent call last):
        ...
    ValueError: Value 1000 is out of range.
    """
    if value == 0:
        return 0
    if value < -2 ** (bitwidth - 1) or value >= 2 ** (bitwidth - 1):
        raise ValueError(f"Value {value} is out of range.")

    negative = value < 0
    power_bits = int(math.log2(abs(value)) + 0.5)

    # check if the number exceeds the range
    if not negative and power_bits == bitwidth - 1:
        power_bits -= 1
    assert -2 ** (bitwidth - 1) <= power_bits < 2 ** (bitwidth - 1), power_bits

    result = (-1) ** negative * 2 ** power_bits
    assert is_power_of_two(result), result
    return result


def v_power_of_two(val: Union[int, float]):
    """Vectorized version of "power_of_two()"."""
    vector_power_of_two = np.vectorize(power_of_two, otypes=[np.int32])
    return vector_power_of_two(val)


def random_fixed_array(size: tuple, bitwidth: Bitwidth,
                       signed: bool = True):
    """Create an array of random fixed point numbers."""
    if bitwidth.total_bits is not None:
        arr = np.random.randint(
            2 ** bitwidth.total_bits, size=size, dtype=np.int32)
    return to_fixed_point_array(
        arr, from_value=False, int_bits=bitwidth.int_bits,
        frac_bits=bitwidth.frac_bits, signed=signed)


def main():
    """Some tests to evaluate the functionality:"""
    # arbitrary array
    arbitrary_array = np.arange(9).reshape((3, 3))
    lattice = to_fixed_point_array(
        arbitrary_array, int_bits=4, frac_bits=4, signed=False)
    print(lattice)

    # multiplication
    mul_lattice = lattice * lattice
    print(mul_lattice, type(mul_lattice[0, 0]), mul_lattice[0, 0].format)
    print(to_fixed_point_array(
        mul_lattice, int_bits=4, frac_bits=4, signed=False))

    # random array
    print(random_fixed_array(
        (1, 3, 2, 2), Bitwidth(int_bits=4, frac_bits=4), signed=False))

    # to binary string
    num1 = FpBinary(int_bits=4, frac_bits=4, signed=False, value=3.5)
    print(to_binary_string(num1))

    # back to fixed_point
    num2 = to_fixed_point(
        to_binary_string(num1), int_bits=4, frac_bits=4, signed=False)
    print(num2)

    # to fixed integer (plain value, not twos complement)
    num3 = FpBinary(int_bits=4, frac_bits=4, signed=False, value=9999)
    print(to_fixedint(num3))

    arr1 = random_fixed_array(
        (1, 3, 2, 2), Bitwidth(int_bits=4, frac_bits=4), signed=False)
    print(v_to_fixedint(arr1))


if __name__ == "__main__":
    main()
