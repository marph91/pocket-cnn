library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
library util;
  use util.math.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity line_buffer is
  generic(
    C_DATA_WIDTH       	: integer range 1 to 64 := 8;
    C_CH                : integer range 1 to 1024 := 16;
    C_WIDTH             : integer range 1 to 2048 := 20;
    C_WINDOW_SIZE       : integer range 1 to 2048 := 3
  );
  port(
    isl_clk   : in  std_logic;
    isl_reset : in  std_logic;
    isl_ce    : in  std_logic;
    isl_valid : in  std_logic;
    islv_data : in  std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    osl_valid : out std_logic;
    oslv_data : out std_logic_vector(C_WINDOW_SIZE * C_DATA_WIDTH - 1 downto 0)
  );
end line_buffer;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of line_buffer is
  constant C_OUTPUT_REG : integer range 0 to 1 := 1;
  constant C_BRAM_SIZE : integer range 1 to C_WIDTH*C_CH := C_WIDTH*C_CH - C_OUTPUT_REG;
  constant C_BRAM_DATA_WIDTH : integer range 0 to (C_WINDOW_SIZE-1)*C_DATA_WIDTH := (C_WINDOW_SIZE - 1) * C_DATA_WIDTH;

  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  signal sl_valid_out : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_WINDOW_SIZE * C_DATA_WIDTH - 1 downto 0) := (others => '0');

  signal usig_addr_cnt : unsigned(log2(C_BRAM_SIZE - 1) - 1 downto 0) := (others => '0');
  constant C_BRAM_ADDR_WIDTH : integer range 1 to usig_addr_cnt'LENGTH := usig_addr_cnt'LENGTH;

  signal sl_bram_en : std_logic;
  signal slv_bram_data_in : std_logic_vector(C_BRAM_DATA_WIDTH - 1 downto 0);
  signal slv_bram_data_out : std_logic_vector(C_BRAM_DATA_WIDTH - 1 downto 0);

begin 
  ------------------------------------------
  -- Component Instantiations
  ------------------------------------------   
  bram_buffer : entity work.bram
  generic map(
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
  sl_bram_en <= isl_valid and isl_ce;

  -- move data one line "down"
  gen_bram_lb_connect:
  for i in 0 to (C_WINDOW_SIZE - 3) generate
    slv_bram_data_in((C_DATA_WIDTH - 1) + (i + 1) * C_DATA_WIDTH downto (i + 1) * C_DATA_WIDTH) 
      <= slv_bram_data_out((C_DATA_WIDTH - 1) + i * C_DATA_WIDTH downto i * C_DATA_WIDTH);
  end generate gen_bram_lb_connect;

  proc_counter : process(isl_clk)
  begin  
    if rising_edge(isl_clk) then
      if isl_reset = '0' then
        usig_addr_cnt <= (others => '0');
      else        
        if isl_ce = '1' then
          if isl_valid = '1' then
            if usig_addr_cnt < C_BRAM_SIZE - 2 then
              usig_addr_cnt <= usig_addr_cnt + 1;
            else
              usig_addr_cnt <= (others => '0');
            end if;
          end if;
        end if;
      end if;
    end if;
  end process proc_counter;     

  proc_output_assign : process (isl_clk)
  begin   
    if rising_edge(isl_clk) then
      if isl_reset = '0' then
        sl_valid_out <= '0';
      else        
        if isl_ce = '1' then             
          if isl_valid = '1' then
            slv_data_out(C_DATA_WIDTH - 1 downto 0) <= islv_data;
            for i in 1 to C_WINDOW_SIZE - 1 loop
              slv_data_out((i + 1) * C_DATA_WIDTH - 1 downto i * C_DATA_WIDTH) 
                <= slv_bram_data_out(i * C_DATA_WIDTH - 1 downto (i - 1) * C_DATA_WIDTH);
            end loop;
          end if;

          sl_valid_out <= isl_valid;
        end if;
      end if;
    end if;
  end process proc_output_assign;

  osl_valid <= sl_valid_out;
  oslv_data <= slv_data_out;
end architecture behavioral;
