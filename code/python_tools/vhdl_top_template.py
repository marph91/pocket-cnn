from shutil import copyfile


def vhdl_top_template(param, weight_dir, param_file):
    """"Parsing Caffe prototxt to VHDL parameter file"""
    pe = param["pe"]
    conv_names = param["conv_names"]
    bitwidth = param["bitwidth"]

    # adapt top to pe (vhdl generic loops arent accessable through ghdl vpi
    # workaround: provide various toplevel files and always replace top.vhd)
    copyfile("VHDL/src/top.vhd_%dpe" % (pe), "VHDL/src/top.vhd")

    # prepare some param strings
    bws, weight_dirs, bias_dirs = "", "", ""
    for i, bw in enumerate(bitwidth[:-1]):
        bws += "\t\t" + str(i+1) + " => (" + ", ".join(map(str, bw)) + "),\n"
    for i, name in enumerate(conv_names[:-1]):
        weight_dirs += "\t\t\"%s/W_%s.txt\",\n" % (weight_dir, name)
    for i, name in enumerate(conv_names[:-1]):
        bias_dirs += "\t\t\"%s/B_%s.txt\",\n" % (weight_dir, name)
    len_weights = str(len("%s/W_%s.txt" % (weight_dir, conv_names[0])))

    # write parameter into file
    with open(param_file, "w") as outfile:
        outfile.write("\
library ieee;\n\tuse ieee.std_logic_1164.all;\n\n\
package cnn_parameter is\n\
\tconstant C_DATA_TOTAL_BITS : integer range 1 to 16 := " + str(bitwidth[0][0]) + ";\n\n\
\tconstant C_IMG_WIDTH_IN : integer range 2 to 512 := " + str(param["input_width"]) + ";\n\
\tconstant C_IMG_HEIGHT_IN : integer range 2 to 512 := " + str(param["input_height"]) + ";\n\n\
\tconstant C_PE : integer range 1 to 100 := " + str(pe) + ";\n\n\
\tconstant C_SCALE : integer range 0 to 256 := " + str(param["scale"]) + ";\n\n\
\t-- 0 - preprocessing, 1 to C_PE - pe, C_PE+1 - average\n\
\tconstant C_RELU : std_logic_vector(1 to C_PE) := \"" + "".join(map(str, param["relu"])) + "\";\n\
\tconstant C_LEAKY_RELU : std_logic_vector(1 to C_PE) := \"" + "".join(map(str, param["leaky_relu"])) + "\";\
\n\n\ttype t_pad_array is array (1 to C_PE) of integer range 0 to 1;\n\
\tconstant C_PAD: t_pad_array := (" + ", ".join(map(str, param["pad"])) + ");\n\n\
\ttype t_win_array is array (1 to C_PE) of integer range 0 to 3;\n\
\tconstant C_CONV_KSIZE : t_win_array := (" + ", ".join(map(str, param["conv_kernel"])) + ");\n\
\tconstant C_CONV_STRIDE : t_win_array := (" + ", ".join(map(str, param["conv_stride"])) + ");\n\
\tconstant C_WIN_POOL : t_win_array := (" + ", ".join(map(str, param["pool_kernel"])) + ");\n\
\tconstant C_POOL_STRIDE : t_win_array := (" + ", ".join(map(str, param["pool_stride"])) + ");\n\n\
\ttype t_ch_array is array (0 to C_PE) of integer range 1 to 512;\n\
\tconstant C_CH: t_ch_array := (" + ", ".join(map(str, param["channel"])) + ");\n\n\
\t-- 0 - bitwidth data, 1 - bitwidth frac data in, 2 - bitwidth frac data out\
\n\
\t-- 3 - bitwidth weights, 4 - bitwidth frac weights\n\
\ttype t_bitwidth_array is array (1 to C_PE, 0 to 4) of integer range 0 to \
C_DATA_TOTAL_BITS;\n\
\tconstant C_BITWIDTH: t_bitwidth_array := (\n\
" + bws + "\
\t\t" + str(pe) + " => (" + ", ".join(map(str, bitwidth[pe-1])) + "));\n\n\
\ttype t_weights_array is array (1 to C_PE) of string(1 to " + len_weights + ");\n\
\tconstant STR_WEIGHTS_INIT : t_weights_array := (\n\
" + weight_dirs + "\t\t\"" + weight_dir + "/W_" + conv_names[pe-1] + ".txt\");\n\
\tconstant STR_BIAS_INIT : t_weights_array := (\n\
" + bias_dirs + "\t\t\"" + weight_dir + "/B_" + conv_names[pe-1] + ".txt\");\n\
end cnn_parameter;")
