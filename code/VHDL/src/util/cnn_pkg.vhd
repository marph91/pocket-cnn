library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package cnn_pkg is
  -- TODO: make the bitwidth parametrizable
  type t_slv_array_2d is array(natural range <>, natural range <>) of std_logic_vector(7 downto 0);

  type t_int_array_1d is array (natural range <>) of integer;
  type t_int_array_2d is array (natural range <>, natural range <>) of integer;

  type t_str_array_1d is array (natural range <>) of string;
end cnn_pkg;