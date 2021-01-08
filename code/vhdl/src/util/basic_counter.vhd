
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.math_pkg.all;

entity basic_counter is
  generic (
    C_MAX       : integer;
    C_INCREMENT : integer range 1 to C_MAX := 1
  );
  port (
    isl_clk     : in    std_logic;
    isl_reset   : in    std_logic;
    isl_valid   : in    std_logic;
    oint_count  : out   integer range 0 to C_MAX - 1;
    osl_maximum : out   std_logic
  );
end entity basic_counter;

architecture behavioral of basic_counter is

  signal usig_count : unsigned(log2(C_MAX) - 1 downto 0) := (others => '0');

begin

  gen_no_count : if C_MAX = 1 generate

    -- There is no counting if the maximum is 1.

    proc_count : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        osl_maximum <= isl_valid;
      end if;

    end process proc_count;

  else generate

    gen_counter : if is_power_of_two(C_MAX) generate

      proc_count : process (isl_clk) is
      begin

        if (rising_edge(isl_clk)) then
          osl_maximum <= '0';
          if (isl_reset = '1') then
            usig_count <= (others => '0');
          elsif (isl_valid = '1') then
            usig_count  <= usig_count + C_INCREMENT;
            osl_maximum <= '1' when (usig_count = C_MAX - C_INCREMENT) else '0';
          end if;
        end if;

      end process proc_count;

    else generate

      proc_count : process (isl_clk) is
      begin

        if (rising_edge(isl_clk)) then
          osl_maximum <= '0';
          if (isl_reset = '1') then
            usig_count <= (others => '0');
          elsif (isl_valid = '1') then
            if (usig_count /= C_MAX - C_INCREMENT) then
              usig_count <= usig_count + C_INCREMENT;
            else
              usig_count  <= (others => '0');
              osl_maximum <= '1';
            end if;
          end if;
        end if;

      end process proc_count;

    end generate gen_counter;

    oint_count <= to_integer(usig_count);

  end generate gen_no_count;

end architecture behavioral;
