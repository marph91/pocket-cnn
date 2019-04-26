library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity channel_buffer is
    generic(
    C_DATA_WIDTH  : integer range 1 to 32;
    C_CH_IN       : integer range 1 to 512; -- C_CH
    C_CH_OUT      : integer range 1 to 512; -- C_REPEAT
    C_WINDOW_SIZE : integer range 1 to 3 := 3
  );
  port(
    isl_clk     : in std_logic;
    isl_reset   : in std_logic;
    isl_ce      : in std_logic;
    isl_valid   : in std_logic;
    islv_data   : in std_logic_vector(C_DATA_WIDTH*C_WINDOW_SIZE*C_WINDOW_SIZE-1 downto 0);
    oslv_data   : out std_logic_vector(C_DATA_WIDTH*C_WINDOW_SIZE*C_WINDOW_SIZE-1 downto 0);
    osl_valid   : out std_logic;
    osl_rdy     : out std_logic
    );
end channel_buffer;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavior of channel_buffer is
  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  signal sl_valid_in : std_logic := '0';
  signal sl_valid_out : std_logic := '0';
  signal int_ch_in_cnt : integer range 0 to C_CH_IN-1 := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH_IN-1 := 0;
  signal int_repeat_cnt : integer range 0 to C_CH_OUT-1 := 0;

  type t_1d_array is array (natural range <>) of std_logic_vector(C_DATA_WIDTH*C_WINDOW_SIZE*C_WINDOW_SIZE - 1 downto 0);
  signal a_ch : t_1d_array(0 to C_CH_IN - 1);

begin
  proc_data : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        a_ch(0) <= islv_data;
        for i in 1 to C_CH_IN-1 loop
          a_ch(i) <= a_ch(i-1);
        end loop;
      elsif sl_valid_out = '1' then
        a_ch(0) <= a_ch(C_CH_IN-1);
        for i in 1 to C_CH_IN-1 loop
          a_ch(i) <= a_ch(i-1);
        end loop;
      end if;
    end if;
  end process proc_data;

  proc_channel_buffer : process(isl_clk) is
  begin
    if rising_edge(isl_clk) then
      if isl_ce = '1' then
        sl_valid_in <= isl_valid;
        if isl_valid = '1' then
          sl_valid_out <= '1';
          if int_ch_in_cnt < C_CH_IN-1 then
            int_ch_in_cnt <= int_ch_in_cnt+1;
          else
            int_ch_in_cnt <= 0;
          end if;
        end if;

        if sl_valid_out = '1' then
          if int_ch_out_cnt < C_CH_IN-1 then
            int_ch_out_cnt <= int_ch_out_cnt+1;
          else
            int_ch_out_cnt <= 0;
            if int_repeat_cnt < C_CH_OUT-1 then
              int_repeat_cnt <= int_repeat_cnt+1;
            else
              int_repeat_cnt <= 0;
              sl_valid_out <= '0';
            end if;
          end if;
        end if;
      end if;
    end if;
  end process proc_channel_buffer;

  osl_rdy <= not (sl_valid_out or sl_valid_in or isl_valid);
  oslv_data <= a_ch(0);
  osl_valid <= sl_valid_out;
end architecture behavior;
