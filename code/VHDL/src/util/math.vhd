library ieee;
  use ieee.fixed_pkg.all;

-----------------------------------------------------------------------------------------------------------------------
-- Package declaration
-----------------------------------------------------------------------------------------------------------------------
package math is
  function log2(x : natural) return integer;
  function max(l, r : integer) return integer;
  function max(l, r : sfixed) return sfixed;
  function min(l, r : integer) return integer;
end package math;

-----------------------------------------------------------------------------------------------------------------------
-- Package body
-----------------------------------------------------------------------------------------------------------------------
package body math is

  -- compute the binary logarithm
  function log2(x : natural) return integer is
    variable i : integer := 0;
  begin
    if x = 0 then
      return 0;
    else
      while 2**i < x loop
        i := i + 1;
      end loop;
      return i;
    end if;
  end function log2;

  -- chose the maximum of two integer
  function max(l, r : integer) return integer is
    begin
    if l > r then
      return l;
    else
      return r;
    end if;
  end max;

  -- chose the maximum of two signed fixed numbers
  function max(l, r : sfixed) return sfixed is
  begin
    if l > r then
      return l;
    else
      return r;
    end if;
  end max;

  -- chose the minimum of two integer
  function min(l, r : integer) return integer is
    begin
      if l < r then
      return l;
    else
      return r;
    end if;
  end min;
end math;