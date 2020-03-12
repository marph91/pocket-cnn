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
  use vunit_lib.array_pkg.all;

entity tb_window_ctrl is
  generic (
    runner_cfg        : string;

    C_DATA_TOTAL_BITS : integer;

    C_CH_IN           : integer;
    C_CH_OUT          : integer;
    C_IMG_WIDTH       : integer;
    C_IMG_HEIGHT      : integer;

    C_KSIZE           : integer;
    C_STRIDE          : integer;

    C_PARALLEL        : integer := 0
  );
end entity;

architecture tb of tb_window_ctrl is
  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0) := (others => '0');
  signal a_data_out : t_kernel_array(0 to C_PARALLEL*(C_CH_IN-1))(0 to C_KSIZE-1, 0 to C_KSIZE-1);
  signal sl_valid_out : std_logic := '0';
  signal sl_rdy : std_logic := '0';

  signal sl_start : std_logic := '0';

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity cnn_lib.window_ctrl
  generic map (
    C_DATA_TOTAL_BITS  => C_DATA_TOTAL_BITS,

    C_CH_IN            => C_CH_IN,
    C_CH_OUT           => C_CH_OUT,
    C_IMG_WIDTH        => C_IMG_WIDTH,
    C_IMG_HEIGHT       => C_IMG_HEIGHT,

    C_KSIZE            => C_KSIZE,
    C_STRIDE           => C_STRIDE
  )
  port map (
    isl_clk   => sl_clk,
    isl_rst_n => '1',
    isl_ce    => '1',
    isl_start => sl_start,
    isl_valid => sl_valid_in,
    islv_data => slv_data_in,
    oa_data   => a_data_out,
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
    report ("bitwidth: " & to_string(C_DATA_TOTAL_BITS));
    report ("Sending image of size " &
            to_string(C_IMG_WIDTH) & "x" &
            to_string(C_IMG_HEIGHT) & "x" &
            to_string(C_CH_IN));
    report ("Expecting kernels of size " &
            to_string(C_KSIZE) & "x" &
            to_string(C_KSIZE) & "x" &
            to_string(C_CH_OUT));

    data_src := load_csv(tb_path(runner_cfg) & "input_" & to_string(C_KSIZE) & "_" & to_string(C_STRIDE) & ".csv");
    data_ref := load_csv(tb_path(runner_cfg) & "output_" & to_string(C_KSIZE) & "_" & to_string(C_STRIDE) & ".csv");

    check_equal(data_src.width, C_IMG_WIDTH*C_IMG_HEIGHT*C_CH_IN, "input_width");
    check_equal(data_src.height, 1, "input_height");
    check_equal(data_src.depth, 1, "input_depth");

    check_equal(data_ref.width, C_KSIZE*C_KSIZE*C_CH_IN, "output_width"); -- channels, get repeated C_CH_OUT times
    check_equal(data_ref.height, ((C_IMG_WIDTH-(C_KSIZE-C_STRIDE))/C_STRIDE) *
                                 ((C_IMG_HEIGHT-(C_KSIZE-C_STRIDE))/C_STRIDE), "output_height"); -- number of positions of the kernel
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
    while i < data_src.height*data_src.width*data_src.depth loop
      wait until rising_edge(sl_clk) and sl_rdy = '1';
      sl_valid_in <= '1';
      for ch_in in 0 to C_CH_IN-1 loop
        slv_data_in <= std_logic_vector(to_unsigned(get(data_src, i), slv_data_in'length));
        report_position(i, C_IMG_HEIGHT, C_IMG_WIDTH, C_CH_IN,
                        "input: ", ", val=" & to_string(get(data_src, i)));
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

    -- one row in the output file for each image position
    int_x_out := (C_IMG_WIDTH-(C_KSIZE-C_STRIDE))/C_STRIDE;
    int_y_out := (C_IMG_HEIGHT-(C_KSIZE-C_STRIDE))/C_STRIDE;
    for pos in 0 to int_x_out*int_y_out-1 loop
      for ch_out in 0 to C_CH_OUT-1 loop
        -- reference data stays the same for all output channels of one image position
        for ch_in in 0 to C_CH_IN-1 loop
          wait until rising_edge(sl_clk) and sl_valid_out = '1';
          for x in 0 to C_KSIZE-1 loop
            for y in 0 to C_KSIZE-1 loop
              report to_string(a_data_out(0)(C_KSIZE-1-x, C_KSIZE-1-y)) &
                    " " & to_string(get(data_ref, ch_in*C_KSIZE*C_KSIZE+x+y*C_KSIZE, pos));
              check_equal(a_data_out(0)(C_KSIZE-1-x, C_KSIZE-1-y), get(data_ref, ch_in*C_KSIZE*C_KSIZE+x+y*C_KSIZE, pos),
                          "pos=" & to_string(pos) & ", ch_in=" & to_string(ch_in) & ", ch_out=" & to_string(ch_out));
            end loop;
          end loop;
        end loop;
      end loop;
    end loop;

    report ("Done checking");
    data_check_done <= true;
  end process;
end architecture;