
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;

library util;
  use util.math_pkg.all;

entity pool_ave is
  generic (
    C_TOTAL_BITS : integer range 1 to 16 := 8;
    C_FRAC_BITS  : integer range 0 to 16 := 8;

    C_POOL_CH    : integer range 1 to 512 := 4;
    C_IMG_WIDTH  : integer range 1 to 512 := 6;
    C_IMG_HEIGHT : integer range 1 to 512 := 6
  );
  port (
    isl_clk   : in    std_logic;
    isl_start : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_TOTAL_BITS - 1 downto 0);
    oslv_data : out   std_logic_vector(C_TOTAL_BITS - 1 downto 0);
    osl_valid : out   std_logic
  );
end entity pool_ave;

architecture behavioral of pool_ave is

  constant C_INT_BITS : integer range 1 to 16 := C_TOTAL_BITS - C_FRAC_BITS;

  -- temporary higher int width to prevent overflow while summing up channel/pixel
  -- new bitwidth = log2(C_IMG_HEIGHT*C_IMG_WIDTH*(2^old bitwidth)) = log2(C_IMG_HEIGHT*C_IMG_WIDTH) + old bitwidth -> new bw = lb(16*(2^7)) = 12
  constant C_INTW_SUM   : integer := C_INT_BITS + log2(C_IMG_HEIGHT * C_IMG_WIDTH);
  constant C_FRACW_REZI : integer range 1 to 16 := 16;

  signal sl_input_valid_d1 : std_logic := '0';
  signal sl_input_valid_d2 : std_logic := '0';
  signal sl_input_valid_d3 : std_logic := '0';

  -- fixed point multiplication yields: A'left + B'left + 1 downto -(A'right + B'right)
  signal    sfix_average    : sfixed(C_INTW_SUM + 1 downto - C_FRAC_BITS - C_FRACW_REZI) := (others => '0');
  attribute use_dsp : string;
  attribute use_dsp of sfix_average : signal is "yes";
  signal    sfix_average_d1 : sfixed(C_INTW_SUM + 1 downto - C_FRAC_BITS - C_FRACW_REZI) := (others => '0');

  -- TODO: try real instead of sfixed
  -- to_sfixed() yields always one fractional bit. Thus the reciprocal has at least 2 integer bits.
  constant C_RECIPROCAL : sfixed(1 downto - C_FRACW_REZI) := reciprocal(to_sfixed(C_IMG_HEIGHT * C_IMG_WIDTH, C_FRACW_REZI, 0));
  signal   slv_average  : std_logic_vector(C_TOTAL_BITS - 1 downto 0) := (others => '0');

  signal int_data_in_cnt : integer range 0 to C_IMG_WIDTH * C_IMG_HEIGHT * C_POOL_CH  - C_POOL_CH + 1 := 0;

  type t_1d_array is array (natural range <>) of sfixed(C_INTW_SUM - 1 downto - C_FRAC_BITS);

  signal a_ch_buffer : t_1d_array(0 to C_POOL_CH - 1) := (others => (others => '0'));

  signal sl_output_valid : std_logic := '0';

begin

  -------------------------------------------------------
  -- Process: Average Pooling (average of each channel)
  -- Stage 1: sum up the values of every channel
  -- Stage 2*: multiply with reciprocal
  -- Stage 3: pipeline DSP output
  -- Stage 4: resize output
  -- *Stage 2 is entered when full image except of last pixel (C_IMG_HEIGHT*C_IMG_WIDTH*C_POOL_CH-C_POOL_CH) is loaded
  -------------------------------------------------------
  proc_pool_ave : process (isl_clk) is

    variable v_sfix_sum : sfixed(C_INTW_SUM - 1 downto - C_FRAC_BITS);

  begin

    if (rising_edge(isl_clk)) then
      if (isl_start = '1') then
        a_ch_buffer     <= (others => (others => '0'));
        int_data_in_cnt <= C_IMG_HEIGHT * C_IMG_WIDTH * C_POOL_CH - C_POOL_CH + 1;
      else
        sl_input_valid_d1 <= isl_valid;
        if (int_data_in_cnt = 0) then
          sl_input_valid_d2 <= sl_input_valid_d1;
        end if;
        sl_input_valid_d3 <= sl_input_valid_d2;
        sl_output_valid   <= sl_input_valid_d3;

        if (isl_valid = '1') then
          if (int_data_in_cnt /= 0) then
            int_data_in_cnt <= int_data_in_cnt - 1;
          end if;
          v_sfix_sum := resize(
                        a_ch_buffer(C_POOL_CH - 1) +
                        to_sfixed(islv_data,
                        C_INT_BITS - 1, - C_FRAC_BITS),
                        v_sfix_sum, fixed_wrap, fixed_truncate);
          a_ch_buffer <= v_sfix_sum & a_ch_buffer(0 to a_ch_buffer'HIGH - 1);
        end if;

        ------------------------DIVIDE OPTIONS---------------------------
        -- 1. simple divide
        -- sfix_average <= a_ch_buffer(0)/to_sfixed(C_IMG_HEIGHT*C_IMG_WIDTH, 8, 0);
        --
        -- 2. divide with round properties (round, guard bits)
        -- sfix_average <= divide(a_ch_buffer(0), to_sfixed(C_IMG_HEIGHT*C_IMG_WIDTH, 8, 0), fixed_truncate, 0)
        --
        -- 3. multiply with reciprocal -> best for timing and ressource usage!
        -- sfix_average <= a_ch_buffer(0) * C_RECIPROCAL;
        -----------------------------------------------------------------

        if (sl_input_valid_d1 = '1') then
          sfix_average <= a_ch_buffer(0) * C_RECIPROCAL;
        end if;

        if (sl_input_valid_d2 = '1') then
          sfix_average_d1 <= sfix_average;
        end if;

        if (sl_input_valid_d3 = '1') then
          slv_average <= to_slv(resize(
                         sfix_average_d1,
                         C_INT_BITS - 1, - C_FRAC_BITS, fixed_wrap, fixed_round));
        end if;
      end if;
    end if;

  end process proc_pool_ave;

  oslv_data <= slv_average;
  osl_valid <= sl_output_valid;

end architecture behavioral;
