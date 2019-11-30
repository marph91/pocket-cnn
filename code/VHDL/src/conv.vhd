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
    C_DATA_TOTAL_BITS     : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN   : integer range 0 to 16 := 4;
    C_DATA_FRAC_BITS_OUT  : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS  : integer range 1 to 16 := 8;
    C_WEIGHTS_FRAC_BITS   : integer range 0 to 16 := 4;
    
    C_KSIZE           : integer range 1 to 3 := 3;
    C_CH_IN           : integer range 1 to 512 := 4;
    C_CH_OUT          : integer range 1 to 512 := 8;
    STR_WEIGHTS_INIT  : string := "/home/workspace/microcnn/code/VHDL/sim/cocotb/conv/weights.txt";
    STR_BIAS_INIT     : string := "/home/workspace/microcnn/code/VHDL/sim/cocotb/conv/bias.txt"
  );
  port (
    isl_clk       : in std_logic;
    isl_rst_n     : in std_logic;
    isl_ce        : in std_logic;
    isl_valid     : in std_logic;
    ia_data       : in t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    oslv_data     : out std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    osl_valid     : out std_logic
  );
end conv;

architecture behavioral of conv is
  constant C_INT_BITS_DATA : integer range 0 to 16 := C_DATA_TOTAL_BITS-C_DATA_FRAC_BITS_IN;

  -- for BRAM
  constant C_BRAM_DATA_WIDTH : integer range C_WEIGHTS_TOTAL_BITS*C_KSIZE*C_KSIZE to C_WEIGHTS_TOTAL_BITS*C_KSIZE*C_KSIZE := C_WEIGHTS_TOTAL_BITS*(C_KSIZE*C_KSIZE);
  constant C_BRAM_SIZE : integer range C_CH_IN*C_CH_OUT to C_CH_IN*C_CH_OUT := C_CH_IN*C_CH_OUT;
  signal usig_addr_cnt : unsigned(log2(C_BRAM_SIZE - 1) - 1 downto 0) := (others => '0');
  constant C_BRAM_ADDR_WIDTH : integer range 1 to usig_addr_cnt'LENGTH := usig_addr_cnt'LENGTH;
  signal slv_ram_weights : std_logic_vector(C_BRAM_DATA_WIDTH-1 downto 0);

  signal usig_addr_cnt_b : unsigned(log2(C_CH_OUT) - 1 downto 0) := (others => '0');
  constant C_BRAM_ADDR_WIDTH_B : integer range 1 to usig_addr_cnt_b'LENGTH := usig_addr_cnt_b'LENGTH;
  signal slv_ram_bias : std_logic_vector(C_WEIGHTS_TOTAL_BITS-1 downto 0);

  -- +log2(C_CH_IN)-1 because all C_CH_IN are summed up -> broaden data width to avoid overflow
  -- new bitwidth = log2(C_CH_IN*(2^old bitwidth-1)) = log2(C_CH_IN) + old bitwidth -> new bw = lb(64) + 8 = 14
  constant C_SUM_TOTAL_BITS : integer range 0 to 32 := C_DATA_TOTAL_BITS+C_WEIGHTS_TOTAL_BITS+1+log2(C_KSIZE-1)*2+log2(C_CH_IN);
  constant C_SUM_FRAC_BITS : integer range 0 to 32 := C_DATA_FRAC_BITS_IN+C_WEIGHTS_FRAC_BITS;
  constant C_SUM_INT_BITS : integer range 0 to 32 := C_SUM_TOTAL_BITS-C_SUM_FRAC_BITS;
  signal sfix_sum : sfixed(C_SUM_INT_BITS-1 downto -C_SUM_FRAC_BITS) := (others => '0');
  -- 1 bit larger than sfix_sum
  signal sfix_sum_bias : sfixed(C_SUM_INT_BITS downto -C_SUM_FRAC_BITS) := (others => '0');

  -- for Convolution
  signal sl_valid_in_d1 : std_logic := '0';
  signal a_data_mm_in : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal a_weights_mm_in : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal slv_conv_data_out : std_logic_vector(C_SUM_TOTAL_BITS-log2(C_CH_IN)-1 downto 0);
  signal sl_conv_valid_out : std_logic := '0';
  signal sl_conv_valid_out_d1 : std_logic := '0';
  signal sl_conv_valid_out_d2 : std_logic := '0';

  signal sl_valid_out : std_logic := '0';
  signal sl_valid_out_d1 : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal int_mm_out_cnt : integer range 0 to C_CH_IN*C_CH_OUT-1 := 0;

  -- debug
  signal int_ch_in_cnt : integer := 0;
  signal int_pixel_in_cnt : integer := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH_OUT-1 := 0;
  signal int_pixel_out_cnt : integer := 0;

begin
  i_bram_weights : entity work.bram
  generic map(
    C_DATA_WIDTH  => C_BRAM_DATA_WIDTH,
    C_ADDR_WIDTH  => C_BRAM_ADDR_WIDTH,
    C_SIZE        => C_BRAM_SIZE,
    C_OUTPUT_REG  => 0, -- TODO: check timing
    STR_INIT      => STR_WEIGHTS_INIT
  )
  port map (
    isl_clk   => isl_clk,
    isl_en    => '1',
    isl_we    => '0',
    islv_addr => std_logic_vector(usig_addr_cnt),
    islv_data => (others => '0'),
    oslv_data => slv_ram_weights
  );
  gen_array_1d: for i in 0 to C_KSIZE-1 generate
    gen_array_2d: for j in 0 to C_KSIZE-1 generate
      a_weights_mm_in(i, j) <= slv_ram_weights(((i+j*C_KSIZE)+1)*C_DATA_TOTAL_BITS-1 downto ((i+j*C_KSIZE))*C_DATA_TOTAL_BITS);
    end generate gen_array_2d;
  end generate gen_array_1d;

  i_bram_bias : entity work.bram
  generic map(
    C_DATA_WIDTH  => C_WEIGHTS_TOTAL_BITS,
    C_ADDR_WIDTH  => C_BRAM_ADDR_WIDTH_B,
    C_SIZE        => C_CH_OUT,
    C_OUTPUT_REG  => 0, -- TODO: check timing
    STR_INIT      => STR_BIAS_INIT
  )
  port map (
    isl_clk   => isl_clk,
    isl_en    => '1',
    isl_we    => '0',
    islv_addr => std_logic_vector(usig_addr_cnt_b),
    islv_data => (others => '0'),
    oslv_data => slv_ram_bias
  );

  i_mm : entity work.mm
  generic map (
    C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,
    C_DATA_FRAC_BITS_IN   => C_DATA_FRAC_BITS_IN,
    C_WEIGHTS_TOTAL_BITS  => C_WEIGHTS_TOTAL_BITS,
    C_WEIGHTS_FRAC_BITS   => C_WEIGHTS_FRAC_BITS,
    C_KSIZE               => C_KSIZE
  )
  port map (
    isl_clk       => isl_clk,
    isl_rst_n     => isl_rst_n,
    isl_ce        => isl_ce,
    isl_valid     => sl_valid_in_d1,
    ia_data       => a_data_mm_in,
    ia_weights    => a_weights_mm_in,
    oslv_data     => slv_conv_data_out,
    osl_valid     => sl_conv_valid_out
  );

  proc_cnt : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        int_pixel_in_cnt <= 0;
        int_pixel_out_cnt <= 0;
      elsif isl_ce = '1' then
        if isl_valid = '1' then
          if int_ch_in_cnt < C_CH_IN*C_CH_OUT-1 then
            int_ch_in_cnt <= int_ch_in_cnt+1;
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
    end if;
  end process proc_cnt;

  proc_data : process(isl_clk)
    variable v_sfix_sum : sfixed(C_SUM_INT_BITS-1 downto -C_SUM_FRAC_BITS) := (others => '0');
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        usig_addr_cnt <= (others => '0');
        usig_addr_cnt_b <= (others => '0');
      elsif isl_ce = '1' then
        if isl_valid = '1' then
          usig_addr_cnt <= unsigned(usig_addr_cnt)+1;
        end if;

        -- wait one cycle for bram data to be available
        sl_valid_in_d1 <= isl_valid;
        a_data_mm_in <= ia_data;

        if sl_conv_valid_out = '1' then
          if int_mm_out_cnt < C_CH_IN-1 then
            int_mm_out_cnt <= int_mm_out_cnt+1;
          else
            int_mm_out_cnt <= 0;
            usig_addr_cnt_b <= unsigned(usig_addr_cnt_b)+1;
          end if;
          if int_mm_out_cnt = 0 then
            v_sfix_sum := (others => '0');
          end if;
          
          v_sfix_sum := resize(
            v_sfix_sum + to_sfixed(slv_conv_data_out,
            C_SUM_INT_BITS-log2(C_CH_IN)-1, -C_SUM_FRAC_BITS),
            C_SUM_INT_BITS-1, -C_SUM_FRAC_BITS, fixed_wrap, fixed_truncate);
          sfix_sum <= v_sfix_sum;
        end if;

        if sl_conv_valid_out_d1 = '1' then
          sfix_sum_bias <= sfix_sum + to_sfixed(slv_ram_bias,
            C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1, -C_WEIGHTS_FRAC_BITS);
        end if;

        if sl_conv_valid_out_d2 = '1' then
          -- resize/round only at this point
          slv_data_out <= to_slv(resize(sfix_sum_bias,
            C_DATA_TOTAL_BITS-C_DATA_FRAC_BITS_OUT-1, -C_DATA_FRAC_BITS_OUT,
            fixed_saturate, fixed_round));
        end if;

        sl_conv_valid_out_d1 <= sl_conv_valid_out;
        sl_conv_valid_out_d2 <= sl_conv_valid_out_d1;
        sl_valid_out <= sl_conv_valid_out_d2 when int_mm_out_cnt = 0 and not (C_CH_IN > 1 and sl_valid_out = '1') else '0';
        sl_valid_out_d1 <= sl_valid_out;
      end if;
    end if;
  end process proc_data;

  oslv_data <= slv_data_out;
  osl_valid <= sl_valid_out_d1 when C_CH_IN > 1 else sl_valid_out;
end behavioral;