#!/usr/bin/env python3

from os.path import join, dirname
from vunit import VUnit
from glob import glob
import imp

def create_test_suites(prj):
    root = dirname(__file__)
    run_scripts = glob(join(root, "*", "run.py"))

    for run_script in run_scripts:
        file_handle, path_name, description = imp.find_module("run", [dirname(run_script)])
        run = imp.load_module("run", file_handle, path_name, description)
        run.create_test_suite(prj)
        file_handle.close()

prj = VUnit.from_argv()
create_test_suites(prj)
prj.main()
