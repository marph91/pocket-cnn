#!/usr/bin/env python3
import os
import errno

import numpy as np
import PIL.Image


def create_dir(dirname):
    """Create directory if it doesn't already exist."""
    if not os.path.exists(dirname):
        try:
            os.makedirs(dirname)
        except OSError as exc:
            # Guard against race condition
            if exc.errno != errno.EEXIST:
                raise


def load_image(path, width, height, mode="L"):
    """Load an image."""
    image = PIL.Image.open(path)
    image = np.asarray(image.convert(mode).resize(
        (width, height), PIL.Image.BILINEAR))
    return image


def print_args(args):
    print("================FLAGS===================")
    for key, value in args.__dict__.items():
        print("{}: {}".format(key, value))
    print("========================================")


def print_cwd():
    print(os.path.dirname(os.path.realpath(__file__)))
    print(os.getcwd())


def set_log_level(level):
    # suppress most of caffe output
    # 0 - debug, 1 - info, 2 - warnings, 3 - errors
    os.environ["GLOG_minloglevel"] = str(level)
