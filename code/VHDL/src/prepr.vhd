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
entity prepr is
  generic (
    C_INT_WIDTH   : integer range 1 to 16 := 8;
    C_FRAC_WIDTH  : integer range 0 to 16 := 8;
    C_SHIFT       : integer range 0 to 32 := 6
  );
  port (
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
    oslv_data : out std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
    osl_valid : out std_logic
  );
end prepr;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of prepr is
begin
  oslv_data <= to_slv(resize(
    -- convert/scale input (8 bit greyscale) to fixed point required by net (from caffe: /64 -> q2.6)
    to_sfixed('0' & islv_data, C_INT_WIDTH+C_FRAC_WIDTH-C_SHIFT, -C_SHIFT),
      C_INT_WIDTH-1, -C_FRAC_WIDTH, fixed_wrap, fixed_round));
  osl_valid <= isl_valid;
end behavioral;
