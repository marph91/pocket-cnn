library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
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

  signal sl_data_rdy : std_logic := '0';
  signal sl_valid_out : std_logic := '0';
  signal sl_rdy : std_logic := '0';

  signal int_ch_in_cnt : integer range 0 to C_CH-1 := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH-1 := 0;

  signal usig_index_buffer_in,
         usig_index_buffer_out : unsigned(0 downto 0) := "0";

  type t_1d_array is array (natural range 0 to 1) of t_slv_array_1d(0 to C_CH-1);
  signal a_ch : t_1d_array := (others => (others => (others => '0')));

begin
  proc_data: process(isl_clk)
    variable int_index_buffer_in,
             int_index_buffer_out : integer range 0 to 1 := 0;
  begin
    if rising_edge(isl_clk) then
      -- use a buffer, which has two data slots to prevent data from getting lost
      int_index_buffer_in := to_integer(usig_index_buffer_in);
      int_index_buffer_out := to_integer(usig_index_buffer_out);
      if isl_valid = '1' then
        a_ch(int_index_buffer_in)(0) <= islv_data;
        for i in 1 to C_CH-1 loop
          a_ch(int_index_buffer_in)(i) <= a_ch(int_index_buffer_in)(i-1);
        end loop;
      end if;
      if sl_valid_out = '1' then
        a_ch(int_index_buffer_out)(0) <= (others => '0');
        for i in 1 to C_CH-1 loop
          a_ch(int_index_buffer_out)(i) <= a_ch(int_index_buffer_out)(i-1);
        end loop;
      end if;
    end if;
  end process;

  proc_ctrl: process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_start = '1' then
        -- prevent problems with STRIDE /= KERNEL_SIZE at multiple images
        int_ch_in_cnt <= 0;
        int_ch_out_cnt <= 0;
        sl_rdy <= '1';
        usig_index_buffer_in <= "0";
        usig_index_buffer_out <= "0";
      elsif isl_valid = '1' then
        sl_rdy <= '0';
        if int_ch_in_cnt < C_CH-1 then
          int_ch_in_cnt <= int_ch_in_cnt+1;
        else
          int_ch_in_cnt <= 0;
          sl_data_rdy <= '1';
          usig_index_buffer_in <= not usig_index_buffer_in;
        end if;
      end if;

      -- buffer current data until the next element is ready
      if sl_data_rdy = '1' and isl_get = '1' then
        sl_valid_out <= '1';
      end if;

      if sl_valid_out = '1' then
        if int_ch_out_cnt < C_CH-1 then
          int_ch_out_cnt <= int_ch_out_cnt+1;
        else
          int_ch_out_cnt <= 0;
          sl_valid_out <= '0';
          sl_rdy <= '1';
          -- TODO: check if this works with multiple input images.
          --       I. e. when the initial buffer indice are different.
          sl_data_rdy <= '1' when usig_index_buffer_out = usig_index_buffer_in else '0';
          usig_index_buffer_out <= not usig_index_buffer_out;
        end if;
      end if;
    end if;
  end process;

  oslv_data <= a_ch(to_integer(usig_index_buffer_out))(C_CH-1);
  osl_valid <= sl_valid_out;
  osl_rdy <= sl_rdy and isl_get;
end architecture behavior;