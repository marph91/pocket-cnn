library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;
	use ieee.fixed_pkg.all;
	use ieee.fixed_float_types.all;
library util;
	use util.math.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity conv_buf is
	generic (
		C_DATA_WIDTH_DATA		: integer range 1 to 16 := 8;
		C_FRAC_WIDTH_IN			: integer range 0 to 16 := 4;
		C_FRAC_WIDTH_OUT		: integer range 0 to 16 := 4;
		C_DATA_WIDTH_WEIGHTS 	: integer range 1 to 16 := 4;
		C_FRAC_WIDTH_WEIGHTS	: integer range 0 to 16 := 3;
		
		C_CONV_DIM 		: integer range 1 to 3 := 3;
		C_STRIDE		: integer range 1 to 3 := 1;
		C_CH_IN			: integer range 1 to 512 := 1;
		C_CH_OUT		: integer range 1 to 512 := 16;
		C_WIDTH			: integer range 1 to 512 := 36;
		C_HEIGHT		: integer range 1 to 512 := 16;
		STR_W_INIT		: string := "";
		STR_B_INIT		: string := ""
	);
	port ( 
		isl_clk 	: in std_logic;
		isl_rst_n	: in std_logic;
		isl_ce		: in std_logic;
		isl_get		: in std_logic;
		isl_start	: in std_logic;
		isl_valid	: in std_logic;
		islv_data	: in std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
		oslv_data	: out std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
		osl_valid	: out std_logic;
		osl_rdy		: out std_logic
	);
end conv_buf;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of conv_buf is

	------------------------------------------
	-- Signal Declarations
	------------------------------------------
	-- counter
	signal int_col 				: integer range 0 to C_WIDTH := 0;
	signal int_row	 			: integer range 0 to C_HEIGHT := 0;
	signal int_ch_in_cnt		: integer range 0 to C_CH_IN-1 := 0;
	signal int_ch_out_cnt		: integer range 0 to C_CH_OUT-1 := 0;
	signal int_conv_out_cnt		: integer range 0 to C_CH_IN*C_CH_OUT-1 := 0;
	signal int_conv_in_cnt		: integer range 0 to C_CH_IN*C_CH_OUT-1 := 0;
	signal int_pixel_in_cnt		: integer range 0 to C_HEIGHT*C_WIDTH := 0;
	signal int_pixel_out_cnt	: integer range 0 to C_HEIGHT*C_WIDTH := 0;

	-- for BRAM
	signal sl_bram_get_weights 	: std_logic := '0';
	constant C_BRAM_DATA_WIDTH 	: integer range 1 to C_DATA_WIDTH_WEIGHTS*(C_CONV_DIM*C_CONV_DIM) := C_DATA_WIDTH_WEIGHTS*(C_CONV_DIM*C_CONV_DIM);
	constant C_BRAM_SIZE		: integer range 1 to C_CH_IN*C_CH_OUT := C_CH_IN*C_CH_OUT;
	signal usig_addr_cnt		: unsigned(log2(C_BRAM_SIZE - 1) - 1 downto 0) := (others => '0');
	constant C_BRAM_ADDR_WIDTH 	: integer range 1 to usig_addr_cnt'LENGTH := usig_addr_cnt'LENGTH;
	signal slv_ram_data			: std_logic_vector(C_BRAM_DATA_WIDTH-1 downto 0);
	
	signal usig_addr_cnt_b		: unsigned(log2(C_CH_OUT) - 1 downto 0) := (others => '0');
	constant C_BRAM_ADDR_WIDTH_B	: integer range 1 to usig_addr_cnt_b'LENGTH := usig_addr_cnt_b'LENGTH;
	signal slv_ram_data_b		: std_logic_vector(C_DATA_WIDTH_WEIGHTS-1 downto 0);

	-- for line buffer
	signal slv_pad_data			: std_logic_vector(C_DATA_WIDTH_DATA - 1 downto 0);
	signal sl_lb_input_valid	: std_logic := '0';
	signal slv_lb_data_in		: std_logic_vector(C_DATA_WIDTH_DATA - 1 downto 0);
	signal sl_lb_output_valid	: std_logic := '0';
	signal slv_lb_data_out		: std_logic_vector(C_CONV_DIM*C_DATA_WIDTH_DATA - 1 downto 0);

	-- for window buffer
	signal sl_repeat 			: std_logic := '0';
	signal sl_wb_output_valid 	: std_logic := '0';
	signal slv_wb_data_out 		: std_logic_vector(C_CONV_DIM*C_CONV_DIM*C_DATA_WIDTH_DATA - 1 downto 0);

	-- for FSM
	type states is (FILL, LOAD, LOAD2, LOAD3, CALC, STRIDE);
	signal state 				: states := FILL;

	signal sl_output_valid		: std_logic := '0';
	signal sl_output_valid_delay		: std_logic := '0';
	signal sl_output_valid_delay2		: std_logic := '0';

	-- +log2(C_CH_IN)-1 weil ueber alle C_CH_IN summiert wird -> Datenbreite erweitern, damit kein saturate angewendet werden muss
	-- 6 bit int mehr um FIXED_SATURATE zu sparen und trotzdem ueberlauf zu vermeiden
	-- new bitwidth = log2(C_CH_IN*(2^old bitwidth-1)) = log2(C_CH_IN) + old bitwidth -> new bw = lb(64) + 8 = 14
	constant C_DW_SUM			: integer range 0 to 32 := C_DATA_WIDTH_DATA+C_DATA_WIDTH_WEIGHTS+1+log2(C_CONV_DIM-1)+log2(C_CONV_DIM-1)+log2(C_CH_IN);
	signal sfix_sum_tmp 		: sfixed(C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS-1 downto -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS) := (others => '0');
	-- 1 bit larger than sfix_sum_tmp
	signal sfix_sum_tmp_bias	: sfixed(C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS downto -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS) := (others => '0');
	
	-- for Convolution
	signal sl_conv_rdy	 		: std_logic := '0';
	signal sl_conv_input_valid 	: std_logic := '0';
	signal sl_conv_input_valid_delay 	: std_logic := '0';
	signal slv_conv_data_in		: std_logic_vector(C_CONV_DIM*C_CONV_DIM*C_DATA_WIDTH_DATA - 1 downto 0);
	signal slv_conv_data_out 	: std_logic_vector(C_DW_SUM-log2(C_CH_IN)-1 downto 0);
	signal sl_conv_output_valid	: std_logic := '0';
	signal sl_conv_output_valid_delay	: std_logic := '0';
	signal slv_sum				: std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);
	
	signal slv_data_out			: std_logic_vector(C_DATA_WIDTH_DATA-1 downto 0);

	signal sl_rdy 				: std_logic := '0';

	-- debug
	type t_2d_array is array (natural range <>, natural range <>) of std_logic_vector(C_DATA_WIDTH_DATA - 1 downto 0);
	type t_1d_array is array (natural range <>) of std_logic_vector(C_DATA_WIDTH_DATA - 1 downto 0); 
	signal a_conv_data_in		: t_2d_array(0 to C_CONV_DIM - 1,0 to C_CONV_DIM - 1);
	signal a_data_out			: t_1d_array(0 to C_CH_OUT - 1);
	signal a_sum_tmp			: t_1d_array(0 to C_CH_IN - 1) := (others => (others => '0'));

begin
	-----------------------------------
	-- BRAM for storing weights
	-----------------------------------
	bram_weights : entity work.bram
	generic map(
		C_DATA_WIDTH		=> C_BRAM_DATA_WIDTH,
		C_ADDR_WIDTH		=> C_BRAM_ADDR_WIDTH,
		C_SIZE				=> C_BRAM_SIZE,
		C_OUTPUT_REG   	=> 1,
		STR_INIT			=> STR_W_INIT
	)
	port map (
		isl_clk => isl_clk,
		isl_en => sl_bram_get_weights,
		isl_we => '0', -- only write during init
		islv_addr => std_logic_vector(usig_addr_cnt),
		islv_data => (others => '0'),
		oslv_data => slv_ram_data
	);

	-----------------------------------
	-- BRAM for storing bias
	-----------------------------------
	bram_bias : entity work.bram
	generic map(
		C_DATA_WIDTH		=> C_DATA_WIDTH_WEIGHTS,
		C_ADDR_WIDTH		=> C_BRAM_ADDR_WIDTH_B,
		C_SIZE				=> C_CH_OUT,
		C_OUTPUT_REG   	=> 0, -- TODO: check timing
		STR_INIT			=> STR_B_INIT
	)
	port map (
		isl_clk => isl_clk,
		isl_en => sl_bram_get_weights,
		isl_we => '0', -- only write during init
		islv_addr => std_logic_vector(usig_addr_cnt_b),
		islv_data => (others => '0'),
		oslv_data => slv_ram_data_b
	);
	
-- 	attribute shreg_extract : string;
-- 	attribute shreg_extract of work.bram : entity is "no";

	sl_lb_input_valid <= isl_valid; -- for FSM, probably replaceable
	gen_scalar : if C_CONV_DIM = 1 generate
		-----------------------------------
		-- Channel Buffer
		-----------------------------------
		channel_buffer : entity work.channel_buffer
		generic map(
			C_DATA_WIDTH 	=> C_DATA_WIDTH_DATA,
			C_CH			=> C_CH_IN
		)
		port map(
			isl_clk		=> isl_clk,
			isl_reset 	=> isl_rst_n,
			isl_ce 		=> isl_ce,
			isl_repeat	=> sl_repeat,
			isl_valid	=> isl_valid,
			islv_data	=> islv_data,
			osl_valid	=> sl_wb_output_valid,
			oslv_data	=> slv_wb_data_out
		);
	end generate;

	gen_kernel : if (C_CONV_DIM > 1) generate
		-----------------------------------
		-- Line Buffer
		-----------------------------------
		line_buffer : entity work.line_buffer
		generic map(
			C_DATA_WIDTH		=> C_DATA_WIDTH_DATA,
			C_CH				=> C_CH_IN,
			C_WIDTH		=> C_WIDTH, -- 36
			C_WINDOW_SIZE 	=> C_CONV_DIM
		)
		port map(
			isl_clk 	=> isl_clk,
			isl_reset 	=> isl_rst_n,
			isl_ce 		=> isl_ce,
			isl_valid 	=> isl_valid,
			islv_data 	=> islv_data,
			osl_valid	=> sl_lb_output_valid,
			oslv_data 	=> slv_lb_data_out
		);
		
-- 		attribute shreg_extract : string;
-- 		attribute shreg_extract of work.line_buffer : entity is "no";

		-----------------------------------
		-- Window Buffer
		-----------------------------------
		window_buffer : entity work.window_buffer
		generic map(
			C_DATA_WIDTH 	=> C_DATA_WIDTH_DATA,
			C_CH			=> C_CH_IN,
			C_WINDOW_SIZE	=> C_CONV_DIM
		)
		port map(
			isl_clk		=> isl_clk,
			isl_reset 	=> isl_rst_n,
			isl_ce 		=> isl_ce,
			isl_repeat	=> sl_repeat,
			isl_valid	=> sl_lb_output_valid,
			islv_data	=> slv_lb_data_out,
			osl_valid	=> sl_wb_output_valid,
			oslv_data	=> slv_wb_data_out
		);
	end generate;

	-----------------------------------
	-- Convolution
	-----------------------------------
	conv : entity work.conv
	generic map (
		C_DATA_WIDTH_DATA		=> C_DATA_WIDTH_DATA,
		C_FRAC_WIDTH_IN			=> C_FRAC_WIDTH_IN,
		C_DATA_WIDTH_WEIGHTS 	=> C_DATA_WIDTH_WEIGHTS,
		C_FRAC_WIDTH_WEIGHTS	=> C_FRAC_WIDTH_WEIGHTS,
		C_CONV_DIM				=> C_CONV_DIM
	)
	port map (
		isl_clk 		=> isl_clk,
		isl_rst_n		=> isl_rst_n,
		isl_ce			=> isl_ce,
		isl_valid		=> sl_conv_input_valid,
		islv_data		=> slv_conv_data_in,
		islv_weights	=> slv_ram_data,--((C_CONV_DIM*C_CONV_DIM+1)*C_DATA_WIDTH_WEIGHTS-1 downto C_DATA_WIDTH_WEIGHTS),
-- 		islv_bias		=> slv_ram_data(C_DATA_WIDTH_WEIGHTS - 1 downto 0),
		oslv_data		=> slv_conv_data_out,
		osl_valid		=> sl_conv_output_valid
	);

	-------------------------------------------------------
	-- Process: Counter
	-------------------------------------------------------
	proc_cnt : process (isl_clk) is
	begin
		if (rising_edge(isl_clk)) then
			if (isl_rst_n = '0') then
				int_pixel_in_cnt <= 0;
				int_pixel_out_cnt <= 0;
			elsif (isl_start = '1') then
				-- have to be resetted at start because of odd kernels (3x3+2) -> image dimensions arent fitting kernel stride
				int_pixel_in_cnt <= 0;
				int_pixel_out_cnt <= 0;
				int_row <= 0;
				int_col <= 0;
-- 				int_ch_in_cnt <= 0;
			elsif (isl_ce = '1') then
				if (isl_valid = '1') then
					if (int_ch_in_cnt < C_CH_IN-1) then
						int_ch_in_cnt <= int_ch_in_cnt+1;
					else
						int_ch_in_cnt <= 0;
						int_pixel_in_cnt <= int_pixel_in_cnt+1;
						if (int_col < C_WIDTH-1) then
							int_col <= int_col+1;
						else
							int_col <= 0;
							if (int_row < C_HEIGHT-1) then
								int_row <= int_row+1;
							else
								int_row <= 0;
							end if;
						end if;
					end if;
				end if;
				
				if (sl_conv_input_valid = '1') then
					if (int_conv_in_cnt < C_CH_IN*C_CH_OUT-1) then
						int_conv_in_cnt <= int_conv_in_cnt+1;
					else
						int_conv_in_cnt <= 0;
					end if;
				end if;
				
				if (sl_conv_output_valid = '1') then
					if (int_conv_out_cnt < C_CH_IN*C_CH_OUT-1) then
						int_conv_out_cnt <= int_conv_out_cnt+1;
					else
						int_conv_out_cnt <= 0;
					end if;
				end if;
				
				if (sl_output_valid_delay2 = '1') then
					if (int_ch_out_cnt < C_CH_OUT-1) then
						int_ch_out_cnt <= int_ch_out_cnt+1;
					else
						int_ch_out_cnt <= 0;
						int_pixel_out_cnt <= int_pixel_out_cnt+1;
					end if;
				end if;
			end if;
		end if;
	end process proc_cnt;
	
	-------------------------------------------------------
	-- Process: States
	-------------------------------------------------------
	proc_states : process (isl_clk) is
	begin
		if (rising_edge(isl_clk)) then
			if (isl_rst_n = '0') then
				state <= FILL;
			elsif (isl_start = '1') then
				state <= FILL;
			elsif (isl_ce = '1') then
				case state is 

					when FILL =>
						if (int_pixel_in_cnt = (C_CONV_DIM-1)*C_WIDTH+C_CONV_DIM-1) then
							state <= LOAD;
						end if;

					when LOAD =>
						if (C_CONV_DIM = 1) then
							if ((isl_valid = '1') and ((int_ch_in_cnt+1) mod C_CH_IN = 0)) then
								state <= LOAD2;
							end if;
						else
							if (sl_lb_input_valid = '1') then
								state <= LOAD2;
							end if;
						end if;

					when LOAD2 => 
						state <= LOAD3;

					when LOAD3 => 
						state <= CALC;

					when CALC => 
						if ((sl_conv_input_valid = '0' and 
							sl_conv_input_valid_delay = '1') and
							(int_col = 0 or C_STRIDE > 1)) then
								state <= STRIDE;
						elsif (sl_conv_input_valid = '0' and 
							sl_conv_input_valid_delay = '1' and
							((int_col /= 0) or (C_CONV_DIM = 1))) then
								state <= LOAD;
						end if;

					when STRIDE =>
						if ((int_row+1-C_CONV_DIM+C_STRIDE) mod C_STRIDE = 0 and 	-- every C_STRIDE row (C_CONV_DIM+C_STRIDE offset)
							((int_col+1-C_CONV_DIM+C_STRIDE) mod C_STRIDE = 0) and 	-- every C_STRIDE col (C_CONV_DIM+C_STRIDE offset)
							((int_col+1) > C_CONV_DIM-1)) then						-- shift window at end/start of line
								state <= LOAD;
						end if;

					when OTHERS => 
						state <= FILL;

				end case;
			end if;
		end if;
	end process proc_states;

	-------------------------------------------------------
	-- Process: Data shift test
	-------------------------------------------------------
	proc_data : process (isl_clk) is
	variable v_sfix_sum_tmp : sfixed(C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS-1 downto -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS) := (others => '0');-- resize(to_sfixed(slv_ram_data_b, C_DATA_WIDTH_WEIGHTS-C_FRAC_WIDTH_WEIGHTS-1, -C_FRAC_WIDTH_WEIGHTS), C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS-1, -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS); --(others => '0');
	begin 
		if (rising_edge(isl_clk)) then

			if (isl_rst_n = '0') then
				usig_addr_cnt_b <= (others => '0');
			elsif (C_CH_IN = 1 and sl_conv_output_valid = '1') then
				usig_addr_cnt_b <= unsigned(usig_addr_cnt_b)+1;
			elsif (C_CH_IN > 1 and sl_output_valid = '1') then
				if (int_ch_out_cnt < C_CH_OUT-1) then
					usig_addr_cnt_b <= unsigned(usig_addr_cnt_b)+1;
				else
					-- just needed for C_CH_OUT /= 2^x
					usig_addr_cnt_b <= (others => '0');
				end if;
			end if;
			-- sum up
			if (sl_output_valid = '1') then
-- 			if ((sl_conv_input_valid = '1' and sl_conv_input_valid_delay = '0') or
-- 				(C_CH_IN = 1 and sl_conv_output_valid = '1')) then
				v_sfix_sum_tmp := (others => '0');
-- 				resize(
-- 					to_sfixed(slv_ram_data_b, C_DATA_WIDTH_WEIGHTS-C_FRAC_WIDTH_WEIGHTS-1, -C_FRAC_WIDTH_WEIGHTS), 
-- 					C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS-1, -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS);--(others => '0');
				
			end if;
			if (sl_conv_output_valid = '1') then
				v_sfix_sum_tmp := resize(
					v_sfix_sum_tmp + to_sfixed(slv_conv_data_out, 
					C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS-log2(C_CH_IN)-1, -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS), 
					C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS-1, -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS, fixed_wrap, fixed_truncate);
			end if;

			sfix_sum_tmp <= v_sfix_sum_tmp;
			
-- 			resize(
-- 				v_sfix_sum_tmp + to_sfixed(slv_ram_data_b, C_DATA_WIDTH_WEIGHTS-C_FRAC_WIDTH_WEIGHTS-1, -C_FRAC_WIDTH_WEIGHTS),
-- 				C_DW_SUM-C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS, -C_FRAC_WIDTH_IN-C_FRAC_WIDTH_WEIGHTS);
			
			sfix_sum_tmp_bias <= sfix_sum_tmp + to_sfixed(slv_ram_data_b, C_DATA_WIDTH_WEIGHTS-C_FRAC_WIDTH_WEIGHTS-1, -C_FRAC_WIDTH_WEIGHTS);
				
			-- resize operation just at this point
			slv_data_out <= to_slv(resize(sfix_sum_tmp_bias, C_DATA_WIDTH_DATA-C_FRAC_WIDTH_OUT-1, -C_FRAC_WIDTH_OUT, fixed_saturate, fixed_round)); -- truncate just at this point

			-- delay of 1 cycle
			slv_conv_data_in <= slv_wb_data_out;

			-- pragma translate_off
			for i in 0 to C_CONV_DIM-1 loop
				for j in 0 to C_CONV_DIM-1 loop
					a_conv_data_in(j, i) <= slv_wb_data_out(((i+j*C_CONV_DIM)+1)*C_DATA_WIDTH_DATA-1 downto ((i+j*C_CONV_DIM))*C_DATA_WIDTH_DATA);
				end loop;
			end loop;
			-- pragma translate_on
		end if;
	end process proc_data;

	-------------------------------------------------------
	-- Process: State actions
	-------------------------------------------------------
	proc_actions : process (isl_clk) is
	begin
		if (rising_edge(isl_clk)) then 
			sl_conv_input_valid_delay <= sl_conv_input_valid;
			if (isl_rst_n = '0') then
				usig_addr_cnt <= (others => '0');
-- 				usig_addr_cnt_b <= (others => '0');
				sl_conv_rdy <= '0';
			elsif (isl_ce = '1') then
				case state is 
					when FILL =>
						-- wait for initial delay
						sl_conv_rdy <= '1';

					when LOAD =>
						if (isl_valid = '0') then
							sl_conv_rdy <= '1';
						else
							sl_conv_rdy <= '0';
						end if;
						sl_bram_get_weights <= '1'; -- evtl weglassbar??

					when LOAD2 =>
						usig_addr_cnt <= unsigned(usig_addr_cnt)+1;
-- 						if (C_CH_IN = 1) then
-- 							usig_addr_cnt_b <= unsigned(usig_addr_cnt_b)+1;
-- 						end if;
						sl_bram_get_weights <= '1';

					when LOAD3 =>
						-- load address one cycle earlier
						usig_addr_cnt <= unsigned(usig_addr_cnt)+1;
-- 						if (C_CH_IN = 1) then
-- 							usig_addr_cnt_b <= unsigned(usig_addr_cnt_b)+1;
-- 						end if;
						sl_conv_input_valid <= '1';

					when CALC => 
						if (sl_conv_input_valid = '1' or sl_conv_input_valid_delay = '0') then
							if (int_conv_in_cnt < C_CH_IN*C_CH_OUT-1) then
								sl_conv_input_valid <= '1';
								if (int_conv_in_cnt < C_CH_IN*C_CH_OUT-3) then
									usig_addr_cnt <= unsigned(usig_addr_cnt)+1;
								else
									-- just needed for C_CH_OUT /= 2^x
									usig_addr_cnt <= (others => '0');
-- 									if (C_CH_IN = 1) then
-- 										usig_addr_cnt_b <= unsigned(usig_addr_cnt_b)+1;
-- 									end if;
								end if;
-- 								if (C_CH_IN > 1 and int_conv_in_cnt mod C_CH_IN = 0) then
-- 									usig_addr_cnt_b <= unsigned(usig_addr_cnt_b)+1;
-- 								end if;
							else
								sl_conv_input_valid <= '0';
							end if;
						end if;
					
					when STRIDE =>
						-- wait for 2 or 4 cycles (delay for shift to new line)
						-- request new data
						sl_conv_rdy <= '1';

					when OTHERS =>
						null;

				end case;
			end if;
		end if;
	end process proc_actions;
	
	-------------------------------------------------------
	-- Process: Support signals
	-------------------------------------------------------
	proc_support : process (isl_clk) is
	begin 
		if (rising_edge(isl_clk)) then
			if (C_CH_IN = 1) then
				sl_output_valid <= sl_conv_output_valid;
			elsif ((int_conv_out_cnt+1) mod C_CH_IN = 0) then
				sl_output_valid <= '1';
			else
				sl_output_valid <= '0';
			end if;
			sl_output_valid_delay <= sl_output_valid;
			sl_output_valid_delay2 <= sl_output_valid_delay;
			if ((sl_lb_input_valid = '0') and 
				(sl_conv_input_valid = '1') and 
				(int_conv_in_cnt+3 < C_CH_IN*C_CH_OUT)) then
					sl_repeat <= '1';
			else
				sl_repeat <= '0';
			end if;
		end if;
	end process proc_support;
	
-- 	oslv_data <= slv_lb_data_in; --debug
-- 	osl_valid <= sl_lb_input_valid; --debug
	oslv_data <= slv_data_out;
	osl_valid <= sl_output_valid_delay2;
	osl_rdy <= sl_conv_rdy and isl_get;-- when (int_pixel_in_cnt < C_WIDTH*C_HEIGHT) else '0';
end behavioral;
