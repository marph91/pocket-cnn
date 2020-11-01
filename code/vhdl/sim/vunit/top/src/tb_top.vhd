library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
-- library std is predefined: https://www.hdlworks.com/hdl_corner/vhdl_ref/VHDLContents/LibraryClause.htm
  use std.textio.all;

library sim;
  use sim.common.all;
library cnn_lib;
library util;
  use util.array_pkg.all;

library vunit_lib;
  context vunit_lib.vunit_context;

entity tb_top is
  generic (
    runner_cfg        : string;

    C_FOLDER          : string;
    C_DATA_TOTAL_BITS : integer;
    C_IMG_WIDTH_IN    : integer;
    C_IMG_HEIGHT_IN   : integer;
    C_PE              : integer;
    C_RELU            : string;
    C_LEAKY_RELU      : string;
    C_PAD             : string;
    C_CONV_KSIZE      : string;
    C_CONV_STRIDE     : string;
    C_POOL_KSIZE      : string;
    C_POOL_STRIDE     : string;
    C_CH              : string;
    C_BITWIDTH        : string;
    C_STR_LENGTH      : integer;
    C_WEIGHTS_INIT    : string;
    C_BIAS_INIT       : string;

    C_PARALLEL_CH     : string
  );
end tb_top;

architecture behavioral of tb_top is
  -- Decode an integer array from a string. Separators are ", ".
  impure function decode_integer_array(encoded_integer_vector : string; start_index : integer) return t_int_array_1d is
    variable parts : lines_t := split(encoded_integer_vector, ", ");
    variable return_value : t_int_array_1d(start_index to parts'LENGTH-1+start_index);
  begin
    for i in parts'range loop
      return_value(i+start_index) := integer'value(parts(i).all);
    end loop;

    return return_value;
  end;

  -- Decode a 2d integer array from a string. Outer separators are "; ", inner separators are ", ".
  impure function decode_integer_array(encoded_integer_vector : string; start_index : integer) return t_int_array_2d is
    variable outer_parts : lines_t := split(encoded_integer_vector, "; ");
    variable inner_parts : lines_t;
    variable inner_string : string(1 to 13);
    -- outer list: PE, inner list: 5 parts of the bitwidth for each PE
    variable return_value : t_int_array_2d(start_index to outer_parts'LENGTH-1+start_index, 0 to 4);
  begin
    for i in outer_parts'range loop
      read(outer_parts(i), inner_string);
      inner_parts := split(inner_string, ", ");
      assert inner_parts'LENGTH = return_value'LENGTH(2) report "inner bitwidths don't match";
      for j in inner_parts'range loop
        return_value(i+start_index, j) := integer'value(inner_parts(j).all);
      end loop;
    end loop;

    return return_value;
  end;

  -- Decode a string array from a string. Separators are ", ".
  impure function decode_string_array(encoded_integer_vector : string) return t_str_array_1d is
    variable parts : lines_t := split(encoded_integer_vector, ", ");
    variable return_value : t_str_array_1d(1 to parts'LENGTH)(1 to C_STR_LENGTH);
  begin
    for i in parts'range loop
      read(parts(i), return_value(i+1));
    end loop;
    return return_value;
  end;

  -- Decode a slv from a string. Valid characters are only '0' and '1'.
  function str_to_slv(encoded_slv_string : string) return std_logic_vector is
    variable slv : std_logic_vector(encoded_slv_string'length-1 downto 0);
  begin
    for i in encoded_slv_string'range loop
      case encoded_slv_string(i) is
        when '0' =>
          slv(i-1) := '0';
        when '1' =>
          slv(i-1) := '1';
        when others =>
          slv(i-1) := 'U';
      end case;
    end loop;
    return slv;
  end function str_to_slv;

  signal sl_clk           : std_logic := '0';
  signal sl_rdy           : std_logic := '0';
  signal sl_get           : std_logic := '0';
  signal sl_start         : std_logic := '0';
  signal sl_valid_in      : std_logic := '0';
  signal slv_data_in      : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal slv_data_out     : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal sl_valid_out     : std_logic;
  signal sl_finish        : std_logic;

  constant C_CH_ARRAY     : t_int_array_1d := decode_integer_array(C_CH, 0);
  constant C_IMG_DEPTH_IN : integer := C_CH_ARRAY(0);

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal sl_start_test : std_logic := '0';
  signal int_input_cnt : integer := 0;
  signal sl_img_finished : std_logic := '0';

  signal data_check_done, stimuli_done : boolean := false;

begin
  dut: entity cnn_lib.top
  generic map (
    C_DATA_TOTAL_BITS => C_DATA_TOTAL_BITS,
    C_IMG_WIDTH_IN => C_IMG_WIDTH_IN,
    C_IMG_HEIGHT_IN => C_IMG_HEIGHT_IN,
    C_PE => C_PE,
    -- 0 - preprocessing, 1 to C_PE - pe, C_PE+1 - average
    C_RELU => str_to_slv(C_RELU),
    C_LEAKY_RELU => str_to_slv(C_LEAKY_RELU),
    C_PAD => decode_integer_array(C_PAD, 1),
    C_CONV_KSIZE => decode_integer_array(C_CONV_KSIZE, 1),
    C_CONV_STRIDE => decode_integer_array(C_CONV_STRIDE, 1),
    C_POOL_KSIZE => decode_integer_array(C_POOL_KSIZE, 1),
    C_POOL_STRIDE => decode_integer_array(C_POOL_STRIDE, 1),
    C_CH => C_CH_ARRAY,
    -- 0 - bitwidth data, 1 - bitwidth frac data in, 2 - bitwidth frac data out
    -- 3 - bitwidth weights, 4 - bitwidth frac weights
    C_BITWIDTH => decode_integer_array(C_BITWIDTH, 1),
    C_STR_LENGTH => C_STR_LENGTH,
    C_WEIGHTS_INIT => decode_string_array(C_WEIGHTS_INIT),
    C_BIAS_INIT => decode_string_array(C_BIAS_INIT),

    C_PARALLEL_CH => decode_integer_array(C_PARALLEL_CH, 1)
  )
  port map (
    isl_clk     => sl_clk,
    isl_get     => sl_get,
    isl_start   => sl_start,
    isl_valid   => sl_valid_in,
    islv_data   => slv_data_in,
    oslv_data   => slv_data_out,
    osl_valid   => sl_valid_out,
    osl_rdy     => sl_rdy,
    osl_finish  => sl_finish
  );

  main : process
    procedure run_test is
    begin
      wait until rising_edge(sl_clk);
      sl_start_test <= '1';
      wait until rising_edge(sl_clk);
      sl_start_test <= '0';
      wait until rising_edge(sl_clk);
      -- TODO:
      -- report active_test_case;
      -- report running_test_case;
      wait until (stimuli_done and
                  data_check_done and
                  rising_edge(sl_clk));
    end procedure;
  begin
    test_runner_setup(runner, runner_cfg);
    -- don't stop integration tests when one value is wrong
    set_stop_level(failure);
    data_src := load_csv(tb_path(runner_cfg) & C_FOLDER & "/input.csv");
    data_ref := load_csv(tb_path(runner_cfg) & C_FOLDER & "/output.csv");

    -- check whether the image dimensions between loaded data and parameter file fit
    check_equal(data_src.width, C_IMG_WIDTH_IN * C_IMG_HEIGHT_IN * C_IMG_DEPTH_IN, "input_width");
    check_equal(data_src.height, 1, "input_height");
    check_equal(data_src.depth, 1, "input_depth");
    -- last channel is equivalent to the amount of classes
    check_equal(data_ref.width, C_CH_ARRAY(C_PE), "output_width");
    check_equal(data_ref.height, 1, "output_height");
    check_equal(data_ref.depth, 1, "output_depth");
    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  -- stop integration tests if they are stuck
  test_runner_watchdog(runner, 200 us);

  clk_gen(sl_clk, C_CLK_PERIOD);

  proc_stimuli: process
  begin
    wait until rising_edge(sl_clk) and sl_start_test = '1';
    stimuli_done <= false;

    report ("Sending image of size " &
            to_string(C_IMG_WIDTH_IN) & "x" &
            to_string(C_IMG_HEIGHT_IN) & "x" &
            to_string(C_IMG_DEPTH_IN));

    wait until rising_edge(sl_clk);
    sl_get <= '1';
    sl_start <= '0';
    sl_valid_in <= '0';
    slv_data_in <= (others => '0');

    for images in 0 to 1 loop
      wait until rising_edge(sl_clk);
      sl_start <= '1';
      int_input_cnt <= 0;
      wait until rising_edge(sl_clk);
      sl_start <= '0';
      wait until rising_edge(sl_clk);

      while sl_img_finished = '0' loop
        wait until rising_edge(sl_clk) and sl_rdy = '1';
        if int_input_cnt < C_IMG_WIDTH_IN * C_IMG_HEIGHT_IN * C_IMG_DEPTH_IN then
          sl_valid_in <= '1';
          for w in 0 to C_IMG_DEPTH_IN-1 loop
            int_input_cnt <= int_input_cnt + 1;
            slv_data_in <= std_logic_vector(to_unsigned(get(data_src, int_input_cnt), slv_data_in'length));
            report_position(int_input_cnt, C_IMG_HEIGHT_IN, C_IMG_WIDTH_IN, C_IMG_DEPTH_IN,
                            "input: ", ", val=" & to_string(get(data_src, int_input_cnt)));
            wait until rising_edge(sl_clk);
          end loop;
          sl_valid_in <= '0';
        end if;
      end loop;
    end loop;

    stimuli_done <= true;
  end process;

  proc_img_finished: process(sl_clk)
  begin
    if rising_edge(sl_clk) then
      if sl_start = '1' then
        sl_img_finished <= '0';
      elsif sl_finish = '1' then
        sl_img_finished <= '1';
      end if;
    end if;
  end process;

  proc_data_check: process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;

    for images in 0 to 1 loop
      for x in 0 to data_ref.width-1 loop
        wait until rising_edge(sl_clk) and sl_valid_out = '1';
        report_position(x, data_ref.width, 1, 1,
                        "output: ", ", val=" & to_string(get(data_ref, x)));
        check_equal(slv_data_out, get(data_ref, x));
      end loop;
      wait until rising_edge(sl_clk) and sl_finish = '1';
    end loop;

    report ("Done checking");
    data_check_done <= true;
  end process;
end behavioral;