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

entity tb_channel_repeater is
  generic (
    runner_cfg        : string;

    C_DATA_WIDTH      : integer;

    C_CH              : integer;
    C_REPEAT          : integer;
    C_KSIZE           : integer;

    C_PARALLEL        : integer
  );
end entity;

architecture tb of tb_channel_repeater is
  signal sl_clk : std_logic := '0';
  signal sl_valid_in : std_logic := '0';
  signal a_data_in : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
  signal a_data_out : t_kernel_array(0 to C_PARALLEL*(C_CH-1))(0 to C_KSIZE-1, 0 to C_KSIZE-1);
  signal sl_valid_out : std_logic := '0';
  signal sl_rdy : std_logic := '0';

  shared variable data_src : integer_array_t;
  shared variable data_ref : integer_array_t;

  signal data_check_done, stimuli_done : boolean := false;
begin
  dut : entity cnn_lib.channel_repeater
  generic map (
    C_DATA_WIDTH  => C_DATA_WIDTH,

    C_CH          => C_CH,
    C_REPEAT      => C_REPEAT,
    C_KSIZE       => C_KSIZE,

    C_PARALLEL    => C_PARALLEL
  )
  port map (
    isl_clk   => sl_clk,
    isl_valid => sl_valid_in,
    ia_data   => a_data_in,
    oa_data   => a_data_out,
    osl_valid => sl_valid_out,
    osl_rdy   => sl_rdy
  );

  main : process
    procedure run_test is
    begin
      wait until rising_edge(sl_clk);

      wait until (stimuli_done and
                  data_check_done and
                  rising_edge(sl_clk));
    end procedure;

  begin
    test_runner_setup(runner, runner_cfg);
    report ("bitwidth: " & to_string(C_DATA_WIDTH));
    report ("Channel in: " & to_string(C_CH));
    report ("Channel out: " & to_string(C_REPEAT));

    data_src := load_csv(tb_path(runner_cfg) & "gen/input_" & to_string(C_KSIZE) & "_" & to_string(C_PARALLEL) & ".csv");
    data_ref := load_csv(tb_path(runner_cfg) & "gen/output_" & to_string(C_KSIZE) & "_" & to_string(C_PARALLEL) & ".csv");

    check_equal(data_src.width, C_KSIZE*C_KSIZE*C_CH, "input_width");
    check_equal(data_src.height, 1, "input_height");
    check_equal(data_src.depth, 1, "input_depth");

    check_equal(data_ref.width, C_KSIZE*C_KSIZE*C_CH*C_REPEAT, "output_width"); -- channels, get repeated C_CH_OUT times
    check_equal(data_ref.height, 1, "output_height");
    check_equal(data_ref.depth, 1, "output_depth");

    run_test;
    test_runner_cleanup(runner);
    wait;
  end process;

  clk_gen(sl_clk, C_CLK_PERIOD);

  stimuli_process : process
    variable i : integer;
  begin
    wait until rising_edge(sl_clk);
    stimuli_done <= false;

    sl_valid_in <= '0';
    wait until rising_edge(sl_clk);

    wait until rising_edge(sl_clk) and sl_rdy = '1';
    sl_valid_in <= '1';
    for ch in 0 to C_CH-1 loop
      for x in 0 to C_KSIZE-1 loop
        for y in 0 to C_KSIZE-1 loop
          i := C_KSIZE*C_KSIZE*ch + C_KSIZE*y + x;
          report "ch: " & to_string(ch) & " x: " & to_string(x) & " y: " & to_string(y) &
                 " data: " & to_string(get(data_src, i));
          a_data_in(x, y) <= std_logic_vector(to_unsigned(get(data_src, i), a_data_in(0, 0)'length));
        end loop;
      end loop;
      wait until rising_edge(sl_clk);
    end loop;
    sl_valid_in <= '0';
    wait until rising_edge(sl_clk);

    stimuli_done <= true;
    wait;
  end process;

  data_check_process : process
    variable i, v_ch_parallel, v_ch : integer;
  begin
    wait until rising_edge(sl_clk);
    data_check_done <= false;
    wait until rising_edge(sl_clk);

    if C_PARALLEL = 0 then
      v_ch_parallel := 1;
    else
      v_ch_parallel := C_CH;
    end if;

    for r in 0 to C_REPEAT-1 loop
      for para_factor in 0 to C_CH/v_ch_parallel-1 loop
        wait until rising_edge(sl_clk) and sl_valid_out = '1';
        for ch in 0 to v_ch_parallel-1 loop
          v_ch := para_factor + ch;
          for x in 0 to C_KSIZE-1 loop
            for y in 0 to C_KSIZE-1 loop
              i := C_KSIZE*C_KSIZE*C_CH*r + C_KSIZE*C_KSIZE*v_ch + C_KSIZE*y + x;
              report "repeat: " & to_string(r) & " ch: " & to_string(v_ch) & " x: " & to_string(x) & " y: " & to_string(y) &
                    " data: " & to_string(get(data_ref, i));
              if C_PARALLEL = 0 then
                check_equal(a_data_out(0)(x, y), get(data_ref, i));
              else
                check_equal(a_data_out(v_ch)(x, y), get(data_ref, i));
              end if;
            end loop;
          end loop;
        end loop;
      end loop;
    end loop;

    report ("Done checking");
    data_check_done <= true;
    wait;
  end process;
end architecture;