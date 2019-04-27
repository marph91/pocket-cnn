#!/usr/bin/env python3

# disable, because assigning values to signals is needed
# pylint: disable=pointless-statement

import random

import cocotb
from cocotb.clock import Clock
from cocotb.monitors import Monitor
from cocotb.regression import TestFactory
from cocotb.scoreboard import Scoreboard
from cocotb.triggers import RisingEdge

import tools_cocotb


class LineBufferMonitor(Monitor):
    """Represents a monitor for the output values of a line buffer."""
    def __init__(self, name, dut):
        self.name = name
        self.valid = dut.osl_valid
        self.data = dut.oslv_data
        self.bitwidth = dut.C_DATA_WIDTH.value.integer
        self.window_size = dut.C_KSIZE.value.integer
        super().__init__()

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            yield RisingEdge(self.valid)
            values = tools_cocotb.split_slv(self.data.value.integer,
                                            self.bitwidth,
                                            self.window_size*self.bitwidth)
            self._recv(values)


class LineBufferModel:
    """Represent a software model of a line buffer."""
    def __init__(self, channel, width, window_size):
        self.channel = channel
        self.width = width
        self.window_size = window_size
        self.buffer = [0] * channel * width * (window_size - 1)
        self.expected_output = []

    def __call__(self, value):
        """Always when a new input is given:
           - pick and return the specific value for each line
           - add the input and remove the oldest value from the buffer
        """
        self.expected_output.append(
            [self.buffer[self.channel * self.width * i]
             for i in reversed(range(self.window_size-1))] + [value])
        self.buffer.append(value)
        self.buffer.pop(0)


@cocotb.coroutine
def run_test(dut):
    """setup testbench and run a test"""

    # setup monitor, software model and scoreboard
    output_mon = LineBufferMonitor("output", dut)
    line_buffer = LineBufferModel(dut.C_CH.value.integer,
                                  dut.C_IMG_WIDTH.value.integer,
                                  dut.C_KSIZE.value.integer)
    scoreboard = Scoreboard(dut)
    scoreboard.add_interface(output_mon, line_buffer.expected_output)

    # setup clock
    clk = Clock(dut.isl_clk, 10, "ns")
    cocotb.fork(clk.start())

    # reset/initialize values
    dut.isl_valid <= 0
    dut.islv_data <= 0
    dut.isl_ce <= 1
    yield RisingEdge(dut.isl_clk)

    # stimuli
    for _ in range(100):
        in_data = random.randint(0, 2**8-1)
        dut.islv_data <= in_data
        line_buffer(in_data)
        dut.isl_valid <= 1
        yield RisingEdge(dut.isl_clk)
        dut.isl_valid <= 0
        yield RisingEdge(dut.isl_clk)

    # TODO: print short scoreboard summary
    raise scoreboard.result


def run_tb():
    """run the testbench with given inputs"""

    testbench = TestFactory(run_test)
    testbench.generate_tests()


run_tb()
