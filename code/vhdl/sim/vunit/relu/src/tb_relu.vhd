library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library cnn_lib;

library sim;
  use sim.common.all;

library vunit_lib;
  context vunit_lib.vunit_context;

entity tb_relu is
  generic (
    runner_cfg    : string;
    leaky_string  : string;
    sample_cnt    : integer;
    C_LEAKY       : std_logic := '0';
    C_TOTAL_BITS  : integer := 4;
    C_FRAC_BITS   : integer := 4
  );
end entity;

architecture tb of tb_relu is
  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_TOTAL_BITS-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_TOTAL_BITS-1 downto 0) := (others => '0');

  signal sl_start : std_logic := '0';

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity cnn_lib.relu
  generic map (
    C_TOTAL_BITS  => C_TOTAL_BITS,
    C_FRAC_BITS   => C_FRAC_BITS,
    C_LEAKY       => C_LEAKY
  )
  port map (
    isl_clk   => sl_clk,
    isl_valid => sl_valid_in,
    islv_data => slv_data_in,
    oslv_data => slv_data_out,
    osl_valid => sl_valid_out
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
    data_src := load_csv(tb_path(runner_cfg) & "input" & leaky_string & ".csv");
    data_ref := load_csv(tb_path(runner_cfg) & "output" & leaky_string & ".csv");
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
    sl_valid_in <= '1';
    for x in 0 to sample_cnt-1 loop
      slv_data_in <= std_logic_vector(to_unsigned(get(data_src, x), C_TOTAL_BITS));
      wait until rising_edge(sl_clk);
    end loop;
    sl_valid_in <= '0';

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;

    for x in 0 to sample_cnt-1 loop
      wait until rising_edge(sl_clk) and sl_valid_out = '1';
      report (to_string(slv_data_out) & " " & to_string(get(data_ref, x)));
      check_equal(slv_data_out, get(data_ref, x));
    end loop;

    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;
