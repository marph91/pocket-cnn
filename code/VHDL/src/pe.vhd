library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
library util;
  use util.math.all;

entity pe is
  generic (
    C_DATA_TOTAL_BITS     : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN   : integer range 0 to 16 := 4;
    C_DATA_FRAC_BITS_OUT  : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS  : integer range 1 to 16 := 4;
    C_WEIGHTS_FRAC_BITS   : integer range 0 to 16 := 3;

    C_IMG_WIDTH       : integer range 1 to 512 := 36;
    C_IMG_HEIGHT      : integer range 1 to 512 := 16;
    C_CH_IN           : integer range 1 to 512 := 1;
    C_CH_OUT          : integer range 1 to 512 := 16;
    C_CONV_KSIZE      : integer range 1 to 3 := 3;
    C_CONV_STRIDE     : integer range 1 to 3 := 3;
    C_WIN_SIZE_POOL   : integer range 0 to 3 := 2;
    C_POOL_STRIDE     : integer range 0 to 3 := 2;
    C_PAD             : integer range 0 to 1 := 0;
    C_RELU            : std_logic := '0';
    C_LEAKY           : std_logic := '0';
    STR_WEIGHTS_INIT  : string := "";
    STR_BIAS_INIT     : string := ""
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_get   : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    oslv_data : out std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end pe;

architecture behavioral of pe is

  -- calculate the padding at bottom (dependent of conv stride and kernel size)
  function f_set_pad_bottom return integer is
    variable v_pad : integer range 0 to 1 := 0;
  begin
    if (C_PAD > 0) and (C_PAD >= C_CONV_KSIZE - C_CONV_STRIDE) then
      v_pad := C_PAD - (C_CONV_KSIZE - C_CONV_STRIDE);
    else
      v_pad := C_PAD;
    end if;
    return v_pad;
  end f_set_pad_bottom;

  -- padding
  constant C_PAD_BOTTOM : integer range 0 to 1 := f_set_pad_bottom;
  signal slv_pad_data_out : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal sl_pad_output_valid : std_logic := '0';
  signal sl_pad_rdy : std_logic := '0';
  signal sl_pad_get : std_logic := '0';

  -- convolution channel burst
  signal slv_conv_data_in : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal sl_conv_input_valid : std_logic := '0';
  signal sl_conv_burst_rdy : std_logic := '0';

  -- convolution
  signal slv_conv_data_out : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal sl_conv_output_valid : std_logic := '0';
  signal sl_conv_rdy : std_logic := '0';

  -- relu
  signal slv_relu_data_out : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal sl_relu_output_valid : std_logic := '0';

  -- maxpool channel burst
  signal slv_pool_burst_data_in : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal sl_pool_burst_input_valid : std_logic := '0';
  signal sl_pool_burst_rdy : std_logic := '0';

  -- maxpool
  signal slv_pool_data_in : std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal sl_pool_input_valid : std_logic := '0';
  signal sl_pool_rdy : std_logic := '0';

  -- debug
  signal int_ch_in_cnt : integer range 0 to C_CH_IN-1 := 0;
  signal int_pixel_in_cnt : integer range 0 to C_IMG_HEIGHT*C_IMG_WIDTH := 0;
  signal int_col : integer range 0 to C_IMG_WIDTH := 0;
  signal int_row : integer range 0 to C_IMG_HEIGHT := 0;

begin
  proc_cnt : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        int_pixel_in_cnt <= 0;
        int_ch_in_cnt <= 0;
        int_col <= 0;
        int_row <= 0;
      elsif isl_start = '1' then
        -- have to be resetted at start because of odd kernels (3x3+2) -> image dimensions arent fitting kernel stride
        int_pixel_in_cnt <= 0;
        int_ch_in_cnt <= 0;
        int_col <= 0;
        int_row <= 0;
      elsif isl_ce = '1' then
        if isl_valid = '1' then
          if int_ch_in_cnt < C_CH_IN-1 then
            int_ch_in_cnt <= int_ch_in_cnt+1;
          else
            int_ch_in_cnt <= 0;
            int_pixel_in_cnt <= int_pixel_in_cnt+1;
            if int_col < C_IMG_WIDTH-1 then
              int_col <= int_col+1;
            else
              int_col <= 0;
              if int_row < C_IMG_HEIGHT-1 then
                int_row <= int_row+1;
              else
                int_row <= 0;
              end if;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process proc_cnt;

  -- zero padding
  gen_no_pad : if C_PAD = 0 generate
    sl_pad_output_valid <= isl_valid;
    slv_pad_data_out <= islv_data;
    sl_pad_rdy <= '1';
  end generate;

  gen_pad : if C_PAD > 0 generate
    sl_pad_get <= sl_conv_burst_rdy and sl_conv_rdy;
    i_zero_pad : entity work.zero_pad
    generic map(
      C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_IN,
      C_IMG_WIDTH   => C_IMG_WIDTH,
      C_IMG_HEIGHT  => C_IMG_HEIGHT,
      C_PAD_TOP     => C_PAD,
      C_PAD_BOTTOM  => C_PAD_BOTTOM,
      C_PAD_LEFT    => C_PAD,
      C_PAD_RIGHT   => C_PAD
    )
    port map(
      isl_clk   => isl_clk,
      isl_rst_n => isl_rst_n,
      isl_ce    => isl_ce,
      isl_get   => sl_pad_get,
      isl_start => isl_start,
      isl_valid => isl_valid,
      islv_data => islv_data,
      oslv_data => slv_pad_data_out,
      osl_valid => sl_pad_output_valid,
      osl_rdy   => sl_pad_rdy
    );
  end generate;

  -- burst
  gen_no_burst : if C_CH_IN = 1 generate
    slv_conv_data_in <= slv_pad_data_out;
    sl_conv_input_valid <= sl_pad_output_valid;
    sl_conv_burst_rdy <= '1';
  end generate gen_no_burst;

  gen_burst : if C_CH_IN > 1 generate
    i_channel_burst_conv : entity work.channel_burst
    generic map(
      C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_IN
    )
    port map(
      isl_clk   => isl_clk,
      isl_reset => isl_rst_n,
      isl_get   => sl_conv_rdy,
      isl_start => isl_start,
      isl_valid => sl_pad_output_valid,
      islv_data => slv_pad_data_out,
      oslv_data => slv_conv_data_in,
      osl_valid => sl_conv_input_valid,
      osl_rdy   => sl_conv_burst_rdy
    );
  end generate gen_burst;

  -- convolution
  i_conv_top : entity work.conv_top
  generic map(
    C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,
    C_DATA_FRAC_BITS_IN   => C_DATA_FRAC_BITS_IN,
    C_DATA_FRAC_BITS_OUT  => C_DATA_FRAC_BITS_OUT,
    C_WEIGHTS_TOTAL_BITS  => C_WEIGHTS_TOTAL_BITS,
    C_WEIGHTS_FRAC_BITS   => C_WEIGHTS_FRAC_BITS,

    C_KSIZE           => C_CONV_KSIZE,
    C_STRIDE          => C_CONV_STRIDE,
    C_CH_IN           => C_CH_IN,
    C_CH_OUT          => C_CH_OUT,
    C_IMG_WIDTH       => C_IMG_WIDTH+2*C_PAD,
    C_IMG_HEIGHT      => C_IMG_HEIGHT+2*C_PAD,
    STR_WEIGHTS_INIT  => STR_WEIGHTS_INIT,
    STR_BIAS_INIT     => STR_BIAS_INIT
  )
  port map(
    isl_clk   => isl_clk,
    isl_rst_n => isl_rst_n,
    isl_ce    => isl_ce,
    isl_get   => isl_get,
    isl_start => isl_start,
    isl_valid => sl_conv_input_valid,
    islv_data => slv_conv_data_in,
    osl_valid => sl_conv_output_valid,
    oslv_data => slv_conv_data_out,
    osl_rdy   => sl_conv_rdy
  );

  gen_no_relu_no_pool : if C_RELU = '0' and C_WIN_SIZE_POOL = 0 generate
    sl_pool_rdy <= '1';
    oslv_data <= slv_conv_data_out;
    osl_valid <= sl_conv_output_valid;
  end generate;

  -- relu
  gen_relu : if C_RELU = '1' generate
    i_relu : entity work.relu
    generic map (
      C_TOTAL_BITS => C_DATA_TOTAL_BITS,
      C_FRAC_BITS  => C_DATA_FRAC_BITS_OUT,
      C_LEAKY      => C_LEAKY
    )
    port map (
      isl_clk   => isl_clk,
      isl_ce    => isl_ce,
      isl_valid => sl_conv_output_valid,
      islv_data => slv_conv_data_out,
      oslv_data => slv_relu_data_out,
      osl_valid => sl_relu_output_valid
    );

    -- assign relu outputs
    gen_relu_no_pool : if C_WIN_SIZE_POOL = 0 generate
      sl_pool_rdy <= '1';
      oslv_data <= slv_relu_data_out;
      osl_valid <= sl_relu_output_valid;
    end generate;
    gen_relu_pool : if C_WIN_SIZE_POOL > 0 generate
      slv_pool_data_in <= slv_relu_data_out;
      sl_pool_input_valid <= sl_relu_output_valid;
    end generate;
  end generate;

  -- max pooling
  gen_pool : if C_WIN_SIZE_POOL > 0 generate
    i_channel_burst_max : entity work.channel_burst
    generic map(
      C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_OUT
    )
    port map(
      isl_clk   => isl_clk,
      isl_reset => isl_rst_n,
      isl_get   => '1',
      isl_start => isl_start,
      isl_valid => sl_pool_input_valid,
      islv_data => slv_pool_data_in,
      oslv_data => slv_pool_burst_data_in,
      osl_valid => sl_pool_burst_input_valid,
      osl_rdy   => sl_pool_burst_rdy
    );

    i_max_top : entity work.max_top
    generic map (
      C_TOTAL_BITS  => C_DATA_TOTAL_BITS,
      C_FRAC_BITS   => C_DATA_FRAC_BITS_OUT,

      C_KSIZE       => C_WIN_SIZE_POOL,
      C_STRIDE      => C_POOL_STRIDE,
      C_CH          => C_CH_OUT,
      C_IMG_WIDTH   => (C_IMG_WIDTH+2*C_PAD-(C_CONV_KSIZE-C_CONV_STRIDE))/C_CONV_STRIDE,
      C_IMG_HEIGHT  => (C_IMG_HEIGHT+2*C_PAD-(C_CONV_KSIZE-C_CONV_STRIDE))/C_CONV_STRIDE
    )
    port map (
      isl_clk   => isl_clk,
      isl_rst_n => isl_rst_n,
      isl_ce    => isl_ce,
      isl_get   => '1',
      isl_start => isl_start,
      isl_valid => sl_pool_burst_input_valid,
      islv_data => slv_pool_burst_data_in,
      oslv_data => oslv_data,
      osl_valid => osl_valid,
      osl_rdy   => sl_pool_rdy
    );

    gen_pool_no_relu : if C_RELU = '0' generate
      slv_pool_data_in <= slv_conv_data_out;
      sl_pool_input_valid <= sl_conv_output_valid;
    end generate;
  end generate;

  osl_rdy <= sl_pad_rdy and sl_conv_burst_rdy and sl_conv_rdy and isl_get;
end behavioral;