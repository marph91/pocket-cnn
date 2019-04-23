#!/usr/bin/env python3

from collections import namedtuple
import math
import random

import numpy as np

import cocotb
from cocotb.clock import Clock
from cocotb.monitors import Monitor
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory
from cocotb.result import TestFailure
from cocotb.scoreboard import Scoreboard

from fixfloat import fixedint2ffloat


class WindowMonitor(Monitor):
    """Represents a monitor for the output values of a line buffer."""
    def __init__(self, name, gen, clk, valid, data, callback=None, event=None):
        self.bits_data = gen.bits_data
        self.kernel_size = gen.kernel_size
        
        self.clk = clk
        self.name = name
        self.valid = valid
        self.data = data
        Monitor.__init__(self, callback, event)

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            yield RisingEdge(self.clk)
            if bool(self.valid.value.integer):
                print("recv:", self.data.value)
                print("recv:", self.data, split_slv(self.data.value.integer, self.bits_data, self.bits_data*self.kernel_size*self.kernel_size))
                print(self.data.value.integer)
                self._recv(split_slv(self.data.value.integer, self.bits_data, self.bits_data*self.kernel_size*self.kernel_size))


class WindowModel:
    """Represent a software model of a sliding window."""
    def __init__(self, gen):
        self.width = gen.width
        self.height = gen.height
        self.stride = gen.stride
        self.kernel_size = gen.kernel_size
        self.ch_in = gen.ch_in
        self.ch_out = gen.ch_out
        self.row = 0
        self.col = 0
        self.c = 0
        self.expected_output = []
        self.img_1d = []
        self.win = []
        self.pos = 0
        self.data = np.random.randint(2**gen.bits_data, size=(gen.ch_in, gen.height, gen.width))
    
        for col in range(0, gen.width-(gen.kernel_size-1), gen.stride):
            for row in range(0, gen.height-(gen.kernel_size-1), gen.stride):
                roi = self.data[:, col:col+gen.kernel_size, row:row+gen.kernel_size].reshape(gen.ch_in,-1).tolist()
                print(roi)
                self.expected_output.extend(roi * gen.ch_out)
        print(self.data)
        print(self.expected_output)

    def next_input(self):
        next_in = self.data.transpose(1,2,0).flat[self.pos]
        self.pos += 1
        return int(next_in)


def split_slv(data: int, bitwidth, total_width):
    data_split = []
    for i in range(total_width//bitwidth):
        data, splitted = divmod(data, 2**bitwidth)
        data_split.append(splitted)
    return list(reversed(data_split))


@cocotb.coroutine
def run_test(dut):
    """setup testbench and run a test"""
    generics = namedtuple("generics", ["bits_data", "kernel_size", "stride", "ch_in", "ch_out", "width", "height"])
    gen = generics(dut.C_DATA_TOTAL_BITS.value.integer,
                   dut.C_KSIZE.value.integer,
                   dut.C_STRIDE.value.integer,
                   dut.C_CH_IN.value.integer,
                   dut.C_CH_OUT.value.integer,
                   dut.C_IMG_WIDTH.value.integer,
                   dut.C_IMG_HEIGHT.value.integer)

    for _ in range(2):
        # setup monitor, software model and scoreboard
        output_mon = WindowMonitor("output", gen, dut.isl_clk, dut.osl_valid, dut.oslv_data)
        window = WindowModel(gen)
        scoreboard = Scoreboard(dut)
        scoreboard.add_interface(output_mon, window.expected_output)

        # setup clock
        clk = Clock(dut.isl_clk, 10, "ns")
        cocotb.fork(clk.start())
        
        # reset/initialize values
        dut.isl_rst_n <= 0
        dut.isl_valid <= 0
        dut.islv_data <= 0
        yield RisingEdge(dut.isl_clk)
        dut.isl_rst_n <= 1
        dut.isl_ce <= 1
        dut.isl_get <= 1
        yield RisingEdge(dut.isl_clk)
        i = 0
        while i < gen.width:
            j = 0
            while j < gen.height:
                print(bool(dut.osl_rdy.value.integer), dut.osl_rdy.value.integer)
                if bool(dut.osl_rdy.value.integer):
                    print("row, col: ", i, j)
                    for _ in range(gen.ch_in):
                        in_data = window.next_input()
                        print(in_data)
                        print("generics:", gen.ch_in, gen.kernel_size)
                        dut.isl_valid <= 1
                        dut.islv_data <= in_data
                        yield RisingEdge(dut.isl_clk)
                    dut.isl_valid <= 0
                    j += 1
                yield RisingEdge(dut.isl_clk)
            i += 1

        if len(window.expected_output) == 0:
            raise TestFailure("Output is empty.")
        
        for _ in range(50):
            yield RisingEdge(dut.isl_clk)

        raise scoreboard.result


def run_tb():
    """run the testbench with given inputs"""

    testbench = TestFactory(run_test)
    testbench.generate_tests()


run_tb()
