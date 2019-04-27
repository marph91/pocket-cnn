#!/usr/bin/env python3

# disable, because assigning values to signals is needed
# pylint: disable=pointless-statement

from collections import namedtuple

import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory
from cocotb.result import TestFailure
from cocotb.scoreboard import Scoreboard

import tools_cocotb


class ZeroPadModel:
    """Represents a software model of zero padding."""
    def __init__(self, gen):
        self.pos = 0
        self.data = []
        self.expected_output = []
        self.bits_data = gen.bits_data
        self.padding = ((0, 0), (gen.p_top, gen.p_bot),
                        (gen.p_left, gen.p_right))
        self.size = (gen.ch, gen.height, gen.width)

    def generate_new_data(self):
        self.pos = 0
        self.data = np.random.randint(2**self.bits_data, size=self.size)
        padded_data = np.pad(self.data, self.padding, "constant")
        padded_data_1d = list(padded_data.transpose(1, 2, 0).flat)
        self.expected_output.extend([np.asscalar(val) for val in padded_data_1d])
        print(self.data)
        print(padded_data)
        print(self.expected_output)

    def next_input(self):
        next_in = self.data.transpose(1, 2, 0).flat[self.pos]
        self.pos += 1
        return int(next_in)


@cocotb.coroutine
def run_test(dut):
    """setup testbench and run a test"""
    generics = namedtuple("generics", ["bits_data", "ch", "width", "height",
                                       "p_top", "p_bot", "p_left", "p_right"])
    gen = generics(dut.C_DATA_WIDTH.value.integer,
                   dut.C_CH.value.integer,
                   dut.C_IMG_WIDTH.value.integer,
                   dut.C_IMG_HEIGHT.value.integer,
                   dut.C_PAD_TOP.value.integer,
                   dut.C_PAD_BOTTOM.value.integer,
                   dut.C_PAD_LEFT.value.integer,
                   dut.C_PAD_RIGHT.value.integer)

    # setup monitor, software model and scoreboard
    output_mon = tools_cocotb.GeneralMonitor(
        "output", dut.isl_clk, dut.osl_valid, dut.oslv_data)
    pad = ZeroPadModel(gen)
    scoreboard = Scoreboard(dut)
    scoreboard.add_interface(output_mon, pad.expected_output)

    # setup clock
    clk = Clock(dut.isl_clk, 10, "ns")
    cocotb.fork(clk.start())

    # reset/initialize values
    dut.isl_rst_n <= 0
    dut.isl_valid <= 0
    dut.islv_data <= 0
    dut.isl_start <= 0

    for _ in range(10):
        pad.generate_new_data()

        yield RisingEdge(dut.isl_clk)
        dut.isl_rst_n <= 1
        dut.isl_ce <= 1
        dut.isl_get <= 1
        dut.isl_start <= 1
        yield RisingEdge(dut.isl_clk)
        dut.isl_start <= 0
        yield RisingEdge(dut.isl_clk)
        i = 0
        while i < gen.width:
            j = 0
            while j < gen.height:
                if bool(dut.osl_rdy.value.integer):
                    for _ in range(gen.ch):
                        in_data = pad.next_input()
                        print(in_data)
                        dut.isl_valid <= 1
                        dut.islv_data <= in_data
                        yield RisingEdge(dut.isl_clk)
                    dut.isl_valid <= 0
                    yield RisingEdge(dut.isl_clk) # TODO: timing could be improved here
                    j += 1
                yield RisingEdge(dut.isl_clk)
            i += 1

        if pad.expected_output == []:
            raise TestFailure("Output is empty.")

        while dut.int_values_to_pad.value.integer > 0:
            yield RisingEdge(dut.isl_clk)

    raise scoreboard.result


def run_tb():
    """run the testbench with given inputs"""

    testbench = TestFactory(run_test)
    testbench.generate_tests()


run_tb()
