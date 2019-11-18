library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;

library sim;
  use sim.common.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_pool_ave is
  generic (
    runner_cfg    : string;
    tb_path       : string;
    C_TOTAL_BITS  : integer := 3;
    C_FRAC_BITS   : integer := 3;
    C_IMG_WIDTH   : integer := 3;
    C_IMG_HEIGHT  : integer := 3;
    C_IMG_DEPTH   : integer := 3
  );
end entity;

architecture tb of tb_pool_ave is
  constant C_CLK_PERIOD : time := 10 ns;

  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_TOTAL_BITS-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_TOTAL_BITS-1 downto 0) := (others => '0');

  signal sl_start : std_logic := '0';

  shared variable data_src : array_t;
  shared variable data_ref : array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity work.pool_ave
  generic map (
    C_TOTAL_BITS  => C_TOTAL_BITS,
    C_FRAC_BITS   => C_FRAC_BITS,
    C_POOL_CH     => C_IMG_DEPTH,
    C_IMG_WIDTH   => C_IMG_WIDTH,
    C_IMG_HEIGHT  => C_IMG_HEIGHT
  )
  port map (
    isl_clk   => sl_clk,
    isl_rst_n => '1',
    isl_ce    => '1',
    isl_start => sl_start,
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

      wait until (rising_edge(sl_clk) and
                  stimuli_done and
                  data_check_done);
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);
    data_src.load_csv(tb_path & "input.csv");
    data_ref.load_csv(tb_path & "output.csv");
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
            to_string(C_IMG_WIDTH) & "x" &
            to_string(C_IMG_HEIGHT) & "x" &
            to_string(C_IMG_DEPTH));

    for y in 0 to C_IMG_HEIGHT-1 loop
      for x in 0 to C_IMG_WIDTH-1 loop
        wait until rising_edge(sl_clk);
        for w in 0 to C_IMG_DEPTH-1 loop
          sl_valid_in <= '1';
          slv_data_in <= std_logic_vector(to_unsigned(data_src.get(w+(x*C_IMG_DEPTH), y), slv_data_in'length));
          wait until rising_edge(sl_clk);
        end loop;
        sl_valid_in <= '0';
      end loop;
    end loop;

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;
    for w in 0 to C_IMG_DEPTH-1 loop
      wait until rising_edge(sl_clk) and sl_valid_out = '1';
      report ("ch=" & to_string(w) & " " & to_string(slv_data_out) & " " & to_string(data_ref.get(0, w)));
      check_equal(slv_data_out, std_logic_vector(to_unsigned(data_ref.get(0, w), C_TOTAL_BITS)));
    end loop;
    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;