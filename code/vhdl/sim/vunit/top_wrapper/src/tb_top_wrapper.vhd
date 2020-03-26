library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library sim;
  use sim.common.all;
library util;
  use util.cnn_pkg.all;
library integration_test;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_top_wrapper is
  generic (
    runner_cfg        : string;

    C_FOLDER          : string;
    C_IMG_WIDTH_IN    : integer;
    C_IMG_HEIGHT_IN   : integer;
    C_IMG_DEPTH_IN    : integer;
    C_CLASSES         : integer
  );
end;

architecture behavioral of tb_top_wrapper is
  signal sl_clk           : std_logic := '0';
  signal sl_rdy           : std_logic := '0';
  signal sl_get           : std_logic := '0';
  signal sl_start         : std_logic := '0';
  signal sl_valid_in      : std_logic := '0';
  signal slv_data_in      : std_logic_vector(7 downto 0);
  signal slv_data_out     : std_logic_vector(7 downto 0);
  signal sl_valid_out     : std_logic := '0';
  signal sl_finish        : std_logic := '0';

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal sl_start_test : std_logic := '0';

  signal data_check_done, stimuli_done : boolean := false;

begin
  dut: entity integration_test.top_wrapper
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
    check_equal(data_ref.width, C_CLASSES, "output_width");
    check_equal(data_ref.height, 1, "output_height");
    check_equal(data_ref.depth, 1, "output_depth");
    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  -- stop integration tests if they are stuck
  test_runner_watchdog(runner, 50 ms);

  clk_gen(sl_clk, C_CLK_PERIOD);

  stimuli_process : process
    variable i : integer := 0;
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
    wait until rising_edge(sl_clk);
    sl_start <= '1';
    wait until rising_edge(sl_clk);
    sl_start <= '0';

    while i < C_IMG_WIDTH_IN * C_IMG_HEIGHT_IN * C_IMG_DEPTH_IN loop
      wait until rising_edge(sl_clk) and sl_rdy = '1';
      sl_valid_in <= '1';
      for w in 0 to C_IMG_DEPTH_IN-1 loop
        slv_data_in <= std_logic_vector(to_unsigned(get(data_src, i), slv_data_in'length));
        report_position(i, C_IMG_HEIGHT_IN, C_IMG_WIDTH_IN, C_IMG_DEPTH_IN,
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

    for x in 0 to data_ref.width-1 loop
      wait until rising_edge(sl_clk) and sl_valid_out = '1';
      check_equal(slv_data_out, get(data_ref, x));
    end loop;

    wait until sl_finish = '1';
    report ("Done checking");
    data_check_done <= true;
  end process;
end behavioral;