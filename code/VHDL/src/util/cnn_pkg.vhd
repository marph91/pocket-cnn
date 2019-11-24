library ieee;
  use ieee.std_logic_1164.all;
  use ieee.numeric_std.all;

package cnn_pkg is
  -- TODO: make the bitwidth parametrizable
  type t_slv_array_2d is array(natural range <>, natural range <>) of std_logic_vector(7 downto 0);
end cnn_pkg;