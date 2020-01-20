library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library util;
  use util.cnn_pkg.all;

entity window_buffer is
  generic(
    C_DATA_WIDTH  : integer range 1 to 16 := 8;

    C_CH          : integer range 1 to 512 := 4;

    C_KSIZE       : integer range 1 to 3 := 3
  );
  port(
    isl_clk     : in std_logic;
    isl_reset   : in std_logic;
    isl_ce      : in std_logic;
    isl_valid   : in std_logic;
    ia_data     : in t_slv_array_1d(0 to C_KSIZE-1);
    oa_data     : out t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    osl_valid   : out std_logic
  );
end window_buffer;

architecture behavior of window_buffer is
  signal int_ch_cnt : integer range 0 to C_CH-1 := 0;

  signal sl_valid_out : std_logic := '0';

  type t_win_buffer is array (0 to C_CH - 1) of t_slv_array_2d(0 to C_KSIZE - 1, 0 to C_KSIZE - 1);
  signal a_win_buffer : t_win_buffer := (others => (others => (others => (others => '0'))));

begin
  proc_shift_data: process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        -- shift channel (except of first one, which gets assigned later)
        for ch in 1 to C_CH-1 loop
          a_win_buffer(ch) <= a_win_buffer(ch-1);
        end loop;

        -- shift columns and wrap last channel:
        -- each column gets shifted to the next position and
        -- the last channel of the buffer gets wrapped
        for col in 1 to C_KSIZE-1 loop
          for row in 0 to C_KSIZE-1 loop
            a_win_buffer(0)(col, row) <= a_win_buffer(C_CH-1)(col-1, row);
          end loop;
        end loop;

        -- insert new input column
        for col in 0 to C_KSIZE - 1 loop
          for row in 0 to C_KSIZE-1 loop
            a_win_buffer(0)(0, row) <= ia_data(row);
          end loop;
        end loop;
      end if;
    end if;
  end process proc_shift_data;

  proc_valid_out: process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_ce = '1' then
        if isl_valid = '1' then
          if int_ch_cnt < C_CH-1 then
            int_ch_cnt <= int_ch_cnt+1;
          else
            int_ch_cnt <= 0;
          end if;
        end if;
        sl_valid_out <= isl_valid;
      end if;
    end if;
  end process;

  oa_data <= a_win_buffer(0);
  osl_valid <= sl_valid_out;
end architecture behavior;