LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

PACKAGE rom_pack IS

  TYPE arr_uv8  IS ARRAY(natural RANGE<>) OF unsigned(7 DOWNTO 0);

  -- MO6 QDD ROM. 
  CONSTANT ROM_FDD_MO6 : arr_uv8 := (
    x"00",x"00"
    );

  -- TO8 / TO8D floppy
--  CONSTANT ROM_FDD_TO8D : arr_uv8 := (
--    x"00"
--    );

  -- TO 9
  CONSTANT ROM_FDD_WD1770 : arr_uv8 := (
    x"00",x"00"
    );
  

END PACKAGE;