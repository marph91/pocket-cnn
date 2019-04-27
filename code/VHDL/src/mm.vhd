library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;
library util;
  use util.math.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity mm is
  generic (
    C_DATA_TOTAL_BITS     : integer range 1 to 16 := 8;
    C_DATA_FRAC_BITS_IN   : integer range 0 to 16 := 4;
    C_WEIGHTS_TOTAL_BITS  : integer range 1 to 16 := 8;
    C_WEIGHTS_FRAC_BITS   : integer range 0 to 16 := 4;
    C_KSIZE               : integer range 1 to 3 := 3
  );
  port (
    isl_clk       : in std_logic;
    isl_rst_n     : in std_logic;
    isl_ce        : in std_logic;
    isl_valid     : in std_logic;
    islv_data     : in std_logic_vector(C_KSIZE*C_KSIZE*C_DATA_TOTAL_BITS-1 downto 0);
    islv_weights  : in std_logic_vector(C_KSIZE*C_KSIZE*C_WEIGHTS_TOTAL_BITS-1 downto 0);
    oslv_data     : out std_logic_vector(C_DATA_TOTAL_BITS+C_WEIGHTS_TOTAL_BITS+log2(C_KSIZE-1)*2 downto 0);
    osl_valid     : out std_logic
  );
end mm;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of mm is
  constant C_DATA_INT_BITS : integer range 0 to 16 := C_DATA_TOTAL_BITS-C_DATA_FRAC_BITS_IN;

  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  signal slv_stage : std_logic_vector(2 to 6) := (others => '0');

  type t_1d_sfix_array is array (natural range <>) of sfixed(C_DATA_INT_BITS-1 downto -C_DATA_FRAC_BITS_IN);
  signal a_sfix_data : t_1d_sfix_array(0 to C_KSIZE*C_KSIZE-1);

  -- full signal bitwidth after multiplication
  type t_1d_sfix_mult_array is array (natural range <>) of sfixed(C_DATA_INT_BITS+C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1 downto -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS);
  signal a_data_mult : t_1d_sfix_mult_array(0 to C_KSIZE*C_KSIZE-1);
  attribute use_dsp : string;
  attribute use_dsp of a_data_mult : signal is "yes";
  signal a_data_mult_d1 : t_1d_sfix_mult_array(0 to C_KSIZE*C_KSIZE-1);

  -- add bits to avoid using FIXED_SATURATE and avoid overflow
  -- new bitwidth = log2((C_KSIZE-1)*(2^old bitwidth-1)) -> new bw = lb(2*(2^12-1)) = 13
  -- C_KSIZE-1 additions, +1 for bias addition
  constant C_INTW_SUM1 : integer range 0 to 16 := C_DATA_INT_BITS+C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS+1+log2(C_KSIZE-1);
  type t_1d_sfix_add_array is array (natural range <>) of sfixed(C_INTW_SUM1-1 downto -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS);
  signal a_data_mult_resized : t_1d_sfix_add_array(0 to C_KSIZE*C_KSIZE-1);
  signal a_data_tmp : t_1d_sfix_add_array(0 to C_KSIZE-1);

  type t_1d_sfix_weights_array is array (natural range <>) of sfixed(C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1 downto -C_WEIGHTS_FRAC_BITS);
  signal a_sfix_weights : t_1d_sfix_weights_array(0 to C_KSIZE*C_KSIZE-1);

  constant C_INTW_SUM2 : integer range 0 to 16 := C_INTW_SUM1+log2(C_KSIZE-1); -- C_KSIZE-1 additions
  signal slv_data_out : std_logic_vector(C_INTW_SUM2+C_DATA_FRAC_BITS_IN+C_WEIGHTS_FRAC_BITS-1 downto 0);
  signal sl_output_valid : std_logic := '0';

begin
  -------------------------------------------------------
  -- Process: Convolution
  -------------------------------------------------------
  process(isl_clk)
    variable v_sfix_conv_res : t_1d_sfix_add_array(0 to C_KSIZE-1);
    variable v_sfix_data_out : sfixed(C_INTW_SUM2-1 downto -C_DATA_FRAC_BITS_IN-C_WEIGHTS_FRAC_BITS) := (others => '0');
  begin
    if rising_edge(isl_clk) then
      if isl_ce = '1' then

        -- Stage 1: Load Weights and Data
        -- Stage 2: 9x Mult / 1x Mult + Add Bias
        -- Stage 3: Pipeline DSP output
        -- Stage 4: 9x Resize
        -- Stage 5: 2x Add / 1x Add
        -- Stage 6: 2x Add / 1x Add (theoretically not needed for 1x1 conv)
        -- Total: 3x3 Convolution / 1x1 Convolution

        slv_stage <= isl_valid & slv_stage(slv_stage'LOW to slv_stage'HIGH-1);
        sl_output_valid <= slv_stage(slv_stage'HIGH);

        if isl_valid = '1' then
          for j in 0 to C_KSIZE-1 loop
            for i in 0 to C_KSIZE-1 loop
              a_sfix_data(i+j*C_KSIZE) <= to_sfixed(islv_data(((i+1)+j*C_KSIZE)*C_DATA_TOTAL_BITS-1 downto
                (i+j*C_KSIZE)*C_DATA_TOTAL_BITS),C_DATA_INT_BITS-1, -C_DATA_FRAC_BITS_IN);
              a_sfix_weights(i+j*C_KSIZE) <= to_sfixed(islv_weights(((i+1)+j*C_KSIZE)*C_WEIGHTS_TOTAL_BITS-1 downto
                (i+j*C_KSIZE)*C_WEIGHTS_TOTAL_BITS), C_WEIGHTS_TOTAL_BITS-C_WEIGHTS_FRAC_BITS-1, -C_WEIGHTS_FRAC_BITS);
            end loop;
          end loop;
        end if;

        if slv_stage(2) = '1' then
          for j in 0 to C_KSIZE-1 loop
            for i in 0 to C_KSIZE-1 loop
              a_data_mult(i+j*C_KSIZE) <=
                a_sfix_data(i+j*C_KSIZE) * a_sfix_weights(i+j*C_KSIZE);
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
                a_data_mult_d1(i+j*C_KSIZE),
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
    end if;
  end process;

  oslv_data <= slv_data_out;
  osl_valid <= sl_output_valid;
end behavioral;