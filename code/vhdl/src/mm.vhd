library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;
library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;

entity mm is
  generic (
    C_FIRST_STAGE         : integer range 0 to 1 := 0;

    C_DATA_TOTAL_BITS     : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN   : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS  : integer range 1 to 16 := 8;
    C_WEIGHTS_FRAC_BITS   : integer range 0 to 16 := 4;

    C_KSIZE               : integer range 1 to 3 := 3
  );
  port (
    isl_clk       : in std_logic;
    isl_valid     : in std_logic;
    ia_data       : in t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    ia_weights    : in t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    oslv_data     : out std_logic_vector(C_DATA_TOTAL_BITS+C_WEIGHTS_TOTAL_BITS+log2(C_KSIZE-1)*2+C_FIRST_STAGE downto 0);
    osl_valid     : out std_logic
  );
end mm;

architecture behavioral of mm is
  constant C_DATA_INT_BITS : integer range 1 to 16 := C_DATA_TOTAL_BITS-C_DATA_FRAC_BITS_IN;

  signal slv_stage : std_logic_vector(2 to 6) := (others => '0');

  type t_sfix_array_2d is array (natural range <>, natural range <>) of sfixed(C_DATA_INT_BITS-1+C_FIRST_STAGE downto -C_DATA_FRAC_BITS_IN);
  signal a_sfix_data : t_sfix_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

  -- full signal bitwidth after multiplication
  type t_sfix_mult_array_2d is array (natural range <>, natural range <>)
    of sfixed(C_DATA_INT_BITS+C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1+C_FIRST_STAGE downto -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS);
  signal a_data_mult : t_sfix_mult_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  attribute use_dsp : string;
  attribute use_dsp of a_data_mult : signal is "no";
  signal a_data_mult_d1 : t_sfix_mult_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

  -- add bits to avoid using FIXED_SATURATE and avoid overflow
  -- new bitwidth = log2((C_KSIZE-1)*(2^old bitwidth-1)) -> new bw = lb(2*(2^12-1)) = 13
  -- C_KSIZE-1 additions, +1 for bias addition, +1 for sign at first stage
  constant C_INTW_SUM1 : integer range 1 to 32 := C_DATA_INT_BITS+C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS+1+log2(C_KSIZE-1)+C_FIRST_STAGE;
  type t_1d_sfix_add_array is array (natural range <>) of sfixed(C_INTW_SUM1-1 downto -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS);
  signal a_data_mult_resized : t_1d_sfix_add_array(0 to C_KSIZE*C_KSIZE-1) := (others => (others => '0'));
  signal a_data_tmp : t_1d_sfix_add_array(0 to C_KSIZE-1) := (others => (others => '0'));

  type t_sfix_weights_array_2d is array (natural range <>, natural range <>) of sfixed(C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1 downto -C_WEIGHTS_FRAC_BITS);
  signal a_sfix_weights : t_sfix_weights_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

  constant C_INTW_SUM2 : integer range 1 to 32 := C_INTW_SUM1+log2(C_KSIZE-1); -- C_KSIZE-1 additions
  signal slv_data_out : std_logic_vector(C_INTW_SUM2+C_DATA_FRAC_BITS_IN+C_WEIGHTS_FRAC_BITS-1 downto 0);
  signal sl_output_valid : std_logic := '0';

begin
  -------------------------------------------------------
  -- Process: Convolution (3x3 / 2x2 / 1x1)
  -- Stage 1: Load Weights and Data
  -- Stage 2: 3x3 / 2x2 / 1x1 Mult
  -- Stage 3: Pipeline DSP output
  -- Stage 4: Resize
  -- Stage 5: 2x / 1x / 1x Add
  -- Stage 6: 2x / 1x / 1x Add (theoretically not needed for 1x1 conv)
  -------------------------------------------------------
  gen_input_type : if C_FIRST_STAGE = 1 generate
    -- TODO: For the first stage, input data is taken as ufixed to obtain the full 8 bit of image data.
    --       For the other stages, the type is sfixed.
    --       Is there an easier way to achieve this behaviour?
    process(isl_clk)
    begin
      if rising_edge(isl_clk) then
        if isl_valid = '1' then
          for j in 0 to C_KSIZE-1 loop
            for i in 0 to C_KSIZE-1 loop
              a_sfix_data(i, j) <= to_sfixed('0' & ia_data(i, j), C_DATA_INT_BITS, -C_DATA_FRAC_BITS_IN);
              a_sfix_weights(i, j) <= to_sfixed(ia_weights(i, j), C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1, -C_WEIGHTS_FRAC_BITS);
            end loop;
          end loop;
        end if;
      end if;
    end process;
  else generate
    process(isl_clk)
    begin
      if rising_edge(isl_clk) then
        if isl_valid = '1' then
          for j in 0 to C_KSIZE-1 loop
            for i in 0 to C_KSIZE-1 loop
              a_sfix_data(i, j) <= to_sfixed(ia_data(i, j), C_DATA_INT_BITS-1, -C_DATA_FRAC_BITS_IN);
              a_sfix_weights(i, j) <= to_sfixed(ia_weights(i, j), C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1, -C_WEIGHTS_FRAC_BITS);
            end loop;
          end loop;
        end if;
      end if;
    end process;
  end generate;

  process(isl_clk)
    variable v_sfix_conv_res : t_1d_sfix_add_array(0 to C_KSIZE-1);
    variable v_sfix_data_out : sfixed(C_INTW_SUM2-1 downto -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS) := (others => '0');
  begin
    if rising_edge(isl_clk) then
      slv_stage <= isl_valid & slv_stage(slv_stage'LOW to slv_stage'HIGH-1);
      sl_output_valid <= slv_stage(slv_stage'HIGH);

      if slv_stage(2) = '1' then
        for j in 0 to C_KSIZE-1 loop
          for i in 0 to C_KSIZE-1 loop
            a_data_mult(i, j) <= a_sfix_data(i, j) * a_sfix_weights(i, j);
          end loop;
        end loop;
      end if;

      if slv_stage(3) = '1' then
        a_data_mult_d1 <= a_data_mult;
      end if;

      if slv_stage(4) = '1' then
        for j in 0 to C_KSIZE-1 loop
          for i in 0 to C_KSIZE-1 loop
            a_data_mult_resized(i+j*C_KSIZE) <= resize(
              a_data_mult_d1(i, j),
              C_INTW_SUM1-1, -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS, fixed_wrap, fixed_truncate);
          end loop;
        end loop;
      end if;

      if slv_stage(5) = '1' then
        for j in 0 to C_KSIZE-1 loop
          v_sfix_conv_res(j) := a_data_mult_resized(j*C_KSIZE);
          for i in 1 to C_KSIZE-1 loop
            v_sfix_conv_res(j) := resize(
              v_sfix_conv_res(j) +
              a_data_mult_resized(i+j*C_KSIZE),
              C_INTW_SUM1-1, -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS, fixed_wrap, fixed_truncate);
          end loop;
        end loop;
        a_data_tmp <= v_sfix_conv_res;
      end if;

      if slv_stage(6) = '1' then
        v_sfix_data_out := (others => '0');
        for j in 0 to C_KSIZE-1 loop
          v_sfix_data_out := resize(
            v_sfix_data_out + a_data_tmp(j),
            C_INTW_SUM2-1, -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS, fixed_wrap, fixed_truncate);
        end loop;
        slv_data_out <= to_slv(v_sfix_data_out);
      end if;
    end if;
  end process;

  oslv_data <= slv_data_out;
  osl_valid <= sl_output_valid;
end behavioral;