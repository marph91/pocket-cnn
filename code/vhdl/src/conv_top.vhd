library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;

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
  -- window control
  signal a_win_data_out, a_win_data_out_d1 : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal sl_win_valid_out, sl_win_valid_out_d1 : std_logic := '0';

  -- weights and bias (BRAM)
  constant C_BRAM_DATA_WIDTH : integer := C_WEIGHTS_TOTAL_BITS*(C_KSIZE*C_KSIZE);
  constant C_BRAM_SIZE : integer := C_CH_IN*C_CH_OUT;
  signal usig_addr_cnt : unsigned(log2(C_BRAM_SIZE) - 1 downto 0) := (others => '0');
  constant C_BRAM_ADDR_WIDTH : integer := usig_addr_cnt'LENGTH;
  signal slv_weights : std_logic_vector(C_BRAM_DATA_WIDTH-1 downto 0);
  signal a_weights : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

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
    osl_valid => sl_win_valid_out,
    osl_rdy   => osl_rdy
  );

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
    oslv_data => slv_weights
  );
  gen_array_1d: for i in 0 to C_KSIZE-1 generate
    gen_array_2d: for j in 0 to C_KSIZE-1 generate
      a_weights(i, j) <= slv_weights(((i+j*C_KSIZE)+1)*C_WEIGHTS_TOTAL_BITS-1 downto (i+j*C_KSIZE)*C_WEIGHTS_TOTAL_BITS);
    end generate;
  end generate;

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
    STR_BIAS_INIT         => STR_BIAS_INIT
  )
  port map (
    isl_clk    => isl_clk,
    isl_rst_n  => isl_rst_n,
    isl_ce     => isl_ce,
    isl_valid  => sl_win_valid_out_d1,
    ia_data    => a_win_data_out_d1,
    ia_weights => a_weights,
    oslv_data  => oslv_data,
    osl_valid  => osl_valid
  );

  proc_data : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        usig_addr_cnt <= (others => '0');
        -- usig_addr_cnt_b <= (others => '0');
      elsif isl_ce = '1' then
        -- delay window control data for synchronisation with weight BRAM 
        a_win_data_out_d1 <= a_win_data_out;
        sl_win_valid_out_d1 <= sl_win_valid_out;

        -- weight BRAM addresses depend on window control
        if sl_win_valid_out = '1' then
          if usig_addr_cnt < C_BRAM_SIZE-1 then
            usig_addr_cnt <= unsigned(usig_addr_cnt) + 1;
          else
            usig_addr_cnt <= (others => '0');
          end if;
        end if;
      end if;
    end if;
  end process;
end behavioral;