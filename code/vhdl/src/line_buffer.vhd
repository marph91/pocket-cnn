
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;

entity LINE_BUFFER is
  generic (
    C_DATA_WIDTH  : integer range 1 to 64   := 8;

    C_CH          : integer range 1 to 1024 := 16;
    C_IMG_WIDTH   : integer range 1 to 2048 := 20;

    C_KSIZE       : integer range 1 to 2048 := 3
  );
  port (
    isl_clk   : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    oa_data   : out   t_slv_array_1d(0 to C_KSIZE - 1);
    osl_valid : out   std_logic
  );
end entity LINE_BUFFER;

architecture BEHAVIORAL of LINE_BUFFER is

  constant C_OUTPUT_REG      : integer range 0 to 1 := 1;
  constant C_BRAM_SIZE       : integer := C_IMG_WIDTH*C_CH - C_OUTPUT_REG;
  constant C_BRAM_DATA_WIDTH : integer := (C_KSIZE - 1) * C_DATA_WIDTH;

  signal sl_valid_out      : std_logic := '0';
  signal a_data_out        : t_slv_array_1d(0 to C_KSIZE - 1) := (others => (others => '0'));

  signal usig_addr_cnt     : unsigned(log2(C_BRAM_SIZE - 1) - 1 downto 0) := (others => '0');
  constant C_BRAM_ADDR_WIDTH : integer := usig_addr_cnt'LENGTH;

  signal sl_bram_en        : std_logic;
  signal slv_bram_data_in  : std_logic_vector(C_BRAM_DATA_WIDTH - 1 downto 0);
  signal slv_bram_data_out : std_logic_vector(C_BRAM_DATA_WIDTH - 1 downto 0);

begin

  i_bram : entity work.BRAM
    generic map (
      C_DATA_WIDTH  => C_BRAM_DATA_WIDTH,
      C_ADDR_WIDTH  => C_BRAM_ADDR_WIDTH,
      C_SIZE        => C_BRAM_SIZE,
      C_OUTPUT_REG  => C_OUTPUT_REG
    )
    port map (
      isl_clk   => isl_clk,
      isl_en    => sl_bram_en,
      isl_we    => '1',
      islv_addr => std_logic_vector(usig_addr_cnt),
      islv_data => slv_bram_data_in,
      oslv_data => slv_bram_data_out
    );

  -- incoming data is written to BRAM and also output
  slv_bram_data_in(C_DATA_WIDTH - 1 downto 0) <= islv_data;
  sl_bram_en                                  <= isl_valid;

  -- move data one line "down"

  GEN_BRAM_LB_CONNECT : for i in 0 to (C_KSIZE - 3) generate
    slv_bram_data_in((C_DATA_WIDTH - 1) + (i + 1) * C_DATA_WIDTH downto (i + 1) * C_DATA_WIDTH)
      <= slv_bram_data_out((C_DATA_WIDTH - 1) + i * C_DATA_WIDTH downto i * C_DATA_WIDTH);
  end generate GEN_BRAM_LB_CONNECT;

  PROC_COUNTER : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_valid = '1') then
        if (usig_addr_cnt < C_BRAM_SIZE - 2) then
          usig_addr_cnt <= usig_addr_cnt + 1;
        else
          usig_addr_cnt <= (others => '0');
        end if;
      end if;
    end if;

  end process PROC_COUNTER;

  PROC_OUTPUT_ASSIGN : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_valid = '1') then
        a_data_out(0) <= islv_data;
        for i in 1 to C_KSIZE - 1 loop
          a_data_out(i) <= slv_bram_data_out(i * C_DATA_WIDTH - 1 downto (i - 1) * C_DATA_WIDTH);
        end loop;
      end if;

      sl_valid_out <= isl_valid;
    end if;

  end process PROC_OUTPUT_ASSIGN;

  osl_valid <= sl_valid_out;
  oa_data   <= a_data_out;

end architecture BEHAVIORAL;
