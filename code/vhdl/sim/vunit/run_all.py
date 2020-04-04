#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import imp
import os
import subprocess

from vunit import VUnit


def create_test_suites(prj):
    """Gather the testbenches of all modules and run them."""
    root = os.path.dirname(__file__)

    prj.add_array_util()
    sim_lib = prj.add_library("sim", allow_duplicate=True)
    sim_lib.add_source_files("common.vhd")
    util_lib = prj.add_library("util", allow_duplicate=True)
    util_lib.add_source_files("../../src/util/*.vhd")
    cnn_lib = prj.add_library("cnn_lib", allow_duplicate=True)
    cnn_lib.add_source_files("../../src/*.vhd")

    run_scripts = glob(os.path.join(root, "*", "run.py"))
    for run_script in run_scripts:
        mod = imp.find_module("run", [os.path.dirname(run_script)])
        run = imp.load_module("run", *mod)
        run.create_test_suite(prj)
        mod[0].close()

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
    os.environ["VUNIT_SIMULATOR"] = "ghdl"
    PRJ = VUnit.from_argv()
    create_test_suites(PRJ)
    PRJ.main(post_run=post_run)
