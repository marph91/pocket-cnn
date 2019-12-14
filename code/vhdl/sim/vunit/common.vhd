library ieee;
  use ieee.std_logic_1164.all;

package common is
  constant C_CLK_PERIOD : time := 10 ns;

  procedure clk_gen(signal clk : out std_logic; constant PERIOD : time);

  procedure report_position(cnt : in integer;
                            constant HEIGHT : integer;
                            constant WIDTH : integer;
                            constant DEPTH : integer;
                            constant name : string := "";
                            constant info : string := "");
end package common;

package body common is
  -- clock generation
  procedure clk_gen(signal clk : out std_logic; constant PERIOD : time) is
    constant HIGH_TIME : time := PERIOD / 2;
    constant LOW_TIME  : time := PERIOD - HIGH_TIME;
  begin
    assert (HIGH_TIME /= 0 fs) report "clk: frequency is too high" severity FAILURE;
    loop
      clk <= '1';
      wait for HIGH_TIME;
      clk <= '0';
      wait for LOW_TIME;
    end loop;
  end procedure;

  -- convert a simple data count to an image position
  procedure report_position(cnt : in integer;
                            constant HEIGHT : integer;
                            constant WIDTH : integer;
                            constant DEPTH : integer;
                            constant name : string := "";
                            constant info : string := "") is
    variable h, w, d, hw : integer;
  begin
    assert WIDTH /= 0;
    assert DEPTH /= 0;
    d := cnt mod DEPTH;
    hw := cnt / DEPTH;
    w := hw mod WIDTH;
    h := hw / WIDTH;
    assert h < HEIGHT;

    report name &
           "cnt=" & to_string(cnt) &
           ", h=" & to_string(h) &
           ", w=" & to_string(w) &
           ", d=" & to_string(d) &
           info;
  end procedure;
end package body common;