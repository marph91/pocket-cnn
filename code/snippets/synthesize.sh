#!/bin/sh

set -e

ROOT="$(pwd)/../.."
SRC="$ROOT/code/vhdl/src"

rm -rf build
mkdir -p build
cd build

# analyze the sources
ghdl -a --std=08 --work=util "$SRC/util/cnn_pkg.vhd"
ghdl -a --std=08 --work=util "$SRC/util/math_pkg.vhd"

ghdl -a --std=08 --work=cnn_lib "$SRC/bram.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/channel_repeater.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/relu.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/zero_pad.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/pool_ave.vhd"

ghdl -a --std=08 --work=cnn_lib "$SRC/line_buffer.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/window_buffer.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/window_ctrl.vhd"

ghdl -a --std=08 --work=cnn_lib "$SRC/mm.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/conv.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/conv_top.vhd"

ghdl -a --std=08 --work=cnn_lib "$SRC/pool_max.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/max_top.vhd"

ghdl -a --std=08 --work=cnn_lib "$SRC/pe.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/top.vhd"

# create a toplevel wrapper and weights
python3 "$ROOT/code/python_tools/vhdl_top_template.py"

# analyze the top wrapper
ghdl -a --std=08 --work=cnn_lib "top_wrapper.vhd"

# synthesize the design
ghdl --synth --std=08 --work=cnn_lib top_wrapper

# yosys -m ghdl -p 'ghdl --std=08 --work=cnn_lib top_wrapper; synth_ice40 -json aes.json'
# nextpnr-ice40 --hx1k --json top_wrapper.json --asc top_wrapper.asc
# icepack top_wrapper.asc top_wrapper.bin
# iceprog top_wrapper.bin