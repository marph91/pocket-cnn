library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package cnn_pkg is
  -- TODO: make the bitwidth parametrizable
  type t_slv_array_2d is array(natural range <>, natural range <>) of std_logic_vector(7 downto 0);

  type t_pad_array is array (natural range <>) of integer range 0 to 1;
  type t_win_array is array (natural range <>) of integer range 0 to 3;
  type t_ch_array is array (natural range <>) of integer range 1 to 512;
  type t_bitwidth_array is array (natural range <>, natural range <>) of integer range 0 to 16;
  type t_weights_array is array (natural range <>) of string;
end cnn_pkg;