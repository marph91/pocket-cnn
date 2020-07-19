
library ieee;
  use ieee.fixed_pkg.all;

package math_pkg is

  function log2 (x : integer) return integer;

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
