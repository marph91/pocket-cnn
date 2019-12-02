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
    C_DATA_TOTAL_BITS     : integer range 1 to 16 := 8;

    C_CH_IN           : integer range 1 to 512 := 1;
    C_CH_OUT          : integer range 1 to 512 := 8;
    C_IMG_WIDTH       : integer range 1 to 512 := 8;
    C_IMG_HEIGHT      : integer range 1 to 512 := 8;

    C_KSIZE           : integer range 1 to 3 := 3;
    C_STRIDE          : integer range 1 to 3 := 1
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_get   : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_DATA_TOTAL_BITS-1 downto 0);
    oa_data   : out t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end window_ctrl;

architecture behavioral of window_ctrl is
  signal isl_valid_d1 : std_logic := '0';

  -- counter
  signal int_col : integer range 0 to C_IMG_WIDTH := 0;
  signal int_row : integer range 0 to C_IMG_HEIGHT := 0;
  signal int_ch_in_cnt : integer range 0 to C_CH_IN := 0;
  signal int_ch_out_cnt : integer range 0 to C_CH_IN := 0;
  signal int_repetition_cnt : integer range 0 to C_CH_OUT := 0;
  signal int_pixel_in_cnt : integer := 0;-- TODO: range 0 to C_IMG_HEIGHT*C_IMG_WIDTH := 0;
  signal int_pixel_out_cnt : integer := 0;-- TODO: range 0 to C_IMG_HEIGHT*C_IMG_WIDTH := 0;

  -- for line buffer
  signal sl_lb_valid_out : std_logic := '0';
  signal slv_lb_data_out : std_logic_vector(C_KSIZE*C_DATA_TOTAL_BITS - 1 downto 0);

  -- for window buffer
  signal sl_wb_valid_out : std_logic := '0';
  signal a_wb_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));

  -- for channel buffer
  signal sl_chb_repeat : std_logic := '0';
  signal sl_chb_valid_in : std_logic := '0';
  signal sl_chb_valid_in_d1 : std_logic := '0';
  signal sl_chb_valid_out : std_logic := '0';
  signal a_chb_data_in : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal a_chb_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
  signal sl_chb_rdy : std_logic := '0';

  signal sl_output_valid : std_logic := '0';
  signal a_data_out : t_slv_array_2d(0 to C_KSIZE-1, 0 to C_KSIZE-1) := (others => (others => (others => '0')));
begin
  gen_kernel : if C_KSIZE > 1 generate
    -- line buffer
    i_line_buffer : entity work.line_buffer
    generic map(
      C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
      C_CH          => C_CH_IN,
      C_IMG_WIDTH   => C_IMG_WIDTH,
      C_KSIZE => C_KSIZE
    )
    port map(
      isl_clk   => isl_clk,
      isl_reset => isl_rst_n,
      isl_ce    => isl_ce,
      isl_valid => isl_valid,
      islv_data => islv_data,
      oslv_data => slv_lb_data_out,
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
      isl_reset   => isl_rst_n,
      isl_ce      => isl_ce,
      isl_valid   => sl_lb_valid_out,
      islv_data   => slv_lb_data_out,
      oa_data     => a_wb_data_out,
      osl_valid   => sl_wb_valid_out
    );

    sl_chb_valid_in <= sl_wb_valid_out;
    a_chb_data_in <= a_wb_data_out;
  end generate;

  gen_scalar : if C_KSIZE = 1 generate
    sl_chb_valid_in <= isl_valid;
    a_chb_data_in(0, 0) <= islv_data;
  end generate;

  -- channel buffer
  i_channel_buffer : entity work.channel_buffer
  generic map(
    C_DATA_WIDTH  => C_DATA_TOTAL_BITS,
    C_CH          => C_CH_IN,
    C_REPEAT      => C_CH_OUT,
    C_KSIZE       => C_KSIZE
  )
  port map(
    isl_clk     => isl_clk,
    isl_reset   => isl_rst_n,
    isl_ce      => isl_ce,
    isl_repeat  => sl_chb_repeat,
    isl_valid   => sl_chb_valid_in,
    ia_data     => a_chb_data_in,
    oa_data     => a_chb_data_out,
    osl_valid   => sl_chb_valid_out,
    osl_rdy     => sl_chb_rdy
  );
  sl_chb_repeat <= '1' when int_pixel_in_cnt >= (C_KSIZE-1)*C_IMG_WIDTH+C_KSIZE-1 else '0';

  proc_cnt : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_rst_n = '0' then
        int_pixel_in_cnt <= 0;
        int_row <= 0;
        int_col <= 0;
      elsif isl_start = '1' then
        -- have to be resetted at start because of odd kernels (3x3+2)
        -- because image dimensions aren't fitting kernel stride
        int_pixel_in_cnt <= 0;
        int_row <= 0;
        int_col <= 0;
      elsif isl_ce = '1' then
        if sl_chb_valid_in_d1 = '1' then
          if int_ch_in_cnt < C_CH_IN-1 then
            int_ch_in_cnt <= int_ch_in_cnt+1;
          else
            int_ch_in_cnt <= 0;
            int_pixel_in_cnt <= int_pixel_in_cnt+1;
            -- TODO: function for converting between col, row and pixel_cnt
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

  -------------------------------------------------------
  -- Process: Output valid
  -- The output is valid in the following cases:
  --    1. after initial buffering
  --    2. every C_STRIDE row
  --    3. every C_STRIDE column
  --    4. when the window is not shifted at end/start of line
  -------------------------------------------------------
  proc_output_valid : process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      if isl_ce = '1' then
        a_data_out <= a_chb_data_out;
        if sl_chb_valid_in_d1 = '1' and
            int_pixel_in_cnt >= (C_KSIZE-1)*C_IMG_WIDTH+C_KSIZE-1 and
            (int_row+1-C_KSIZE+C_STRIDE) mod C_STRIDE = 0 and
            (int_col+1-C_KSIZE+C_STRIDE) mod C_STRIDE = 0 and
            int_col+1 > C_KSIZE-1 then
          sl_output_valid <= '1';
        elsif int_repetition_cnt = C_CH_OUT-1 and int_ch_out_cnt = C_CH_IN-1 then -- only for ch_in = 1
          sl_output_valid <= '0';
        end if;

        sl_chb_valid_in_d1 <= sl_chb_valid_in;
      end if;

      isl_valid_d1 <= isl_valid;
    end if;
  end process proc_output_valid;

  oa_data <= a_data_out;
  osl_valid <= sl_output_valid;
  osl_rdy <= isl_get and sl_chb_rdy and not isl_valid_d1;
end behavioral;