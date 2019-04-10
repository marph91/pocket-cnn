library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_relu is
  generic (
    runner_cfg : string;
    tb_path : string;
    ref_file : string;
    sample_cnt : integer;
    C_LEAKY : std_logic := '0';
    C_INT_WIDTH : integer := 4;
    C_FRAC_WIDTH : integer := 4
  );
end entity;

architecture tb of tb_relu is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_DATA_WIDTH : integer := C_INT_WIDTH + C_FRAC_WIDTH;

  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');

  signal sl_start : std_logic := '0';

  shared variable data_src : array_t;
  shared variable data_ref : array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity work.relu
  generic map (
    C_INT_WIDTH   => C_INT_WIDTH,
    C_FRAC_WIDTH  => C_FRAC_WIDTH,
    C_LEAKY       => C_LEAKY
  )
  port map (
    isl_clk       => sl_clk,
    isl_ce        => '1',
    isl_valid     => sl_valid_in,
    islv_data     => slv_data_in,
    oslv_data     => slv_data_out,
    osl_valid     => sl_valid_out
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
    data_src.load_csv(tb_path & "input.csv");
    data_ref.load_csv(tb_path & ref_file);
    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  clk_process : process
  begin
    sl_clk <= '1';
    wait for C_CLK_PERIOD/2;
    sl_clk <= '0';
    wait for C_CLK_PERIOD/2;
  end process;

  stimuli_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    stimuli_done <= false;

    wait until rising_edge(sl_clk);
    sl_valid_in <= '1';
    for x in 0 to sample_cnt-1 loop
      slv_data_in <= std_logic_vector(to_signed(data_src.get(x), C_DATA_WIDTH));
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
      report (to_string(slv_data_out) & " " & to_string(data_ref.get(x)));
      check_equal(slv_data_out, data_ref.get(x));
    end loop;

    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;
