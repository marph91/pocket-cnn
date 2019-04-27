#!/usr/bin/env python3
import glob
import argparse
import os
import sys
import numpy as np

# pylint: disable=E0401
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import Timer, RisingEdge
from cocotb.regression import TestFactory
from cocotb.result import TestFailure

import cnn_frameworks

import fixfloat
import tools_common as common

# TODO: automatize running of test cnn architectures
# signals == blobs
# test 1 - 4 PE; conv: 3x3+1+pad, 1x1; max: 2x2+2, 3x3+3
# signals = [dut, dut.prepr, dut.stage1.gen_relu.relu, dut.stage1,
#            dut.stage2.gen_relu.relu, dut.stage2, dut.stage3, dut.stage4,
#            dut.ave]
# test 2 - 4 PE; conv: 3x3+2+pad, 1x1; max: 3x3+2
# signals = [dut, dut.prepr, dut.stage1, dut.stage2.gen_relu.relu, dut.stage2,
#            dut.stage3, dut.stage4, dut.ave]
# test 3 - 6 PE; 2*(conv - conv - pool)
# signals = [dut, dut.prepr, dut.stage1, dut.stage2.gen_relu.relu, dut.stage2,
#            dut.stage3, dut.stage4.gen_relu.relu, dut.stage4, dut.stage5,
#            dut.stage6, dut.ave]
# test 4 - 5 PE; conv: 2x2+1, 3x3+1+pad, 1x1; max: 2x2+1, 3x3+3, 3x3+2,
#                Leaky ReLU; 3*(conv - pool)
# signals = [dut, dut.prepr, dut.stage1.gen_relu.relu, dut.stage1,
#            dut.stage2.gen_relu.relu, dut.stage2, dut.stage3.gen_relu.relu,
#            dut.stage3, dut.stage4, dut.stage5, dut.ave]

DEBUG = bool(int(os.environ["DEBUG"]))
DEBUG_DIR = os.environ["TB_ROOT"] + "/DEBUG/"


def parse_signals(dut):
    """Getting list of signals out of VHDL module hierarchy."""
    # dictionary, because parsed order of stages is wrong
    stages = {}

    # disable stdout, because "for submodule in dut:" somehow produces output
    sys.stdout = open(os.devnull, "w")

    for submodule in dut:
        if "stage" in submodule._name:
            stages.update({submodule._name: []})

            # get convolution (inclusive relu) blob
            try:
                stages[submodule._name].append(submodule.gen_relu.relu)
            except AttributeError:
                stages[submodule._name].append(submodule.conv_buf)

            # get pool blob
            try:
                stages[submodule._name].append(submodule.gen_pool.max_buf)
            except AttributeError:
                pass

    # enable stdout
    sys.stdout = sys.__stdout__

    # add input and output blobs to list of signals
    signals = [dut, dut.prepr]
    [signals.append(signal) for key in stages.keys() for signal in stages[key]]
    signals.append(dut.ave)
    return signals


def format_array(fl_list):
    """Format numpy array and return list."""
    return ["%.3f" % fl for fl in fl_list.flat]


def softmax(scores):
    """Calculate softmax function for class scores."""
    y = np.empty(scores.shape)
    for index, data in enumerate(scores.flat):
        y[0, index, 0, 0] = np.exp(data)/np.sum(np.exp(scores[0, :, 0, 0]))
    return y


# ==============================================================================
@cocotb.coroutine
def gen_debug(clk, dut, exp_out, outfile, cnn):
    """Collects the results of the dut and calculates differences to
    software cnn inference.
    """
    # TODO: use monitor and scoreboard of cocotb
    test_out = [[] for _ in range(len(exp_out))]

    # get list of signals and their bitwidth
    signals = parse_signals(dut)
    bitwidths = cnn.parse_bitwidths()
    if len(signals) != len(bitwidths):
        raise TestFailure("Each signal should have a bitwidth assigned: "
                          "%d =! %d" % (len(signals), len(bitwidths)))
    yield RisingEdge(dut.isl_clk)

    # sample all the signal values of the dut stages
    while dut.osl_finish == 0:
        yield RisingEdge(dut.isl_clk)
        if signals[0].isl_valid == 1:
            test_out[0].append(fixfloat.fixed2float(
                "0" + signals[0].islv_data.value.binstr, bitwidths[0][0],
                bitwidths[0][1]))
        for i, signal in enumerate(signals[1:]):
            if signal.osl_valid == 1:
                test_out[i+1].append(fixfloat.fixed2float(
                    signal.oslv_data.value.binstr, bitwidths[i+1][0],
                    bitwidths[i+1][1]))

    # fit sampled data (test_out) into shape of expected data (exp_out)
    test_out = [np.asarray(test_out[i]).reshape(
        -1, exp_out[i].shape[1]).T.reshape(exp_out[i].shape)
                for i in range(len(exp_out))]

    brief_out = []
    for layer in range(len(test_out)):
        # compare just whole layers
        if layer < len(test_out)-1:
            if not np.array_equal(exp_out[layer], test_out[layer]):
                dut._log.info("Warning: difference in layer %d. See DEBUG "
                              "folder." % (layer))

        # collect output values and compare to expected values
        # and write them to files
        diff_str, out_str = [], []
        diff_str.append("Expected output, simulated output\n")
        for ch_in in range(len(test_out[layer])):
            for ch_out in range(len(test_out[layer][ch_in])):
                diff_str.append("Output Channel %d\n" % (ch_out+1))
                out_str.append("\n\nOutput Channel %d\n" % (ch_out+1))
                for w in range(len(test_out[layer][ch_in][ch_out])):
                    out_str.append("\n")
                    for h in range(len(test_out[layer][ch_in][ch_out][w])):
                        out_val = test_out[layer][ch_in][ch_out][w][h]
                        exp_val = exp_out[layer][ch_in][ch_out][w][h]
                        out_str.append("%f " % (out_val))
                        if (exp_val != out_val):
                            diff_str.append("%d %d %d %d %f %f\n" %
                                            (ch_in+1, ch_out+1, w+1, h+1,
                                             exp_val, out_val))
        with open("%s%d_DIFF.txt" % (DEBUG_DIR, layer), "w") as ofile:
            ofile.write("".join(diff_str))
        with open("%s%d_OUT.txt" % (DEBUG_DIR, layer), "w") as ofile:
            ofile.write("".join(out_str))

        # create brief layer wise summary
        diff = test_out[layer] - exp_out[layer]
        err_abs = np.sum(abs(diff))
        err_rel = np.average(abs(diff))
        brief_out.append("%d %f %f\n" % (layer, err_abs, err_rel))

    # softmax error for brief summary
    diff = softmax(test_out[-1]) - softmax(exp_out[-1])
    err_soft_abs = np.sum(abs(diff))
    err_soft_rel = np.average(abs(diff))
    brief_out.append("%d %f %f\n" % (layer+1, err_soft_abs, err_soft_rel))
    with open(outfile, "w") as ofile:
        ofile.write("".join(brief_out))


# ==============================================================================
@cocotb.coroutine
def run_test(dut, files=None, cnn=None):
    """Setup testbench and run a test."""
    # setup clock
    clk = Clock(dut.isl_clk, 4, "ns")
    cocotb.fork(clk.start())

    infile, outfile = files if DEBUG else (files, None)

    # extract bitwiths and height/width from design to support multiple
    # cnn frameworks
    width = dut.stage1.C_IMG_WIDTH.value.integer
    height = dut.stage1.C_IMG_HEIGHT.value.integer
    exp_out = cnn.inference(infile, width, height)
    dut._log.info("{} result ready.".format(os.environ["CNN_FW"]))

    if DEBUG is True:
        # neglect last layer of exp_out (softmax), it gets calculated on PS
        cocotb.fork(gen_debug(dut.isl_clk, dut, exp_out[0:-1], outfile, cnn))

    # reset/initialize values
    cnt_lines = 0
    dut.isl_rst_n <= 0
    dut.isl_ce <= 0
    dut.isl_get <= 0
    dut.isl_start <= 0
    dut.isl_valid <= 0
    dut.islv_data <= 0
    yield RisingEdge(dut.isl_clk)
    dut.isl_rst_n <= 1
    dut.isl_ce <= 1
    dut.isl_get <= 1
    dut.isl_start <= 1

    yield RisingEdge(dut.isl_clk)
    dut.isl_start <= 0

    # load image
    dut._log.info("Start loading image.")
    exp_out_flat = exp_out[0].flat
    while (cnt_lines < np.prod(exp_out[0].shape)):
        if dut.osl_rdy == 1 and dut.isl_valid == 0:
            dut.isl_valid <= 1
            # round because exp_out are stored float numbers, f. e.: 123.999997
            dut_input = int(round(exp_out_flat[cnt_lines]))
            dut.islv_data <= dut_input
            cnt_lines += 1
            yield RisingEdge(dut.isl_clk)
            dut.isl_valid <= 0
            # two cycles delay, because else too much data would be sent in
            yield RisingEdge(dut.isl_clk)
            yield RisingEdge(dut.isl_clk)
        yield RisingEdge(dut.isl_clk)
    dut._log.info("Finished loading image.")

    dut_out = []
    dut_out_bin = []
    while dut.osl_finish == 0:
        # collect the data outputs of the dut
        if dut.osl_valid == 1:
            dut_out.append(fixfloat.fixed2float(
                dut.oslv_data.value.binstr,
                dut.ave.C_TOTAL_BITS.value.integer - \
                dut.ave.C_FRAC_BITS.value.integer,
                dut.ave.C_FRAC_BITS.value.integer))
            dut_out_bin.append(dut.oslv_data.value.binstr)
        yield RisingEdge(dut.isl_clk)
    dut._log.info("Finished processing image.")

    dut_out = np.reshape(np.asarray(dut_out), exp_out[-2].shape, "F")
    dut._log.info("******************CLASS SCORES******************")
    dut._log.info("Sim Result: {}".format(["%02X" % (int(i, 2))
                                           for i in dut_out_bin]))
    dut._log.info("Sim Result: {}".format(format_array(dut_out)))
    dut._log.info("Software Result: {}".format(format_array(exp_out[-2])))
    dut._log.info("Threshold: 0.0")
    diff = np.asarray(exp_out[-2]) - np.asarray(dut_out)
    dut._log.info("Error: {}".format(format_array(diff)))
    dut._log.info("Total error: {:.3f}".format(np.sum(abs(diff))))
    dut._log.info("Relative error: {:.3f}".format(np.average(abs(diff))))

    if np.any(diff != 0):
        raise TestFailure("Too big error.")


def run_tb():
    """Run the testbench with given inputs."""
    tb = TestFactory(run_test)

    FILES = os.environ["TEST_FILES"]
    file_list = glob.glob(FILES)

    if os.environ["CNN_FW"] == "caffe":
        cnn = [cnn_frameworks.Caffe()]
    elif os.environ["CNN_FW"] == "pytorch":
        cnn = [cnn_frameworks.Pytorch()]
    else:
        raise ValueError("Framework %s not supported" % os.environ["CNN_FW"])

    if DEBUG:
        common.create_dir(DEBUG_DIR)

        runs = ["%d %s\n" % (run+1, img) for run, img in enumerate(file_list)]
        with open("%sruns.txt" % (DEBUG_DIR), "w") as ofile:
            ofile.write("".join(runs))

        out_list = [(d, "%sresult_%d.txt" % (DEBUG_DIR, i))
                    for i, d in enumerate(file_list)]
    else:
        out_list = file_list
    tb.add_option("files", out_list)
    tb.add_option("cnn", cnn)
    tb.generate_tests()

run_tb()
