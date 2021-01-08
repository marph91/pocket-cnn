
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.array_pkg.all;

entity output_buffer is
  generic (
    C_TOTAL_BITS : integer range 1 to 16  := 8;
    C_CH         : integer range 1 to 512 := 4
  );
  port (
    isl_clk   : in    std_logic;
    isl_get   : in    std_logic;
    isl_start : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_TOTAL_BITS - 1 downto 0);
    oslv_data : out   std_logic_vector(C_TOTAL_BITS - 1 downto 0);
    osl_valid : out   std_logic;
    osl_rdy   : out   std_logic
  );
end entity output_buffer;

architecture behavioral of output_buffer is

  type t_states is (IDLE, WAIT_RDY, SEND);

  signal state : t_states := IDLE;

  signal int_input_cnt  : integer range 0 to C_CH - 1 := 0;
  signal int_output_cnt : integer range 0 to C_CH - 1 := 0;

  signal a_buffer_in  : t_slv_array_1d(0 to C_CH - 1) := (others => (others => '0'));
  signal a_buffer_out : t_slv_array_1d(0 to C_CH - 1) := (others => (others => '0'));

  signal sl_buffer_rdy : std_logic := '0';

  signal isl_valid_d1 : std_logic := '0';
  signal islv_data_d1 : std_logic_vector(C_TOTAL_BITS - 1 downto 0) := (others => '0');

  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_TOTAL_BITS - 1 downto 0) := (others => '0');

begin

  i_channel_counter : entity util.basic_counter
    generic map (
      C_MAX => C_CH
    )
    port map (
      isl_clk     => isl_clk,
      isl_reset   => isl_start,
      isl_valid   => isl_valid,
      oint_count  => open,
      osl_maximum => sl_buffer_rdy
    );

  -- buffer one full pixel
  -- send only when the next module is ready
  -- new input will be also buffered when output is sent
  proc_output_buffer : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_valid = '1') then
        a_buffer_in <= a_buffer_in(1 to a_buffer_in'HIGH) & islv_data;
      end if;

      case state is

        when IDLE =>
          if (sl_buffer_rdy = '1') then
            a_buffer_out <= a_buffer_in;
            state        <= WAIT_RDY;
          end if;

        when WAIT_RDY =>
          if (isl_get = '1') then
            state        <= SEND;
            sl_valid_out <= '1';
          end if;

        when SEND =>
          a_buffer_out <= a_buffer_out(1 to a_buffer_out'HIGH) & a_buffer_out(0);

          if (int_output_cnt /= C_CH - 1) then
            int_output_cnt <= int_output_cnt + 1;
          else
            int_output_cnt <= 0;
            state          <= IDLE;
            sl_valid_out   <= '0';
          end if;

      end case;

    end if;

  end process proc_output_buffer;

  osl_rdy   <= '1' when state = IDLE else
               '0';
  oslv_data <= a_buffer_out(0);
  osl_valid <= sl_valid_out;

end architecture behavioral;
