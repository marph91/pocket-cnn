#!/usr/bin/env python3
import argparse

from google.protobuf import text_format
import numpy as np

from fixfloat import float2fixed
import tools_common as common


def img2bin(source, dest, val_line=1):
    """Write image to binary file."""
    common.create_dir(dest)

    img_fixed, img_float, img_bin = [], [], []
    tmp_fixed, tmp_float = [], []
    for index, item in enumerate(np.nditer(source)):
        # write to first position of line (order needed at BRAM)
        # 9:0 and [1:] because of sign bit
        item_fixed = str(float2fixed(item, 9, 0))[1:]
        tmp_fixed.insert(0, item_fixed)
        tmp_float.insert(0, item_fixed + " " + str(item) + " ")
        img_bin.append(chr(int(item_fixed, 2)))

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
    args = PARSER.parse_args()

    IMG = common.load_image(args.input_image, args.output_height,
                            args.output_width, mode="L")

    img2bin(IMG, args.output_destination, args.val_line)
