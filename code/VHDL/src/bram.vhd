library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library std;
  use std.textio.all;
library util;
  use util.math_pkg.all;

entity bram is
  generic(
    C_DATA_WIDTH  : integer;
    C_ADDR_WIDTH  : integer;
    C_SIZE        : integer;
    C_OUTPUT_REG  : integer range 0 to 1 := 0;
    STR_INIT      : string := ""
  );
  port(
    isl_clk   : in std_logic;
    isl_en    : in std_logic;
    isl_we    : in std_logic;
    islv_addr : in std_logic_vector(C_ADDR_WIDTH - 1 downto 0);
    islv_data : in std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    oslv_data : out std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0')
  );
end bram;

architecture behavioral of bram is
  -- constant to prevent overflow in loop variable (max: 2^16-1)
  constant C_SPLIT : integer range 1 to (C_SIZE+1)/65536+1 := (C_SIZE+1)/65536+1;

  type t_ram is array(0 to C_SIZE - 1) of bit_vector(C_DATA_WIDTH - 1 downto 0);

  -- load content from file to bram
  impure function load_content (filename : in string) return t_ram is
    file ram_file : text open read_mode is filename;
    variable ram_file_line : line;
    variable RAM : t_ram;
  begin
    for i in 0 to C_SPLIT-1 loop
      for j in 0 to C_SIZE/C_SPLIT-1 loop
        readline (ram_file, ram_file_line);
        read (ram_file_line, RAM(j+i*C_SIZE/C_SPLIT));
      end loop;
    end loop;
    return RAM;
  end function;

  -- check whether the filename is valid
  impure function init_ram (filename : in string) return t_ram is
    variable RAM : t_ram;
  begin
    if filename'LENGTH > 0 then
      RAM := load_content(filename);
    end if;
    return RAM;
  end function;

  signal a_RAM : t_ram := init_ram(STR_INIT);
  attribute ram_style : string;
  attribute ram_style of a_RAM : signal is "block";
  signal slv_data : bit_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

begin
  process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_en = '1' then
        report to_string(islv_addr);
        if isl_we = '1' then
          a_RAM(to_integer(unsigned(islv_addr))) <= to_bitvector(islv_data);
        end if;
        slv_data <= a_RAM(to_integer(unsigned(islv_addr)));
      end if;
    end if;
  end process;

  gen_no_reg : if C_OUTPUT_REG = 0 generate
    oslv_data <= to_stdlogicvector(slv_data);
  end generate;

  gen_reg : if C_OUTPUT_REG = 1 generate
    process(isl_clk)
    begin
      if rising_edge(isl_clk) then
        if isl_en = '1' then
          oslv_data <= to_stdlogicvector(slv_data);
        end if;
      end if;
    end process;
  end generate;
end behavioral;