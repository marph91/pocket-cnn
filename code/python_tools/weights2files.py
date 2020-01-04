import os

import numpy as np

from fixfloat import float2fixed


def weights2files(kernel, bias, data_bits: int, frac_bits: int,
                  layer_name: str, output_dir: str) -> None:
    """Write quantized data of weights and bias to files."""
    os.makedirs(output_dir, exist_ok=True)

    line_w, line_b, debug_w, debug_b = [], [], [], []
    shape = kernel.shape
    int_bits = data_bits - frac_bits
    ch_in = 0
    for ch_out, item in enumerate(np.nditer(kernel)):
        sfix = float2fixed(item, int_bits, frac_bits)

        line_w.append(str(sfix))
        debug_w.append(str(item) + " ")
        if (ch_out+1) % (shape[2] * shape[3]) == 0:
            if (ch_in+1) % shape[1] == 0:
                line_b.append(str(
                    float2fixed(bias[int((ch_out+1) / (shape[1] * shape[2] *
                                                       shape[3])-1)],
                                int_bits, frac_bits)))
                line_b.append("\n")
                debug_b.append(str(
                    bias[int((ch_out+1) / (shape[1]*shape[2]*shape[3])-1)]))
                debug_b.append("\n")
            line_w.append("\n")
            debug_w.append("\n")
            ch_in += 1

    with open(output_dir + "/W_" + layer_name + ".txt", "w") as outfile:
        outfile.write("".join(line_w))
    with open(output_dir + "/W_" + layer_name + "_debug.txt", "w") as outfile:
        outfile.write("".join(debug_w))
    with open(output_dir + "/B_" + layer_name + ".txt", "w") as outfile:
        outfile.write("".join(line_b))
    with open(output_dir + "/B_" + layer_name + "_debug.txt", "w") as outfile:
        outfile.write("".join(debug_b))
