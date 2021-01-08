#!/bin/sh

if [ -z "$1" ]; then
    echo "Please specify the relative path to the root directory."
    exit 1
fi
ROOT="$1"

set -e

rm -rf build
mkdir -p build
cd build

# analyze the sources
SRC="$ROOT/../code/vhdl/src"

# utilities and helper modules
ghdl -a --std=08 --work=util "$SRC/util/array_pkg.vhd"
ghdl -a --std=08 --work=util "$SRC/util/math_pkg.vhd"
ghdl -a --std=08 --work=util "$SRC/util/bram.vhd"
ghdl -a --std=08 --work=util "$SRC/util/basic_counter.vhd"
ghdl -a --std=08 --work=util "$SRC/util/pixel_counter.vhd"
ghdl -a --std=08 --work=util "$SRC/util/output_buffer.vhd"

# window buffer
ghdl -a --std=08 --work=window_ctrl_lib "$SRC/window_ctrl/channel_repeater.vhd"
ghdl -a --std=08 --work=window_ctrl_lib "$SRC/window_ctrl/line_buffer.vhd"
ghdl -a --std=08 --work=window_ctrl_lib "$SRC/window_ctrl/window_buffer.vhd"
ghdl -a --std=08 --work=window_ctrl_lib "$SRC/window_ctrl/window_ctrl.vhd"

# smaller layers (relu, zero padding, average pooling)
ghdl -a --std=08 --work=cnn_lib "$SRC/relu.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/zero_pad.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/pool_ave.vhd"

# convolution
ghdl -a --std=08 --work=cnn_lib "$SRC/mm.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/conv.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/conv_top.vhd"

# maximum pooling
ghdl -a --std=08 --work=cnn_lib "$SRC/pool_max.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/max_top.vhd"

# upper modules
ghdl -a --std=08 --work=cnn_lib "$SRC/pe.vhd"
ghdl -a --std=08 --work=cnn_lib "$SRC/top.vhd"

# create a toplevel wrapper and weights
python3 "$ROOT/../code/python_tools/vhdl_top_template.py"

# analyze the top wrapper
ghdl -a --std=08 --work=cnn_lib "top_wrapper.vhd"

# synthesize the design
#ghdl --synth --std=08 --work=cnn_lib top_wrapper

yosys -m ghdl -p 'ghdl --std=08 --work=cnn_lib --no-formal top_wrapper; synth_ice40 -json top_wrapper.json'
# nextpnr-ice40 --hx1k --package tq144 --json top_wrapper.json --asc top_wrapper.asc
# icepack top_wrapper.asc top_wrapper.bin
# iceprog top_wrapper.bin