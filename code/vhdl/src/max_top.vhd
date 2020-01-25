library ieee;
  use ieee.std_logic_1164.all;
library util;
  use util.cnn_pkg.all;

entity max_top is
  generic (
    C_TOTAL_BITS  : integer range 1 to 16 := 8;
    C_FRAC_BITS   : integer range 0 to 16 := 4;

    C_CH          : integer range 1 to 512 := 1;
    C_IMG_WIDTH   : integer range 1 to 512 := 36;
    C_IMG_HEIGHT  : integer range 1 to 512 := 16;

    C_KSIZE       : integer range 0 to 16 := 4;
    C_STRIDE      : integer range 1 to 3 := 1
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_TOTAL_BITS-1 downto 0);
    oslv_data : out std_logic_vector(C_TOTAL_BITS-1 downto 0);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end max_top;

architecture behavioral of max_top is
  signal a_win_data_out : t_kernel_array(0 to 0)(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => (others => '0'))));
  signal slv_win_valid_out : std_logic := '0';

begin
  i_window_ctrl : entity work.window_ctrl
  generic map (
    C_DATA_TOTAL_BITS => C_TOTAL_BITS,

    C_KSIZE           => C_KSIZE,
    C_STRIDE          => C_STRIDE,
    C_CH_IN           => C_CH,
    C_CH_OUT          => 1, -- no repetition at maximum pooling needed
    C_IMG_WIDTH       => C_IMG_WIDTH,
    C_IMG_HEIGHT      => C_IMG_HEIGHT
  )
  port map (
    isl_clk   => isl_clk,
    isl_rst_n => isl_rst_n,
    isl_ce    => isl_ce,
    isl_start => isl_start,
    isl_valid => isl_valid,
    islv_data => islv_data,
    oa_data   => a_win_data_out,
    osl_valid => slv_win_valid_out,
    osl_rdy   => osl_rdy
  );

  i_max : entity work.pool_max
  generic map (
    C_KSIZE       => C_KSIZE,
    C_TOTAL_BITS  => C_TOTAL_BITS,
    C_FRAC_BITS   => C_FRAC_BITS
  )
  port map (
    isl_clk   => isl_clk,
    isl_rst_n => isl_rst_n,
    isl_ce    => isl_ce,
    isl_valid => slv_win_valid_out,
    ia_data   => a_win_data_out(0),
    oslv_data => oslv_data,
    osl_valid => osl_valid
  );
end behavioral;