library ieee;
  use ieee.std_logic_1164.all;
library util;
  use util.cnn_pkg.all;

entity channel_burst is
  generic(
    C_DATA_WIDTH  : integer range 1 to 32 := 8;

    C_CH          : integer range 1 to 512 := 8
  );
  port(
    isl_clk   : in std_logic;
    isl_reset : in std_logic;
    isl_get   : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_DATA_WIDTH-1 downto 0);
    oslv_data : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end channel_burst;

architecture behavior of channel_burst is
  signal sl_valid_in : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal slv_data_in_d1 : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal sl_bursted : std_logic := '0';

  signal sl_rdy : std_logic := '0';
  signal sl_valid_out : std_logic := '0';
  signal int_ch_in_cnt : integer range 0 to C_CH := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH := 0;
  signal int_ch_to_burst : integer range 0 to C_CH := 0;

  signal a_ch : t_slv_array_1d(0 to C_CH) := (others => (others => '0'));

begin
  proc_data : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      -- 0 to C_CH, that isl_valid = '1' and int_ch_to_burst > 1 can be handled at the same time
      if isl_valid = '1' then
        a_ch(0) <= islv_data;
        for i in 1 to C_CH loop
          a_ch(i) <= a_ch(i-1);
        end loop;
      end if;
      if (int_ch_to_burst <= 1) or
        (int_ch_to_burst = C_CH and isl_get = '0' and sl_valid_out <= '0') or
        (isl_start = '1') then
          sl_valid_out <= '0';
      else
        for i in 1 to C_CH loop
          a_ch(i) <= a_ch(i-1);
        end loop;
        sl_valid_out <= '1';
      end if;
    end if;
  end process proc_data;

  proc_cnt : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      sl_valid_in <= isl_valid;
      slv_data_in <= islv_data;
      slv_data_in_d1 <= slv_data_in;

      if isl_start = '1' then
        sl_bursted <= '0';
        -- prevent problems with STRIDE /= KERNEL_SIZE at multiple images
        int_ch_to_burst <= 0;
        int_ch_in_cnt <= 0;
        int_ch_out_cnt <= 0;
      elsif isl_valid = '1' then
        if sl_valid_in = '1' and isl_get = '1' then
          -- signal is already in burst mode
          sl_bursted <= '1';
        end if;
        if int_ch_in_cnt < C_CH-1 then
          int_ch_in_cnt <= int_ch_in_cnt+1;
        else
          if sl_bursted = '0' then
            int_ch_to_burst <= C_CH;
          end if;
          int_ch_in_cnt <= 0;
        end if;
      elsif sl_valid_in = '0' and int_ch_out_cnt = C_CH-1 then
        sl_bursted <= '0';
      end if;

      if sl_valid_out = '1' then
        int_ch_to_burst <= int_ch_to_burst-1;
      end if;

      if isl_start = '0' and (sl_bursted = '1' or sl_valid_out = '1') then
        if int_ch_out_cnt < C_CH-1 then
          int_ch_out_cnt <= int_ch_out_cnt+1;
        else
          int_ch_out_cnt <= 0;
        end if;
      end if;

      -- TODO: osl_rdy changes to '0' one input too early
      if int_ch_in_cnt = C_CH-1 or int_ch_to_burst > 0 or sl_bursted = '1' then
        sl_rdy <= '0';
      else
        sl_rdy <= '1';
      end if;
    end if;
  end process proc_cnt;

  oslv_data <= slv_data_in_d1 when sl_bursted = '1' else a_ch(C_CH);
  osl_valid <= sl_bursted or sl_valid_out;
  osl_rdy <= sl_rdy and isl_get;
end architecture behavior;