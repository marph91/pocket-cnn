#!/usr/bin/env python3

# disable, because assigning values to signals is needed
# pylint: disable=pointless-statement

from collections import namedtuple
import random

import cocotb
from cocotb.clock import Clock
from cocotb.monitors import Monitor
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory
from cocotb.scoreboard import Scoreboard

import tools_cocotb


class WindowMonitor(Monitor):
    """Represents a monitor for the output values of a window buffer."""
    def __init__(self, name, gen, clk, valid, data):
        self.clk = clk
        self.name = name
        self.valid = valid
        self.data = data

        self.bits_data = gen.bits_data
        self.ch = gen.ch
        self.kernel_size = gen.kernel_size

        super().__init__()

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            yield RisingEdge(self.clk)
            if bool(self.valid.value.integer):
                data_list = tools_cocotb.split_slv(
                    self.data.value.integer, self.bits_data,
                    self.bits_data*self.kernel_size*self.kernel_size)
                # reorder in line segments
                data_reordered = []
                for k in range(self.kernel_size):
                    data_reordered += data_list[k::self.kernel_size]
                print("recv:", self.data, data_reordered)
                self._recv(data_reordered)


class WindowModel:
    """Represent a software model of a window buffer."""
    def __init__(self, gen):
        self.bits_data = gen.bits_data
        self.ch = gen.ch
        self.kernel_size = gen.kernel_size

        self.col_cnt = 0
        self.ch_cnt = 0

        self.expected_output = []
        self.img_1d = []
        self.pos = 0

        self.column_segments = [[0]*self.kernel_size] \
            * (self.ch*(self.kernel_size-1))

    def __call__(self, data):
        # collect all column segments and combine them to a window
        self.column_segments.append(tools_cocotb.split_slv(
            data, self.bits_data, self.bits_data*self.kernel_size))

        win = []
        for k in range(self.kernel_size):
            win += self.column_segments[self.pos+k*self.ch]
        self.pos += 1

        self.expected_output.append(win)
        print("exp:", win)


@cocotb.coroutine
def run_test(dut):
    """setup testbench and run a test"""
    generics = namedtuple("generics", ["bits_data", "ch", "kernel_size"])
    gen = generics(dut.C_DATA_WIDTH.value.integer,
                   dut.C_CH.value.integer,
                   dut.C_KSIZE.value.integer)

    # setup monitor, software model and scoreboard
    output_mon = WindowMonitor("output", gen, dut.isl_clk, dut.osl_valid,
                               dut.oslv_data)
    window = WindowModel(gen)
    scoreboard = Scoreboard(dut)
    scoreboard.add_interface(output_mon, window.expected_output)

    # setup clock
    clk = Clock(dut.isl_clk, 10, "ns")
    cocotb.fork(clk.start())

    # reset/initialize values
    dut.isl_valid <= 0
    dut.islv_data <= 0
    yield RisingEdge(dut.isl_clk)
    dut.isl_ce <= 1
    yield RisingEdge(dut.isl_clk)

    yield RisingEdge(dut.isl_clk)
    for _ in range(gen.kernel_size*gen.ch*10):
        in_data = random.randint(0, 2**(gen.bits_data*gen.kernel_size))
        window(in_data)
        dut.isl_valid <= 1
        dut.islv_data <= in_data
        yield RisingEdge(dut.isl_clk)
        dut.isl_valid <= 0
        yield RisingEdge(dut.isl_clk)

    dut.isl_valid <= 0
    for _ in range(50):
        yield RisingEdge(dut.isl_clk)

    raise scoreboard.result


def run_tb():
    """run the testbench with given inputs"""

    testbench = TestFactory(run_test)
    testbench.generate_tests()


run_tb()
