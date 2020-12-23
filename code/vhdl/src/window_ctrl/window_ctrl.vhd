
library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;

library util;
  use util.array_pkg.all;

library window_ctrl_lib;

entity window_ctrl is
  generic (
    -- global data bitwidth
    C_BITWIDTH : integer range 1 to 16 := 8;

    -- image properties
    C_CH_IN      : integer range 1 to 512 := 1; -- input channel
    C_CH_OUT     : integer range 1 to 512 := 8; -- output channel (i. e. how often the output data gets repeated)
    C_IMG_WIDTH  : integer range 1 to 512 := 8; -- image width
    C_IMG_HEIGHT : integer range 1 to 512 := 8; -- image height

    -- kernel properties
    C_KERNEL_SIZE : integer range 1 to 5 := 3; -- kernel size (squared)
    C_STRIDE      : integer range 1 to 3 := 1; -- kernel stride

    -- further configuration
    C_PARALLEL_CH : integer range 1 to 512 := 1 -- defines how many channels should be put out in parallel
  );
  port (
    isl_clk   : in    std_logic;
    isl_start : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_BITWIDTH - 1 downto 0);
    oslv_data : out   std_logic_vector(C_PARALLEL_CH * C_KERNEL_SIZE * C_KERNEL_SIZE * C_BITWIDTH - 1 downto 0);
    osl_valid : out   std_logic;
    osl_rdy   : out   std_logic
  );
end entity window_ctrl;

architecture behavioral of window_ctrl is

  -- counter
  signal int_col       : integer range 0 to C_IMG_WIDTH - 1 := 0;
  signal int_row       : integer range 0 to C_IMG_HEIGHT - 1 := 0;
  signal int_pixel_cnt : integer range 0 to C_IMG_HEIGHT * C_IMG_WIDTH := 0;

  -- for line buffer
  signal sl_lb_valid_out : std_logic := '0';
  signal a_lb_data_out   : t_slv_array_1d(0 to C_KERNEL_SIZE - 1);

  -- for window buffer
  signal sl_wb_valid_out : std_logic := '0';
  signal a_wb_data_out   : t_slv_array_2d(0 to C_KERNEL_SIZE - 1, 0 to C_KERNEL_SIZE - 1) := (others => (others => (others => '0')));

  -- for selector
  signal sl_flush                 : std_logic := '0';
  signal sl_selector_valid_in     : std_logic := '0';
  signal sl_selector_valid_out    : std_logic := '0';
  signal sl_selector_valid_out_d1 : std_logic := '0';
  signal sl_selector_valid_out_d2 : std_logic := '0';
  signal a_selector_data_in       : t_slv_array_2d(0 to C_KERNEL_SIZE - 1, 0 to C_KERNEL_SIZE - 1) := (others => (others => (others => '0')));
  signal a_selector_data_out      : t_slv_array_2d(0 to C_KERNEL_SIZE - 1, 0 to C_KERNEL_SIZE - 1) := (others => (others => (others => '0')));

  -- for channel repeater
  signal sl_repeater_valid_out : std_logic := '0';
  signal a_repeater_data_out   : t_kernel_array(0 to C_PARALLEL_CH - 1)(0 to C_KERNEL_SIZE - 1, 0 to C_KERNEL_SIZE - 1) := (others => (others => (others => (others => '0'))));
  signal sl_repeater_rdy       : std_logic := '0';

  signal slv_data_out : std_logic_vector(C_PARALLEL_CH * C_KERNEL_SIZE * C_KERNEL_SIZE * C_BITWIDTH - 1 downto 0) := (others => '0');

begin

  gen_window_buffer : if C_KERNEL_SIZE = 1 generate
    sl_selector_valid_out_d2  <= isl_valid;
    a_selector_data_out(0, 0) <= islv_data;
  else generate
    -- line buffer
    -- one cycle delay
    i_line_buffer : entity window_ctrl_lib.line_buffer
      generic map (
        C_BITWIDTH    => C_BITWIDTH,
        C_CH          => C_CH_IN,
        C_IMG_WIDTH   => C_IMG_WIDTH,
        C_KERNEL_SIZE => C_KERNEL_SIZE
      )
      port map (
        isl_clk   => isl_clk,
        isl_valid => isl_valid,
        islv_data => islv_data,
        oa_data   => a_lb_data_out,
        osl_valid => sl_lb_valid_out
      );

    -- window buffer
    -- one cycle delay
    i_window_buffer : entity window_ctrl_lib.window_buffer
      generic map (
        C_BITWIDTH    => C_BITWIDTH,
        C_CH          => C_CH_IN,
        C_KERNEL_SIZE => C_KERNEL_SIZE
      )
      port map (
        isl_clk   => isl_clk,
        isl_valid => sl_lb_valid_out,
        ia_data   => a_lb_data_out,
        oa_data   => a_wb_data_out,
        osl_valid => sl_wb_valid_out
      );

    sl_selector_valid_in <= sl_wb_valid_out;
    a_selector_data_in   <= a_wb_data_out;

    -------------------------------------------------------
    -- The data is only needed if all of the following conditions are satisfied:
    --    1. after initial buffering
    --    2. every C_STRIDE row
    --    3. every C_STRIDE column
    --    4. when the window is not shifted at end/start of line
    -------------------------------------------------------
    sl_flush <= '1' when int_pixel_cnt < (C_KERNEL_SIZE - 1) * C_IMG_WIDTH + C_KERNEL_SIZE - 1 else
                '0';

    proc_selector : process (isl_clk) is
    begin

      if (rising_edge(isl_clk)) then
        -- The delay is caused by line and window buffer.
        sl_selector_valid_out_d1 <= sl_selector_valid_out;
        sl_selector_valid_out_d2 <= sl_selector_valid_out_d1;

        if (isl_valid = '1' and
            sl_flush = '0' and
            (int_row + 1 - C_KERNEL_SIZE + C_STRIDE) mod C_STRIDE = 0 and
            (int_col + 1 - C_KERNEL_SIZE + C_STRIDE) mod C_STRIDE = 0 and
            int_col + 1 > C_KERNEL_SIZE - 1) then
          sl_selector_valid_out <= '1';
        else
          sl_selector_valid_out <= '0';
        end if;

        a_selector_data_out <= a_selector_data_in;
      end if;

    end process proc_selector;

  end generate gen_window_buffer;

  gen_channel_repeater : if C_CH_OUT > 1 generate
    -- channel repeater
    i_channel_repeater : entity window_ctrl_lib.channel_repeater
      generic map (
        C_BITWIDTH    => C_BITWIDTH,
        C_CH          => C_CH_IN,
        C_REPEAT      => C_CH_OUT,
        C_KERNEL_SIZE => C_KERNEL_SIZE,

        C_PARALLEL_CH => C_PARALLEL_CH
      )
      port map (
        isl_clk   => isl_clk,
        isl_valid => sl_selector_valid_out_d2,
        ia_data   => a_selector_data_out,
        oa_data   => a_repeater_data_out,
        osl_valid => sl_repeater_valid_out,
        osl_rdy   => sl_repeater_rdy
      );

  else generate
    sl_repeater_valid_out  <= sl_selector_valid_out_d2;
    a_repeater_data_out(0) <= a_selector_data_out;
    sl_repeater_rdy        <= '1';
  end generate gen_channel_repeater;

  i_pixel_counter_in : entity util.pixel_counter(single_process)
    generic map (
      C_HEIGHT  => C_IMG_HEIGHT,
      C_WIDTH   => C_IMG_WIDTH,
      C_CHANNEL => C_CH_IN
    )
    port map (
      isl_clk      => isl_clk,
      isl_reset    => isl_start,
      isl_valid    => isl_valid,
      oint_pixel   => int_pixel_cnt,
      oint_row     => int_row,
      oint_column  => int_col,
      oint_channel => open
    );

  -- synthesis translate off
  i_pixel_counter_out : entity util.pixel_counter(single_process)
    generic map (
      C_HEIGHT  => 1,
      C_WIDTH   => C_CH_OUT,
      C_CHANNEL => C_CH_IN
    )
    port map (
      isl_clk      => isl_clk,
      isl_reset    => isl_start,
      isl_valid    => sl_repeater_valid_out,
      oint_pixel   => open,
      oint_row     => open,
      oint_column  => open,
      oint_channel => open
    );

  -- synthesis translate on

  oslv_data <= array_to_slv(a_repeater_data_out);
  osl_valid <= sl_repeater_valid_out;
  -- Use isl_valid, sl_lb_valid_out and sl_wb_valid_out to get three less cycles of the ready signal.
  -- Else too much data would get sent in.
  osl_rdy <= '1' when sl_flush else
             sl_repeater_rdy and not (isl_valid or sl_lb_valid_out or sl_wb_valid_out);

end architecture behavioral;
