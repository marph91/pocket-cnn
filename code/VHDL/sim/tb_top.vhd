library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.math_real.all;
library ieee_proposed;
  use ieee_proposed.fixed_pkg.all;
library std;
  use std.textio.all;

entity tb_top is
end tb_top;

architecture behavioral of tb_top is

  constant C_DATA_WIDTH : integer := 8;

  component top is
    port (
      isl_clk     : in std_logic;
      isl_rst_n   : in std_logic;
      isl_ce      : in std_logic;
      isl_get     : in std_logic;
      isl_start   : in std_logic;
      isl_valid   : in std_logic;
      islv_data   : in std_logic_vector(C_DATA_WIDTH-1 downto 0);
      oslv_data   : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
      osl_valid   : out std_logic;
      osl_rdy     : out std_logic;
      osl_finish  : out std_logic
    );
  end component;

  signal sl_clk           : std_logic := '0';
  signal sl_rst_n         : std_logic := '0';
  signal sl_ce            : std_logic := '0';
  signal sl_rdy           : std_logic := '0';
  signal sl_get           : std_logic := '0';
  signal sl_start         : std_logic := '0';
  signal sl_input_valid   : std_logic := '0';
  signal slv_data_in      : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal slv_data_out     : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal sl_output_valid  : std_logic;
  signal sl_finish        : std_logic;

  type t_str_array is array (natural range <>) of string(1 to 48);
  signal files : t_str_array(0 to 1) := ("/home/workspace/microcnn/code/VHDL/sim/IMAGE1.txt",
                                         "/home/workspace/microcnn/code/VHDL/sim/IMAGE2.txt");

  constant C_CLK_PERIOD : time := 10 ns;

begin
  dut: top port map (
    isl_clk     => sl_clk,
    isl_rst_n   => sl_rst_n,
    isl_ce      => sl_ce,
    isl_get     => sl_get,
    isl_start   => sl_start,
    isl_valid   => sl_input_valid,
    islv_data   => slv_data_in,
    oslv_data   => slv_data_out,
    osl_valid   => sl_output_valid,
    osl_rdy     => sl_rdy,
    osl_finish  => sl_finish
  );

  clk_proc : process
  begin
    sl_clk <= '1';
    wait for C_CLK_PERIOD/2;
    sl_clk <= '0';
    wait for C_CLK_PERIOD/2;
  end process;

  stim_proc : process
  variable rand_num     : real;
  variable seed1, seed2 : positive;
  variable rand_range   : real := 1.0;
  file file_pointer     : text;
  variable inline       : line;
  variable pixel        : bit_vector(C_DATA_WIDTH-1 downto 0);
  begin
    sl_rst_n <= '0';
    wait for 10*C_CLK_PERIOD;
    sl_rst_n <= '1';
    sl_ce <= '1';
    wait for 10*C_CLK_PERIOD;

    for i in 0 to 1 loop
      -- load 2 times the same image
      sl_start <= '1';
      sl_get <= '1';
      wait for C_CLK_PERIOD;
      sl_rst_n <= '1';
      sl_start <= '0';

      file_open(file_pointer, files(i), READ_MODE);
      while not endfile(file_pointer) loop
        if sl_rdy = '1' and sl_input_valid = '0' then

          -- reading a line from the file.
          readline(file_pointer, inline);
          -- reading the data from the line and putting it in a real type variable.
          read(inline, pixel);
          -- put the value available in variable in a signal.
          slv_data_in <= to_stdlogicvector(pixel);
          sl_input_valid <= '1';
          wait for C_CLK_PERIOD;
          sl_input_valid <= '0';
        else
          sl_input_valid <= '0';
        end if;
        wait for C_CLK_PERIOD;
        wait for C_CLK_PERIOD;
      end loop;
      file_close(file_pointer);
      wait until sl_finish = '1';
      wait for C_CLK_PERIOD;
    end loop;
    wait;
  end process;
end behavioral;