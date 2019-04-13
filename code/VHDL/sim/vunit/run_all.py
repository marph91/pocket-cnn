#!/usr/bin/env python3

"""Run all unit tests, contained by the subfolders."""

from glob import glob
import imp
from os.path import join, dirname

from vunit import VUnit


def create_test_suites(prj):
    root = dirname(__file__)
    run_scripts = glob(join(root, "*", "run.py"))

    for run_script in run_scripts:
        mod = imp.find_module("run", [dirname(run_script)])
        run = imp.load_module("run", *mod)
        run.create_test_suite(prj)
        mod[0].close()


if __name__ == "__main__":
    PRJ = VUnit.from_argv()
    create_test_suites(PRJ)
    PRJ.main()
