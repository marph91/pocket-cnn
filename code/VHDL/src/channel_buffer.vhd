library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity channel_buffer is
    generic(
    C_DATA_WIDTH  : integer range 1 to 32;
    C_CH          : integer range 1 to 512
  );
  port(
    isl_clk     : in std_logic;
    isl_reset   : in std_logic;
    isl_ce      : in std_logic;
    isl_repeat  : in std_logic;
    isl_valid   : in std_logic;
    islv_data   : in std_logic_vector(C_DATA_WIDTH-1 downto 0);
    oslv_data   : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
    osl_valid   : out std_logic
    );
end channel_buffer;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavior of channel_buffer is
  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  signal sl_valid_out : std_logic := '0';
  signal sl_repeat : std_logic := '0';
  signal int_ch_in_cnt : integer range 0 to C_CH-1 := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH-1 := 0;

  type t_1d_array is array (natural range <>) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  -- type t_wb_din_array is array (natural range <>) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal a_ch : t_1d_array(0 to C_CH - 1);

begin
  proc_data : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        a_ch(0) <= islv_data;
        for i in 1 to C_CH-1 loop
          a_ch(i) <= a_ch(i-1);
        end loop;
      end if;
      if isl_repeat = '1' or sl_repeat = '1' then
        a_ch(0) <= a_ch(C_CH-1);
        for i in 1 to C_CH-1 loop
          a_ch(i) <= a_ch(i-1);
        end loop;
      end if;
    end if;
  end process proc_data;

  proc_channel_buffer : process(isl_clk) is
  begin
    if rising_edge(isl_clk) then
      if isl_ce = '1' then
        if isl_valid = '1' then
          if int_ch_in_cnt < C_CH-1 then
            int_ch_in_cnt <= int_ch_in_cnt+1;
          else
            int_ch_in_cnt <= 0;
            -- repeat saved data for first time
            sl_repeat <= '1';
          end if;
        end if;
        if sl_valid_out = '1' then
          if int_ch_out_cnt < C_CH-1 then
            int_ch_out_cnt <= int_ch_out_cnt+1;
            if int_ch_out_cnt = C_CH-2 then
              sl_repeat <= '0';
            end if;
          else
            int_ch_out_cnt <= 0;
          end if;
        end if;
        sl_valid_out <= isl_repeat or sl_repeat;
      end if;
    end if;
  end process proc_channel_buffer;

  oslv_data <= a_ch(0);
  osl_valid <= sl_valid_out;
end architecture behavior;
