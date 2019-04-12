library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
library util;
  use util.math.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity pool_max is
  generic (
    C_POOL_DIM    : integer range 2 to 3 := 2;
    C_INT_WIDTH   : integer range 1 to 16 := 8;
    C_FRAC_WIDTH  : integer range 0 to 16 := 8
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_POOL_DIM*C_POOL_DIM*(C_INT_WIDTH+C_FRAC_WIDTH)-1 downto 0);
    oslv_data : out std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
    osl_valid : out std_logic
  );
end pool_max;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of pool_max is
  

  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  signal sl_input_valid_d1 : std_logic := '0';
  signal slv_data_in : std_logic_vector(C_POOL_DIM*C_POOL_DIM*(C_INT_WIDTH+C_FRAC_WIDTH)-1 downto 0);
  signal slv_data_tmp : std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
  signal slv_data_delay : std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
  signal slv_data_out : std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
  signal sl_output_valid : std_logic := '0';

  type t_1d_sfix_array is array (natural range <>) of sfixed(C_INT_WIDTH-1 downto -C_FRAC_WIDTH);
  signal a_max_tmp : t_1d_sfix_array(0 to C_POOL_DIM-1);

begin
  process(isl_clk)
    variable v_a_current_max : t_1d_sfix_array(0 to C_POOL_DIM-1);
    variable v_sfix_current_max_tmp : sfixed(C_INT_WIDTH-1 downto -C_FRAC_WIDTH);
    variable v_sfix_A : sfixed(C_INT_WIDTH-1 downto -C_FRAC_WIDTH);
    variable v_sfix_B : sfixed(C_INT_WIDTH-1 downto -C_FRAC_WIDTH);
  begin
    if rising_edge(isl_clk) then
      if isl_ce = '1' then
        -- Stage 1: 2x compare / 1x compare
        -- Stage 2: 2x compare / 1x compare
        -- Summary: 3x3 maxpool / 2x2 maxpool

        -- Stage 1
        for j in 0 to C_POOL_DIM-1 loop
          v_a_current_max(j) := to_sfixed(islv_data((j*C_POOL_DIM+1)*(C_INT_WIDTH+C_FRAC_WIDTH)-1 downto
            (j*C_POOL_DIM)*(C_INT_WIDTH+C_FRAC_WIDTH)), C_INT_WIDTH-1, -C_FRAC_WIDTH);
          for i in 1 to C_POOL_DIM-1 loop
            v_sfix_A := to_sfixed(islv_data(((i+1)+j*C_POOL_DIM)*(C_INT_WIDTH+C_FRAC_WIDTH)-1 downto
              (i+j*C_POOL_DIM)*(C_INT_WIDTH+C_FRAC_WIDTH)), C_INT_WIDTH-1, -C_FRAC_WIDTH);
            v_a_current_max(j) := max(v_sfix_A, v_a_current_max(j));
          end loop;
        end loop;
        a_max_tmp <= v_a_current_max;

        -- Stage 2
        v_sfix_current_max_tmp := a_max_tmp(0);
        for j in 1 to C_POOL_DIM-1 loop
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
