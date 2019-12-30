library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;
library cnn_lib;

entity top is
  generic(
    C_DATA_TOTAL_BITS : integer range 1 to 16;
    C_IMG_WIDTH_IN : integer range 2 to 512;
	  C_IMG_HEIGHT_IN : integer range 2 to 512;

	  C_PE : integer range 1 to 100;

	  C_SCALE : integer range 0 to 256;

    -- 0 - preprocessing, 1 to C_PE - pe, C_PE+1 - average
    C_RELU : std_logic_vector(C_PE downto 1); -- slv gets turned around after parsing
    C_LEAKY_RELU : std_logic_vector(C_PE downto 1);

	  C_PAD: t_int_array_1d(1 to C_PE);

	  C_CONV_KSIZE : t_int_array_1d(1 to C_PE);
	  C_CONV_STRIDE : t_int_array_1d(1 to C_PE);
	  C_POOL_KSIZE : t_int_array_1d(1 to C_PE);
	  C_POOL_STRIDE : t_int_array_1d(1 to C_PE);

	  C_CH : t_int_array_1d(0 to C_PE);

    -- 0 - bitwidth data, 1 - bitwidth frac data in, 2 - bitwidth frac data out
    -- 3 - bitwidth weights, 4 - bitwidth frac weights
	  C_BITWIDTH : t_int_array_2d(1 to C_PE, 0 to 4);

    C_STR_LENGTH : integer range 1 to 256;
    STR_WEIGHTS_INIT : t_str_array_1d(1 to C_PE)(1 to C_STR_LENGTH);
	  STR_BIAS_INIT : t_str_array_1d(1 to C_PE)(1 to C_STR_LENGTH)
  );
  port (
    isl_clk   	: in std_logic;
    isl_rst_n 	: in std_logic;
    isl_ce    	: in std_logic;
    isl_get   	: in std_logic;
    isl_start 	: in std_logic;
    isl_valid 	: in std_logic;
    islv_data 	: in std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    oslv_data 	: out std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    osl_valid 	: out std_logic;
    osl_rdy   	: out std_logic;
    osl_finish  : out std_logic
  );
end top;

architecture behavioral of top is
  -- TODO: is subtype with integer range possible?
  type t_img_size_array is array (1 to C_PE) of integer range 1 to 512;

  -- calculate the image size at every layer
  function f_calc_size (size : in integer range 1 to 512) return t_img_size_array is
    variable v_a_size : t_img_size_array;
    variable v_int_size_conv : integer range 1 to 512;
  begin
    v_a_size(1) := size;
    for i in 2 to C_PE loop
      -- stride conv just useful if no pooling layer in pe (either reduce image dimensions in conv OR pool)
      -- ite to protect from division by 0
      v_int_size_conv := (v_a_size(i-1) + 2*C_PAD(i-1) - (C_CONV_KSIZE(i-1) - C_CONV_STRIDE(i-1))) /
                          C_CONV_STRIDE(i-1);
      if (C_POOL_STRIDE(i-1) > 0) then
        v_a_size(i) := (v_int_size_conv - (C_POOL_KSIZE(i-1) - C_POOL_STRIDE(i-1))) /
                        C_POOL_STRIDE(i-1);
      else
        v_a_size(i) := v_int_size_conv;
      end if;
    end loop;
    return v_a_size;
  end f_calc_size;

  constant C_IMG_WIDTH : t_img_size_array := f_calc_size(C_IMG_WIDTH_IN);
  constant C_IMG_HEIGHT : t_img_size_array := f_calc_size(C_IMG_HEIGHT_IN);

  signal sl_output_valid : std_logic_vector(0 to C_PE+1) := (others => '0');

  type t_data_array is array (0 to C_PE+1) of std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
  signal a_data_out : t_data_array := (others => (others => '0'));

  -- C_PE+1 == isl_get
  signal slv_rdy : std_logic_vector(1 to C_PE+1) := (others => '0');

  -- signals for finish interrupt
  signal int_data_out_cnt : integer range 0 to C_CH(C_CH'RIGHT) := 0;
  signal sl_output_finish : std_logic := '0';

begin
  -----------------------------------
  -- Stage 0 (preprocessing input)
  -----------------------------------
  i_prepr : entity cnn_lib.prepr
  generic map (
    C_TOTAL_BITS => C_BITWIDTH(1, 0),
    C_FRAC_BITS  => C_BITWIDTH(1, 1),
    C_SHIFT      => log2(C_SCALE)
  )
  port map (
    isl_valid => isl_valid,
    islv_data => islv_data,
    oslv_data => a_data_out(0),
    osl_valid => sl_output_valid(0)
  );

  slv_rdy(C_PE+1) <= isl_get;
  gen_stages : for i in 1 to C_PE generate
    -----------------------------------
    -- Stage 1 to C_PE: processing elements
    -----------------------------------
    i_stage : entity cnn_lib.pe
    generic map (
      C_DATA_TOTAL_BITS    => C_BITWIDTH(i, 0),
      C_DATA_FRAC_BITS_IN  => C_BITWIDTH(i, 1),
      C_DATA_FRAC_BITS_OUT => C_BITWIDTH(i, 2),
      C_WEIGHTS_TOTAL_BITS => C_BITWIDTH(i, 3),
      C_WEIGHTS_FRAC_BITS  => C_BITWIDTH(i, 4),

      C_IMG_WIDTH       => C_IMG_WIDTH(i),
      C_IMG_HEIGHT      => C_IMG_HEIGHT(i),
      C_CH_IN           => C_CH(i-1),
      C_CH_OUT          => C_CH(i),
      C_CONV_KSIZE      => C_CONV_KSIZE(i),
      C_CONV_STRIDE     => C_CONV_STRIDE(i),
      C_POOL_KSIZE      => C_POOL_KSIZE(i),
      C_POOL_STRIDE     => C_POOL_STRIDE(i),
      C_PAD             => C_PAD(i),
      C_RELU            => C_RELU(i),
      C_LEAKY           => C_LEAKY_RELU(i),
      STR_WEIGHTS_INIT  => STR_WEIGHTS_INIT(i),
      STR_BIAS_INIT     => STR_BIAS_INIT(i)
    )
    port map (
      isl_clk   => isl_clk,
      isl_rst_n => isl_rst_n,
      isl_ce    => isl_ce,
      isl_get   => slv_rdy(i+1),
      isl_start => isl_start,
      isl_valid => sl_output_valid(i-1),
      islv_data => a_data_out(i-1),
      oslv_data => a_data_out(i),
      osl_valid => sl_output_valid(i),
      osl_rdy   => slv_rdy(i)
    );
  end generate;

  -----------------------------------
  -- Stage C_PE+1 (global average)
  -----------------------------------
  i_ave : entity cnn_lib.pool_ave
  generic map (
    C_TOTAL_BITS  => C_BITWIDTH(C_PE, 0),
    C_FRAC_BITS   => C_BITWIDTH(C_PE, 2),
    C_POOL_CH     => C_CH(C_PE),
    C_IMG_WIDTH   => C_IMG_WIDTH(C_PE),
    C_IMG_HEIGHT  => C_IMG_HEIGHT(C_PE)
  )
  port map (
    isl_clk   => isl_clk,
    isl_rst_n => isl_rst_n,
    isl_ce    => isl_ce,
    isl_start => isl_start,
    isl_valid => sl_output_valid(C_PE),
    islv_data => a_data_out(C_PE),
    oslv_data => a_data_out(C_PE+1),
    osl_valid => sl_output_valid(C_PE+1)
  );

  --------------------------------------------------------------
  -- Process: Generate finish signal for interrupt
  --------------------------------------------------------------
  finish_proc : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if sl_output_valid(C_PE+1) = '1' then
        int_data_out_cnt <= int_data_out_cnt+1;
      end if;
      if int_data_out_cnt < C_CH(C_CH'RIGHT) then
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
  osl_rdy <= (slv_rdy(1) and isl_get and not isl_valid) when (int_data_out_cnt < C_CH(C_CH'RIGHT)) else '0';
end behavioral;
