library ieee;
	use ieee.std_logic_1164.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity zero_pad is
	generic (
		C_DATA_WIDTH	: integer range 1 to 16 := 8;
		C_CH					: integer range 1 to 512 := 16;
		C_WIDTH				: integer range 1 to 512 := 32;
		C_HEIGHT			: integer range 1 to 512 := 32;
		C_PAD_TOP	 		: integer range 0 to 1 := 1;
		C_PAD_BOTTOM 	: integer range 0 to 1 := 1;
		C_PAD_LEFT 		: integer range 0 to 1 := 1;
		C_PAD_RIGHT 	: integer range 0 to 1 := 1
    );   
	port ( 
		isl_clk 	: in std_logic;
		isl_rst_n	: in std_logic;
		isl_ce		: in std_logic;
		isl_get		: in std_logic;
		isl_start	: in std_logic;
		isl_valid	: in std_logic;
		islv_data	: in std_logic_vector(C_DATA_WIDTH-1 downto 0);
		oslv_data	: out std_logic_vector(C_DATA_WIDTH-1 downto 0);
		osl_valid	: out std_logic;
		osl_rdy		: out std_logic
	);
end entity;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of zero_pad is
  
	constant C_WIDTH_OUT : integer range 1 to C_WIDTH + C_PAD_LEFT + C_PAD_RIGHT := C_WIDTH + C_PAD_LEFT + C_PAD_RIGHT;
	constant C_HEIGHT_OUT : integer range 1 to C_HEIGHT + C_PAD_TOP + C_PAD_BOTTOM := C_HEIGHT + C_PAD_TOP + C_PAD_BOTTOM; 

	------------------------------------------
	-- Signal Declarations
	------------------------------------------
	-- counter
	signal int_ch : integer range 0 to C_CH := 0;
	signal int_ch_out : integer range 0 to C_CH := 0;
	signal int_row : integer range 0 to C_HEIGHT := 0;
	signal int_col : integer range 0 to C_WIDTH := 0;
	signal int_data_in_cnt : integer range 0 to C_HEIGHT*C_WIDTH := 0;
	signal int_data_out_cnt	: integer range 0 to C_HEIGHT_OUT*C_WIDTH_OUT := 0;

	signal int_pixel_to_pad	: integer range 0 to (C_WIDTH_OUT + C_PAD_LEFT)*C_CH+1 := 0;
	signal int_burst : integer range 0 to C_CH := 0;

	signal sl_output_valid : std_logic := '0';
	signal slv_data_out : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
	signal sl_rdy : std_logic := '0';
  
begin
	-------------------------------------------------------
	-- Process: Counter
	-------------------------------------------------------
	-- TODO: int_pixel_to_pad arent pixel, but pixel*channel
	proc_cnt : process (isl_clk)
	begin
		if rising_edge(isl_clk) then
			if isl_rst_n = '0' then
				int_data_out_cnt <= 0;
				int_data_in_cnt <= 0;
			elsif isl_start = '1' then
				int_pixel_to_pad <= (C_WIDTH_OUT + C_PAD_LEFT)*C_CH;
				int_data_out_cnt <= 0;
				int_data_in_cnt <= 0;
				-- prevent problems with STRIDE /= KERNEL_SIZE at multiple images
				int_row <= 0;
				int_col <= 0;
-- 				int_ch_out <= 0;
			elsif isl_valid = '1' then
				if int_ch < C_CH-1 then
				    int_ch <= int_ch+1;
				else
					int_ch <= 0;
					int_data_in_cnt <= int_data_in_cnt+1;
					if int_col = C_WIDTH-1 then
						int_col <= 0;
						int_pixel_to_pad <= (C_PAD_RIGHT + C_PAD_LEFT)*C_CH+1; -- +1, because if output_valid=1 one gets subtracted immediately
						if int_row = C_HEIGHT-1 then
							int_row <= 0;
							if (C_PAD_BOTTOM > 0) then
								int_pixel_to_pad <= (C_WIDTH_OUT + C_PAD_RIGHT)*C_CH+1;
							else
								-- overwrites int_pixel_to_pad from previous int_col ite
								int_pixel_to_pad <= 0;
							end if;
						else
							int_row <= int_row+1;
						end if;
					else
						int_col <= int_col+1;
					end if;
				end if;
			elsif sl_output_valid = '1' then
				if int_pixel_to_pad > 0 then
					int_pixel_to_pad <= int_pixel_to_pad-1;
				end if;
				if int_ch_out < C_CH-1 then
				    int_ch_out <= int_ch_out+1;
				else
					int_data_out_cnt <= int_data_out_cnt+1;
					int_ch_out <= 0;
				end if;
			end if;
		end if;
	end process proc_cnt;
	
	-------------------------------------------------------
	-- Process: Padding
	-------------------------------------------------------
	proc_pad: process(isl_clk)
	begin
		if rising_edge(isl_clk) then
			if isl_start = '1' then
				sl_rdy <= '0';
				-- prevent problems with STRIDE /= KERNEL_SIZE at multiple images
-- 				int_burst <= 0;
-- 				sl_output_valid <= '0';
			elsif isl_ce = '1' then
				if isl_valid = '1' then
					slv_data_out <= islv_data;
					sl_output_valid <= '1';
				elsif int_pixel_to_pad /= 0 then
					sl_rdy <= '0';
					slv_data_out <= (others => '0');
					if isl_get = '1' and sl_output_valid = '0' then
						sl_output_valid <= '1';
						int_burst <= C_CH-1;
					elsif int_burst > 0 then
						sl_output_valid <= '1';
						int_burst <= int_burst-1;
					else
						sl_output_valid <= '0';
					end if;
				else
					sl_output_valid <= '0';
					sl_rdy <= '1';
				end if;
			end if;
		end if;
	end process proc_pad;
  
	osl_valid <= sl_output_valid;
	oslv_data <= slv_data_out;
	osl_rdy <= sl_rdy and isl_get;
end architecture;
