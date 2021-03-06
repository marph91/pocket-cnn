
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;

entity relu is
  generic (
    C_TOTAL_BITS : integer range 1 to 32 := 8;
    C_FRAC_BITS  : integer range 0 to 16 := 8;
    -- 0: normal ReLU (if x<0: then y=0)
    -- 1: leaky ReLU (if x<0: then y=0.125*x)
    C_LEAKY : std_logic := '0'
  );
  port (
    isl_clk   : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_TOTAL_BITS - 1 downto 0);
    oslv_data : out   std_logic_vector(C_TOTAL_BITS - 1 downto 0);
    osl_valid : out   std_logic
  );
end entity relu;

architecture behavioral of relu is

  constant C_INT_BITS      : integer range 1 to 16 := C_TOTAL_BITS - C_FRAC_BITS;
  signal   sl_output_valid : std_logic := '0';

begin

  -- use generate statement instead of if-else in process
  -- it is more code, but needs less ressources

  gen_relu : if C_LEAKY = '0' generate

    proc_relu : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        if (isl_valid = '1') then
          if (islv_data(C_TOTAL_BITS - 1) = '0') then
            oslv_data <= islv_data;
          else
            oslv_data <= (others => '0');
          end if;
        end if;
        sl_output_valid <= isl_valid;
      end if;

    end process proc_relu;

  else generate

    gen_leaky_relu : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        if (isl_valid = '1') then
          if (islv_data(C_TOTAL_BITS - 1) = '0') then
            oslv_data <= islv_data;
          else
            oslv_data <= to_slv(resize(
                         to_sfixed(islv_data, C_INT_BITS - 1, - C_FRAC_BITS),
                         C_INT_BITS + 2, - C_FRAC_BITS + 3,
                         fixed_saturate, fixed_round));
          end if;
        end if;
        sl_output_valid <= isl_valid;
      end if;

    end process gen_leaky_relu;

  end generate gen_relu;

  osl_valid <= sl_output_valid;

end architecture behavioral;
