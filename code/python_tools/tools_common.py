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
