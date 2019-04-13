library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;

-----------------------------------------------------------------------------------------------------------------------
-- Entity Section
-----------------------------------------------------------------------------------------------------------------------
entity max_buf is
  generic (
    C_CH          : integer range 1 to 512 := 16;
    C_POOL_DIM    : integer range 2 to 3 := 2;
    C_STRIDE      : integer range 1 to 3 := 2;
    C_WIDTH       : integer range 1 to 512 := 34;
    C_HEIGHT      : integer range 1 to 512 := 16;
    C_INT_WIDTH   : integer range 1 to 16 := 8;
    C_FRAC_WIDTH  : integer range 0 to 16 := 8
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_get   : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
    oslv_data : out std_logic_vector(C_INT_WIDTH+C_FRAC_WIDTH-1 downto 0);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end max_buf;

-----------------------------------------------------------------------------------------------------------------------
-- Architecture Section
-----------------------------------------------------------------------------------------------------------------------
architecture behavioral of max_buf is
  constant C_DATA_WIDTH : integer range 1 to C_INT_WIDTH+C_FRAC_WIDTH := C_INT_WIDTH+C_FRAC_WIDTH;

  ------------------------------------------
  -- Signal Declarations
  ------------------------------------------
  -- counter
  signal int_ch_in_cnt : integer range 0 to C_CH-1 := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH-1 := 0;
  signal int_row : integer range 0 to C_HEIGHT := 0;
  signal int_col : integer range 0 to C_WIDTH := 0;
  signal int_pixel_in_cnt : integer range 0 to C_HEIGHT*C_WIDTH := 0;
  signal int_pixel_out_cnt : integer range 0 to C_HEIGHT*C_WIDTH := 0;

  -- for line buffer
  signal sl_lb_output_valid : std_logic := '0';
  signal slv_lb_data_out : std_logic_vector(C_POOL_DIM*C_DATA_WIDTH - 1 downto 0) := (others => '0');

  -- for window buffer
  signal sl_wb_repeat : std_logic := '0';
  signal sl_wb_output_valid : std_logic := '0';
  signal slv_wb_data_out : std_logic_vector(C_POOL_DIM*C_POOL_DIM*C_DATA_WIDTH - 1 downto 0) := (others => '0');

  -- for FSM
  type states is (FILL, STRIDE, LOAD, LOAD2, CALC);
  signal state : states := FILL;
  signal sl_filled : std_logic := '0';
  signal sl_output_valid : std_logic := '0';

  --for maxpool
  signal sl_max_input_valid : std_logic := '0';
  signal slv_max_data_in : std_logic_vector(C_POOL_DIM*C_POOL_DIM*C_DATA_WIDTH - 1 downto 0);-- := (others => '0');
  signal sl_max_output_valid : std_logic := '0';
  signal slv_max_data_out : std_logic_vector(C_DATA_WIDTH - 1 downto 0) := (others => '0');

  signal slv_data_out : std_logic_vector(C_DATA_WIDTH-1 downto 0);
  signal sl_rdy : std_logic := '0';

  -- debug
  type t_wb_dout_array is array (natural range <>, natural range <>) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal a_max_data_in    : t_wb_dout_array(0 to C_POOL_DIM - 1,0 to C_POOL_DIM - 1);

begin
  -----------------------------------
  -- Line Buffer
  -----------------------------------
  line_buffer : entity work.line_buffer
  generic map(
    C_DATA_WIDTH  => C_DATA_WIDTH,
    C_CH          => C_CH,
    C_WIDTH       => C_WIDTH,
    C_WINDOW_SIZE => C_POOL_DIM
  )
  port map(
    isl_clk     => isl_clk,
    isl_reset   => isl_rst_n,
    isl_ce      => isl_ce,
    isl_valid   => isl_valid,
    islv_data   => islv_data,
    osl_valid   => sl_lb_output_valid,
    oslv_data   => slv_lb_data_out
  );

  -----------------------------------
  -- Window Buffer
  -----------------------------------
  window_buffer_max : entity work.window_buffer
  generic map(
    C_DATA_WIDTH  => C_DATA_WIDTH,
    C_CH          => C_CH,
    C_WINDOW_SIZE => C_POOL_DIM
  )
  port map(
    isl_clk     => isl_clk,
    isl_reset   => isl_rst_n,
    isl_ce      => isl_ce,
    isl_repeat  => sl_wb_repeat,
    isl_valid   => sl_lb_output_valid,
    islv_data   => slv_lb_data_out,
    osl_valid   => sl_wb_output_valid,
    oslv_data   => slv_wb_data_out
  );

  -----------------------------------
  -- Max Pool
  -----------------------------------
  max : entity work.pool_max
  generic map (
    C_POOL_DIM    => C_POOL_DIM,
    C_INT_WIDTH   => C_INT_WIDTH,
    C_FRAC_WIDTH  => C_FRAC_WIDTH
  )
  port map (
    isl_clk   => isl_clk,
    isl_rst_n => isl_rst_n,
    isl_ce    => isl_ce,
    isl_valid => sl_wb_output_valid,
    islv_data => slv_wb_data_out,
    oslv_data => slv_max_data_out,
    osl_valid => sl_max_output_valid
  );

  -------------------------------------------------------
  -- Process: Counter
  -------------------------------------------------------
  proc_cnt : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        int_pixel_in_cnt <= 0;
        int_pixel_out_cnt <= 0;
      elsif isl_start = '1' then
        -- have to be resetted at start because of odd kernels (3x3+2) -> image dimensions arent fitting kernel stride
        int_pixel_in_cnt <= 0;
        int_pixel_out_cnt <= 0;
        int_row <= 0;
        int_col <= 0;
      elsif isl_ce = '1' then
        if isl_valid = '1' then
          if int_ch_in_cnt < C_CH-1 then
            int_ch_in_cnt <= int_ch_in_cnt+1;
          else
            int_ch_in_cnt <= 0;
            if int_col < C_WIDTH-1 then
              int_col <= int_col+1;
            else
              int_col <= 0;
              if int_row < C_HEIGHT-1 then
                int_row <= int_row+1;
              else
                int_row <= 0;
              end if;
            end if;
            int_pixel_in_cnt <= int_pixel_in_cnt+1;
          end if;
        end if;

        if sl_output_valid = '1' then
          if int_ch_out_cnt < C_CH-1 then
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
  proc_states : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        state <= FILL;
      elsif isl_start = '1' then
        state <= FILL;
      elsif isl_ce = '1' then
        case state is

          when FILL =>
            if int_pixel_in_cnt = (C_POOL_DIM-1)*C_WIDTH+C_POOL_DIM-1 then
              state <= LOAD;
            end if;

          when STRIDE =>
            if (int_row+1-C_POOL_DIM+C_STRIDE) mod C_STRIDE = 0 and   -- every C_STRIDE row (C_POOL_DIM+C_STRIDE offset)
              ((int_col+1-C_POOL_DIM+C_STRIDE) mod C_STRIDE = 0) and  -- every C_STRIDE col (C_POOL_DIM+C_STRIDE offset)
              ((int_col+1) > C_POOL_DIM-1) then                       -- shift window at end/start of line
                state <= LOAD;
            end if;

          when LOAD =>
            if isl_valid = '1' then
              state <= LOAD2;
            end if;

          when LOAD2 =>
            state <= CALC;

          when CALC =>
            if sl_max_output_valid = '0' and sl_output_valid = '1' then
              state <= STRIDE;
            end if;

          when OTHERS =>
            state <= FILL;

        end case;
      end if;
    end if;
  end process proc_states;

  -------------------------------------------------------
  -- Process: Data shift
  -------------------------------------------------------
  proc_data : process(isl_clk) is
  begin
    if rising_edge(isl_clk) then
      -- pragma translate_off
      for i in 0 to C_POOL_DIM-1 loop
        for j in 0 to C_POOL_DIM-1 loop
          a_max_data_in(j, i) <=
            slv_wb_data_out(C_DATA_WIDTH*((i+j*C_POOL_DIM)+1)-1 downto
            C_DATA_WIDTH*((i+j*C_POOL_DIM)));
        end loop;
      end loop;
      -- pragma translate_on

      slv_data_out <= slv_max_data_out;
    end if;
  end process proc_data;

  -------------------------------------------------------
  -- Process: State actions
  -------------------------------------------------------
  proc_actions : process(isl_clk) is
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        sl_output_valid <= '0';
      elsif isl_ce = '1' then
        case state is
          when FILL =>
            sl_rdy <= '1';

          when STRIDE =>
            sl_rdy <= '1';

          when LOAD2 =>
            sl_rdy <= '0';

          when CALC =>
            sl_output_valid <= sl_max_output_valid;

          when OTHERS =>
            null;

        end case;
      end if;

      if sl_rdy = '1' and isl_valid = '1' then
        sl_rdy <= '0';
      end if;
    end if;
  end process proc_actions;

  oslv_data <= slv_data_out;
  osl_valid <= sl_output_valid;
  osl_rdy <= sl_rdy and isl_get when int_pixel_in_cnt < C_WIDTH*C_HEIGHT else '0';
end behavioral;
