#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import imp
import os

from vunit import VUnit


def create_test_suites(prj):
    root = os.path.dirname(__file__)
    run_scripts = glob(os.path.join(root, "*", "run.py"))

    # TODO: add code coverage
    # ui.set_sim_option("enable_coverage", True)
    # ui.set_compile_option("ghdl.flags",["-g", "-fprofile-arcs", "-ftest-coverage"])
    # ui.set_sim_option("ghdl.elab_flags",["-Wl,-lgcov", "-Wl,--coverage"])

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
