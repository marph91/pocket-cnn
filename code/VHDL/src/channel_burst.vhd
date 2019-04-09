library ieee;
	use ieee.std_logic_1164.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity channel_burst is
    generic(
		C_DATA_WIDTH	: integer range 1 to 32 := 8;
		C_CH					: integer range 1 to 512 := 1
	);
	port(
		isl_clk   : in std_logic;
		isl_reset : in std_logic;
		isl_get		: in std_logic;
		isl_start	: in std_logic;
		isl_valid : in std_logic;
		islv_data	: in std_logic_vector(C_DATA_WIDTH-1 downto 0);
		oslv_data	: out std_logic_vector(C_DATA_WIDTH-1 downto 0);
		osl_valid : out std_logic;
		osl_rdy		: out std_logic
    );
end channel_burst;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavior of channel_burst is
	------------------------------------------
	-- Signal Declarations
	------------------------------------------
	signal sl_input_valid : std_logic := '0';
	signal slv_data_in : std_logic_vector(C_DATA_WIDTH-1 downto 0);
	signal slv_data_in_delay : std_logic_vector(C_DATA_WIDTH-1 downto 0);
	signal sl_bursted : std_logic := '0';
    
	signal sl_rdy : std_logic := '0';
	signal sl_output_valid : std_logic := '0';
	signal int_ch_in_cnt : integer range 0 to C_CH := 0;
	signal int_ch_out_cnt : integer range 0 to C_CH := 0;
	signal int_ch_to_burst : integer range 0 to C_CH := 0;

	type t_1d_array is array (natural range <>) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);
	signal a_ch : t_1d_array(0 to C_CH);

begin
	proc_data : process (isl_clk) is
	begin
		if (rising_edge(isl_clk)) then 
			-- to 0 to C_CH, that isl_valid = '1' and int_ch_to_burst > 1 can be handled at the same time
			if (isl_valid = '1') then
				a_ch(0) <= islv_data;
				for i in 1 to C_CH loop
					a_ch(i) <= a_ch(i-1);
				end loop;
			end if;
			if (int_ch_to_burst <= 1) or 
				(int_ch_to_burst = C_CH and isl_get = '0' and sl_output_valid <= '0') or
				(isl_start = '1') then
					sl_output_valid <= '0';
			else
				for i in 1 to C_CH loop
					a_ch(i) <= a_ch(i-1);
				end loop;
				sl_output_valid <= '1';
			end if;
		end if;
	end process proc_data;

	proc_cnt : process (isl_clk) is
	begin
		if (rising_edge(isl_clk)) then 
			slv_data_in <= islv_data;
			slv_data_in_delay <= slv_data_in;
			sl_input_valid <= isl_valid;
			
			if (isl_start = '1') then
				sl_bursted <= '0';
				-- prevent problems with STRIDE /= KERNEL_SIZE at multiple images
				int_ch_to_burst <= 0;
				int_ch_in_cnt <= 0;
				int_ch_out_cnt <= 0;
			elsif (isl_valid = '1') then
				if (sl_input_valid = '1' and isl_get = '1') then
					-- signal is already in burst mode
					sl_bursted <= '1';
				end if;
				if (int_ch_in_cnt < C_CH-1) then
					int_ch_in_cnt <= int_ch_in_cnt+1;
				else
					if (sl_bursted = '0') then
						int_ch_to_burst <= C_CH;
					end if;
					int_ch_in_cnt <= 0;
				end if;
			elsif (sl_input_valid = '0' and int_ch_out_cnt = C_CH-1) then
				sl_bursted <= '0';
			end if;
			
			if (sl_output_valid = '1') then
				int_ch_to_burst <= int_ch_to_burst-1;
			end if;
			
			if (isl_start = '1') then
				-- prevent problems with STRIDE /= KERNEL_SIZE at multiple images
				int_ch_out_cnt <= 0;
			elsif (sl_bursted = '1' or sl_output_valid = '1') then
				if (int_ch_out_cnt < C_CH-1) then
					int_ch_out_cnt <= int_ch_out_cnt+1;
				else
					int_ch_out_cnt <= 0;
				end if;
			end if;

			if (int_ch_in_cnt = C_CH-1 or int_ch_to_burst > 0 or sl_bursted = '1') then
				sl_rdy <= '0';
			else
				sl_rdy <= '1';
			end if;
		end if;
	end process proc_cnt;

	oslv_data <= slv_data_in_delay when sl_bursted = '1' else a_ch(C_CH);
	osl_valid <= sl_bursted or sl_output_valid;
	osl_rdy <= sl_rdy and isl_get;
end architecture behavior;
