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
    islv_data   : in std_logic_vector(C_KSIZE*C_DATA_WIDTH-1 downto 0);
    oa_data     : out t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    osl_valid   : out std_logic
  );
end window_buffer;

architecture behavior of window_buffer is
  signal int_ch_cnt : integer range 0 to C_CH-1 := 0;

  signal sl_valid_out : std_logic := '0';
  signal a_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

  signal a_win : t_slv_array_2d(0 to C_KSIZE*C_KSIZE - 1, 0 to C_CH - 1) := (others => (others => (others => '0')));

begin
  proc_shift_data : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      -- TODO: look for other possibility to replace loops
      --       -> multidimensional slice not allowed
      if isl_valid = '1' then
        -- shift pixel
        for i in 1 to C_KSIZE*C_KSIZE-1 loop
          a_win(i, 0) <= a_win(i-1, C_CH-1);
        end loop;

        -- insert new input column
        for i in 0 to C_KSIZE - 1 loop
          -- normal input
          a_win(i*C_KSIZE,0) <= islv_data((i+1)*C_DATA_WIDTH-1 downto i*C_DATA_WIDTH);
        end loop;

        -- shift channels
        for i in 0 to C_KSIZE*C_KSIZE-1 loop
          for j in 1 to C_CH-1 loop
            a_win(i, j) <= a_win(i, j-1);
          end loop;
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
      a_data_out(i, j) <= a_win(i+j*C_KSIZE, 0);
    end generate output_gen_2d;
  end generate output_gen_1d;

  oa_data <= a_data_out;
  osl_valid <= sl_valid_out;
end architecture behavior;