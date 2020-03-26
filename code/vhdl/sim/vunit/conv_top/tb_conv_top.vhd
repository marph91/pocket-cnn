library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;

library cnn_lib;

library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;

library sim;
  use sim.common.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_conv_top is
  generic (
    runner_cfg            : string;

    C_FIRST_STAGE         : integer;

    C_DATA_TOTAL_BITS     : integer;
    C_DATA_FRAC_BITS_IN   : integer;
    C_DATA_FRAC_BITS_OUT  : integer;
    C_WEIGHTS_TOTAL_BITS  : integer;
    C_WEIGHTS_FRAC_BITS   : integer;

    C_CH_IN               : integer;
    C_CH_OUT              : integer;
    C_IMG_WIDTH           : integer;
    C_IMG_HEIGHT          : integer;

    C_KSIZE               : integer;
    C_STRIDE              : integer;
    C_WEIGHTS_INIT        : string;
    C_BIAS_INIT           : string;

    C_PARALLEL            : integer
  );
end entity;

architecture tb of tb_conv_top is
  constant C_IMG_HEIGHT_OUT : integer := (C_IMG_HEIGHT-(C_KSIZE-C_STRIDE))/C_STRIDE;
  constant C_IMG_WIDTH_OUT : integer := (C_IMG_WIDTH-(C_KSIZE-C_STRIDE))/C_STRIDE;

  signal sl_clk : std_logic := '0';
  signal sl_valid_in, sl_valid_out : std_logic := '0';
  signal slv_data_in, slv_data_out : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0) := (others => '0');

  signal sl_rdy : std_logic := '0';
  signal sl_start : std_logic := '0';

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity cnn_lib.conv_top
  generic map(
    C_FIRST_STAGE         => C_FIRST_STAGE,

    C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,
    C_DATA_FRAC_BITS_IN   => C_DATA_FRAC_BITS_IN,
    C_DATA_FRAC_BITS_OUT  => C_DATA_FRAC_BITS_OUT,
    C_WEIGHTS_TOTAL_BITS  => C_WEIGHTS_TOTAL_BITS,
    C_WEIGHTS_FRAC_BITS   => C_WEIGHTS_FRAC_BITS,

    C_KSIZE           => C_KSIZE,
    C_STRIDE          => C_STRIDE,
    C_CH_IN           => C_CH_IN,
    C_CH_OUT          => C_CH_OUT,
    C_IMG_WIDTH       => C_IMG_WIDTH,
    C_IMG_HEIGHT      => C_IMG_HEIGHT,
    C_WEIGHTS_INIT    => C_WEIGHTS_INIT,
    C_BIAS_INIT       => C_BIAS_INIT,

    C_PARALLEL        => C_PARALLEL
  )
  port map(
    isl_clk   => sl_clk,
    isl_start => sl_start,
    isl_valid => sl_valid_in,
    islv_data => slv_data_in,
    oslv_data => slv_data_out,
    osl_valid => sl_valid_out,
    osl_rdy   => sl_rdy
  );

  main : process
    procedure run_test is
    begin
      wait until rising_edge(sl_clk);
      sl_start <= '1';
      wait until rising_edge(sl_clk);
      sl_start <= '0';
      wait until rising_edge(sl_clk);

      wait until (stimuli_done and
                  data_check_done and
                  rising_edge(sl_clk));
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);
    report ("first stage: " & to_string(C_FIRST_STAGE) & " " &
            "bitwidths: " &
            to_string(C_DATA_TOTAL_BITS) & " " &
            to_string(C_DATA_FRAC_BITS_IN) & " " &
            to_string(C_WEIGHTS_TOTAL_BITS) & " " &
            to_string(C_WEIGHTS_FRAC_BITS));
    data_src := load_csv(tb_path(runner_cfg) & "gen/input_" & to_string(C_KSIZE) & "_" & to_string(C_STRIDE) & "_" & to_string(C_PARALLEL) & ".csv");
    data_ref := load_csv(tb_path(runner_cfg) & "gen/output_" & to_string(C_KSIZE) & "_" & to_string(C_STRIDE) & "_" & to_string(C_PARALLEL) & ".csv");

    check_equal(data_src.width, C_IMG_WIDTH*C_IMG_HEIGHT*C_CH_IN, "input_width");
    check_equal(data_src.height, 1, "input_height");
    check_equal(data_src.depth, 1, "input_depth");

    check_equal(data_ref.width, ((C_IMG_WIDTH-(C_KSIZE-C_STRIDE))/C_STRIDE) *
                                ((C_IMG_HEIGHT-(C_KSIZE-C_STRIDE))/C_STRIDE) * -- number of positions of the kernel
                                C_CH_OUT, "output_width");
    check_equal(data_ref.height, 1, "output_height");
    check_equal(data_ref.depth, 1, "output_depth");
    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  clk_gen(sl_clk, C_CLK_PERIOD);

  stimuli_process : process
    variable i : integer := 0;
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    stimuli_done <= false;

    report ("Sending image of size " &
            to_string(C_IMG_WIDTH) & "x" &
            to_string(C_IMG_HEIGHT) & "x" &
            to_string(C_CH_IN));
    report ("Expecting output of size " &
            to_string((C_IMG_WIDTH-(C_KSIZE-C_STRIDE))/C_STRIDE) & "x" &
            to_string((C_IMG_HEIGHT-(C_KSIZE-C_STRIDE))/C_STRIDE) & "x" &
            to_string(C_CH_OUT));

    wait until rising_edge(sl_clk);

    -- increment stream based: channel > width > height
    while i < data_src.height*data_src.width*data_src.depth loop
      wait until rising_edge(sl_clk) and sl_rdy = '1';
      sl_valid_in <= '1';
      for ch_in in 0 to C_CH_IN-1 loop
        slv_data_in <= std_logic_vector(to_unsigned(get(data_src, i), slv_data_in'length));
        report_position(i, C_IMG_HEIGHT, C_IMG_WIDTH, C_CH_IN,
                        "input: ", ", val=" & to_string(get(data_src, i)));
        wait until rising_edge(sl_clk);
        i := i + 1;
      end loop;
      sl_valid_in <= '0';
    end loop;
    wait until rising_edge(sl_clk);

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;

    for i in 0 to C_IMG_HEIGHT_OUT*C_IMG_WIDTH_OUT*C_CH_OUT-1 loop
      wait until rising_edge(sl_clk) and sl_valid_out = '1';
      report_position(i, C_IMG_HEIGHT_OUT, C_IMG_WIDTH_OUT, C_CH_OUT, "output: ");
      check_equal(slv_data_out, std_logic_vector(to_unsigned(get(data_ref, i), slv_data_out'length)));
    end loop;

    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;
