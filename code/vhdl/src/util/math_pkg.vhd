
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;

package math_pkg is

  function log2 (x : integer) return integer;

  function is_power_of_two (int_value : integer) return std_logic;

  function max (l, r : sfixed) return sfixed;

end package math_pkg;

package body math_pkg is
  -- compute the binary logarithm

  function log2 (x : integer) return integer is
    variable i : integer;
  begin
    i := 0;
    while 2 ** i < x loop
      i := i + 1;
    end loop;
    return i;
  end function log2;

  -- check whether an integer is a power of two

  function is_power_of_two (int_value : integer) return std_logic is
    variable usig_value     : unsigned(31 downto 0);
    variable int_ones_count : integer range 0 to 32;
  begin
    usig_value := to_unsigned(int_value, 32);
    int_ones_count := 0;
    for i in usig_value'range loop

      if (usig_value(i) = '1') then
        int_ones_count := int_ones_count + 1;
      end if;

    end loop;

    if (int_ones_count = 1) then
      return '1';
    end if;

    return '0';
  end function is_power_of_two;

  -- obtain the maximum of two signed fixed point numbers

  function max (l, r : sfixed) return sfixed is
  begin

    if (l > r) then
      return l;
    else
      return r;
    end if;

  end max;

end math_pkg;
