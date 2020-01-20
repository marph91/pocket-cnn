library ieee;
  use ieee.std_logic_1164.all;

entity zero_pad is
  generic (
    C_DATA_WIDTH  : integer range 1 to 16 := 8;

    C_CH          : integer range 1 to 512 := 16;
    C_IMG_WIDTH   : integer range 1 to 512 := 32;
    C_IMG_HEIGHT  : integer range 1 to 512 := 32;

    C_PAD_TOP     : integer range 0 to 1 := 1;
    C_PAD_BOTTOM  : integer range 0 to 1 := 1;
    C_PAD_LEFT    : integer range 0 to 1 := 1;
    C_PAD_RIGHT   : integer range 0 to 1 := 1
  );
  port (
    isl_clk   : in std_logic;
    isl_rst_n : in std_logic;
    isl_ce    : in std_logic;
    isl_get   : in std_logic;
    isl_start : in std_logic;
    isl_valid : in std_logic;
    islv_data : in std_logic_vector(C_DATA_WIDTH-1 downto 0);
    oslv_data : out std_logic_vector(C_DATA_WIDTH-1 downto 0);
    osl_valid : out std_logic;
    osl_rdy   : out std_logic
  );
end entity;

architecture behavioral of zero_pad is
  constant C_IMG_WIDTH_OUT : integer := C_IMG_WIDTH + C_PAD_LEFT + C_PAD_RIGHT;
  constant C_IMG_HEIGHT_OUT : integer := C_IMG_HEIGHT + C_PAD_TOP + C_PAD_BOTTOM;

  -- counter
  signal int_ch_in : integer range 0 to C_CH-1 := 0;
  signal int_ch_out : integer range 0 to C_CH := 0;
  signal int_row : integer range 0 to C_IMG_HEIGHT-1 := 0;
  signal int_col : integer range 0 to C_IMG_WIDTH-1 := 0;
  signal int_pixel_to_pad : integer range 0 to C_IMG_WIDTH_OUT + C_PAD_LEFT + 1 := 0;

  signal sl_output_valid : std_logic := '0';
  signal slv_data_out : std_logic_vector(C_DATA_WIDTH - 1 downto 0);
  signal sl_rdy : std_logic := '0';

  type t_states IS (IDLE, PAD, PAD_PIXEL, FORWARD_DATA);
  signal state : t_states := IDLE;

begin
  proc_pad: process(isl_clk)
  begin
    if rising_edge(isl_clk) then
      -- Determine the image position to set int_pixel_to_pad.
      -- There are three posibilities for padding:
      -- 1. at the start of the image
      -- 2. after each row
      -- 3. at the end of the image
      if isl_start = '1' then
        -- padding at the start of the image
        int_pixel_to_pad <= C_IMG_WIDTH_OUT + C_PAD_LEFT;
        -- prevent problems with STRIDE /= KERNEL_SIZE at multiple images
        int_row <= 0;
        int_col <= 0;
        state <= IDLE;
      elsif isl_valid = '1' then
        if int_ch_in < C_CH-1 then
          int_ch_in <= int_ch_in+1;
        else
          int_ch_in <= 0;
          if int_col < C_IMG_WIDTH-1 then
            int_col <= int_col+1;
          else
            int_col <= 0;
            -- padding after each row
            int_pixel_to_pad <= C_PAD_RIGHT + C_PAD_LEFT;
            if int_row < C_IMG_HEIGHT-1 then
              int_row <= int_row+1;
            else
              int_row <= 0;
              -- padding at the end of the image
              if C_PAD_BOTTOM > 0 then
                int_pixel_to_pad <= C_IMG_WIDTH_OUT + C_PAD_RIGHT;
              else
                int_pixel_to_pad <= 0;
              end if;
            end if;
          end if;
        end if;
      end if;

      -- states are dependent on current state and int_pixel_to_pad
      case state is
        when IDLE =>
          sl_rdy <= '0';
          if int_pixel_to_pad > 0 then
            state <= PAD;
          end if;

        when PAD =>
          if int_pixel_to_pad > 0 then
            if isl_get = '1' then
              state <= PAD_PIXEL;
              int_pixel_to_pad <= int_pixel_to_pad-1;
            end if;
          else
            state <= FORWARD_DATA;
          end if;

        when PAD_PIXEL =>
          if int_ch_out < C_CH then
            int_ch_out <= int_ch_out+1;
            sl_output_valid <= '1';
            slv_data_out <= (others => '0');
          else
            int_ch_out <= 0;
            sl_output_valid <= '0';
            state <= PAD;
          end if;

        when FORWARD_DATA =>
          sl_rdy <= '1';
          slv_data_out <= islv_data;
          sl_output_valid <= isl_valid;
          if int_pixel_to_pad > 0 then
            state <= PAD;
            sl_rdy <= '0';
          end if;

      end case;
    end if;
  end process;

  osl_valid <= sl_output_valid;
  oslv_data <= slv_data_out;
  osl_rdy <= sl_rdy and isl_get;
end architecture;