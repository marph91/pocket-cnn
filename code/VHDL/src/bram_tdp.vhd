library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library util;
  use util.math.all;

entity bram_tdp is
  generic(
    C_DATA_WIDTH_A  : integer := 8;
    C_ADDR_WIDTH_A  : integer := 10;
    C_SIZE_A        : integer := 1024;

    C_DATA_WIDTH_B  : integer := 32;
    C_ADDR_WIDTH_B  : integer := 8;
    C_SIZE_B        : integer := 256
  );
  port(
    isl_clk_a   : in std_logic;
    isl_en_a    : in std_logic;
    isl_we_a    : in std_logic;
    islv_addr_a : in std_logic_vector(C_ADDR_WIDTH_A - 1 downto 0);
    oslv_data_a : out std_logic_vector(C_DATA_WIDTH_A - 1 downto 0);

    isl_clk_b   : in std_logic;
    isl_en_b    : in std_logic;
    isl_we_b    : in std_logic;
    islv_addr_b : in std_logic_vector(C_ADDR_WIDTH_B - 1 downto 0);
    islv_data_b : in std_logic_vector(C_DATA_WIDTH_B - 1 downto 0)
  );
end bram_tdp;

architecture behavioral of bram_tdp is
  constant C_MIN_WIDTH : integer := util.math.min(C_DATA_WIDTH_A, C_DATA_WIDTH_B);
  constant C_MAX_WIDTH : integer := util.math.max(C_DATA_WIDTH_A, C_DATA_WIDTH_B);
  constant C_MAX_SIZE : integer := util.math.max(C_SIZE_A, C_SIZE_B);
  constant C_RATIO : integer := C_MAX_WIDTH / C_MIN_WIDTH;

  type t_ram is array (0 to C_MAX_SIZE - 1) of std_logic_vector(C_MIN_WIDTH - 1 downto 0);
  signal a_ram : t_ram := (others => (others => '0'));
  signal slv_read_a : std_logic_vector(C_DATA_WIDTH_A - 1 downto 0) := (others => '0');
  signal slv_data_out_a : std_logic_vector(C_DATA_WIDTH_A - 1 downto 0) := (others => '0');

begin
  -- reading from port a
  process(isl_clk_a)
  begin
    if rising_edge(isl_clk_a) then
      if isl_en_a = '1' then
        if isl_we_a = '0' then
          slv_read_a <= a_ram(to_integer(unsigned(islv_addr_a)));
        end if;
      end if;
      slv_data_out_a <= slv_read_a;
    end if;
  end process;

  -- writing to port b
  process(isl_clk_b)
  begin
    if rising_edge(isl_clk_b) then
      for i in 0 to C_RATIO - 1 loop
        if isl_en_b = '1' then
          if isl_we_b = '1' then
            a_ram(to_integer(unsigned(islv_addr_b & std_logic_vector(to_unsigned(i, log2(C_RATIO)))))) <= islv_data_b((i + 1) * C_MIN_WIDTH - 1 downto i * C_MIN_WIDTH);
          end if;
        end if;
      end loop;
    end if;
  end process;

  oslv_data_a <= slv_data_out_a;
end behavioral;