#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import imp
import os

from vunit import VUnit


def create_test_suites(prj):
    root = os.path.dirname(__file__)

    prj.add_array_util()
    sim_lib = prj.add_library("sim", allow_duplicate=True)
    sim_lib.add_source_files("common.vhd")
    util_lib = prj.add_library("util", allow_duplicate=True)
    util_lib.add_source_files("../../src/util/*.vhd")
    cnn_lib = prj.add_library("cnn_lib", allow_duplicate=True)
    cnn_lib.add_source_files("../../src/*.vhd")

    # TODO: add code coverage
    # prj.set_sim_option("enable_coverage", True)
    # prj.set_compile_option("ghdl.flags",["-g", "-fprofile-arcs", "-ftest-coverage"])
    # prj.set_sim_option("ghdl.elab_flags",["-Wl,-lgcov", "-Wl,--coverage"])

    run_scripts = glob(os.path.join(root, "*", "run.py"))
    for run_script in run_scripts:
        mod = imp.find_module("run", [os.path.dirname(run_script)])
        run = imp.load_module("run", *mod)
        run.create_test_suite(prj)
        mod[0].close()


if __name__ == "__main__":
    os.environ["VUNIT_SIMULATOR"] = "ghdl"
    PRJ = VUnit.from_argv()
    create_test_suites(PRJ)
    PRJ.main()
