library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;

library sim;
  use sim.common.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_pool_max is
  generic (
    runner_cfg    : string;
    tb_path       : string;
    C_KSIZE       : integer := 6;
    C_TOTAL_BITS  : integer := 6;
    C_FRAC_BITS   : integer := 3
  );
end entity;

architecture tb of tb_pool_max is
  constant C_CLK_PERIOD : time := 10 ns;

  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_KSIZE*C_KSIZE*C_TOTAL_BITS-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_TOTAL_BITS-1 downto 0) := (others => '0');

  signal sl_start : std_logic := '0';

  shared variable data_src : array_t;
  shared variable data_ref : array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity work.pool_max
  generic map (
    C_KSIZE       => C_KSIZE,
    C_TOTAL_BITS  => C_TOTAL_BITS,
    C_FRAC_BITS   => C_FRAC_BITS
  )
  port map (
    isl_clk   => sl_clk,
    isl_rst_n => '1',
    isl_ce    => '1',
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
    data_src.load_csv(tb_path & "input" & to_string(C_KSIZE) & ".csv");
    data_ref.load_csv(tb_path & "output" & to_string(C_KSIZE) & ".csv");
    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  clk_gen(sl_clk, C_CLK_PERIOD);

  stimuli_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    stimuli_done <= false;

    report ("Sending image of size " &
            to_string(C_KSIZE) & "x" &
            to_string(C_KSIZE));

    wait until rising_edge(sl_clk);
    sl_valid_in <= '1';
    for y in 0 to C_KSIZE-1 loop
      for x in 0 to C_KSIZE-1 loop
        slv_data_in((x+y*C_KSIZE+1)*C_TOTAL_BITS-1 downto (x+y*C_KSIZE)*C_TOTAL_BITS) <= std_logic_vector(to_unsigned(data_src.get(x, y), C_TOTAL_BITS));
      end loop;
    end loop;
    wait until rising_edge(sl_clk);
    sl_valid_in <= '0';

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;
    wait until rising_edge(sl_clk) and sl_valid_out = '1';
    report (to_string(slv_data_out) & " " & to_string(data_ref.get(0, 0)));
    check_equal(slv_data_out, std_logic_vector(to_unsigned(data_ref.get(0, 0), C_TOTAL_BITS)));
    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;
