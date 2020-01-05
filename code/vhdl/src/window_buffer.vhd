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
  signal a_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

  signal a_win : t_slv_array_2d(0 to C_KSIZE*C_KSIZE - 1, 0 to C_CH - 1) := (others => (others => (others => '0')));
  --TODO: signal a_win : t_slv_array_3d(0 to C_KSIZE-1, 0 to C_KSIZE - 1, 0 to C_CH - 1) := (others => (others => (others => (others => '0'))));
  type t_win_array is array (0 to C_CH - 1) of t_slv_array_1d(0 to C_KSIZE*C_KSIZE - 1);
  signal a_win : t_win_array := (others => (others => (others => '0')));

begin
  proc_shift_data : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        -- shift pixel (each pixel gets shifted to the next position and the buffer gets wrapped)
        for pixel in 1 to C_KSIZE*C_KSIZE-1 loop
          a_win(0)(pixel) <= a_win(C_CH-1)(pixel-1);
        end loop;

        -- insert new input column
        for col in 0 to C_KSIZE - 1 loop
          a_win(0)(col*C_KSIZE) <= ia_data(col);
        end loop;

        -- shift channels (except of the first one, which was the last output and will be discarded now)
        for ch in 1 to C_CH-1 loop
          a_win(ch) <= a_win(ch-1);
        end loop;
      end if;
    end if;
  end process proc_shift_data;

  proc_window_buffer : process(isl_clk)
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
  end process proc_window_buffer;

  output_gen_1d : for i in 0 to C_KSIZE-1 generate
    output_gen_2d : for j in 0 to C_KSIZE-1 generate
      a_data_out(i, j) <= a_win(0)(i+j*C_KSIZE);
    end generate;
  end generate;

  oa_data <= a_data_out;
  osl_valid <= sl_valid_out;
end architecture behavior;