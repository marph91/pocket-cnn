
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

entity BRAM is
  generic (
    C_DATA_WIDTH  : integer;
    C_ADDR_WIDTH  : integer;
    C_SIZE        : integer;
    C_OUTPUT_REG  : integer range 0 to 1 := 0
  );
  port (
    isl_clk   : in    std_logic;
    isl_en    : in    std_logic;
    isl_we    : in    std_logic;
    islv_addr : in    std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    islv_data : in    std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    oslv_data : out   std_logic_vector(C_DATA_WIDTH - 1 downto 0)
  );
end entity BRAM;

architecture BEHAVIORAL of BRAM is

  type t_ram is array(0 to C_SIZE - 1) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);

  signal a_ram    : t_ram;
  attribute ram_style : string;
  attribute ram_style of a_ram : signal is "block";
  signal slv_data : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

begin

  PROC_BRAM : process (isl_clk) is
  begin

    if rising_edge(isl_clk) then
      if (isl_en = '1') then
        if (isl_we = '1') then
          a_ram(to_integer(unsigned(islv_addr))) <= islv_data;
        end if;
        slv_data <= a_ram(to_integer(unsigned(islv_addr)));
      end if;
    end if;

  end process PROC_BRAM;

  GEN_OUTPUT_REG : if C_OUTPUT_REG = 0 generate
    oslv_data <= slv_data;
  elsif C_OUTPUT_REG = 1 generate

    PROC_OUTPUT_REG : process (isl_clk) is
    begin

      if rising_edge(isl_clk) then
        if (isl_en = '1') then
          oslv_data <= slv_data;
        end if;
      end if;

    end process PROC_OUTPUT_REG;

  end generate GEN_OUTPUT_REG;

end architecture BEHAVIORAL;
