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

entity tb_mm is
  generic (
    runner_cfg            : string;

    C_FIRST_STAGE         : integer;
    C_DATA_TOTAL_BITS     : integer;
    C_DATA_FRAC_BITS_IN   : integer;
    C_WEIGHTS_TOTAL_BITS  : integer;
    C_WEIGHTS_FRAC_BITS   : integer;

    C_KSIZE               : integer
  );
end entity;

architecture tb of tb_mm is
  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal a_data_in,
         a_weights_in : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_TOTAL_BITS+C_WEIGHTS_TOTAL_BITS+log2(C_KSIZE-1)*2+C_FIRST_STAGE downto 0) := (others => '0');

  signal sl_start : std_logic := '0';

  shared variable data_src : integer_array_t;
  shared variable weights_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity cnn_lib.mm
  generic map (
    C_FIRST_STAGE         => C_FIRST_STAGE,

    C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,
    C_DATA_FRAC_BITS_IN   => C_DATA_FRAC_BITS_IN,
    C_WEIGHTS_TOTAL_BITS  => C_WEIGHTS_TOTAL_BITS,
    C_WEIGHTS_FRAC_BITS   => C_WEIGHTS_FRAC_BITS,

    C_KSIZE               => C_KSIZE
  )
  port map (
    isl_clk    => sl_clk,
    isl_valid  => sl_valid_in,
    ia_data    => a_data_in,
    ia_weights => a_weights_in,
    oslv_data  => slv_data_out,
    osl_valid  => sl_valid_out
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
    if C_FIRST_STAGE = 1 then
      data_src := load_csv(tb_path(runner_cfg) & "input_data_stage1.csv");
      weights_src := load_csv(tb_path(runner_cfg) & "input_weights_stage1.csv");
      data_ref := load_csv(tb_path(runner_cfg) & "output_stage1.csv");
    else
      data_src := load_csv(tb_path(runner_cfg) & "input_data" & to_string(C_KSIZE) & ".csv");
      weights_src := load_csv(tb_path(runner_cfg) & "input_weights" & to_string(C_KSIZE) & ".csv");
      data_ref := load_csv(tb_path(runner_cfg) & "output" & to_string(C_KSIZE) & ".csv");
    end if;

    check_equal(data_src.width, C_KSIZE, "input_width");
    check_equal(data_src.height, C_KSIZE, "input_height");
    check_equal(data_src.depth, 1, "input_depth");

    check_equal(weights_src.width, C_KSIZE, "input_width");
    check_equal(weights_src.height, C_KSIZE, "input_height");
    check_equal(weights_src.depth, 1, "input_depth");

    check_equal(data_ref.width, 1, "output_width");
    check_equal(data_ref.height, 1, "output_height");
    check_equal(data_ref.depth, 1, "output_depth");
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
    for x in 0 to C_KSIZE-1 loop
      for y in 0 to C_KSIZE-1 loop
        a_data_in(x, y) <= std_logic_vector(to_unsigned(get(data_src, x, y), C_DATA_TOTAL_BITS));
        a_weights_in(x, y) <= std_logic_vector(to_unsigned(get(weights_src, x, y), C_WEIGHTS_TOTAL_BITS));
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
    report (to_string(slv_data_out) & " " & to_string(get(data_ref, 0, 0)));
    report to_string(C_DATA_TOTAL_BITS+C_WEIGHTS_TOTAL_BITS+log2(C_KSIZE-1)*2);
    check_equal(slv_data_out, std_logic_vector(to_unsigned(get(data_ref, 0, 0),
      C_DATA_TOTAL_BITS+C_WEIGHTS_TOTAL_BITS+log2(C_KSIZE-1)*2+1+C_FIRST_STAGE)));

    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;
