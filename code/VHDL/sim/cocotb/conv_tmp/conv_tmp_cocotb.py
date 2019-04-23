#!/usr/bin/env python3

from collections import namedtuple
import math
import random

import cocotb
from cocotb.clock import Clock
from cocotb.monitors import Monitor
from cocotb.triggers import RisingEdge
from cocotb.regression import TestFactory
from cocotb.scoreboard import Scoreboard

from fixfloat import fixedint2ffloat


class ConvMonitor(Monitor):
    """Represents a monitor for the output values of a line buffer."""
    def __init__(self, name, gen, valid, data, callback=None, event=None):
        self.name = name
        self.valid = valid
        self.data = data
        Monitor.__init__(self, callback, event)

    @cocotb.coroutine
    def _monitor_recv(self):
        while True:
            yield RisingEdge(self.valid)
            print(self.data)
            # values = fixedint2ffloat(self.data.value.integer,
            #                          self.out_int_width, self.out_frac_width)
            self._recv(self.data)


# class ConvModel:
#     """Represent a software model of a convolution."""
#     def __init__(self, gen):
#         self.window_size = gen.dim
#         self.int_width_data = gen.int_data
#         self.frac_width_data = gen.frac_data
#         self.int_width_weights = gen.int_weight
#         self.frac_width_weights = gen.frac_weight
#         self.expected_output = []

#     def __call__(self, data, weights):
#         assert len(data) == len(weights)
#         out_data_ref = 0
#         for i, _ in enumerate(data):
#             fixed_data = fixedint2ffloat(data[i], self.int_width_data,
#                                          self.frac_width_data)
#             fixed_weights = fixedint2ffloat(weights[i], self.int_width_weights,
#                                             self.frac_width_weights)
#             out_data_ref += fixed_data * fixed_weights

#         self.expected_output.append(out_data_ref)


# def concatenate(data, bitwidth):
#     data_concat = 0
#     for i, d in enumerate(data):
#         data_concat += d << (bitwidth*i)
#     return data_concat


# def random_input(bitwidth, dim):
#     return [random.randint(0, 2**bitwidth-1) for _ in range(dim**2)]


@cocotb.coroutine
def run_test(dut):
    """setup testbench and run a test"""
    # TODO: single/burst mode
    # generics = namedtuple("generics", ["bits_data", "int_data", "frac_data",
    #                                    "bits_weight", "int_weight",
    #                                    "frac_weight", "kernel_size", "stride", "ch_in", "ch_out", ])
    # gen = generics(dut.C_DATA_TOTAL_BITS.value.integer,
    #                dut.C_DATA_TOTAL_BITS.value.integer -
    #                dut.C_DATA_FRAC_BITS_IN.value.integer,
    #                dut.C_DATA_FRAC_BITS_IN.value.integer,
    #                dut.C_WEIGHTS_TOTAL_BITS.value.integer,
    #                dut.C_WEIGHTS_TOTAL_BITS.value.integer -
    #                dut.C_WEIGHTS_FRAC_BITS.value.integer,
    #                dut.C_WEIGHTS_FRAC_BITS.value.integer,
    #                dut.C_CONV_KSIZE.value.integer)

    # setup monitor, software model and scoreboard
    gen=None
    output_mon = ConvMonitor("output", gen, dut.osl_valid, dut.oslv_data)
    # output_mon = ConvMonitor("output2", gen, dut.isl_clk, dut.sfix_sum_tmp)
    # conv = ConvModel(gen)
    # scoreboard = Scoreboard(dut)
    # scoreboard.add_interface(output_mon, conv.expected_output)

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
    yield RisingEdge(dut.isl_clk)

    for i in range(4*8):#gen.C_CH_IN):
        dut.isl_valid <= 1
        dut.islv_data <= i
        yield RisingEdge(dut.isl_clk)
        dut.isl_valid <= 0
        yield RisingEdge(dut.isl_clk)
    
    dut.isl_valid <= 0
    for _ in range(50):
        yield RisingEdge(dut.isl_clk)

    # TODO: print short scoreboard summary
    # raise scoreboard.result


def run_tb():
    """run the testbench with given inputs"""

    testbench = TestFactory(run_test)
    testbench.generate_tests()


run_tb()
