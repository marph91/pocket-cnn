#!/usr/bin/env python3

import argparse
import os
import glob
import tarfile
import tools_common as common


def untar_archive(archive):
    """Untar archive and create hierarchy"""

    # name of the model root folder
    model_root = os.path.join(
        os.path.dirname(archive), os.path.basename(archive).split(".")[0])

    common.create_dir(model_root)
    common.create_dir(model_root + "/caffe")

    # extract the tar archive
    if tarfile.is_tarfile(archive):
        with tarfile.open(archive) as tf:
            tf.extractall(model_root + "/caffe")
    else:
        raise ValueError(
            "Unknown file type for {}".format(os.path.basename(archive)))

    # remove files not needed in further workflow
    for extracted_file in glob.glob(model_root + "/caffe/*"):
        if (not extracted_file.endswith(".caffemodel") or
                os.path.basename(extracted_file) == "train_val.prototxt"):
            os.remove(extracted_file)

    os.rename(archive, model_root + "/caffe/" + os.path.basename(archive))

if __name__ == "__main__":
    parser = argparse.ArgumentParser(
        description="Untar a DIGITS archive.")
    parser.add_argument(
        "archive", help="Path to DIGITS archive.")
    args = parser.parse_args()

    untar_archive(args.archive)
