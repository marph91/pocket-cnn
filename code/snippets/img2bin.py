#!/usr/bin/env python3

"""Convert images to a binary representation."""

import argparse
import os

import numpy as np
import PIL.Image

from fixfloat import float2fixed


def load_image(path, width, height, mode="L"):
    """Load an image."""
    image = PIL.Image.open(path)
    image = np.asarray(image.convert(mode).resize(
        (width, height), PIL.Image.BILINEAR))
    return image


def img2bin(source, dest, val_line=1):
    """Write image to binary file."""
    os.makedirs(dest, exist_ok=True)

    img_fixed, img_float, img_bin = [], [], []
    tmp_fixed, tmp_float = [], []
    for index, item in enumerate(np.nditer(source)):
        # write to first position of line (order needed at BRAM)
        # 9:0 and [1:] because of sign bit
        item_fixed = str(float2fixed(item, 9, 0))[1:]
        tmp_fixed.insert(0, item_fixed)
        tmp_float.insert(0, "%s %d " % (item_fixed, item))
        img_bin.append(int(item_fixed, 2).to_bytes(1, byteorder='big'))

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


if __name__ == "__main__":
    PARSER = argparse.ArgumentParser()
    PARSER.add_argument("input_image", type=str)
    PARSER.add_argument("output_width", type=int)
    PARSER.add_argument("output_height", type=int)
    PARSER.add_argument("output_destination", type=str)
    PARSER.add_argument("val_line", type=int, help="values per line (1 or 4)")
    ARGS = PARSER.parse_args()

    IMG = common.load_image(ARGS.input_image, ARGS.output_height,
                            ARGS.output_width)

    img2bin(IMG, ARGS.output_destination, ARGS.val_line)
