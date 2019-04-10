library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
library util;
  use util.math.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity pe is
  generic (
    C_DATA_WIDTH_DATA     : integer range 1 to 16 := 8;
    C_FRAC_WIDTH_IN       : integer range 0 to 16 := 4;
    C_FRAC_WIDTH_OUT      : integer range 0 to 16 := 4;
    C_DATA_WIDTH_WEIGHTS  : integer range 1 to 16 := 4;
    C_FRAC_WIDTH_WEIGHTS  : integer range 0 to 16 := 3;

    C_WIDTH         : integer range 1 to 512 := 36;
    C_HEIGHT        : integer range 1 to 512 := 16;
    C_CHANNEL_IN    : integer range 1 to 512 := 1;
    C_CHANNEL_OUT   : integer range 1 to 512 := 16;
    C_WIN_SIZE_CONV : integer range 1 to 3 := 3;
    C_STRIDE_CONV   : integer range 1 to 3 := 3;
    C_WIN_SIZE_POOL : integer range 0 to 3 := 2;
    C_STRIDE_POOL   : integer range 0 to 3 := 2;
    C_PAD           : integer range 0 to 1 := 0;
    C_RELU          : std_logic := '0';
    C_LEAKY         : std_logic := '0';
    STR_W_INIT      : string := "";
    STR_B_INIT      : string := ""
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_get   : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
    oslv_data : out std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end pe;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of pe is

  ------------------------------------------
  -- Function: calculate the padding at bottom (dependent of conv stride and kernel size)
  ------------------------------------------
  function f_set_pad_bot return integer is
    variable v_pad : integer range 0 to 1 := 0;
  begin
    if (C_PAD > 0) and (C_PAD >= C_WIN_SIZE_CONV - C_STRIDE_CONV) then
      v_pad := C_PAD - (C_WIN_SIZE_CONV - C_STRIDE_CONV);
    else
      v_pad := C_PAD;
    end if;
    return v_pad;
  end f_set_pad_bot;

  constant C_PAD_BOTTOM : integer range 0 to 1 := f_set_pad_bot;

  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  -- padding
  signal slv_pad_data_out : std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
  signal sl_pad_output_valid : std_logic := '0';
  signal sl_pad_rdy : std_logic := '0';
  signal sl_pad_get : std_logic := '0';

  -- convolution channel burst
  signal slv_conv_data_in : std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
  signal sl_conv_input_valid : std_logic := '0';
  signal sl_conv_burst_rdy : std_logic := '0';

  -- convolution
  signal slv_conv_data_out : std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
  signal sl_conv_output_valid : std_logic := '0';
  signal sl_conv_rdy : std_logic := '0';

  -- relu
  signal slv_relu_data_out : std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
  signal sl_relu_output_valid : std_logic := '0';

  -- maxpool channel burst
  signal slv_pool_burst_data_in : std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
  signal sl_pool_burst_input_valid : std_logic := '0';
  signal sl_pool_burst_rdy : std_logic := '0';

  -- maxpool
  signal slv_pool_data_in : std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
  signal sl_pool_input_valid : std_logic := '0';
  signal sl_pool_rdy : std_logic := '0';

begin
  gen_no_pad : if C_PAD = 0 generate
    sl_pad_output_valid <= isl_valid;
    slv_pad_data_out <= islv_data;
    sl_pad_rdy <= '1';
  end generate;
  gen_pad : if C_PAD > 0 generate
    -------------------------------------------------------
    -- Zero Padding
    -------------------------------------------------------
    sl_pad_get <= sl_conv_burst_rdy and sl_conv_rdy;
    zero_pad : entity work.zero_pad
    generic map(
      C_DATA_WIDTH  => C_DATA_WIDTH_DATA,
      C_CH          => C_CHANNEL_IN,
      C_WIDTH       => C_WIDTH,
      C_HEIGHT      => C_HEIGHT,
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

  gen_no_burst : if C_CHANNEL_IN = 1 generate
    slv_conv_data_in <= slv_pad_data_out;
    sl_conv_input_valid <= sl_pad_output_valid;
    sl_conv_burst_rdy <= '1';
  end generate gen_no_burst;

  gen_burst : if C_CHANNEL_IN > 1 generate
    -----------------------------------
    -- Burst
    -----------------------------------
    channel_burst : entity work.channel_burst
    generic map(
      C_DATA_WIDTH  => C_DATA_WIDTH_DATA,
      C_CH          => C_CHANNEL_IN
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

  -----------------------------------
  -- Convolution with line and window buffer
  -----------------------------------
  conv_buf : entity work.conv_buf
  generic map(
    C_DATA_WIDTH_DATA     => C_DATA_WIDTH_DATA,
    C_FRAC_WIDTH_IN       => C_FRAC_WIDTH_IN,
    C_FRAC_WIDTH_OUT      => C_FRAC_WIDTH_OUT,
    C_DATA_WIDTH_WEIGHTS  => C_DATA_WIDTH_WEIGHTS,
    C_FRAC_WIDTH_WEIGHTS  => C_FRAC_WIDTH_WEIGHTS,

    C_CONV_DIM  => C_WIN_SIZE_CONV,
    C_STRIDE    => C_STRIDE_CONV,
    C_CH_IN     => C_CHANNEL_IN,
    C_CH_OUT    => C_CHANNEL_OUT,
    C_WIDTH     => C_WIDTH+2*C_PAD,
    C_HEIGHT    => C_HEIGHT+2*C_PAD,
    STR_W_INIT  => STR_W_INIT,
    STR_B_INIT  => STR_B_INIT
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

  gen_relu : if C_RELU = '1' generate
    -----------------------------------
    -- ReLU
    -----------------------------------
    relu : entity work.relu
    generic map (
      C_INT_WIDTH   => C_DATA_WIDTH_DATA-C_FRAC_WIDTH_OUT,
      C_FRAC_WIDTH  => C_FRAC_WIDTH_OUT,
      C_LEAKY       => C_LEAKY
    )
    port map (
      isl_clk   => isl_clk,
      isl_ce    => isl_ce,
      isl_valid => sl_conv_output_valid,
      islv_data => slv_conv_data_out,
      oslv_data => slv_relu_data_out,
      osl_valid => sl_relu_output_valid
    );
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

  gen_pool : if C_WIN_SIZE_POOL > 0 generate
    -----------------------------------
    -- Burst
    -----------------------------------
    channel_burst : entity work.channel_burst
    generic map(
      C_DATA_WIDTH  => C_DATA_WIDTH_DATA,
      C_CH          => C_CHANNEL_OUT
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

    -----------------------------------
    -- Maxpool with line and window buffer
    -----------------------------------
    max_buf : entity work.max_buf
    generic map (
      C_INT_WIDTH   => C_DATA_WIDTH_DATA-C_FRAC_WIDTH_OUT,
      C_FRAC_WIDTH  => C_FRAC_WIDTH_OUT,

      C_POOL_DIM  => C_WIN_SIZE_POOL,
      C_STRIDE    => C_STRIDE_POOL,
      C_CH        => C_CHANNEL_OUT,
      C_WIDTH     => (C_WIDTH+2*C_PAD-(C_WIN_SIZE_CONV-C_STRIDE_CONV))/C_STRIDE_CONV,
      C_HEIGHT    => (C_HEIGHT+2*C_PAD-(C_WIN_SIZE_CONV-C_STRIDE_CONV))/C_STRIDE_CONV
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
