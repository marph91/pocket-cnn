#!/bin/bash

if [ -z "$1" ]; then
    echo "Please specify the root directory."
    exit 1
fi
ROOT="$1"

# python checks
# TODO: fix code in all the run.py files
find "$ROOT" -name "*.py" -print0 | xargs -0 python3 -m doctest
flake8 "$ROOT/code/python_tools"
MYPYPATH="$ROOT/code/python_tools" mypy "$ROOT/code/python_tools" --config-file "$ROOT/mypy.ini"
pylint "$ROOT/code/python_tools"

# shell checks
find "$ROOT" -path "$ROOT/vivado" -prune -o -name "*.sh" -print0 | xargs -0 shellcheck