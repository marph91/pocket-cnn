library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_zero_pad is
  generic (
    runner_cfg      : string;
    tb_path         : string;
    C_IMG_WIDTH     : integer := 6;
    C_IMG_HEIGHT    : integer := 6;
    C_CH : integer  := 3
  );
end entity;

architecture tb of tb_zero_pad is
  constant C_CLK_PERIOD : time := 10 ns;
  constant C_DATA_WIDTH : integer := 8;

  signal sl_clk : std_logic := '0';
  signal sl_start : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_WIDTH-1 downto 0) := (others => '0');
  signal sl_rdy : std_logic := '0';
  signal sl_get : std_logic := '1';

  shared variable data_src : array_t;
  shared variable data_ref : array_t;
  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity work.zero_pad
  generic map (
    C_DATA_WIDTH  => C_DATA_WIDTH,
    C_CH          => C_CH,
    C_IMG_WIDTH   => C_IMG_WIDTH,
    C_IMG_HEIGHT  => C_IMG_HEIGHT,
    C_PAD_TOP     => 1,
    C_PAD_BOTTOM  => 1,
    C_PAD_LEFT    => 1,
    C_PAD_RIGHT   => 1
    )
  port map (
    isl_clk     => sl_clk,
    isl_rst_n   => '1',
    isl_ce      => '1',
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
    data_src.load_csv(tb_path & "input.csv");
    data_ref.load_csv(tb_path & "output.csv");
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

    report ("Sending image of size " &
            to_string(data_src.width/C_CH) & "x" &
            to_string(data_src.height) & "x" &
            to_string(C_CH));
    report ("Expecting image of size " &
            to_string(data_ref.width/C_CH) & "x" &
            to_string(data_ref.height) & "x" &
            to_string(C_CH));

    for y in 0 to data_src.height-1 loop
      for x in 0 to data_src.width/C_CH-1 loop
        wait until rising_edge(sl_clk) and sl_rdy = '1';
        sl_valid_in <= '1';
        for w in 0 to C_CH-1 loop
          slv_data_in <= std_logic_vector(to_unsigned(data_src.get(w+(x*C_CH), y), slv_data_in'length));
          report("w=" & to_string(x) & ", h=" & to_string(y) & ", ch=" & to_string(w) & ", in_val=" & to_string(std_logic_vector(to_unsigned(data_src.get(x*(w+1), y), slv_data_in'length))));
          wait until rising_edge(sl_clk);
        end loop;
        sl_valid_in <= '0';
        wait until rising_edge(sl_clk);
      end loop;
    end loop;

    stimuli_done <= true;
  end process;

  data_check_process : process
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;
    for y in 0 to data_ref.height-1 loop
      for x in 0 to data_ref.width-1 loop
        wait until rising_edge(sl_clk) and sl_valid_out = '1';
        report("w=" & to_string(x/C_CH) & ", h=" & to_string(y) & ", ch=" & to_string(x rem C_CH) & ", out_val=" & to_string(slv_data_out));
        check_equal(slv_data_out, data_ref.get(x, y),
                    "w=" & to_string(x/C_CH) & ", h=" & to_string(y) & ", ch=" & to_string(x rem C_CH));
      end loop;
    end loop;
    report ("Done checking image of size " &
            to_string(data_ref.width/C_CH) & "x" &
            to_string(data_ref.height) & "x" &
            to_string(C_CH));
    data_check_done <= true;
  end process;
end architecture;