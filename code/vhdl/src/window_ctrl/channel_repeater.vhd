
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.array_pkg.all;

entity channel_repeater is
  generic (
    C_BITWIDTH : integer range 1 to 32 := 8;

    C_CH          : integer range 1 to 512 := 16;
    C_REPEAT      : integer range 1 to 512 := 32;
    C_KERNEL_SIZE : integer range 1 to 5   := 3;

    C_PARALLEL_CH : integer range 1 to 512 := 1
  );
  port (
    isl_clk   : in    std_logic;
    isl_valid : in    std_logic;
    ia_data   : in    t_slv_array_2d(0 to C_KERNEL_SIZE - 1, 0 to C_KERNEL_SIZE - 1);
    oa_data   : out   t_kernel_array(0 to C_PARALLEL_CH - 1)(0 to C_KERNEL_SIZE - 1, 0 to C_KERNEL_SIZE - 1);
    osl_valid : out   std_logic;
    osl_rdy   : out   std_logic
  );
end entity channel_repeater;

architecture behavior of channel_repeater is

  signal sl_valid_out   : std_logic := '0';
  signal int_ch_in_cnt  : integer range 0 to C_CH - 1 := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH - 1 := 0;
  signal int_repeat_cnt : integer range 0 to C_REPEAT - 1 := 0;

  signal a_ch : t_kernel_array(0 to C_CH - 1)(0 to C_KERNEL_SIZE - 1, 0 to C_KERNEL_SIZE - 1) := (others => (others => (others => (others => '0'))));

begin

  assert (C_CH mod C_PARALLEL_CH = 0) report "invalid parallelization factor " & to_string(C_PARALLEL_CH);

  gen_data : if C_PARALLEL_CH = 1 generate
    -- isl_valid and osl_valid can be active at the same time,
    -- because each only increments one channel.
    proc_data : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        if (isl_valid = '1') then
          -- TODO: slicing doesn't work in ghdl, report bug
          --       a_ch <= ia_data & a_ch(0 to C_CH-2);
          a_ch(0)   <= ia_data;
          for i in 1 to C_CH - 1 loop
            a_ch(i) <= a_ch(i - 1);
          end loop;
        elsif (sl_valid_out = '1') then
          a_ch(0)   <= a_ch(C_CH - 1);
          for i in 1 to C_CH - 1 loop
            a_ch(i) <= a_ch(i - 1);
          end loop;
        end if;
      end if;

    end process proc_data;

  else generate

    -- isl_valid and osl_valid can't be active at the same time,
    -- because they increment differently.
    -- TODO: enable this assertion and fix the corresponding bugs
    -- assert not (isl_valid = '1' and sl_valid_out = '1')
    --   report "input and output can't be active at the same time, because the buffer gets incremented differently!";
    proc_data : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        if (isl_valid = '1') then
          a_ch(C_CH - 1) <= ia_data;
          for i in 0 to C_CH - 2 loop
            a_ch(i)      <= a_ch(i + 1);
          end loop;
        end if;

        if (sl_valid_out = '1') then
          a_ch(C_CH - C_PARALLEL_CH to C_CH - 1) <= a_ch(0 to C_PARALLEL_CH - 1);
          for i in 0 to C_CH - C_PARALLEL_CH - 1 loop
            a_ch(i)                              <= a_ch(i + C_PARALLEL_CH);
          end loop;
          -- TODO: a_ch <= a_ch(C_PARALLEL_CH to C_CH-1) & a_ch(0 to C_PARALLEL_CH-1);
        end if;
      end if;

    end process proc_data;

  end generate gen_data;

  proc_counter : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_valid = '1') then
        -- for C_PARALLEL_CH = 1 the input can get directly forwarded
        if (C_PARALLEL_CH /= 1 and int_ch_in_cnt /= C_CH - 1) then
          int_ch_in_cnt <= int_ch_in_cnt + 1;
        else
          int_ch_in_cnt <= 0;
          sl_valid_out  <= '1';
        end if;
      end if;

      if (sl_valid_out = '1') then
        if (int_ch_out_cnt /= C_CH - C_PARALLEL_CH) then
          int_ch_out_cnt <= int_ch_out_cnt + C_PARALLEL_CH;
        else
          int_ch_out_cnt <= 0;
          if (int_repeat_cnt /= C_REPEAT - 1) then
            int_repeat_cnt <= int_repeat_cnt + 1;
          else
            -- The output is valid all the time until all repetitions are done.
            int_repeat_cnt <= 0;
            sl_valid_out   <= '0';
          end if;
        end if;
      end if;
    end if;

  end process proc_counter;

  osl_rdy   <= not (sl_valid_out or isl_valid);
  osl_valid <= sl_valid_out;
  oa_data   <= a_ch(0 to C_PARALLEL_CH - 1);

end architecture behavior;
