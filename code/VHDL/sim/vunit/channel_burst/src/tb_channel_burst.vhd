library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library sim;
  use sim.common.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_channel_burst is
  generic (
    runner_cfg    : string;
    tb_path       : string;
    interval      : integer;
    C_DATA_WIDTH  : integer;
    C_CH          : integer
  );
end entity;

architecture tb of tb_channel_burst is
  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');

  signal sl_start : std_logic := '0';
  signal sl_rdy : std_logic := '0';

  shared variable data_src_ref : array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity work.channel_burst
  generic map(
    C_DATA_WIDTH  => C_DATA_WIDTH,
    C_CH          => C_CH
  )
  port map(
    isl_clk   => sl_clk,
    isl_reset => '1',
    isl_get   => '1',
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
    data_src_ref.load_csv(tb_path & "input_output.csv");

    check_equal(data_src_ref.width, C_CH, "output_width");
    check_equal(data_src_ref.height, 1, "output_height");
    check_equal(data_src_ref.depth, 1, "output_depth");
    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  clk_gen(sl_clk, C_CLK_PERIOD);

  stimuli_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    stimuli_done <= false;

    wait until rising_edge(sl_clk);
    for x in 0 to data_src_ref.width-1 loop
      sl_valid_in <= '1';
      slv_data_in <= std_logic_vector(to_signed(data_src_ref.get(x), C_DATA_WIDTH));
      wait until rising_edge(sl_clk);
      sl_valid_in <= '0';
      for i in 1 to interval loop
        wait until rising_edge(sl_clk);
      end loop;
    end loop;

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;

    wait until rising_edge(sl_clk) and sl_valid_out = '1';
    for x in 0 to data_src_ref.width-1 loop
      report (to_string(slv_data_out) & " " & to_string(data_src_ref.get(x)));
      check_equal(sl_valid_out, '1');
      check_equal(slv_data_out, data_src_ref.get(x));
      wait until rising_edge(sl_clk);
    end loop;

    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;
