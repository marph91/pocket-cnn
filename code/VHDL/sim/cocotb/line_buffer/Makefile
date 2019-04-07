CWD=$(shell pwd)

VHDL_DIR=/home/workspace/opencnn/code/VHDL/src
COCOTB_ROOT=/home/prog/cocotb
# suppress most of the cocotb log
export COCOTB_REDUCED_LOG_FMT=1

SIM=ghdl
CMD_BIN=ghdl
OPT=-O3
GHDL_ARGS=-g $(OPT) -P$(CWD)/util --ieee=synopsys --std=08

# --vcd slows sim down to half speed
SIM_ARGS+=--ieee-asserts=disable --assert-level=none #--vcd=../test.vcd
SIM_BUILD=work

TOPLEVEL_LANG?=vhdl

VHDL_SOURCES=$(VHDL_DIR)/*.vhd

TOPLEVEL=line_buffer
MODULE=$(TOPLEVEL)_cocotb

CUSTOM_SIM_DEPS=$(CWD)/Makefile

# time resolution like vivado standard
VSIM_ARGS=-t 1ps

all: dirs libs
dirs:
	mkdir -p $(CWD)/work $(CWD)/util #$(CWD)/ieee_proposed

# compile the custom libraries
libs:
	$(CMD_BIN) -a $(OPT) --std=08 --work=util --workdir=util $(VHDL_DIR)/util/*.vhd


include $(COCOTB_ROOT)/makefiles/Makefile.inc
include $(COCOTB_ROOT)/makefiles/Makefile.sim

# override target from cocotb, to force usage of flags -i, -m (previously -a, -e)
# without these flags, the design would be analyzed by filenames alphabetically
# now the design gets analysed hierarchically according to VHDL modules
analyse: $(VHDL_SOURCES) $(SIM_BUILD)
	cd $(SIM_BUILD) && $(CMD) -i $(GHDL_ARGS) --work=$(RTL_LIBRARY) $(VHDL_SOURCES) && $(CMD) -m $(GHDL_ARGS) --work=$(RTL_LIBRARY) $(TOPLEVEL)
