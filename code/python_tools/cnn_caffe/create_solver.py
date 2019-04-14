#!/usr/bin/env python3

import argparse
from collections import OrderedDict


def create_solver(model_prefix, train_file, solver_file, fixed, use_gpu=False):
    """Create solver dictionary with default parameter and write to file.
    https://github.com/BVLC/caffe/wiki/Solver-Prototxt
    """

    mode = "GPU" if use_gpu is True else "CPU"

    if fixed is False:
        solver = OrderedDict([
            ('test_iter', 77),
            ('test_interval', 115),
            ('base_lr', 0.01),
            ('display', 10),
            ('max_iter', 11500),
            ('iter_size', 32),
            ('lr_policy', "\"step\""),
            ('gamma', 0.1),
            ('momentum', 0.9),
            ('weight_decay', 0.0001),
            ('stepsize', 9200),
            ('snapshot', 100),
            ('snapshot_prefix', "\"{}\"".format(model_prefix)),
            ('solver_mode', mode),
            ('random_seed', 42),
            ('net', "\"{}\"".format(train_file)),
            ('solver_type', "SGD")
        ])
    else:
        solver = OrderedDict([
            ('test_iter', 1000),
            ('test_interval', 100),
            ('base_lr', 0.005),
            ('display', 10),
            ('max_iter', 1000),
            ('iter_size', 32),
            ('lr_policy', "\"fixed\""),
            ('momentum', 0.9),
            ('momentum2', 0.999),
            ('delta', 0.00000001),
            ('weight_decay', 0.0002),
            ('snapshot', 500),
            ('snapshot_prefix', "\"{}\"".format(model_prefix)),
            ('solver_mode', mode),
            ('random_seed', 42),
            ('net', "\"{}\"".format(train_file)),
            ('average_loss', 40),
            ('test_initialization', "true"),
            ('solver_type', "SGD")
        ])

    with open(solver_file, 'w') as outfile:
        for key in solver:
            outfile.write('%s: %s\n' % (key, solver[key]))

if __name__ == "__main__":
    # pylint: disable=C0103
    parser = argparse.ArgumentParser(
        description="Create Caffe solver with default values")
    parser.add_argument("model_prefix", type=str)
    parser.add_argument("train_file", type=str)
    parser.add_argument("solver_file", type=str)
    parser.add_argument("--fixed", type=int)
    parser.add_argument("--use_gpu", type=int, help="Use the GPU")
    args = parser.parse_args()

    create_solver(
        args.model_prefix,
        args.train_file,
        args.solver_file,
        args.fixed,
        args.use_gpu,
    )
