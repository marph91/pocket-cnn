
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.array_pkg.all;
  use util.math_pkg.all;

library window_ctrl_lib;

entity conv_top is
  generic (
    C_FIRST_STAGE : integer range 0 to 1 := 0;

    C_DATA_TOTAL_BITS    : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN  : integer range 0 to 16 := 4;
    C_DATA_FRAC_BITS_OUT : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS : integer range 1 to 16 := 4;
    C_WEIGHTS_FRAC_BITS  : integer range 0 to 16 := 3;

    C_CH_IN      : integer range 1 to 512 := 1;
    C_CH_OUT     : integer range 1 to 512 := 16;
    C_IMG_WIDTH  : integer range 1 to 512 := 32;
    C_IMG_HEIGHT : integer range 1 to 512 := 32;

    C_KSIZE        : integer range 1 to 5 := 3;
    C_STRIDE       : integer range 1 to 3 := 1;
    C_WEIGHTS_INIT : string               := "";
    C_BIAS_INIT    : string               := "";

    C_PARALLEL_CH : integer range 1 to 512 := 1
  );
  port (
    isl_clk   : in    std_logic;
    isl_start : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
    oslv_data : out   std_logic_vector(C_DATA_TOTAL_BITS - 1 downto 0);
    osl_valid : out   std_logic;
    osl_rdy   : out   std_logic
  );
end entity conv_top;

architecture behavioral of conv_top is

  -- window control
  signal slv_win_data_out : std_logic_vector(C_PARALLEL_CH * C_KSIZE * C_KSIZE * C_DATA_TOTAL_BITS - 1 downto 0);
  signal a_win_data_out   : t_kernel_array(0 to C_PARALLEL_CH - 1)(0 to C_KSIZE - 1, 0 to C_KSIZE - 1);
  signal sl_win_valid_out : std_logic := '0';

  -- weights
  constant C_WEIGHTS    : t_kernel_array := init_weights(C_WEIGHTS_INIT, C_CH_IN * C_CH_OUT, C_KSIZE, 8);
  signal   int_addr_cnt : integer range 0 to C_CH_IN * C_CH_OUT := 0;
  signal   a_weights    : t_kernel_array(0 to C_PARALLEL_CH - 1)(0 to C_KSIZE - 1, 0 to C_KSIZE - 1) := (others => (others => (others => (others => '0'))));

begin

  i_window_ctrl : entity window_ctrl_lib.window_ctrl
    generic map (
      C_BITWIDTH            => C_DATA_TOTAL_BITS,

      C_KERNEL_SIZE         => C_KSIZE,
      C_STRIDE              => C_STRIDE,
      C_CH_IN               => C_CH_IN,
      C_CH_OUT              => C_CH_OUT,
      C_IMG_WIDTH           => C_IMG_WIDTH,
      C_IMG_HEIGHT          => C_IMG_HEIGHT,

      C_PARALLEL_CH         => C_PARALLEL_CH
    )
    port map (
      isl_clk   => isl_clk,
      isl_start => isl_start,
      isl_valid => isl_valid,
      islv_data => islv_data,
      oslv_data => slv_win_data_out,
      osl_valid => sl_win_valid_out,
      osl_rdy   => osl_rdy
    );

  a_win_data_out <= slv_to_array(slv_win_data_out, C_PARALLEL_CH, C_KSIZE);

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
      C_BIAS_INIT           => C_BIAS_INIT,

      C_PARALLEL_CH         => C_PARALLEL_CH
    )
    port map (
      isl_clk    => isl_clk,
      isl_start  => isl_start,
      isl_valid  => sl_win_valid_out,
      ia_data    => a_win_data_out,
      ia_weights => a_weights,
      oslv_data  => oslv_data,
      osl_valid  => osl_valid
    );

  gen_weights : for ch_in in 0 to C_PARALLEL_CH - 1 generate
    a_weights(ch_in) <= C_WEIGHTS(int_addr_cnt + ch_in);
  end generate gen_weights;

  i_address_counter : entity util.basic_counter
    generic map (
      C_MAX => C_CH_IN * C_CH_OUT,
      C_INCREMENT => C_PARALLEL_CH,
      C_COUNT_DOWN => 0
    )
    port map (
      isl_clk     => isl_clk,
      isl_reset   => '0',
      -- weight addresses depend on window control
      isl_valid   => sl_win_valid_out,
      oint_count  => int_addr_cnt,
      osl_maximum => open
    );

end architecture behavioral;
