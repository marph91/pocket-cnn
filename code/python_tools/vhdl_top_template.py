def vhdl_top_template(param, param_file):
    """"Generating a VHDL toplevel wrapper with all needed CNN parameter."""
    pe = param["pe"]
    conv_names = param["conv_names"]
    bitwidth = param["bitwidth"]

    # prepare some param strings
    bws, weight_dirs, bias_dirs = "", "", ""
    for i, bw in enumerate(bitwidth[:-1]):
        bws += "      " + str(i+1) + " => (" + ", ".join(map(str, bw)) + "),\n"
    for i, name in enumerate(conv_names[:-1]):
        weight_dirs += "      \"%s/W_%s.txt\",\n" % (param["weight_dir"], name)
    for i, name in enumerate(conv_names[:-1]):
        bias_dirs += "      \"%s/B_%s.txt\",\n" % (param["weight_dir"], name)

    # write parameter into file
    with open(param_file, "w") as outfile:
        outfile.write("\
-- generated file!\n\
-- used to provide cocotb compatibility and toplevel for synthesis\n\n\
library ieee;\n\
  use ieee.std_logic_1164.all;\n\
library util;\n\
  use util.cnn_pkg.all;\n\n\
entity top_wrapper is\n\
  port (\n\
    isl_clk    : in std_logic;\n\
    isl_rst_n  : in std_logic;\n\
    isl_ce     : in std_logic;\n\
    isl_get    : in std_logic;\n\
    isl_start  : in std_logic;\n\
    isl_valid  : in std_logic;\n\
    islv_data  : in std_logic_vector(" + str(bitwidth[0][0]) + "-1 downto 0);\n\
    oslv_data  : out std_logic_vector(" + str(bitwidth[0][0]) + "-1 downto 0);\n\
    osl_valid  : out std_logic;\n\
    osl_rdy    : out std_logic;\n\
    osl_finish : out std_logic\n\
  );\n\
end top_wrapper;\n\n\
architecture behavioral of top_wrapper is\n\
begin\n\
  i_top : entity work.top\n\
  generic map (\n\
    C_DATA_TOTAL_BITS => " + str(bitwidth[0][0]) + ",\n\
    C_IMG_WIDTH_IN => " + str(param["input_width"]) + ",\n\
    C_IMG_HEIGHT_IN => " + str(param["input_height"]) + ",\n\
    C_PE => " + str(pe) + ",\n\
    C_SCALE => " + str(param["scale"]) + ", \n\
    -- 0 - preprocessing, 1 to C_PE - pe, C_PE+1 - average\n\
    C_RELU => \"" + "".join(map(str, param["relu"])) + "\",\n\
    C_LEAKY_RELU => \"" + "".join(map(str, param["leaky_relu"])) + "\",\n\
    C_PAD => (" + ", ".join(map(str, param["pad"])) + "),\n\
    C_CONV_KSIZE => (" + ", ".join(map(str, param["conv_kernel"])) + "),\n\
    C_CONV_STRIDE => (" + ", ".join(map(str, param["conv_stride"])) + "),\n\
    C_POOL_KSIZE => (" + ", ".join(map(str, param["pool_kernel"])) + "),\n\
    C_POOL_STRIDE => (" + ", ".join(map(str, param["pool_stride"])) + "),\n\
    C_CH => (" + ", ".join(map(str, param["channel"])) + "), \n\
    -- 0 - bitwidth data, 1 - bitwidth frac data in, 2 - bitwidth frac data out\n\
    -- 3 - bitwidth weights, 4 - bitwidth frac weights\n\
    C_BITWIDTH => (\n\
" + bws + "\
      " + str(pe) + " => (" + ", ".join(map(str, bitwidth[pe-1])) + ")),\n\
    C_STR_LENGTH => " + str(param["len_weights"]) + ",\n\
    C_WEIGHTS_INIT => (\n\
" + weight_dirs + "      \"" + param["weight_dir"] + "/W_" + conv_names[pe-1] + ".txt\"),\n\
    C_BIAS_INIT => (\n\
" + bias_dirs + "      \"" + param["weight_dir"] + "/B_" + conv_names[pe-1] + ".txt\")\n\
  )\n\
  port map (\n\
    isl_clk     => isl_clk,\n\
    isl_rst_n   => isl_rst_n,\n\
    isl_ce      => isl_ce,\n\
    isl_get     => isl_get,\n\
    isl_start   => isl_start,\n\
    isl_valid   => isl_valid,\n\
    islv_data   => islv_data,\n\
    oslv_data   => oslv_data,\n\
    osl_valid   => osl_valid,\n\
    osl_rdy     => osl_rdy,\n\
    osl_finish  => osl_finish\n\
  );\n\
end behavioral;")
