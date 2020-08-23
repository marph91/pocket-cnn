#!/usr/bin/env python3

"""Convert images to a binary representation."""

import argparse
import os

import numpy as np
import PIL.Image

from fpbinary import FpBinary
from fp_helper import to_binary_string


def load_image(path, width, height, mode="L"):
    """Load an image."""
    image = PIL.Image.open(path)
    image = np.asarray(image.convert(mode).resize(
        (width, height), PIL.Image.BILINEAR))
    return image


def img_to_bin(source, dest, val_line=1):
    """Write image to binary file."""
    os.makedirs(dest, exist_ok=True)

    img_fixed, img_float, img_bin = [], [], []
    tmp_fixed, tmp_float = [], []
    for index, item in enumerate(np.nditer(source)):
        # write to first position of line (order needed at BRAM)
        item_fixed = to_binary_string(FpBinary(8, 0, signed=False, value=item))
        tmp_fixed.insert(0, item_fixed)
        tmp_float.insert(0, "%s %d " % (item_fixed, item))
        img_bin.append(int(item_fixed, 2).to_bytes(1, byteorder="big"))

        if (index+1) % val_line == 0:
            img_fixed.extend(tmp_fixed + ["\n"])
            tmp_fixed = []

            img_float.extend(tmp_float + ["\n"])
            tmp_float = []

    with open(dest + "/IMAGE.txt", "w") as outfile:
        outfile.write("".join(img_fixed))
    with open(dest + "/IMAGE_DEBUG.txt", "w") as outfile:
        outfile.write("".join(img_float))
    with open(dest + "/IMAGE.bin", "wb") as outfile:
        outfile.write(b"".join(img_bin))


def main():
    """Main function."""
    parser = argparse.ArgumentParser()
    parser.add_argument("input_image", type=str)
    parser.add_argument("output_width", type=int)
    parser.add_argument("output_height", type=int)
    parser.add_argument("output_directory", type=str)
    parser.add_argument("val_line", type=int, help="values per line (1 or 4)")
    args = parser.parse_args()

    img = load_image(args.input_image, args.output_height, args.output_width)

    img_to_bin(img, args.output_directory, args.val_line)


if __name__ == "__main__":
    main()
