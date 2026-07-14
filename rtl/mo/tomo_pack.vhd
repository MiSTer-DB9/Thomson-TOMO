LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

PACKAGE tomo_pack IS

  -- 1Mo = 512k RAM + 256k ROM + 256k CART
  CONSTANT BASE_RAM  : unsigned(19 DOWNTO 0) := x"00000"; -- RAM
  CONSTANT BASE_ROM  : unsigned(19 DOWNTO 0) := x"80000"; -- ROM
  CONSTANT BASE_CART : unsigned(19 DOWNTO 0) := x"C0000"; -- CARTRIDGE
  
  -----------------------------------------------------------------------------
  SUBTYPE type_model IS natural RANGE 0 TO 15;

  -- GEN1
  CONSTANT T_TO7   : type_model := 8;

  -- GEN 2
  CONSTANT T_MO5   : type_model := 1;
  CONSTANT T_TO770 : type_model := 9;
  CONSTANT T_TO9   : type_model := 10;
  
  -- GEN 3
  CONSTANT T_MO6   : type_model := 2;  -- +PC128
  CONSTANT T_TO8   : type_model := 11; -- +TO8D
  CONSTANT T_TO9P  : type_model := 12;
  
  
  CONSTANT KB_FR : natural := 0; -- French
  CONSTANT KB_IT : natural := 1; -- Italian (Olivetti)
  CONSTANT KB_DE : natural := 2; -- Deutch

  -----------------------------------------------------------------------------
  CONSTANT SPEED_1x : uv2 :="00"; -- 1MHz
  CONSTANT SPEED_2x : uv2 :="01"; -- 2MHz
  CONSTANT SPEED_4x : uv2 :="10"; -- 4MHz
  
  -----------------------------------------------------------------------------
  -- ROM CRCS (DcMOTO ROMS)

  CONSTANT CRC32_MO5E   : uv32 := x"56F1_1CF3";
  CONSTANT CRC32_MO5NR  : uv32 := x"4161_1B90";
  CONSTANT CRC32_MO5_10 : uv32 := x"F62D_2F3A";
  CONSTANT CRC32_MO5_11 : uv32 := x"237C_60BF";
  CONSTANT CRC32_MO6_1  : uv32 := x"45E8_59C6";
  CONSTANT CRC32_MO6_2  : uv32 := x"B443_0A3B";
  CONSTANT CRC32_MO6_3  : uv32 := x"7A01_2322";
  CONSTANT CRC32_PC128  : uv32 := x"FC17_3504"; -- (Olivetti)

  CONSTANT CRC32_TO7    : uv32 := x"0E78_26DA";
  CONSTANT CRC32_TO770  : uv32 := x"8951_8862";
  CONSTANT CRC32_TO8_A  : uv32 := x"5C67_D00B";
  CONSTANT CRC32_TO8_B  : uv32 := x"7D03_B210";
  CONSTANT CRC32_TO8D   : uv32 := x"8BFB_5ECD";
  CONSTANT CRC32_TO9    : uv32 := x"DABF_70ED";
  CONSTANT CRC32_TO9P   : uv32 := x"2488_2B1C";

  -- MOx = FALSE TOx = TRUE
  FUNCTION isto(v : type_model) RETURN boolean;
  -- TOx = FALSE MOx = TRUE
  FUNCTION ismo(v : type_model) RETURN boolean;

  TYPE type_rom IS RECORD
    crc : uv32;
    m   : type_model;
    kb  : natural RANGE 0 TO 3;
  END RECORD;

  TYPE arr_rom IS ARRAY (natural RANGE <>) OF type_rom;

  CONSTANT ROMS : arr_rom := (
    (CRC32_MO5E,   T_MO5,  KB_FR),
    (CRC32_MO5_10, T_MO5,  KB_FR),
    (CRC32_MO5_11, T_MO5,  KB_FR),
    (CRC32_MO6_1,  T_MO6,  KB_FR),
    (CRC32_MO6_2,  T_MO6,  KB_FR),
    (CRC32_MO6_3,  T_MO6,  KB_FR),
    (CRC32_MO5NR,  T_MO6,  KB_FR),
    (CRC32_PC128,  T_MO6,  KB_IT),
    (CRC32_TO7,    T_TO7,  KB_FR),
    (CRC32_TO770,  T_TO770,KB_FR),
    (CRC32_TO8_A,  T_TO8,  KB_FR),
    (CRC32_TO8_B,  T_TO8,  KB_FR),
    (CRC32_TO8D,   T_TO8,  KB_FR),
    (CRC32_TO9,    T_TO9,  KB_FR),
    (CRC32_TO9P,   T_TO9P, KB_FR));

  -----------------------------------------------------------------------------
  TYPE enum_sel IS (
    RAM,
    ROM,
    CARTO,          -- MEMO5 / MEMO7 Cartridge
      
    PIA_MO,         -- MC6821 : MO5 / MOO6 : KBD / Tape / LightPen
    PIA_TO,         -- MC6821 : TO7 / TO770 / TO8 / TO9 / TO9+ : Clavier, crayon, cassette, imprimante...

    PIA_JEUX,       -- MC6821 : Games / Sound
    
    TIM,            -- MC6846 Timer / IO
    ACIA,           -- MC6850 ACIA KBD. TO9 / TO9+

    GAGMP,          -- Discrete       : TO7
                    -- Gate Array     : MO5 / TO770 / TO9
                    -- Gate Mode Page : MO6 / TO8 / TO9+
                    -- + Palette chip

    FDD_THMFC1,     -- THMFC1 FDD / QDD Internal TO8 + TO9+ , extension on others
    ROM_THMFC1,     -- FDD ROM CD90-351

    NOSEL
  );

  -----------------------------------------------------------------------------
  FUNCTION crc8 (
    CONSTANT d   : IN unsigned(7 DOWNTO 0);
    CONSTANT crc : IN unsigned(31 DOWNTO 0)) RETURN unsigned;

  -----------------------------------------------------------------------------

END PACKAGE tomo_pack;  

--#############################################################################

PACKAGE BODY tomo_pack IS

  ---------------------------------------------------------
  -- MOx = FALSE TOx = TRUE
  FUNCTION isto(v : type_model) RETURN boolean IS
  BEGIN
    RETURN (v>= T_TO7);
  END FUNCTION isto;

  FUNCTION ismo(v : type_model) RETURN boolean IS
  BEGIN
    RETURN NOT (v>= T_TO7);
  END FUNCTION ismo;


  ---------------------------------------------------------
  FUNCTION crc8 (
    CONSTANT d   : IN unsigned(7 DOWNTO 0);
    CONSTANT crc : IN unsigned(31 DOWNTO 0)) RETURN unsigned IS
    VARIABLE co : unsigned(31 DOWNTO 0);
    VARIABLE h  : unsigned(7 DOWNTO 0);
  BEGIN
    h(0):=d(0) XOR crc(31);
    h(1):=d(1) XOR crc(30);
    h(2):=d(2) XOR crc(29);
    h(3):=d(3) XOR crc(28);
    h(4):=d(4) XOR crc(27);
    h(5):=d(5) XOR crc(26);
    h(6):=d(6) XOR crc(25) XOR h(0);
    h(7):=d(7) XOR crc(24) XOR h(1);
    co(0) :=h(7);
    co(1) :=h(6) XOR h(7);
    co(2) :=h(5) XOR h(6) XOR h(7);
    co(3) :=h(4) XOR h(5) XOR h(6);
    co(4) :=h(3) XOR h(4) XOR h(5) XOR h(7);
    co(5) :=h(2) XOR h(3) XOR h(4) XOR h(6) XOR h(7);
    co(6) :=h(1) XOR h(2) XOR h(3) XOR h(5) XOR h(6);
    co(7) :=h(0) XOR h(1) XOR h(2) XOR h(4) XOR h(5) XOR h(7);
    co(8) := crc(0) XOR h(0) XOR h(1) XOR h(3) XOR h(4) XOR h(6) XOR h(7);
    co(9) := crc(1) XOR h(0) XOR h(2) XOR h(3) XOR h(5) XOR h(6);
    co(10):= crc(2) XOR h(1) XOR h(2) XOR h(4) XOR h(5) XOR h(7);
    co(11):= crc(3) XOR h(0) XOR h(1) XOR h(3) XOR h(4) XOR h(6) XOR h(7);
    co(12):= crc(4) XOR h(0) XOR h(2) XOR h(3) XOR h(5) XOR h(6) XOR h(7);
    co(13):= crc(5) XOR h(1) XOR h(2) XOR h(4) XOR h(5) XOR h(6);
    co(14):= crc(6) XOR h(0) XOR h(1) XOR h(3) XOR h(4) XOR h(5);
    co(15):= crc(7) XOR h(0) XOR h(2) XOR h(3) XOR h(4);
    co(16):= crc(8) XOR h(1) XOR h(2) XOR h(3) XOR h(7);
    co(17):= crc(9) XOR h(0) XOR h(1) XOR h(2) XOR h(6);
    co(18):=crc(10) XOR h(0) XOR h(1) XOR h(5);
    co(19):=crc(11) XOR h(0) XOR h(4);
    co(20):=crc(12) XOR h(3);
    co(21):=crc(13) XOR h(2);
    co(22):=crc(14) XOR h(1) XOR h(7);
    co(23):=crc(15) XOR h(0) XOR h(6) XOR h(7);
    co(24):=crc(16) XOR h(5) XOR h(6);
    co(25):=crc(17) XOR h(4) XOR h(5);
    co(26):=crc(18) XOR h(3) XOR h(4) XOR h(7);
    co(27):=crc(19) XOR h(2) XOR h(3) XOR h(6);
    co(28):=crc(20) XOR h(1) XOR h(2) XOR h(5);
    co(29):=crc(21) XOR h(0) XOR h(1) XOR h(4);
    co(30):=crc(22) XOR h(0) XOR h(3);
    co(31):=crc(23) XOR h(2);
    RETURN co;
  END crc8;

  ---------------------------------------------------------

END PACKAGE BODY tomo_pack;

