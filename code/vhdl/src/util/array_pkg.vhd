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

  function array_to_slv (array_in : t_kernel_array) return std_logic_vector;

  function slv_to_array (slv_in : std_logic_vector; channel : integer; kernel_size : integer) return t_kernel_array;

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

  function array_to_slv (array_in : t_kernel_array) return std_logic_vector is
    variable slv_out        : std_logic_vector((array_in'LENGTH * array_in(0)'LENGTH(1) * array_in(0)'LENGTH(2)) * array_in(0)(0, 0)'LENGTH - 1 downto 0);
    variable bitwidth       : integer;
    variable rows           : integer;
    variable cols           : integer;
    variable channel        : integer;
    variable out_index_high : integer;
    variable out_index_low  : integer;
  begin
    bitwidth := array_in(0)(0, 0)'LENGTH;
    rows := array_in(0)'LENGTH(2);
    cols := array_in(0)'LENGTH(1);
    channel := array_in'LENGTH;
    for current_row in array_in(0)'RANGE(2) loop
      for current_col in array_in(0)'RANGE(1) loop
        for current_channel in array_in'RANGE loop
          out_index_high := (current_channel + current_col * channel + current_row * cols * channel + 1) * bitwidth - 1;
          out_index_low := (current_channel + current_col * channel + current_row * cols * channel) * bitwidth;
          slv_out(out_index_high downto out_index_low) := array_in(current_channel)(current_col, current_row);
        end loop;
      end loop;
    end loop;
    return slv_out;
  end function;

  function slv_to_array (slv_in : std_logic_vector; channel : integer; kernel_size : integer) return t_kernel_array is
    variable array_out     : t_kernel_array(0 to channel - 1)(0 to kernel_size - 1, 0 to kernel_size - 1);
    variable bitwidth      : integer;
    variable in_index_high : integer;
    variable in_index_low  : integer;
  begin
    bitwidth := 8;
    for current_row in array_out(0)'RANGE(2) loop
      for current_col in array_out(0)'RANGE(1) loop
        for current_channel in array_out'RANGE loop
          in_index_high := (current_channel + current_col * channel + current_row * kernel_size * channel + 1) * bitwidth - 1;
          in_index_low := (current_channel + current_col * channel + current_row * kernel_size * channel) * bitwidth;
          array_out(current_channel)(current_col, current_row) := slv_in(in_index_high downto in_index_low);
        end loop;
      end loop;
    end loop;
    return array_out;
  end function;

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

    assert C_NAME'LENGTH > 0;

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

    return a_ram_weights;
  end function;

end array_pkg;
