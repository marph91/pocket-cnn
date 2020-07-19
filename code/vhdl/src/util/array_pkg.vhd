  use std.textio.all;

library ieee;
  use ieee.std_logic_1164.all;
  use ieee.fixed_pkg.all;

package array_pkg is

  -- TODO: make the bitwidth parametrizable

  type t_slv_array_1d is array(natural range <>) of std_logic_vector(7 downto 0);

  type t_slv_array_2d is array(natural range <>, natural range <>) of std_logic_vector(7 downto 0);

  type t_slv_array_3d is array(natural range <>, natural range <>, natural range <>) of std_logic_vector(7 downto 0);

  type t_int_array_1d is array (natural range <>) of integer;

  type t_int_array_2d is array (natural range <>, natural range <>) of integer;

  type t_sfix_array_1d is array (natural range <>) of sfixed;

  type t_sfix_array_2d is array (natural range <>, natural range <>) of sfixed;

  type t_str_array_1d is array (natural range <>) of string;

  type t_ram is array(natural range <>) of std_logic_vector;

  type t_kernel_array is array (natural range <>) of t_slv_array_2d;

  impure function load_content(
    constant C_NAME : in string;
    constant C_SIZE : in integer;
    constant C_WIDTH : in integer) return t_ram;

  impure function init_weights(
    constant C_NAME : in string;
    constant C_SIZE : in integer;
    constant C_KSIZE : in integer;
    constant C_BITS : in integer) return t_kernel_array;

end package array_pkg;

package body array_pkg is
  -- load content from file to bram

  impure function load_content(
    constant C_NAME : in string;
    constant C_SIZE : in integer;
    constant C_WIDTH : in integer) return t_ram is
    file     ram_file      : text open read_mode is C_NAME;
    variable ram_file_line : line;
    variable a_ram         : t_ram(0 to C_SIZE - 1)(C_WIDTH - 1 downto 0);
  begin
    for i in 0 to C_SIZE - 1 loop
      readline(ram_file, ram_file_line);
      read(ram_file_line, a_ram(i));
    end loop;
    return a_ram;
  end function;

  -- check whether the filename is valid
  -- TODO: Why the two functions have to be separated?
  --       Merging them results in a failure without error message.

  impure function init_weights(
    constant C_NAME : in string;
    constant C_SIZE : in integer;
    constant C_KSIZE : in integer;
    constant C_BITS : in integer) return t_kernel_array is
    constant C_WIDTH       : integer := C_BITS * C_KSIZE * C_KSIZE;
    variable a_ram         : t_ram(0 to C_SIZE - 1)(C_WIDTH - 1 downto 0);
    variable a_ram_weights : t_kernel_array(0 to C_SIZE - 1)(0 to C_KSIZE - 1, 0 to C_KSIZE - 1);
    variable v_high_index  : integer;
    variable v_low_index   : integer;
  begin

    if (C_NAME'LENGTH > 0) then
      a_ram := load_content(C_NAME, C_SIZE, C_WIDTH);

      -- convert the loaded data to proper kernels
      for kernel in 0 to C_SIZE - 1 loop
        for i in 0 to C_KSIZE - 1 loop
          for j in 0 to C_KSIZE - 1 loop
            v_high_index                := ((i + j * C_KSIZE) + 1) * C_BITS - 1;
            v_low_index                 := (i + j * C_KSIZE) * C_BITS;
            a_ram_weights(kernel)(i, j) := a_ram(kernel)(v_high_index downto v_low_index);
          end loop;
        end loop;
      end loop;
    end if;

    return a_ram_weights;
  end function;

end array_pkg;
