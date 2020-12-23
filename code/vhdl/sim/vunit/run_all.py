#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import importlib.util
import os
import random
import subprocess

import numpy as np
from vunit import VUnit


def create_test_suites(prj):
    """Gather the testbenches of all modules and run them."""
    root = os.path.dirname(__file__)

    # Don't use "**", because there would be too many matches.
    testbenches = (glob(os.path.join(root, "*", "tb_*.vhd")) +
                   glob(os.path.join(root, "*", "src", "tb_*.vhd")))
    sim_lib = prj.add_library("sim")
    sim_lib.add_source_files("common.vhd")
    sim_lib.add_source_files(testbenches)

    util_lib = prj.add_library("util")
    util_lib.add_source_files("../../src/util/*.vhd")
    window_ctrl_lib = prj.add_library("window_ctrl_lib")
    window_ctrl_lib.add_source_files("../../src/window_ctrl/*.vhd")
    cnn_lib = prj.add_library("cnn_lib")
    cnn_lib.add_source_files("../../src/*.vhd")

    run_scripts = glob(os.path.join(root, "*", "run.py"))
    for run_script in run_scripts:
        spec = importlib.util.spec_from_file_location("run", run_script)
        mod = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(mod)
        mod.create_test_suite(sim_lib)

    # avoid error "type of a shared variable must be a protected type"
    prj.set_compile_option("ghdl.a_flags", ["-frelaxed"])
    prj.set_sim_option("ghdl.elab_flags", ["-frelaxed"])

    # add code coverage if supported
    if prj.simulator_supports_coverage():
        prj.set_sim_option("enable_coverage", True)
        prj.set_compile_option("enable_coverage", True)


def post_run(results):
    """Collect the coverage results and create a report."""
    if PRJ.simulator_supports_coverage():
        results.merge_coverage(file_name="coverage_data")
        subprocess.call(["lcov", "--capture", "--directory", "coverage_data",
                         "--output-file", "coverage.info"])


if __name__ == "__main__":
    random.seed(42)
    np.random.seed(42)
    os.environ["VUNIT_SIMULATOR"] = "ghdl"
    PRJ = VUnit.from_argv()
    create_test_suites(PRJ)
    PRJ.main(post_run=post_run)
