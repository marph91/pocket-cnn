library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;

library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;

library sim;
  use sim.common.all;

library vunit_lib;
  context vunit_lib.vunit_context;
  use vunit_lib.array_pkg.all;

entity tb_max_top is
  generic (
    runner_cfg        : string;
    tb_path           : string;

    C_TOTAL_BITS      : integer;
    C_FRAC_BITS       : integer;

    C_CH              : integer;
    C_IMG_WIDTH       : integer;
    C_IMG_HEIGHT      : integer;

    C_KSIZE           : integer;
    C_STRIDE          : integer
  );
end entity;

architecture tb of tb_max_top is
  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_TOTAL_BITS-1 downto 0) := (others => '0');
  signal slv_data_out : std_logic_vector(C_TOTAL_BITS-1 downto 0) := (others => '0');
  signal sl_valid_out : std_logic := '0';
  signal sl_rdy : std_logic := '0';
  signal sl_get : std_logic := '1';

  signal sl_start : std_logic := '0';

  shared variable data_src : array_t;
  shared variable data_ref : array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity work.max_top
  generic map (
    C_TOTAL_BITS       => C_TOTAL_BITS,
    C_FRAC_BITS        => C_FRAC_BITS,

    C_CH               => C_CH,
    C_IMG_WIDTH        => C_IMG_WIDTH,
    C_IMG_HEIGHT       => C_IMG_HEIGHT,

    C_KSIZE            => C_KSIZE,
    C_STRIDE           => C_STRIDE
  )
  port map (
    isl_clk   => sl_clk,
    isl_rst_n => '1',
    isl_ce    => '1',
    isl_get   => sl_get,
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
    report ("bitwidth: " & to_string(C_TOTAL_BITS));
    report ("Sending image of size " &
            to_string(C_IMG_WIDTH) & "x" &
            to_string(C_IMG_HEIGHT) & "x" &
            to_string(C_CH));

    data_src.load_csv(tb_path & "input_" & to_string(C_KSIZE) & "_" & to_string(C_STRIDE) & ".csv");
    data_ref.load_csv(tb_path & "output_" & to_string(C_KSIZE) & "_" & to_string(C_STRIDE) & ".csv");

    check_equal(data_src.width, C_IMG_WIDTH*C_IMG_HEIGHT*C_CH, "input_width");
    check_equal(data_src.height, 1, "input_height");
    check_equal(data_src.depth, 1, "input_depth");

    check_equal(data_ref.width, ((C_IMG_WIDTH-(C_KSIZE-C_STRIDE))/C_STRIDE) * 
                                ((C_IMG_HEIGHT-(C_KSIZE-C_STRIDE))/C_STRIDE) * -- number of positions of the kernel
                                C_CH, "output_width");
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

    sl_valid_in <= '0';
    wait until rising_edge(sl_clk);

    -- increment stream based: channel > width > height
    while i < data_src.height*data_src.width*data_src.depth-1 loop
    -- for i in 0 to data_src.height*data_src.width*data_src.depth-1 loop
      wait until rising_edge(sl_clk) and sl_rdy = '1';
      sl_valid_in <= '1';
      for ch_in in 0 to C_CH-1 loop
        slv_data_in <= std_logic_vector(to_unsigned(data_src.get(i), slv_data_in'length));
        report("input: " & "i=" & to_string(i) &
               ", in_val=" & to_string(std_logic_vector(to_unsigned(data_src.get(i), slv_data_in'length)))) &
               " " & to_string(data_src.get(i));
        wait until rising_edge(sl_clk);
        i := i + 1;
      end loop;
      sl_valid_in <= '0';
    end loop;
    wait until rising_edge(sl_clk);

    stimuli_done <= true;
  end process;

  data_check_process : process
    variable int_x_out, int_y_out : integer;
  begin
    wait until rising_edge(sl_clk) and sl_start = '1';
    data_check_done <= false;
    wait until rising_edge(sl_clk);

    int_x_out := (C_IMG_WIDTH-(C_KSIZE-C_STRIDE))/C_STRIDE;
    int_y_out := (C_IMG_HEIGHT-(C_KSIZE-C_STRIDE))/C_STRIDE;
    for i in 0 to int_x_out*int_y_out*C_CH-1 loop
      wait until rising_edge(sl_clk) and sl_valid_out = '1';
      check_equal(slv_data_out, data_ref.get(i));
      -- TODO: convert i to height, width, channel for easier debugging
    end loop;
    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;