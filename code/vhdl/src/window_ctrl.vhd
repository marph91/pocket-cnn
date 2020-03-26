library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;
  use ieee.fixed_pkg.all;
  use ieee.fixed_float_types.all;
library util;
  use util.cnn_pkg.all;
  use util.math_pkg.all;

entity window_ctrl is
  generic (
    C_DATA_TOTAL_BITS : integer range 1 to 16 := 8;

    C_CH_IN           : integer range 1 to 512 := 1;
    C_CH_OUT          : integer range 1 to 512 := 8;
    C_IMG_WIDTH       : integer range 1 to 512 := 8;
    C_IMG_HEIGHT      : integer range 1 to 512 := 8;

    C_KSIZE           : integer range 1 to 3 := 3;
    C_STRIDE          : integer range 1 to 3 := 1;

    C_PARALLEL        : integer range 0 to 1 := 0
  );
  port (
    isl_clk   : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    oa_data   : out t_kernel_array(0 to C_PARALLEL*(C_CH_IN-1))(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end;

architecture behavioral of window_ctrl is
  signal isl_valid_d1 : std_logic := '0';

  -- counter
  signal int_col : integer range 0 to C_IMG_WIDTH-1 := 0;
  signal int_row : integer range 0 to C_IMG_HEIGHT-1 := 0;
  signal int_ch_in_cnt : integer range 0 to C_CH_IN-1 := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH_IN-1 := 0;
  signal int_repetition_cnt : integer range 0 to C_CH_OUT-1 := 0;
  signal int_pixel_in_cnt : integer range 0 to C_IMG_HEIGHT*C_IMG_WIDTH := 0;
  signal int_pixel_out_cnt : integer range 0 to C_IMG_HEIGHT*C_IMG_WIDTH := 0;

  -- for line buffer
  signal sl_lb_valid_out : std_logic := '0';
  signal a_lb_data_out : t_slv_array_1d(0 to C_KSIZE-1);

  -- for window buffer
  signal sl_wb_valid_out : std_logic := '0';
  signal a_wb_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

  -- for selector
  signal sl_selector_valid_in,
         sl_selector_valid_out : std_logic := '0';
  signal a_selector_data_in,
         a_selector_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal sl_selector_rdy : std_logic := '0';

  -- for channel repeater
  signal sl_repeater_valid_out : std_logic := '0';
  signal a_repeater_data_out : t_kernel_array(0 to C_PARALLEL*(C_CH_IN-1))(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => (others => '0'))));
  signal sl_repeater_rdy : std_logic := '0';

  signal sl_output_valid : std_logic := '0';
  signal a_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
begin
  gen_window_buffer : if C_KSIZE = 1 generate
    sl_selector_valid_out <= isl_valid;
    a_selector_data_out(0, 0) <= islv_data;
  else generate
    -- line buffer
    i_line_buffer : entity work.line_buffer
    generic map(
      C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_IN,
      C_IMG_WIDTH   => C_IMG_WIDTH,
      C_KSIZE       => C_KSIZE
    )
    port map(
      isl_clk   => isl_clk,
      isl_valid => isl_valid,
      islv_data => islv_data,
      oa_data   => a_lb_data_out,
      osl_valid => sl_lb_valid_out
    );

    -- window buffer
    i_window_buffer : entity work.window_buffer
    generic map(
      C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_IN,
      C_KSIZE       => C_KSIZE
    )
    port map(
      isl_clk     => isl_clk,
      isl_valid   => sl_lb_valid_out,
      ia_data     => a_lb_data_out,
      oa_data     => a_wb_data_out,
      osl_valid   => sl_wb_valid_out
    );

    sl_selector_valid_in <= sl_wb_valid_out;
    a_selector_data_in <= a_wb_data_out;

    -------------------------------------------------------
    -- The data is only needed if all of the following conditions are satisfied:
    --    1. after initial buffering
    --    2. every C_STRIDE row
    --    3. every C_STRIDE column
    --    4. when the window is not shifted at end/start of line
    -------------------------------------------------------
    proc_selector: process(isl_clk)
    begin
      if rising_edge(isl_clk) then
        if sl_selector_valid_in = '1' and
            int_pixel_in_cnt >= (C_KSIZE-1)*C_IMG_WIDTH+C_KSIZE-1 and
            (int_row+1-C_KSIZE+C_STRIDE) mod C_STRIDE = 0 and
            (int_col+1-C_KSIZE+C_STRIDE) mod C_STRIDE = 0 and
            int_col+1 > C_KSIZE-1 then
          sl_selector_valid_out <= '1';
        else
          sl_selector_valid_out <= '0';
        end if;

        a_selector_data_out <= a_selector_data_in;
      end if;
    end process;
  end generate;

  gen_channel_repeater : if C_CH_OUT > 1 generate
    -- channel repeater
    i_channel_repeater : entity work.channel_repeater
    generic map(
      C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_IN,
      C_REPEAT      => C_CH_OUT,
      C_KSIZE       => C_KSIZE,

      C_PARALLEL    => C_PARALLEL
    )
    port map(
      isl_clk     => isl_clk,
      isl_valid   => sl_selector_valid_out,
      ia_data     => a_selector_data_out,
      oa_data     => a_repeater_data_out,
      osl_valid   => sl_repeater_valid_out,
      osl_rdy     => sl_repeater_rdy
    );
  else generate
    sl_repeater_valid_out <= sl_selector_valid_out;
    a_repeater_data_out(0) <= a_selector_data_out;
    sl_repeater_rdy <= '1';
  end generate;

  proc_cnt: process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_start = '1' then
        -- have to be resetted at start because of odd kernels (3x3+2)
        -- because image dimensions aren't fitting kernel stride
        int_ch_in_cnt <= 0;
        int_pixel_in_cnt <= 0;
        int_pixel_out_cnt <= 0;
        int_row <= 0;
        int_col <= 0;
      else
        if sl_selector_valid_in = '1' then
          if int_ch_in_cnt < C_CH_IN-1 then
            int_ch_in_cnt <= int_ch_in_cnt+1;
          else
            int_ch_in_cnt <= 0;
            int_pixel_in_cnt <= int_pixel_in_cnt+1;
            if int_col < C_IMG_WIDTH-1 then
              int_col <= int_col+1;
            else
              int_col <= 0;
              if int_row < C_IMG_HEIGHT-1 then
                int_row <= int_row+1;
              else
                int_row <= 0;
              end if;
            end if;
          end if;
        end if;

        -- for debugging
        if osl_valid = '1' then
          if int_ch_out_cnt < C_CH_IN-1 then
            int_ch_out_cnt <= int_ch_out_cnt+1;
          else
            int_ch_out_cnt <= 0;
            if int_repetition_cnt < C_CH_OUT-1 then
              int_repetition_cnt <= int_repetition_cnt+1;
            else
              int_repetition_cnt <= 0;
              int_pixel_out_cnt <= int_pixel_out_cnt+1;
            end if;
          end if;
        end if;
      end if;
    end if;
  end process proc_cnt;

  oa_data <= a_repeater_data_out;
  osl_valid <= sl_repeater_valid_out;
  -- use sl_lb_valid_out and sl_wb_valid_out to get two less cycles of sl_rdy = '1'
  -- else too much data would get sent in
  osl_rdy <= sl_repeater_rdy and not (sl_lb_valid_out or sl_wb_valid_out);
end behavioral;