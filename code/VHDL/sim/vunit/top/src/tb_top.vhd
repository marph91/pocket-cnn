library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library sim;
  use sim.common.all;

library integration_test_net_1;
-- library integration_test_net_2;
library integration_test_net_3;
-- library integration_test_net_4;
library integration_test_input_ones;
-- library integration_test_input_zeros;
library integration_test_last_weights_zeros;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_top is
  generic (
    runner_cfg   : string;
    tb_path      : string;
    C_FOLDER     : string;
    C_DATA_WIDTH : integer := 8
  );
end tb_top;

architecture behavioral of tb_top is
  signal sl_clk           : std_logic := '0';
  signal sl_rst_n         : std_logic := '0';
  signal sl_ce            : std_logic := '0';
  signal sl_rdy           : std_logic := '0';
  signal sl_get           : std_logic := '0';
  signal sl_start         : std_logic := '0';
  signal sl_valid_in      : std_logic := '0';
  signal slv_data_in      : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal slv_data_out     : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal sl_valid_out     : std_logic;
  signal sl_finish        : std_logic;

  signal int_pixel_cnt    : integer;

  shared variable data_src : array_t;
  shared variable data_ref : array_t;

  signal sl_start_test : std_logic := '0';

  signal data_check_done, stimuli_done : boolean := false;

begin
  gen_net_1 : if C_FOLDER = "test_net_1" generate
    dut: entity integration_test_net_1.top
    port map (
      isl_clk     => sl_clk,
      isl_rst_n   => sl_rst_n,
      isl_ce      => sl_ce,
      isl_get     => sl_get,
      isl_start   => sl_start,
      isl_valid   => sl_valid_in,
      islv_data   => slv_data_in,
      oslv_data   => slv_data_out,
      osl_valid   => sl_valid_out,
      osl_rdy     => sl_rdy,
      osl_finish  => sl_finish
    );
  end generate;
  -- gen_net_2 : if C_FOLDER = "test_net_2" generate
  --   dut: entity integration_test_net_2.top
  --   port map (
  --     isl_clk     => sl_clk,
  --     isl_rst_n   => sl_rst_n,
  --     isl_ce      => sl_ce,
  --     isl_get     => sl_get,
  --     isl_start   => sl_start,
  --     isl_valid   => sl_valid_in,
  --     islv_data   => slv_data_in,
  --     oslv_data   => slv_data_out,
  --     osl_valid   => sl_valid_out,
  --     osl_rdy     => sl_rdy,
  --     osl_finish  => sl_finish
  --   );
  -- end generate;
  gen_net_3 : if C_FOLDER = "test_net_3" generate
    dut: entity integration_test_net_3.top
    port map (
      isl_clk     => sl_clk,
      isl_rst_n   => sl_rst_n,
      isl_ce      => sl_ce,
      isl_get     => sl_get,
      isl_start   => sl_start,
      isl_valid   => sl_valid_in,
      islv_data   => slv_data_in,
      oslv_data   => slv_data_out,
      osl_valid   => sl_valid_out,
      osl_rdy     => sl_rdy,
      osl_finish  => sl_finish
    );
  end generate;
  -- gen_net_4 : if C_FOLDER = "test_net_4" generate
  --   dut: entity integration_test_net_4.top
  --   port map (
  --     isl_clk     => sl_clk,
  --     isl_rst_n   => sl_rst_n,
  --     isl_ce      => sl_ce,
  --     isl_get     => sl_get,
  --     isl_start   => sl_start,
  --     isl_valid   => sl_valid_in,
  --     islv_data   => slv_data_in,
  --     oslv_data   => slv_data_out,
  --     osl_valid   => sl_valid_out,
  --     osl_rdy     => sl_rdy,
  --     osl_finish  => sl_finish
  --   );
  -- end generate;
  gen_input_ones : if C_FOLDER = "test_input_ones" generate
    dut: entity integration_test_input_ones.top
    port map (
      isl_clk     => sl_clk,
      isl_rst_n   => sl_rst_n,
      isl_ce      => sl_ce,
      isl_get     => sl_get,
      isl_start   => sl_start,
      isl_valid   => sl_valid_in,
      islv_data   => slv_data_in,
      oslv_data   => slv_data_out,
      osl_valid   => sl_valid_out,
      osl_rdy     => sl_rdy,
      osl_finish  => sl_finish
    );
  end generate;
  -- gen_input_zeros : if C_FOLDER = "test_input_zeros" generate
  --   dut: entity integration_test_input_zeros.top
  --   port map (
  --     isl_clk     => sl_clk,
  --     isl_rst_n   => sl_rst_n,
  --     isl_ce      => sl_ce,
  --     isl_get     => sl_get,
  --     isl_start   => sl_start,
  --     isl_valid   => sl_valid_in,
  --     islv_data   => slv_data_in,
  --     oslv_data   => slv_data_out,
  --     osl_valid   => sl_valid_out,
  --     osl_rdy     => sl_rdy,
  --     osl_finish  => sl_finish
  --   );
  -- end generate;
  gen_test_last_weights_zeros : if C_FOLDER = "test_last_weights_zeros" generate
    dut: entity integration_test_last_weights_zeros.top
    port map (
      isl_clk     => sl_clk,
      isl_rst_n   => sl_rst_n,
      isl_ce      => sl_ce,
      isl_get     => sl_get,
      isl_start   => sl_start,
      isl_valid   => sl_valid_in,
      islv_data   => slv_data_in,
      oslv_data   => slv_data_out,
      osl_valid   => sl_valid_out,
      osl_rdy     => sl_rdy,
      osl_finish  => sl_finish
    );
  end generate;

  main : process
    procedure run_test is
    begin
      wait until rising_edge(sl_clk);
      sl_start_test <= '1';
      wait until rising_edge(sl_clk);
      sl_start_test <= '0';
      wait until rising_edge(sl_clk);
      report active_test_case;
      report running_test_case;
      wait until (stimuli_done and
                  data_check_done and
                  rising_edge(sl_clk));
    end procedure;
  begin
    test_runner_setup(runner, runner_cfg);
    -- don't stop integration tests when one value is wrong
    set_stop_level(failure);
    -- report active_test_case;
    -- report running_test_case;
    -- TODO: check width and height against cnn_parameter.vhd
    data_src.load_csv(tb_path & C_FOLDER & "/input.csv");
    data_ref.load_csv(tb_path & C_FOLDER & "/output.csv");
    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  -- stop integration tests if they are stuck 
  test_runner_watchdog(runner, 50 ms);

  clk_gen(sl_clk, C_CLK_PERIOD);

  stimuli_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start_test = '1';
    stimuli_done <= false;

    wait until rising_edge(sl_clk);
    sl_rst_n <= '1';
    sl_ce <= '1';
    sl_get <= '1';
    sl_start <= '0';
    sl_valid_in <= '0';
    slv_data_in <= (others => '0');
    wait until rising_edge(sl_clk);
    sl_start <= '1';
    wait until rising_edge(sl_clk);
    sl_start <= '0';
    int_pixel_cnt <= 0;

    for x in 0 to data_src.width-1 loop
      for y in 0 to data_src.height-1 loop
        for z in 0 to data_src.depth-1 loop
          wait until rising_edge(sl_clk) and sl_rdy = '1' and sl_valid_in = '0';
          sl_valid_in <= '1';
          slv_data_in <= std_logic_vector(to_signed(data_src.get(x, y, z), C_DATA_WIDTH));
          int_pixel_cnt <= int_pixel_cnt + 1;
          wait until rising_edge(sl_clk);
          sl_valid_in <= '0';
          -- delay, because else too much data would be sent in
          wait until rising_edge(sl_clk);
          wait until rising_edge(sl_clk);
          wait until rising_edge(sl_clk);
        end loop;
      end loop;
    end loop;

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;

    assert data_ref.width = 1 report to_string(data_ref.width);
    assert data_ref.depth = 1 report to_string(data_ref.depth);
    for x in 0 to data_ref.height-1 loop
      wait until rising_edge(sl_clk) and sl_valid_out = '1';
      check_equal(slv_data_out, data_ref.get(x));
    end loop;

    report ("Done checking");
    data_check_done <= true;
  end process;
end behavioral;
