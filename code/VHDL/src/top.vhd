library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;
library util;
  use util.math.all;

  use work.cnn_parameter.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity top is
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
    osl_rdy   : out std_logic;
    osl_finish  : out std_logic
  );
end top;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of top is
  type t_img_size_array is array (1 to C_PE) of integer range 1 to 512;

  ------------------------------------------
  -- Function: calculate the image size at every layer
  ------------------------------------------
  function f_calc_size (size : in integer range 1 to 512) return t_img_size_array is
    variable v_a_size       : t_img_size_array;
  begin
    v_a_size(1) := size;
    for i in 2 to C_PE loop
      -- stride conv just useful if no pooling layer in pe (either reduce image dimensions in conv OR pool)
      -- ite to protect from division by 0
      if (C_STRIDE_POOL(i-1) > 0) then
        v_a_size(i) := ((v_a_size(i-1)+2*C_PAD(i-1)-(C_CONV_KSIZE(i-1)-C_CONV_STRIDE(i-1)))/C_CONV_STRIDE(i-1)-(C_WIN_POOL(i-1)-C_STRIDE_POOL(i-1)))/C_STRIDE_POOL(i-1);
      else
        v_a_size(i) := (v_a_size(i-1)+2*C_PAD(i-1)-(C_CONV_KSIZE(i-1)-C_CONV_STRIDE(i-1)))/C_CONV_STRIDE(i-1);
      end if;
    end loop;
    return v_a_size;
  end f_calc_size;

  constant C_WIDTH : t_img_size_array := f_calc_size(C_WIDTH_IN);
  constant C_HEIGHT : t_img_size_array := f_calc_size(C_HEIGHT_IN);

  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  signal sl_output_valid      : std_logic_vector(0 to C_PE+1) := (others => '0');

  type t_data_array is array (0 to C_PE+1) of std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
  signal a_data_out         : t_data_array := (others => (others => '0'));

  -- C_PE+1 == isl_get
  signal slv_rdy          : std_logic_vector(1 to C_PE+1) := (others => '0');

  -- signals for finish interrupt
  signal int_data_out_cnt     : integer range 0 to C_CH(C_CH'RIGHT) := 0;
  signal sl_output_finish     : std_logic := '0';

begin
  -----------------------------------
  -- Stage 0 (preprocessing input)
  -----------------------------------
  prepr : entity work.prepr
  generic map (
    C_INT_WIDTH   => C_BITWIDTH(1, 0)-C_BITWIDTH(1, 1),
    C_FRAC_WIDTH  => C_BITWIDTH(1, 1),
    C_SHIFT     => log2(C_SCALE)
  )
  port map (
    isl_valid     => isl_valid,
    islv_data   => islv_data,
    oslv_data     => a_data_out(0),
    osl_valid     => sl_output_valid(0)
    );

  slv_rdy(C_PE+1) <= isl_get;
  -----------------------------------
  -- Stage 1
  -----------------------------------
  stage1 : entity work.pe
  generic map (
    C_DATA_WIDTH_DATA   => C_BITWIDTH(1, 0),
    C_FRAC_WIDTH_IN     => C_BITWIDTH(1, 1),
    C_FRAC_WIDTH_OUT    => C_BITWIDTH(1, 2),
    C_DATA_WIDTH_WEIGHTS  => C_BITWIDTH(1, 3),
    C_FRAC_WIDTH_WEIGHTS  => C_BITWIDTH(1, 4),

    C_WIDTH     => C_WIDTH(1),
    C_HEIGHT    => C_HEIGHT(1),
    C_CH_IN  => C_CH(1-1),
    C_CH_OUT => C_CH(1),
    C_CONV_KSIZE => C_CONV_KSIZE(1),
    C_CONV_STRIDE => C_CONV_STRIDE(1),
    C_WIN_SIZE_POOL => C_WIN_POOL(1),
    C_STRIDE_POOL => C_STRIDE_POOL(1),
    C_PAD     => C_PAD(1),
    C_RELU      => C_RELU(1),
    C_LEAKY     => C_LEAKY_RELU(1),
    STR_W_INIT    => STR_W_INIT(1),
    STR_B_INIT    => STR_B_INIT(1)
  )
  port map (
    isl_clk     => isl_clk,
    isl_rst_n     => isl_rst_n,
    isl_ce      => isl_ce,
    isl_get     => slv_rdy(1+1),
    isl_start   => isl_start,
    isl_valid     => sl_output_valid(1-1),
    islv_data   => a_data_out(1-1),
    oslv_data     => a_data_out(1),
    osl_valid     => sl_output_valid(1),
    osl_rdy     => slv_rdy(1)
  );

  -----------------------------------
  -- Stage 2
  -----------------------------------
  stage2 : entity work.pe
  generic map (
    C_DATA_WIDTH_DATA   => C_BITWIDTH(2, 0),
    C_FRAC_WIDTH_IN     => C_BITWIDTH(2, 1),
    C_FRAC_WIDTH_OUT    => C_BITWIDTH(2, 2),
    C_DATA_WIDTH_WEIGHTS  => C_BITWIDTH(2, 3),
    C_FRAC_WIDTH_WEIGHTS  => C_BITWIDTH(2, 4),

    C_WIDTH     => C_WIDTH(2),
    C_HEIGHT    => C_HEIGHT(2),
    C_CH_IN  => C_CH(2-1),
    C_CH_OUT => C_CH(2),
    C_CONV_KSIZE => C_CONV_KSIZE(2),
    C_CONV_STRIDE => C_CONV_STRIDE(2),
    C_WIN_SIZE_POOL => C_WIN_POOL(2),
    C_STRIDE_POOL => C_STRIDE_POOL(2),
    C_PAD     => C_PAD(2),
    C_RELU      => C_RELU(2),
    C_LEAKY     => C_LEAKY_RELU(2),
    STR_W_INIT    => STR_W_INIT(2),
    STR_B_INIT    => STR_B_INIT(2)
  )
  port map (
    isl_clk     => isl_clk,
    isl_rst_n     => isl_rst_n,
    isl_ce      => isl_ce,
    isl_get     => slv_rdy(2+1),
    isl_start   => isl_start,
    isl_valid     => sl_output_valid(2-1),
    islv_data   => a_data_out(2-1),
    oslv_data     => a_data_out(2),
    osl_valid     => sl_output_valid(2),
    osl_rdy     => slv_rdy(2)
  );

  -----------------------------------
  -- Stage 3
  -----------------------------------
  stage3 : entity work.pe
  generic map (
    C_DATA_WIDTH_DATA   => C_BITWIDTH(3, 0),
    C_FRAC_WIDTH_IN     => C_BITWIDTH(3, 1),
    C_FRAC_WIDTH_OUT    => C_BITWIDTH(3, 2),
    C_DATA_WIDTH_WEIGHTS  => C_BITWIDTH(3, 3),
    C_FRAC_WIDTH_WEIGHTS  => C_BITWIDTH(3, 4),

    C_WIDTH     => C_WIDTH(3),
    C_HEIGHT    => C_HEIGHT(3),
    C_CH_IN  => C_CH(3-1),
    C_CH_OUT => C_CH(3),
    C_CONV_KSIZE => C_CONV_KSIZE(3),
    C_CONV_STRIDE => C_CONV_STRIDE(3),
    C_WIN_SIZE_POOL => C_WIN_POOL(3),
    C_STRIDE_POOL => C_STRIDE_POOL(3),
    C_PAD     => C_PAD(3),
    C_RELU      => C_RELU(3),
    C_LEAKY     => C_LEAKY_RELU(3),
    STR_W_INIT    => STR_W_INIT(3),
    STR_B_INIT    => STR_B_INIT(3)
  )
  port map (
    isl_clk     => isl_clk,
    isl_rst_n     => isl_rst_n,
    isl_ce      => isl_ce,
    isl_get     => '1',--slv_rdy(3+1),
    isl_start   => isl_start,
    isl_valid     => sl_output_valid(3-1),
    islv_data   => a_data_out(3-1),
    oslv_data     => a_data_out(3),
    osl_valid     => sl_output_valid(3),
    osl_rdy     => slv_rdy(3)
  );

  -----------------------------------
  -- Stage 4
  -----------------------------------
  stage4 : entity work.pe
  generic map (
    C_DATA_WIDTH_DATA   => C_BITWIDTH(4, 0),
    C_FRAC_WIDTH_IN     => C_BITWIDTH(4, 1),
    C_FRAC_WIDTH_OUT    => C_BITWIDTH(4, 2),
    C_DATA_WIDTH_WEIGHTS  => C_BITWIDTH(4, 3),
    C_FRAC_WIDTH_WEIGHTS  => C_BITWIDTH(4, 4),

    C_WIDTH     => C_WIDTH(4),
    C_HEIGHT    => C_HEIGHT(4),
    C_CH_IN  => C_CH(4-1),
    C_CH_OUT => C_CH(4),
    C_CONV_KSIZE => C_CONV_KSIZE(4),
    C_CONV_STRIDE => C_CONV_STRIDE(4),
    C_WIN_SIZE_POOL => C_WIN_POOL(4),
    C_STRIDE_POOL => C_STRIDE_POOL(4),
    C_PAD     => C_PAD(4),
    C_RELU      => C_RELU(4),
    C_LEAKY     => C_LEAKY_RELU(4),
    STR_W_INIT    => STR_W_INIT(4),
    STR_B_INIT    => STR_B_INIT(4)
  )
  port map (
    isl_clk     => isl_clk,
    isl_rst_n     => isl_rst_n,
    isl_ce      => isl_ce,
    isl_get     => slv_rdy(4+1),
    isl_start   => isl_start,
    isl_valid     => sl_output_valid(4-1),
    islv_data   => a_data_out(4-1),
    oslv_data     => a_data_out(4),
    osl_valid     => sl_output_valid(4),
    osl_rdy     => slv_rdy(4)
  );

  -----------------------------------
  -- stage C_PE+1 (global average)
  -----------------------------------
  ave : entity work.pool_ave
  generic map (
    C_INT_WIDTH   => C_BITWIDTH(C_PE, 0)-C_BITWIDTH(C_PE, 2),
    C_FRAC_WIDTH  => C_BITWIDTH(C_PE, 2),
    C_POOL_CH   => C_CH(C_PE),
    C_WIDTH     => C_WIDTH(C_PE),
    C_HEIGHT    => C_HEIGHT(C_PE)
  )
  port map (
    isl_clk     => isl_clk,
    isl_rst_n     => isl_rst_n,
    isl_ce      => isl_ce,
    isl_start   => isl_start,
    isl_valid     => sl_output_valid(C_PE),
    islv_data   => a_data_out(C_PE),
    oslv_data     => a_data_out(C_PE+1),
    osl_valid     => sl_output_valid(C_PE+1)
  );

  --------------------------------------------------------------
  -- Process: Generate finish signal for interrupt
  --------------------------------------------------------------
  finish_proc : process(isl_clk) is
  begin
    if (rising_edge(isl_clk)) then
      if (sl_output_valid(C_PE+1) = '1') then
        int_data_out_cnt <= int_data_out_cnt+1;
      end if;
      if (int_data_out_cnt < C_CH(C_CH'RIGHT)) then
        sl_output_finish <= '0';
      else
        sl_output_finish <= '1';
        int_data_out_cnt <= 0;
      end if;
    end if;
  end process;

  osl_finish <= sl_output_finish;
  oslv_data <= a_data_out(C_PE+1);
  osl_valid <= sl_output_valid(C_PE+1);
  osl_rdy <= slv_rdy(1) and isl_get and not isl_valid;-- when (int_data_in_cnt < C_CH(C_CH'RIGHT)) else '0';
end behavioral;
