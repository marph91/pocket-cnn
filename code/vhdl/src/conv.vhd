library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;
library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;

entity conv is
  generic (
    C_FIRST_STAGE         : integer range 0 to 1;

    C_DATA_TOTAL_BITS     : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN   : integer range 0 to 16 := 4;
    C_DATA_FRAC_BITS_OUT  : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS  : integer range 1 to 16 := 8;
    C_WEIGHTS_FRAC_BITS   : integer range 0 to 16 := 4;

    C_CH_IN           : integer range 1 to 512 := 4;
    C_CH_OUT          : integer range 1 to 512 := 8;

    C_KSIZE           : integer range 1 to 3 := 3;
    C_BIAS_INIT       : string := "";

    C_PARALLEL_CH     : integer range 1 to 512 := 1
  );
  port (
    isl_clk       : in std_logic;
    isl_valid     : in std_logic;
    ia_data       : in t_kernel_array(0 to C_PARALLEL_CH-1)(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    ia_weights    : in t_kernel_array(0 to C_PARALLEL_CH-1)(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    oslv_data     : out std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    osl_valid     : out std_logic
  );
end conv;

architecture behavioral of conv is
  -- +log2(C_CH_IN)-1 because all C_CH_IN are summed up -> broaden data width to avoid overflow
  -- new bitwidth = log2(C_CH_IN*(2^old bitwidth-1)) = log2(C_CH_IN) + old bitwidth -> new bw = lb(64) + 8 = 14
  constant C_SUM_TOTAL_BITS : integer range 1 to 32 := C_DATA_TOTAL_BITS+C_WEIGHTS_TOTAL_BITS+1+log2(C_KSIZE-1)*2+log2(C_CH_IN)+C_FIRST_STAGE;
  constant C_SUM_FRAC_BITS : integer range 0 to 32 := C_DATA_FRAC_BITS_IN+C_WEIGHTS_FRAC_BITS;
  constant C_SUM_INT_BITS : integer range 1 to 32 := C_SUM_TOTAL_BITS-C_SUM_FRAC_BITS;
  signal sfix_sum : sfixed(C_SUM_INT_BITS-1 downto -C_SUM_FRAC_BITS) := (others => '0');
  -- 1 bit larger than sfix_sum
  signal sfix_sum_bias : sfixed(C_SUM_INT_BITS downto -C_SUM_FRAC_BITS) := (others => '0');

  -- convolution
  type t_slv_array is array(natural range <>) of std_logic_vector;
  signal slv_mm_data_out : t_slv_array(0 to C_PARALLEL_CH-1)(C_SUM_TOTAL_BITS-log2(C_CH_IN)-1 downto 0);
  signal sl_mm_valid_out : std_logic_vector(C_PARALLEL_CH-1 downto 0) := (others => '0');
  signal sl_mm_valid_out_d1 : std_logic := '0';

  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal int_mm_out_cnt : integer range 0 to C_CH_IN*C_CH_OUT-1 := 0;

  -- bias
  constant C_BIAS : t_kernel_array := init_weights(C_BIAS_INIT, C_CH_OUT, 1, 8);
  signal int_addr_cnt_b : integer range 0 to C_BIAS'HIGH := 0;
  signal slv_bias : std_logic_vector(C_WEIGHTS_TOTAL_BITS-1 downto 0);

  -- debug
  signal int_ch_in_cnt : integer := 0;
  signal int_pixel_in_cnt : integer := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH_OUT-1 := 0;
  signal int_pixel_out_cnt : integer := 0;

begin
  gen_mm: for ch_in in 0 to C_PARALLEL_CH-1 generate
    i_mm : entity work.mm
    generic map (
      C_FIRST_STAGE         => C_FIRST_STAGE,

      C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,
      C_DATA_FRAC_BITS_IN   => C_DATA_FRAC_BITS_IN,
      C_WEIGHTS_TOTAL_BITS  => C_WEIGHTS_TOTAL_BITS,
      C_WEIGHTS_FRAC_BITS   => C_WEIGHTS_FRAC_BITS,

      C_KSIZE               => C_KSIZE
    )
    port map (
      isl_clk       => isl_clk,
      isl_valid     => isl_valid,
      ia_data       => ia_data(ch_in),
      ia_weights    => ia_weights(ch_in),
      oslv_data     => slv_mm_data_out(ch_in),
      osl_valid     => sl_mm_valid_out(ch_in)
    );
  end generate;

  proc_cnt : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_valid = '1' then
        if int_ch_in_cnt < C_CH_IN*C_CH_OUT-C_PARALLEL_CH then
          int_ch_in_cnt <= int_ch_in_cnt+C_PARALLEL_CH;
        else
          int_ch_in_cnt <= 0;
          int_pixel_in_cnt <= int_pixel_in_cnt+1;
        end if;
      end if;

      if sl_valid_out = '1' then
        if int_ch_out_cnt < C_CH_OUT-1 then
          int_ch_out_cnt <= int_ch_out_cnt+1;
        else
          int_ch_out_cnt <= 0;
          int_pixel_out_cnt <= int_pixel_out_cnt+1;
        end if;
      end if;
    end if;
  end process proc_cnt;

  proc_data : process(isl_clk)
    variable v_sfix_sum : sfixed(C_SUM_INT_BITS-1 downto -C_SUM_FRAC_BITS) := (others => '0');
  begin
    if rising_edge(isl_clk) then
      sl_mm_valid_out_d1 <= sl_mm_valid_out(0);

      if sl_mm_valid_out(0) = '1' then
        if C_PARALLEL_CH = 1 and int_mm_out_cnt < C_CH_IN-1 then
          int_mm_out_cnt <= int_mm_out_cnt+1;
        else
          int_mm_out_cnt <= 0;

          -- bias addresses depend on output channel
          if int_addr_cnt_b < C_CH_OUT-1 then
            int_addr_cnt_b <= int_addr_cnt_b + 1;
          else
            int_addr_cnt_b <= 0;
          end if;
        end if;

        -- assign the first value (bias)
        if int_mm_out_cnt = 0 then
          v_sfix_sum := resize(to_sfixed(C_BIAS(int_addr_cnt_b)(0, 0),
            C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1, -C_WEIGHTS_FRAC_BITS),
            C_SUM_INT_BITS-1, -C_SUM_FRAC_BITS, fixed_wrap, fixed_truncate);
        end if;

        for ch_in in 0 to C_PARALLEL_CH-1 loop
          -- always resize the values -> without round, sfix_sum should be big enough
          -- TODO: adder tree needed?
          v_sfix_sum := resize(
            v_sfix_sum + to_sfixed(slv_mm_data_out(ch_in),
              C_SUM_INT_BITS-log2(C_CH_IN)-1, -C_SUM_FRAC_BITS),
            C_SUM_INT_BITS-1, -C_SUM_FRAC_BITS, fixed_wrap, fixed_truncate);
        end loop;
        sfix_sum <= v_sfix_sum;
      end if;

      if sl_mm_valid_out_d1 = '1' then
        -- resize with round only at this point
        slv_data_out <= to_slv(resize(sfix_sum,
          C_DATA_TOTAL_BITS-C_DATA_FRAC_BITS_OUT-1, -C_DATA_FRAC_BITS_OUT,
          fixed_saturate, fixed_round));
      end if;

      sl_valid_out <= sl_mm_valid_out_d1 when int_mm_out_cnt = 0 else '0';
    end if;
  end process proc_data;

  oslv_data <= slv_data_out;
  osl_valid <= sl_valid_out;
end behavioral;