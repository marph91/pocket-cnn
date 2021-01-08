
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;

library util;
  use util.math_pkg.all;

entity pe is
  generic (
    C_FIRST_STAGE : integer range 0 to 1 := 0;

    C_DATA_TOTAL_BITS    : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN  : integer range 0 to 16 := 4;
    C_DATA_FRAC_BITS_OUT : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS : integer range 1 to 16 := 4;
    C_WEIGHTS_FRAC_BITS  : integer range 0 to 16 := 3;

    C_IMG_WIDTH  : integer range 1 to 512 := 36;
    C_IMG_HEIGHT : integer range 1 to 512 := 16;
    C_CH_IN      : integer range 1 to 512 := 1;
    C_CH_OUT     : integer range 1 to 512 := 16;

    C_CONV_KSIZE   : integer range 1 to 5 := 3;
    C_CONV_STRIDE  : integer range 1 to 3 := 3;
    C_POOL_KSIZE   : integer range 0 to 3 := 2;
    C_POOL_STRIDE  : integer range 0 to 3 := 2;
    C_PAD          : integer range 0 to 1 := 0;
    C_RELU         : std_logic            := '0';
    C_LEAKY        : std_logic            := '0';
    C_WEIGHTS_INIT : string               := "";
    C_BIAS_INIT    : string               := "";

    C_PARALLEL_CH : integer range 1 to 512 := 1
  );
  port (
    isl_clk   : in    std_logic;
    isl_get   : in    std_logic;
    isl_start : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
    oslv_data : out   std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
    osl_valid : out   std_logic;
    osl_rdy   : out   std_logic
  );
end entity pe;

architecture behavioral of pe is

  -- padding
  signal slv_pad_data_out : std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
  signal sl_pad_valid_out : std_logic := '0';
  signal sl_pad_rdy       : std_logic := '0';
  signal sl_pad_get       : std_logic := '0';

  -- convolution
  signal slv_conv_data_out : std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
  signal sl_conv_valid_out : std_logic := '0';
  signal sl_conv_rdy       : std_logic := '0';

  -- relu
  signal slv_relu_data_out : std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
  signal sl_relu_valid_out : std_logic := '0';

  -- maxpool
  signal slv_pool_data_in : std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
  signal sl_pool_valid_in : std_logic := '0';

  -- output buffer
  signal slv_output_buffer_data_in : std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
  signal sl_output_buffer_valid_in : std_logic := '0';
  signal sl_output_buffer_rdy      : std_logic := '0';

  -- debug
  signal int_ch_in_cnt    : integer range 0 to C_CH_IN - 1 := 0;
  signal int_pixel_in_cnt : integer range 0 to C_IMG_HEIGHT * C_IMG_WIDTH := 0;
  signal int_col          : integer range 0 to C_IMG_WIDTH := 0;
  signal int_row          : integer range 0 to C_IMG_HEIGHT := 0;

begin

  -- synthesis translate off
  i_pixel_counter : entity util.pixel_counter(single_process)
    generic map (
      C_HEIGHT  => C_IMG_HEIGHT,
      C_WIDTH   => C_IMG_WIDTH,
      C_CHANNEL => C_CH_IN,
      C_CHANNEL_INCREMENT => C_PARALLEL_CH
    )
    port map (
      isl_clk      => isl_clk,
      isl_reset    => isl_start,
      isl_valid    => isl_valid,
      oint_pixel   => int_pixel_in_cnt,
      oint_row     => int_row,
      oint_column  => int_col,
      oint_channel => int_ch_in_cnt
    );

  -- synthesis translate on

  -- zero padding

  gen_pad : if C_PAD = 0 generate
    sl_pad_valid_out <= isl_valid;
    slv_pad_data_out <= islv_data;
    sl_pad_rdy       <= '1';
  else generate
    sl_pad_get       <= sl_conv_rdy;
    i_zero_pad : entity work.zero_pad
      generic map (
        C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
        C_CH          => C_CH_IN,
        C_IMG_WIDTH   => C_IMG_WIDTH,
        C_IMG_HEIGHT  => C_IMG_HEIGHT,
        C_PAD_TOP     => C_PAD,
        C_PAD_BOTTOM  => C_PAD,
        C_PAD_LEFT    => C_PAD,
        C_PAD_RIGHT   => C_PAD
      )
      port map (
        isl_clk   => isl_clk,
        isl_get   => sl_pad_get,
        isl_start => isl_start,
        isl_valid => isl_valid,
        islv_data => islv_data,
        oslv_data => slv_pad_data_out,
        osl_valid => sl_pad_valid_out,
        osl_rdy   => sl_pad_rdy
      );

  end generate gen_pad;

  -- convolution
  i_conv_top : entity work.conv_top
    generic map (
      C_FIRST_STAGE         => C_FIRST_STAGE,

      C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,
      C_DATA_FRAC_BITS_IN   => C_DATA_FRAC_BITS_IN,
      C_DATA_FRAC_BITS_OUT  => C_DATA_FRAC_BITS_OUT,
      C_WEIGHTS_TOTAL_BITS  => C_WEIGHTS_TOTAL_BITS,
      C_WEIGHTS_FRAC_BITS   => C_WEIGHTS_FRAC_BITS,

      C_KSIZE               => C_CONV_KSIZE,
      C_STRIDE              => C_CONV_STRIDE,
      C_CH_IN               => C_CH_IN,
      C_CH_OUT              => C_CH_OUT,
      C_IMG_WIDTH           => C_IMG_WIDTH + 2 * C_PAD,
      C_IMG_HEIGHT          => C_IMG_HEIGHT + 2 * C_PAD,
      C_WEIGHTS_INIT        => C_WEIGHTS_INIT,
      C_BIAS_INIT           => C_BIAS_INIT,

      C_PARALLEL_CH         => C_PARALLEL_CH
    )
    port map (
      isl_clk   => isl_clk,
      isl_start => isl_start,
      isl_valid => sl_pad_valid_out,
      islv_data => slv_pad_data_out,
      osl_valid => sl_conv_valid_out,
      oslv_data => slv_conv_data_out,
      osl_rdy   => sl_conv_rdy
    );

  gen_no_relu_no_pool : if C_RELU = '0' and C_POOL_KSIZE = 0 generate
    slv_output_buffer_data_in <= slv_conv_data_out;
    sl_output_buffer_valid_in <= sl_conv_valid_out;
  end generate gen_no_relu_no_pool;

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
        isl_valid => sl_conv_valid_out,
        islv_data => slv_conv_data_out,
        oslv_data => slv_relu_data_out,
        osl_valid => sl_relu_valid_out
      );

    -- assign relu outputs

    gen_relu_no_pool : if C_POOL_KSIZE = 0 generate
      slv_output_buffer_data_in <= slv_relu_data_out;
      sl_output_buffer_valid_in <= sl_relu_valid_out;
    else generate
      slv_pool_data_in          <= slv_relu_data_out;
      sl_pool_valid_in          <= sl_relu_valid_out;
    end generate gen_relu_no_pool;

  end generate gen_relu;

  -- max pooling

  gen_pool : if C_POOL_KSIZE > 0 generate
    i_max_top : entity work.max_top
      generic map (
        C_TOTAL_BITS  => C_DATA_TOTAL_BITS,
        C_FRAC_BITS   => C_DATA_FRAC_BITS_OUT,

        C_KSIZE       => C_POOL_KSIZE,
        C_STRIDE      => C_POOL_STRIDE,
        C_CH          => C_CH_OUT,
        C_IMG_WIDTH   => (C_IMG_WIDTH + 2 * C_PAD - C_CONV_KSIZE) / C_CONV_STRIDE + 1,
        C_IMG_HEIGHT  => (C_IMG_HEIGHT + 2 * C_PAD - C_CONV_KSIZE) / C_CONV_STRIDE + 1
      )
      port map (
        isl_clk   => isl_clk,
        isl_start => isl_start,
        isl_valid => sl_pool_valid_in,
        islv_data => slv_pool_data_in,
        oslv_data => slv_output_buffer_data_in,
        osl_valid => sl_output_buffer_valid_in
      );

    gen_pool_no_relu : if C_RELU = '0' generate
      slv_pool_data_in <= slv_conv_data_out;
      sl_pool_valid_in <= sl_conv_valid_out;
    end generate gen_pool_no_relu;

  end generate gen_pool;

  i_output_buffer : entity util.output_buffer
    generic map (
      C_TOTAL_BITS  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_OUT
    )
    port map (
      isl_clk   => isl_clk,
      isl_get   => isl_get,
      isl_start => isl_start,
      isl_valid => sl_output_buffer_valid_in,
      islv_data => slv_output_buffer_data_in,
      oslv_data => oslv_data,
      osl_valid => osl_valid,
      osl_rdy   => sl_output_buffer_rdy
    );

  osl_rdy <= sl_pad_rdy and sl_conv_rdy and sl_output_buffer_rdy and isl_get;

end architecture behavioral;
