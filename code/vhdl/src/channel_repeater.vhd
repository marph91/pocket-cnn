library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library util;
  use util.cnn_pkg.all;

entity channel_repeater is
  generic(
    C_DATA_WIDTH  : integer range 1 to 32 := 8;

    C_CH          : integer range 1 to 512 := 16;
    C_REPEAT      : integer range 1 to 512 := 32;
    C_KSIZE       : integer range 1 to 3 := 3;

    C_PARALLEL    : integer range 0 to 1 := 0
  );
  port(
    isl_clk     : in std_logic;
    isl_valid   : in std_logic;
    ia_data     : in t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    oa_data     : out t_kernel_array(0 to C_PARALLEL*(C_CH-1))(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    osl_valid   : out std_logic;
    osl_rdy     : out std_logic
  );
end;

architecture behavior of channel_repeater is
  signal sl_valid_out : std_logic := '0';
  signal int_ch_in_cnt : integer range 0 to C_CH-1 := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH-1 := 0;
  signal int_repeat_cnt : integer range 0 to C_REPEAT-1 := 0;

  signal a_ch : t_kernel_array(0 to C_CH-1)(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => (others => '0'))));

begin
  proc_data : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        a_ch(0) <= ia_data;
        for i in 1 to C_CH-1 loop
          a_ch(i) <= a_ch(i-1);
        end loop;
      elsif C_PARALLEL = 0 and sl_valid_out = '1' then
        a_ch(0) <= a_ch(C_CH-1);
        for i in 1 to C_CH-1 loop
          a_ch(i) <= a_ch(i-1);
        end loop;
      end if;
    end if;
  end process proc_data;

  proc_counter : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        if C_PARALLEL = 1 and int_ch_in_cnt < C_CH-1 then
          int_ch_in_cnt <= int_ch_in_cnt+1;
        else
          int_ch_in_cnt <= 0;
          sl_valid_out <= '1';
        end if;
      end if;

      if sl_valid_out = '1' then
        if C_PARALLEL = 0 and int_ch_out_cnt < C_CH-1 then
          int_ch_out_cnt <= int_ch_out_cnt+1;
        else
          int_ch_out_cnt <= 0;
          if int_repeat_cnt < C_REPEAT-1 then
            int_repeat_cnt <= int_repeat_cnt+1;
          else
            int_repeat_cnt <= 0;
            sl_valid_out <= '0';
          end if;
        end if;
      end if;
    end if;
  end process proc_counter;

  osl_rdy <= not (sl_valid_out or isl_valid);
  osl_valid <= sl_valid_out;
  oa_data(0 to C_PARALLEL*(C_CH-1)) <= a_ch(0 to C_PARALLEL*(C_CH-1));
end architecture behavior;