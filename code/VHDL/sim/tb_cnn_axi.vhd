library ieee;
	use ieee.std_logic_1164.all;
	use ieee.numeric_std.all;
library std;
	use std.textio.all;
library util;
  use util.math.all;

entity tb_cnn_axi is
	generic (
		-- Users to add parameters here
		C_DATA_WIDTH_DATA		: integer range 1 to 16	:= 8;
		C_IMG_WIDTH		: integer range 1 to 512	:= 24;
		C_IMG_HEIGHT    : integer range 1 to 512    := 48;
		--C_DATA_WIDTH_WEIGHTS    : integer range 1 to 16	:= 8;
		--C_CLASSES				: integer range 2 to 3	:= 2;

		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH	: integer range 32 to 32	:= 32;
		C_S00_AXI_ADDR_WIDTH	: integer range 1 to 32		:= 4
	);
end tb_cnn_axi;

architecture behavioral of tb_cnn_axi is

	component cnn_axi_v1_0 is
		generic (
			C_DATA_WIDTH		: integer range 1 to 16	:= C_DATA_WIDTH_DATA;
			C_IMG_WIDTH		: integer range 1 to 512	:= C_IMG_WIDTH;
			C_IMG_HEIGHT    : integer range 1 to 512    := C_IMG_HEIGHT;
			--C_DATA_WIDTH_WEIGHTS    : integer range 1 to 16	:= C_DATA_WIDTH_WEIGHTS;
			--C_CLASSES				: integer range 2 to 3	:= C_CLASSES;

		-- Parameters of Axi Slave Bus Interface S00_AXI
		C_S00_AXI_DATA_WIDTH	: integer range 32 to 32	:= C_S00_AXI_DATA_WIDTH;
		C_S00_AXI_ADDR_WIDTH	: integer range 1 to 32		:= C_S00_AXI_ADDR_WIDTH
	);
	port (
		isl_cnn_aclk : in std_logic;
		isl_cnn_rst_n : in std_logic;
		osl_cnn_finish_interrupt : out std_logic;

		bram_aclk_ext : IN STD_LOGIC;
		bram_en_ext : IN STD_LOGIC;
		bram_we_ext : IN STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH/8-1 DOWNTO 0);
		bram_addr_ext : IN STD_LOGIC_VECTOR(log2(C_IMG_WIDTH*C_IMG_HEIGHT)-1 DOWNTO 0);
		bram_wrdata_ext : IN STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH-1 DOWNTO 0);
		bram_rddata_ext : OUT STD_LOGIC_VECTOR(C_S00_AXI_DATA_WIDTH-1 DOWNTO 0);

		-- Ports of Axi Slave Bus Interface S00_AXI
		s00_axi_aclk	: in std_logic;
		s00_axi_aresetn	: in std_logic;
		s00_axi_awaddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_awprot	: in std_logic_vector(2 downto 0);
		s00_axi_awvalid	: in std_logic;
		s00_axi_awready	: out std_logic;
		s00_axi_wdata	: in std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_wstrb	: in std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
		s00_axi_wvalid	: in std_logic;
		s00_axi_wready	: out std_logic;
		s00_axi_bresp	: out std_logic_vector(1 downto 0);
		s00_axi_bvalid	: out std_logic;
		s00_axi_bready	: in std_logic;
		s00_axi_araddr	: in std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
		s00_axi_arprot	: in std_logic_vector(2 downto 0);
		s00_axi_arvalid	: in std_logic;
		s00_axi_arready	: out std_logic;
		s00_axi_rdata	: out std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
		s00_axi_rresp	: out std_logic_vector(1 downto 0);
		s00_axi_rvalid	: out std_logic;
		s00_axi_rready	: in std_logic
	);
	end component;

	signal sl_clk_axi 			: std_logic := '0';
	signal sl_clk_cnn 			: std_logic := '0';
	signal sl_rst_n				: std_logic := '0';
	signal sl_finish			: std_logic := '0';

	--signal sl_bram_aclk_ext     : std_logic := '0';;
	signal sl_bram_en_ext		: std_logic := '0';
	signal slv_bram_we_ext		: std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
	signal slv_bram_addr_ext	: std_logic_vector(log2(C_IMG_WIDTH*C_IMG_HEIGHT)-1 DOWNTO 0) := (others => '0');
	signal slv_bram_wrdata_ext	: std_logic_vector(C_S00_AXI_DATA_WIDTH-1 DOWNTO 0);
	signal slv_bram_rddata_ext	: std_logic_vector(C_S00_AXI_DATA_WIDTH-1 DOWNTO 0);

	signal sl_s00_axi_aclk_s		: std_logic := '0';
	signal sl_s00_axi_aresetn_s		: std_logic := '0';
	signal slv_s00_axi_awaddr		: std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
	signal slv_s00_axi_awprot		: std_logic_vector(2 downto 0);
	signal sl_s00_axi_awvalid		: std_logic := '0';
	signal sl_s00_axi_awready		: std_logic := '0';
	signal slv_s00_axi_wdata		: std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
	signal slv_s00_axi_wstrb		: std_logic_vector((C_S00_AXI_DATA_WIDTH/8)-1 downto 0);
	signal sl_s00_axi_wvalid		: std_logic := '0';
	signal sl_s00_axi_wready		: std_logic := '0';
	signal slv_s00_axi_bresp		: std_logic_vector(1 downto 0);
	signal sl_s00_axi_bvalid		: std_logic := '0';
	signal sl_s00_axi_bready		: std_logic := '0';
	signal slv_s00_axi_araddr		: std_logic_vector(C_S00_AXI_ADDR_WIDTH-1 downto 0);
	signal slv_s00_axi_arprot		: std_logic_vector(2 downto 0);
	signal sl_s00_axi_arvalid		: std_logic := '0';
	signal sl_s00_axi_arready		: std_logic := '0';
	signal slv_s00_axi_rdata		: std_logic_vector(C_S00_AXI_DATA_WIDTH-1 downto 0);
	signal slv_s00_axi_rresp		: std_logic_vector(1 downto 0);
	signal sl_s00_axi_rvalid		: std_logic := '0';
	signal sl_s00_axi_rready		: std_logic := '0';

	-- Taktrate: 250 MHz (CNN) bzw. 50 MHz (AXI)
	constant C_CLK_PERIOD_AXI 	: time := 20 ns;
	constant C_CLK_PERIOD_CNN	: time := 10 ns;
	
	-- input
	type t_str_array is array (natural range <>) of string(1 to 48);
	signal files : t_str_array(0 to 1) := ("/home/workspace/opencnn/code/VHDL/sim/IMAGE1.txt",
	                                       "/home/workspace/opencnn/code/VHDL/sim/IMAGE2.txt");

begin
	dut: cnn_axi_v1_0 port map (
		isl_cnn_aclk => sl_clk_cnn,
		isl_cnn_rst_n => sl_rst_n,
		osl_cnn_finish_interrupt => sl_finish,

		bram_aclk_ext => sl_clk_axi,
		bram_en_ext => sl_bram_en_ext,
		bram_we_ext => slv_bram_we_ext,
		bram_addr_ext => slv_bram_addr_ext,
		bram_wrdata_ext => slv_bram_wrdata_ext,
		bram_rddata_ext => slv_bram_rddata_ext,
		
		s00_axi_aclk	=> sl_clk_axi,
		s00_axi_aresetn	=> sl_rst_n,
		s00_axi_awaddr	=> slv_s00_axi_awaddr,
		s00_axi_awprot	=> slv_s00_axi_awprot,
		s00_axi_awvalid	=> sl_s00_axi_awvalid,
		s00_axi_awready	=> sl_s00_axi_awready,
		s00_axi_wdata	=> slv_s00_axi_wdata,
		s00_axi_wstrb	=> slv_s00_axi_wstrb,
		s00_axi_wvalid	=> sl_s00_axi_wvalid,
		s00_axi_wready	=> sl_s00_axi_wready,
		s00_axi_bresp	=> slv_s00_axi_bresp,
		s00_axi_bvalid	=> sl_s00_axi_bvalid,
		s00_axi_bready	=> sl_s00_axi_bready,
		s00_axi_araddr	=> slv_s00_axi_araddr,
		s00_axi_arprot	=> slv_s00_axi_arprot,
		s00_axi_arvalid	=> sl_s00_axi_arvalid,
		s00_axi_arready	=> sl_s00_axi_arready,
		s00_axi_rdata	=> slv_s00_axi_rdata,
		s00_axi_rresp	=> slv_s00_axi_rresp,
		s00_axi_rvalid	=> sl_s00_axi_rvalid,
		s00_axi_rready	=> sl_s00_axi_rready
	);

	clk_proc_axi : process
	begin
		sl_clk_axi <= '1';
		wait for C_CLK_PERIOD_AXI/2;
		sl_clk_axi <= '0';
		wait for C_CLK_PERIOD_AXI/2;
	end process;
	
	clk_proc_cnn : process
	begin
		sl_clk_cnn <= '1';
		wait for C_CLK_PERIOD_CNN/2;
		sl_clk_cnn <= '0';
		wait for C_CLK_PERIOD_CNN/2;
	end process;
	
	stim_proc : process
	variable rand_num 		: real;
	variable seed1, seed2	: positive;
	variable rand_range 	: real := 1.0;
	file file_pointer 		: text;
	variable inline			: line;
	variable pixel			: bit_vector(C_DATA_WIDTH_DATA*4-1 downto 0);
	begin
		sl_rst_n <= '0';
		wait for 10*C_CLK_PERIOD_AXI;
		sl_rst_n <= '1';
		sl_bram_en_ext <= '1';
		wait for 10*C_CLK_PERIOD_AXI;

		for i in files'range loop
			slv_bram_we_ext <= "1111";
			file_open(file_pointer, files(i), READ_MODE);
			while (not endfile(file_pointer)) loop
				-- reading a line from the file.
				readline(file_pointer, inline);
				-- reading the data from the line and putting it in a real type variable.
				read(inline, pixel);
				-- put the value available in variable in a signal.
				slv_bram_wrdata_ext <= to_stdlogicvector(pixel);
				wait for C_CLK_PERIOD_AXI;
				if to_integer(unsigned(slv_bram_addr_ext)) = C_IMG_WIDTH*C_IMG_HEIGHT-4 then
					slv_bram_addr_ext <= (others => '0');
				else
					slv_bram_addr_ext <= std_logic_vector(unsigned(slv_bram_addr_ext)+4); -- bram controller always increments by 4
				end if;
			end loop;
			file_close(file_pointer);
			slv_bram_we_ext <= "0000";
			
			-- 2 times same image
			-- start flag = 1
			slv_s00_axi_wdata <= (0 => '1', others => '0');
			sl_s00_axi_wvalid <= '1';
			sl_s00_axi_awvalid <= '1';
			slv_s00_axi_awaddr <= (others => '0');
			slv_s00_axi_wstrb <= (others => '1');
			wait for 2*C_CLK_PERIOD_AXI;
	-- 		wait until sl_s00_axi_bvalid = '1';
	-- 		wait until (sl_s00_axi_awready = '1' and sl_s00_axi_wready = '1');
			
			-- start flag = 0
			slv_s00_axi_wdata <= (others => '0');
			sl_s00_axi_wvalid <= '1';
			sl_s00_axi_awvalid <= '1';
			slv_s00_axi_awaddr <= (others => '0');
			slv_s00_axi_wstrb <= (others => '1');
			wait for 2*C_CLK_PERIOD_AXI;
	-- 		wait until (sl_s00_axi_awready = '1' and sl_s00_axi_wready = '1');
	-- 		wait until sl_s00_axi_bvalid = '1';
			sl_s00_axi_wvalid <= '0';
			sl_s00_axi_awvalid <= '0';
			
			-- ready flag
			wait until sl_finish = '1';
	-- 		slv_bram_addr_ext <= (others => '0');
			
	-- 		slv_s00_axi_rdata <= (0 => '1', others => '0');
	-- 		sl_s00_axi_rvalid <= '1';
			sl_s00_axi_arvalid <= '1';
			sl_s00_axi_rready <= '1';
			-- bits 0 and 1 are reseved
			slv_s00_axi_araddr <= (2 => '1', others => '0');
	-- 		slv_s00_axi_wstrb <= (others => '1');
			wait for 2*C_CLK_PERIOD_AXI;
	-- 		wait until sl_s00_axi_rvalid = '1';
			sl_s00_axi_arvalid <= '0';
			sl_s00_axi_rready <= '0';
		end loop;
		
		
		-- start flag
		-- process image
		-- ready flag
		-- load next image
		wait;
	end process;
end behavioral;