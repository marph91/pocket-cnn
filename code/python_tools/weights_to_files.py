"""Utility to convert weights in a format, which can be loaded
in the VHDL design at simulation and synthesis."""

import os

from fp_helper import to_binary_string


def weights_to_files(kernel, bias, layer_name: str, output_dir: str):
    """Write quantized data of weights and bias to files."""
    # pylint: disable=too-many-locals
    line_w, line_b, debug_w, debug_b = [], [], [], []
    shape = kernel.shape
    ch_in = 1
    for kernel_index, item in enumerate(kernel.flat):
        line_w.append(to_binary_string(item))
        debug_w.append(f"{item} ")
        if (kernel_index+1) % (shape[2] * shape[3]) == 0:
            if ch_in % shape[1] == 0:
                bias_index = ((kernel_index + 1) /
                              (shape[1] * shape[2] * shape[3]) - 1)
                line_b.append(
                    f"{to_binary_string(bias[int(bias_index)])}\n")
                debug_b.append(f"{bias[int(bias_index)]}\n")
            line_w.append("\n")
            debug_w.append("\n")
            ch_in += 1

    os.makedirs(output_dir, exist_ok=True)
    for name, data in (("/W_" + layer_name + ".txt", line_w),
                       ("/W_" + layer_name + "_debug.txt", debug_w),
                       ("/B_" + layer_name + ".txt", line_b),
                       ("/B_" + layer_name + "_debug.txt", debug_b)):
        with open(output_dir + name, "w") as outfile:
            outfile.write("".join(data))
