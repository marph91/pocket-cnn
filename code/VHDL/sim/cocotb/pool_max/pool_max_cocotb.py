#!/usr/bin/env python3

# disable, because assigning values to signals is needed
# pylint: disable=pointless-statement, expression-not-assigned

from collections import namedtuple

import cocotb
from cocotb.clock import Clock
from cocotb.monitors import Monitor
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory
from cocotb.result import TestFailure
from cocotb.scoreboard import Scoreboard

from fixfloat import fixedint2ffloat
import tools_cocotb


class MaxPoolMonitor(Monitor):
    """Represents a monitor for the output values of a line buffer."""
    def __init__(self, name, gen, clk, valid, data):
        self.int_width = gen.int_data
        self.frac_width = gen.frac_data

        self.clk = clk
        self.name = name
        self.valid = valid
        self.data = data
        super().__init__()

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            yield RisingEdge(self.clk)
            if bool(self.valid.value.integer):
                values = fixedint2ffloat(self.data.value.integer,
                                         self.int_width, self.frac_width)
                self._recv(values)


class MaxPoolModel:
    """Represent a software model of a convolution."""
    def __init__(self, gen):
        self.window_size = gen.dim
        self.int_width_data = gen.int_data
        self.frac_width_data = gen.frac_data
        self.expected_output = []

    def __call__(self, data: list):
        out_data_ref = 0
        fixed_data = []
        for value in data:
            fixed_data.append(fixedint2ffloat(value, self.int_width_data,
                                              self.frac_width_data))
        out_data_ref = max(fixed_data)
        self.expected_output.append(out_data_ref)


@cocotb.coroutine
def run_test(dut, burst=True):
    """setup testbench and run a test"""
    # setup clock, do this at first, because more clear error messages appear
    clk = Clock(dut.isl_clk, 10, "ns")
    cocotb.fork(clk.start())

    # parse generics
    generics = namedtuple("generics", ["bits_data", "int_data", "frac_data",
                                       "dim"])
    gen = generics(dut.C_TOTAL_BITS.value.integer,
                   dut.C_TOTAL_BITS.value.integer -
                   dut.C_FRAC_BITS.value.integer,
                   dut.C_FRAC_BITS.value.integer,
                   dut.C_KSIZE.value.integer)

    # setup monitor, software model and scoreboard
    output_mon = MaxPoolMonitor("output", gen, dut.isl_clk, dut.osl_valid, dut.oslv_data)
    maxpool = MaxPoolModel(gen)
    scoreboard = Scoreboard(dut)
    scoreboard.add_interface(output_mon, maxpool.expected_output)

    # reset/initialize values
    dut.isl_rst_n <= 0
    dut.isl_valid <= 0
    dut.islv_data <= 0
    yield RisingEdge(dut.isl_clk)
    dut.isl_rst_n <= 1
    dut.isl_ce <= 1
    yield RisingEdge(dut.isl_clk)

    for _ in range(100):
        in_data = tools_cocotb.random_list(gen.bits_data, gen.dim)
        maxpool(in_data)

        dut.isl_valid <= 1
        dut.islv_data <= tools_cocotb.concatenate(in_data, gen.bits_data)
        yield RisingEdge(dut.isl_clk)
        if not burst:
            dut.isl_valid <= 0
            yield RisingEdge(dut.isl_clk)

    dut.isl_valid <= 0

    if maxpool.expected_output == []:
        raise TestFailure("Output is empty.")

    for _ in range(50):
        yield RisingEdge(dut.isl_clk)

    raise scoreboard.result


def run_tb():
    """run the testbench with given inputs"""

    testbench = TestFactory(run_test)
    testbench.add_option("burst", [True, False])
    testbench.generate_tests()


run_tb()
