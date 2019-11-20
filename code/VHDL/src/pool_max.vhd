library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
library util;
  use util.math.all;

entity pool_max is
  generic (
    C_KSIZE       : integer range 2 to 3 := 2;
    C_TOTAL_BITS  : integer range 1 to 16 := 8;
    C_FRAC_BITS   : integer range 0 to 16 := 4
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_valid : in std_logic;
    -- TODO: use array type instead of concatenated vectors
    islv_data : in std_logic_vector(C_KSIZE*C_KSIZE*C_TOTAL_BITS-1 downto 0);
    oslv_data : out std_logic_vector(C_TOTAL_BITS-1 downto 0);
    osl_valid : out std_logic
  );
end pool_max;

architecture behavioral of pool_max is
  constant C_INT_BITS : integer range 1 to 16 := C_TOTAL_BITS - C_FRAC_BITS;

  signal sl_input_valid_d1 : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_TOTAL_BITS-1 downto 0);
  signal sl_output_valid : std_logic := '0';

  type t_1d_sfix_array is array (natural range <>) of sfixed(C_INT_BITS-1 downto -C_FRAC_BITS);
  signal a_max_tmp : t_1d_sfix_array(0 to C_KSIZE-1);

begin
  -------------------------------------------------------
  -- Process: Maximum Pooling (3x3 / 2x2)
  -- Stage 1: 2x / 1x compare
  -- Stage 2: 2x / 1x compare
  -------------------------------------------------------
  process(isl_clk)
    variable v_a_current_max : t_1d_sfix_array(0 to C_KSIZE-1);
    variable v_sfix_current_max_tmp : sfixed(C_INT_BITS-1 downto -C_FRAC_BITS);
    variable v_sfix_new_value : sfixed(C_INT_BITS-1 downto -C_FRAC_BITS);
  begin
    if rising_edge(isl_clk) then
      if isl_ce = '1' then
        -- Stage 1
        for j in 0 to C_KSIZE-1 loop
          v_a_current_max(j) := to_sfixed(islv_data((j*C_KSIZE+1)*C_TOTAL_BITS-1 downto
            (j*C_KSIZE)*C_TOTAL_BITS), C_INT_BITS-1, -C_FRAC_BITS);
          for i in 1 to C_KSIZE-1 loop
            v_sfix_new_value := to_sfixed(islv_data(((i+1)+j*C_KSIZE)*C_TOTAL_BITS-1 downto
              (i+j*C_KSIZE)*C_TOTAL_BITS), C_INT_BITS-1, -C_FRAC_BITS);
            v_a_current_max(j) := max(v_sfix_new_value, v_a_current_max(j));
          end loop;
        end loop;
        a_max_tmp <= v_a_current_max;

        -- Stage 2
        v_sfix_current_max_tmp := a_max_tmp(0);
        for j in 1 to C_KSIZE-1 loop
          v_sfix_current_max_tmp := max(a_max_tmp(j), v_sfix_current_max_tmp);
        end loop;
        slv_data_out <= to_slv(v_sfix_current_max_tmp);

        sl_input_valid_d1 <= isl_valid;
        sl_output_valid <= sl_input_valid_d1;
      end if;
    end if;
  end process;

  oslv_data <= slv_data_out;
  osl_valid <= sl_output_valid;
end behavioral;