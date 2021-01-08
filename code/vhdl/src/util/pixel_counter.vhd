
library ieee;
  use ieee.std_logic_1164.all;

library util;

-- TODO: Both implementations yield worse resource usage than the original implementation inside several modules.
--       Figure out why this is the case. It would be cleaner to handle the counting in a separate module.

entity pixel_counter is
  generic (
    C_HEIGHT            : integer;
    C_WIDTH             : integer;
    C_CHANNEL           : integer;
    C_CHANNEL_INCREMENT : integer range 1 to C_CHANNEL := 1
  );
  port (
    isl_clk      : in    std_logic;
    isl_reset    : in    std_logic;
    isl_valid    : in    std_logic;
    oint_pixel   : out   integer range 0 to C_HEIGHT * C_WIDTH - 1;
    oint_row     : out   integer range 0 to C_HEIGHT - 1;
    oint_column  : out   integer range 0 to C_WIDTH - 1;
    oint_channel : out   integer range 0 to C_CHANNEL - 1
  );
end entity pixel_counter;

architecture submodules of pixel_counter is

  signal sl_channel_maximum : std_logic := '0';
  signal sl_column_maximum  : std_logic := '0';

begin

  i_channel_count : entity util.basic_counter
    generic map (
      C_MAX       => C_CHANNEL,
      C_INCREMENT => C_CHANNEL_INCREMENT
    )
    port map (
      isl_clk     => isl_clk,
      isl_reset   => isl_reset,
      isl_valid   => isl_valid,
      oint_count  => oint_channel,
      osl_maximum => sl_channel_maximum
    );

  i_column_count : entity util.basic_counter
    generic map (
      C_MAX       => C_WIDTH
    )
    port map (
      isl_clk     => isl_clk,
      isl_reset   => isl_reset,
      isl_valid   => sl_channel_maximum,
      oint_count  => oint_column,
      osl_maximum => sl_column_maximum
    );

  i_row_count : entity util.basic_counter
    generic map (
      C_MAX       => C_HEIGHT
    )
    port map (
      isl_clk     => isl_clk,
      isl_reset   => isl_reset,
      isl_valid   => sl_column_maximum,
      oint_count  => oint_row,
      osl_maximum => open
    );

  -- TODO: function to convert between rows/cols and pixel
  i_pixel_count : entity util.basic_counter
    generic map (
      C_MAX       => C_HEIGHT * C_WIDTH
    )
    port map (
      isl_clk     => isl_clk,
      isl_reset   => isl_reset,
      isl_valid   => sl_channel_maximum,
      oint_count  => oint_pixel,
      osl_maximum => open
    );

end architecture submodules;

architecture single_process of pixel_counter is

  signal int_pixel   : integer range 0 to C_HEIGHT * C_WIDTH - 1 := 0;
  signal int_row     : integer range 0 to C_HEIGHT - 1 := 0;
  signal int_column  : integer range 0 to C_WIDTH - 1 := 0;
  signal int_channel : integer range 0 to C_CHANNEL - 1 := 0;

begin

  proc_cnt : process (isl_clk) is
  begin

    if (rising_edge(isl_clk)) then
      if (isl_reset = '1') then
        int_pixel   <= 0;
        int_channel <= 0;
        int_column  <= 0;
        int_row     <= 0;
      else
        if (isl_valid = '1') then
          if (int_channel /= C_CHANNEL - C_CHANNEL_INCREMENT) then
            int_channel <= int_channel + C_CHANNEL_INCREMENT;
          else
            int_channel <= 0;

            -- row and column count
            if (int_column /= C_WIDTH - 1) then
              int_column <= int_column + 1;
            else
              int_column <= 0;
              if (int_row /= C_HEIGHT - 1) then
                int_row <= int_row + 1;
              else
                int_row <= 0;
              end if;
            end if;

            -- pixel count
            if (int_pixel /= C_HEIGHT * C_WIDTH - 1) then
              int_pixel <= int_pixel + 1;
            else
              int_pixel <= 0;
            end if;
          end if;
        end if;
      end if;
    end if;

  end process proc_cnt;

  oint_pixel   <= int_pixel;
  oint_channel <= int_channel;
  oint_column  <= int_column;
  oint_row     <= int_row;

end architecture single_process;
