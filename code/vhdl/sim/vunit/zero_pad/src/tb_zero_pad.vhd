library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library cnn_lib;

library sim;
  use sim.common.all;

library vunit_lib;
  context vunit_lib.vunit_context;

entity tb_zero_pad is
  generic (
    runner_cfg      : string;
    id              : string;
    C_IMG_WIDTH     : integer;
    C_IMG_HEIGHT    : integer;
    C_IMG_DEPTH     : integer
  );
end entity;

architecture tb of tb_zero_pad is
  constant C_DATA_WIDTH : integer := 8;

  signal sl_clk : std_logic := '0';
  signal sl_start : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal sl_rdy : std_logic := '0';
  signal sl_get : std_logic := '1';

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;
  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity cnn_lib.zero_pad
  generic map (
    C_DATA_WIDTH  => C_DATA_WIDTH,
    C_CH          => C_IMG_DEPTH,
    C_IMG_WIDTH   => C_IMG_WIDTH,
    C_IMG_HEIGHT  => C_IMG_HEIGHT,
    C_PAD_TOP     => 1,
    C_PAD_BOTTOM  => 1,
    C_PAD_LEFT    => 1,
    C_PAD_RIGHT   => 1
    )
  port map (
    isl_clk     => sl_clk,
    isl_get     => sl_get,
    isl_start   => sl_start,
    isl_valid   => sl_valid_in,
    islv_data   => slv_data_in,
    osl_valid   => sl_valid_out,
    oslv_data   => slv_data_out,
    osl_rdy     => sl_rdy
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
    data_src := load_csv(tb_path(runner_cfg) & "input_" & id & ".csv");
    data_ref := load_csv(tb_path(runner_cfg) & "output_" & id & ".csv");
    check_equal(data_src.width, C_IMG_WIDTH * C_IMG_HEIGHT * C_IMG_DEPTH, "input_width");
    check_equal(data_src.height, 1, "input_height");
    check_equal(data_src.depth, 1, "input_depth");

    check_equal(data_ref.width, (C_IMG_WIDTH+2) * (C_IMG_HEIGHT+2) * C_IMG_DEPTH, "output_width");
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
            to_string(C_IMG_DEPTH));
    report ("Expecting image of size " &
            to_string(C_IMG_WIDTH + 2) & "x" &
            to_string(C_IMG_HEIGHT + 2) & "x" &
            to_string(C_IMG_DEPTH));

    -- increment stream based: channel > width > height
    i := 0;
    while i < C_IMG_WIDTH * C_IMG_HEIGHT * C_IMG_DEPTH loop
      wait until rising_edge(sl_clk) and sl_rdy = '1';
      sl_valid_in <= '1';
      for w in 0 to C_IMG_DEPTH-1 loop
        slv_data_in <= std_logic_vector(to_unsigned(get(data_src, i), slv_data_in'length));
        report_position(i, C_IMG_HEIGHT, C_IMG_WIDTH, C_IMG_DEPTH,
                        "input: ", ", val=" & to_string(get(data_src, i)));
        wait until rising_edge(sl_clk);
        i := i + 1;
      end loop;
      sl_valid_in <= '0';
    end loop;

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;
    for i in 0 to (C_IMG_WIDTH+2) * (C_IMG_HEIGHT+2) * C_IMG_DEPTH - 1 loop
      wait until rising_edge(sl_clk) and sl_valid_out = '1';
      report_position(i, C_IMG_HEIGHT+2, C_IMG_WIDTH+2, C_IMG_DEPTH, "output: ");
      check_equal(slv_data_out, std_logic_vector(to_unsigned(get(data_ref, i), slv_data_out'length)));
    end loop;
    report ("Done checking.");
    data_check_done <= true;
  end process;
end architecture;