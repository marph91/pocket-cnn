library ieee;
  use ieee.std_logic_1164.all;
library util;
  use util.cnn_pkg.all;

entity conv_top is
  generic (
    C_FIRST_STAGE         : integer range 0 to 1;

    C_DATA_TOTAL_BITS     : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN   : integer range 0 to 16 := 4;
    C_DATA_FRAC_BITS_OUT  : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS  : integer range 1 to 16 := 4;
    C_WEIGHTS_FRAC_BITS   : integer range 0 to 16 := 3;

    C_CH_IN           : integer range 1 to 512 := 1;
    C_CH_OUT          : integer range 1 to 512 := 16;
    C_IMG_WIDTH       : integer range 1 to 512 := 32;
    C_IMG_HEIGHT      : integer range 1 to 512 := 32;

    C_KSIZE           : integer range 1 to 3 := 3;
    C_STRIDE          : integer range 1 to 3 := 1;
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
end conv_top;

architecture behavioral of conv_top is
  signal a_win_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal slv_win_valid_out : std_logic := '0';

begin
  i_window_ctrl : entity work.window_ctrl
  generic map (
    C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,

    C_KSIZE       => C_KSIZE,
    C_STRIDE      => C_STRIDE,
    C_CH_IN       => C_CH_IN,
    C_CH_OUT      => C_CH_OUT,
    C_IMG_WIDTH   => C_IMG_WIDTH,
    C_IMG_HEIGHT  => C_IMG_HEIGHT
  )
  port map (
    isl_clk   => isl_clk,
    isl_rst_n => isl_rst_n,
    isl_ce    => isl_ce,
    isl_get   => isl_get,
    isl_start => isl_start,
    isl_valid => isl_valid,
    islv_data => islv_data,
    oa_data   => a_win_data_out,
    osl_valid => slv_win_valid_out,
    osl_rdy   => osl_rdy
  );

  i_conv : entity work.conv
  generic map (
    C_FIRST_STAGE         => C_FIRST_STAGE,
    C_DATA_TOTAL_BITS     => C_DATA_TOTAL_BITS,
    C_DATA_FRAC_BITS_IN   => C_DATA_FRAC_BITS_IN,
    C_DATA_FRAC_BITS_OUT  => C_DATA_FRAC_BITS_OUT,
    C_WEIGHTS_TOTAL_BITS  => C_WEIGHTS_TOTAL_BITS,
    C_WEIGHTS_FRAC_BITS   => C_WEIGHTS_FRAC_BITS,
    C_KSIZE               => C_KSIZE,
    C_CH_IN               => C_CH_IN,
    C_CH_OUT              => C_CH_OUT,
    STR_WEIGHTS_INIT      => STR_WEIGHTS_INIT,
    STR_BIAS_INIT         => STR_BIAS_INIT
  )
  port map (
    isl_clk   => isl_clk,
    isl_rst_n => isl_rst_n,
    isl_ce    => isl_ce,
    isl_valid => slv_win_valid_out,
    ia_data   => a_win_data_out,
    oslv_data => oslv_data,
    osl_valid => osl_valid
  );
end behavioral;