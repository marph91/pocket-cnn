#!/bin/bash

if [ -z "$1" ]; then
    echo "Please specify the root directory."
    exit 1
fi
ROOT="$1"

set -e

# python checks
# TODO: fix code in all the run.py files
echo "doctest"
find "$ROOT/code/python_tools" -name "*.py" -print0 | xargs -0 python3 -m doctest
echo "flake8"
flake8 "$ROOT/code/python_tools"
echo "mypy"
MYPYPATH="$ROOT/code/python_tools" mypy "$ROOT/code/python_tools" --config-file "$ROOT/mypy.ini"
echo "pylint"
find "$ROOT/code/python_tools" -name "*.py" -print0 | xargs -0 pylint

# shell checks
echo "shellcheck"
find "$ROOT" -path "$ROOT/vivado" -prune -o -name "*.sh" -print0 | xargs -0 shellcheck