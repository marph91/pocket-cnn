
library ieee;
  use ieee.std_logic_1164.all;

library util;

entity zero_pad is
  generic (
    C_DATA_WIDTH : integer range 1 to 16 := 8;

    C_CH         : integer range 1 to 512 := 16;
    C_IMG_WIDTH  : integer range 1 to 512 := 32;
    C_IMG_HEIGHT : integer range 1 to 512 := 32;

    C_PAD_TOP    : integer range 0 to 1 := 1;
    C_PAD_BOTTOM : integer range 0 to 1 := 1;
    C_PAD_LEFT   : integer range 0 to 1 := 1;
    C_PAD_RIGHT  : integer range 0 to 1 := 1
  );
  port (
    isl_clk   : in    std_logic;
    isl_get   : in    std_logic;
    isl_start : in    std_logic;
    isl_valid : in    std_logic;
    islv_data : in    std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    oslv_data : out   std_logic_vector(C_DATA_WIDTH - 1 downto 0);
    osl_valid : out   std_logic;
    osl_rdy   : out   std_logic
  );
end entity zero_pad;

architecture behavioral of zero_pad is

  constant C_IMG_WIDTH_OUT  : integer := C_IMG_WIDTH + C_PAD_LEFT + C_PAD_RIGHT;
  constant C_IMG_HEIGHT_OUT : integer := C_IMG_HEIGHT + C_PAD_TOP + C_PAD_BOTTOM;

  -- counter
  signal int_ch_in        : integer range 0 to C_CH - 1 := 0;
  signal int_row          : integer range 0 to C_IMG_HEIGHT - 1 := 0;
  signal int_col          : integer range 0 to C_IMG_WIDTH - 1 := 0;
  signal int_pixel_to_pad : integer range 0 to C_IMG_WIDTH_OUT + C_PAD_LEFT + 1 := 0;

  signal sl_pixel_padded  : std_logic := '0';
  signal sl_padding_valid : std_logic := '0';

  signal sl_output_valid : std_logic := '0';
  signal slv_data_out    : std_logic_vector(C_DATA_WIDTH - 1 downto 0);

  type t_states is (IDLE, PAD, PAD_PIXEL, FORWARD_DATA);

  signal state : t_states := IDLE;

begin

  i_pixel_counter_in : entity util.pixel_counter(single_process)
    generic map (
      C_HEIGHT  => C_IMG_HEIGHT,
      C_WIDTH   => C_IMG_WIDTH,
      C_CHANNEL => C_CH
    )
    port map (
      isl_clk      => isl_clk,
      isl_reset    => isl_start,
      isl_valid    => isl_valid,
      oint_pixel   => open,
      oint_row     => int_row,
      oint_column  => int_col,
      oint_channel => int_ch_in
    );

  sl_padding_valid <= '1' when state = PAD_PIXEL and sl_pixel_padded = '0' else
                      '0';
  i_channel_counter_out : entity util.basic_counter
    generic map (
      C_MAX => C_CH
    )
    port map (
      isl_clk     => isl_clk,
      isl_reset   => isl_start,
      isl_valid   => sl_padding_valid,
      oint_count  => open,
      osl_maximum => sl_pixel_padded
    );

  -- Determine the image position to set int_pixel_to_pad.
  -- There are three possibilities for padding:
  --   1. at the start of the image
  --   2. after each row
  --   3. at the end of the image

  -- TODO: Fix padding at start/end for C_PAD > 1.
  proc_pixel_to_pad : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_start = '1') then
        -- padding at the start of the image
        int_pixel_to_pad <= C_IMG_WIDTH_OUT + C_PAD_LEFT;
      elsif (isl_valid = '1') then
        if (int_ch_in = C_CH - 1 and int_col = C_IMG_WIDTH - 1) then
          -- padding after each row
          int_pixel_to_pad <= C_PAD_RIGHT + C_PAD_LEFT;

          if (int_row = C_IMG_HEIGHT - 1) then
            -- padding at the end of the image
            int_pixel_to_pad <= C_PAD_BOTTOM * (C_IMG_WIDTH_OUT + C_PAD_RIGHT);
          end if;
        end if;
      end if;

      if (int_pixel_to_pad /= 0 and isl_get = '1' and state = PAD) then
        assert isl_valid = '0';
        int_pixel_to_pad <= int_pixel_to_pad - 1;
      end if;
    end if;

  end process proc_pixel_to_pad;

  proc_fsm : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      -- states are dependent on current state and int_pixel_to_pad
      case state is

        when IDLE =>
          if (int_pixel_to_pad /= 0) then
            state <= PAD;
          end if;

        when PAD =>
          if (int_pixel_to_pad /= 0) then
            if (isl_get = '1') then
              state <= PAD_PIXEL;
            end if;
          else
            state <= FORWARD_DATA;
          end if;

        when PAD_PIXEL =>
          if (sl_pixel_padded = '0') then
            sl_output_valid <= '1';
            slv_data_out    <= (others => '0');
          else
            sl_output_valid <= '0';
            state           <= PAD;
          end if;

        when FORWARD_DATA =>
          slv_data_out    <= islv_data;
          sl_output_valid <= isl_valid;
          if (int_pixel_to_pad /= 0) then
            state <= PAD;
          end if;

      end case;

    end if;

  end process proc_fsm;

  osl_valid <= sl_output_valid;
  oslv_data <= slv_data_out;
  osl_rdy   <= isl_get when (state = FORWARD_DATA and int_pixel_to_pad = 0) else
               '0';

end architecture behavioral;
