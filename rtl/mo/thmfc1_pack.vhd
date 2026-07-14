LIBRARY IEEE;
USE IEEE.std_logic_1164.ALL;
USE IEEE.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

PACKAGE thmfc1_pack IS

  -----------------------------------------------------------------------------
  -- From TEO Emulator

  CONSTANT MFM_GAP_DATA_VALUE        : uv8     := x"4E";
  CONSTANT MFM_PRE_SYNC_DATA_VALUE   : uv8     := x"00";
  CONSTANT MFM_SYNCHRO_DATA_VALUE    : uv8     := x"A1";
  CONSTANT MFM_SYNCHRO_CLOCK_VALUE   : uv8     := x"0A";
  CONSTANT MFM_INFO_ID               : uv8     := x"FE";
  CONSTANT MFM_SECTOR_ID             : uv8     := x"FB";
  CONSTANT MFM_HEAD_NUMBER           : uv8     := x"00";
  CONSTANT MFM_SIZE_ID               : uv8     := x"01";
  CONSTANT MFM_DATA_CLOCK_VALUE      : uv8     := x"FF";
  CONSTANT MFM_CRC_INFO_INIT         : uv16    := x"B230";
  CONSTANT MFM_CRC_DATA_INIT         : uv16    := x"E295";
  CONSTANT MFM_SECTOR_SIZE           : natural := 362;

  CONSTANT FM_GAP_DATA_VALUE         : uv8     := x"FF";
  CONSTANT FM_PRE_SYNC_DATA_VALUE    : uv8     := x"00";
  CONSTANT FM_SYNCHRO_CLOCK_VALUE    : uv8     := x"C7";
  CONSTANT FM_INFO_ID                : uv8     := x"FE";
  CONSTANT FM_SECTOR_ID              : uv8     := x"FB";
  CONSTANT FM_HEAD_NUMBER            : uv8     := x"00";
  CONSTANT FM_SIZE_ID                : uv8     := x"00";
  CONSTANT FM_DATA_CLOCK_VALUE       : uv8     := x"FF";
  CONSTANT FM_CRC_INFO_INIT          : uv16    := x"EF21";
  CONSTANT FM_CRC_DATA_INIT          : uv16    := x"BF84";
  CONSTANT FM_SECTOR_SIZE            : natural := 174;

  --CONSTANT SYNCHRO_CLOCK_MARK        : uv8     := x"80";
  --CONSTANT SYNCHRO_CLOCK_MARK_WRITE  : uv8     := x"81";
  --CONSTANT DATA_CLOCK_MARK           : uv8     := x"00";
  --CONSTANT DATA_CLOCK_MARK_WRITE     : uv8     := x"01";

  CONSTANT SYNCHRO_CLOCK_MARK        : uv8 := MFM_SYNCHRO_CLOCK_VALUE;
  CONSTANT SYNCHRO_CLOCK_MARK_WRITE  : uv8 := MFM_SYNCHRO_CLOCK_VALUE;
  CONSTANT DATA_CLOCK_MARK           : uv8 := MFM_DATA_CLOCK_VALUE;
  CONSTANT DATA_CLOCK_MARK_WRITE     : uv8 := MFM_DATA_CLOCK_VALUE;


  -- Escape codes for variable data
  CONSTANT E_DATA   : uv8 := x"20";
  CONSTANT E_CRC_LO : uv8 := x"21";
  CONSTANT E_CRC_HI : uv8 := x"22";
  CONSTANT E_TRACK  : uv8 := x"23";
  CONSTANT E_SECTOR : uv8 := x"24";

  CONSTANT DD_BYTE_RATE     : natural := 250000/8; -- 250kbits/s
  CONSTANT DD_SECTOR_SIZE   : natural := 256;
  CONSTANT DD_TRACK_NUMBER  : natural := 80;
  CONSTANT DD_TRACK_SIZE    : natural := 50016 / 8; -- = 6252

  CONSTANT SD_BYTE_RATE     : natural := 125000/8; -- 125kbits/s
  CONSTANT SD_SECTOR_SIZE   : natural := 128;
  CONSTANT SD_TRACK_NUMBER  : natural := 40;
  CONSTANT SD_TRACK_SIZE    : natural := 25008 / 8; -- = 3126

  CONSTANT TRACK_SIZE_MAX   : natural := DD_TRACK_SIZE;
  CONSTANT SECTOR_SIZE_MAX  : natural := DD_SECTOR_SIZE;
--  CONSTANT RAMDISK_SECTOR_SIZE   : natural := DD_SECTOR_SIZE;
  CONSTANT TRACK_NUMBER_MAX : natural := DD_TRACK_NUMBER;

  CONSTANT SECTOR_PER_TRACK : natural := 16;

 -- CONSTANT INVALID_NUMBER   : uv16    := x"FFFF";

  -- DD : 250kbits/s : 5tours/s => 50kbits / piste => 6250 octets
  -- SD : 125kbits/s : 5tours/s => 25kbits / piste => 3125 octets

  -- MFM : DD Sector : 362 octets par secteur : 5792 octets

  -- FM  : SD Sector : 174 octets par secteur : 2784 octets
  
  TYPE arr_natural IS ARRAY(natural RANGE <>) OF natural;
  CONSTANT SECTOR_SIZES : arr_natural := (128,256,512,1024);

  -----------------------------------------------------------------------------
  -- Allocation mémoire :
  -- 2 octets : DATA+SYNC
  -- 8k * 2 = 16k par piste
  -- 16k * 80 pistes = 1280ko par face disquette => alignement 2Mo
  
  -----------------------------------------------------------------------------
  TYPE type_fd_list IS RECORD  
    file_size   : natural RANGE 51200 TO 1310720;
    side_count  : natural RANGE 1     TO 4;
    track_count : natural RANGE 25    TO 80;
    sector_size : natural RANGE SD_SECTOR_SIZE TO DD_SECTOR_SIZE;
    density     : boolean; -- F=SD T=DD
    track_size  : natural RANGE SD_TRACK_SIZE  TO DD_TRACK_SIZE;
  END RECORD type_fd_list;

  TYPE arr_fd_list IS ARRAY(natural RANGE <>) OF type_fd_list;
  
  CONSTANT FD_LIST : arr_fd_list := (
    (   51200, 1, 25, SD_SECTOR_SIZE, false, SD_TRACK_SIZE), -- 400 * 128 : QDD

    (   81920, 1, 40, SD_SECTOR_SIZE, false, SD_TRACK_SIZE), -- 40 * 16 * 128
    (  163840, 1, 40, DD_SECTOR_SIZE, true,  DD_TRACK_SIZE), -- 40 * 16 * 256

    (  327680, 1, 80, DD_SECTOR_SIZE, true,  DD_TRACK_SIZE),  -- SIMPLE FACE : 80*16*256
    (  655360, 2, 80, DD_SECTOR_SIZE, true,  DD_TRACK_SIZE)); -- DOUBLE FACE : 80*16*256*2

    --(  983040, 3, 80, DD_SECTOR_SIZE ),
    --( 1310720, 4, 80, DD_SECTOR_SIZE ));

  -----------------------------------------------------------------------------
  -- SD / FM SECTOR
  --   0  :  16 * FM_GAP_DATA_VALUE
  --  16  :   6 * FM_PRE_SYNC_DATA_VALUE
  --  22  :   1 * FM_INFO_ID (SYNCHRO_CLOCK_MARK)
  --  23  :   1 * track (0..79)
  --  24  :   1 * FM_HEAD_NUMBER
  --  25  :   1 * sector (1..16)
  --  26  :   1 * FM_SIZE_ID
  --  27  :   2 * CRC16
  --  29  :   2 * FM_GAP_DATA_VALUE
  --  31  :   6 * FM_PRE_SYNC_DATA_VALUE
  --  37  :   1 * FM_SECTOR_ID (SYNCHRO_CLOCK_MARK)
  --  38  : 128 * DATA    
  -- 166  :   2 * CRC16
  -- 168  :   6 * MFM_GAP_DATA_VALUE
  -- 174  = Total
  CONSTANT SD_RAW_SECTOR : arr_uv8 := (
    FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, -- 16
    FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE,
    FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE,
    FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE, FM_GAP_DATA_VALUE,
    FM_PRE_SYNC_DATA_VALUE, FM_PRE_SYNC_DATA_VALUE, -- 6
    FM_PRE_SYNC_DATA_VALUE, FM_PRE_SYNC_DATA_VALUE,
    FM_PRE_SYNC_DATA_VALUE, FM_PRE_SYNC_DATA_VALUE,
    FM_INFO_ID,
    E_TRACK,
    FM_HEAD_NUMBER,
    E_SECTOR,
    FM_SIZE_ID,
    E_CRC_HI,
    E_CRC_LO,
    FM_GAP_DATA_VALUE,
    FM_GAP_DATA_VALUE,
    FM_PRE_SYNC_DATA_VALUE, FM_PRE_SYNC_DATA_VALUE,
    FM_PRE_SYNC_DATA_VALUE, FM_PRE_SYNC_DATA_VALUE,
    FM_PRE_SYNC_DATA_VALUE, FM_PRE_SYNC_DATA_VALUE,
    FM_SECTOR_ID, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, -- 128 DATA
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_CRC_HI,
    E_CRC_LO,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, -- FM ?
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE
  );
  CONSTANT SD_RAW_SECTOR_SIZE : natural := SD_RAW_SECTOR'length;

  -----------------------------------------------------------------------------
  -- DD / MFM SECTOR
  --  0  : 32 * MFM_GAP_DATA_VALUE
  --  32 : 12 * MFM_PRE_SYNC_DATA_VALUE
  --  44 :  3 * MFM_SYNCHRO_DATA_VALUE (SYNCHRO_CLOCK_MARK)
  --  47 :  1 * MFM_INFO_ID
  --  48 :  1 * track (0..79)
  --  49 :  1 * MFM_HEAD_NUMBER
  --  50 :  1 * sector (1..16)
  --  51 :  1 * MFM_SIZE_ID
  --  52 :  2 * CRC16
  --  54 : 22 * MFM_GAP_DATA_VALUE
  --  76 : 12 * MFM_PRE_SYNC_DATA_VALUE
  --  88 :  3 * MFM_SYNCHRO_DATA_VALUE (SYNCHRO_CLOCK_MARK)
  --  91 :  1 * MFM_SECTOR_ID
  --  92 : 256 * DATA
  -- 348 :  2 * CRC16
  -- 350 : 12 * MFM_GAP_DATA_VALUE
  -- 362 = Total
  CONSTANT DD_RAW_SECTOR : arr_uv8 := (
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, -- *32
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, -- *12
    MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE,
    MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE,
    MFM_SYNCHRO_DATA_VALUE, MFM_SYNCHRO_DATA_VALUE, MFM_SYNCHRO_DATA_VALUE, -- *3
    MFM_INFO_ID,
    E_TRACK,
    MFM_HEAD_NUMBER,
    E_SECTOR,
    MFM_SIZE_ID,
    E_CRC_HI,
    E_CRC_LO,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, -- *22
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE,
    MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, -- *12
    MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE,
    MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE, MFM_PRE_SYNC_DATA_VALUE,
    MFM_SYNCHRO_DATA_VALUE, MFM_SYNCHRO_DATA_VALUE, MFM_SYNCHRO_DATA_VALUE, -- *3
    MFM_SECTOR_ID,
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, -- 256 DATA
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA,
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, E_DATA, 
    E_CRC_HI,
    E_CRC_LO,
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, -- *12
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, 
    MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE, MFM_GAP_DATA_VALUE
  );
  CONSTANT DD_RAW_SECTOR_SIZE : natural := DD_RAW_SECTOR'length;

  -----------------------------------------------------------------------------
  CONSTANT BE16_64 : arr_uv8(0 TO 3) := (x"03",x"0C",x"30",x"C0");
  CONSTANT BE8_64  : arr_uv8(0 TO 7) := (x"01",x"02",x"04",x"08",
                                         x"10",x"20",x"40",x"80");
  
  -----------------------------------------------------------------------------
  -- CQ90-028 : 
  -- UD90-070 : Lecteur 5"1/4

  -- QD90-128 : QDD + Controller based on MC6852
  -- CD90-015 : Floppy + Controller. based on HD46503S/HD6843A
  -- CD90-351 : FDC controller based on THMFC1
  -- CD90-640 : FDC controller based on WD1770


  -- ROM for floppy/QDD interface 
  -- 4 pages * 2kB
  --   0:7BF = ROM
  -- 7D0:7D7 = THMFC1
  -- 7D8     = Bank switch
  
  CONSTANT ROM_CD90_351 : arr_uv8 := (
    x"4d", x"54", x"44", x"3a", x"16", x"01", x"0b", x"16", x"00", x"a5", x"16", x"00", x"34", x"16", x"00", x"3c",  -- 0000
    x"16", x"00", x"43", x"16", x"00", x"4a", x"16", x"00", x"51", x"16", x"00", x"58", x"16", x"00", x"5f", x"16",  -- 0010
    x"00", x"66", x"16", x"00", x"6d", x"16", x"ff", x"fd", x"16", x"ff", x"fd", x"34", x"46", x"33", x"8c", x"f8",  -- 0020
    x"86", x"03", x"20", x"6c", x"35", x"c6", x"34", x"46", x"33", x"8c", x"cc", x"86", x"03", x"20", x"61", x"35",  -- 0030
    x"c6", x"34", x"46", x"33", x"8c", x"c4", x"86", x"01", x"8d", x"52", x"35", x"c6", x"33", x"8c", x"be", x"86",  -- 0040
    x"02", x"8d", x"49", x"1f", x"30", x"39", x"33", x"8c", x"b7", x"86", x"02", x"8d", x"3f", x"1f", x"30", x"39",  -- 0050
    x"33", x"8c", x"b0", x"86", x"02", x"8d", x"35", x"1f", x"30", x"39", x"33", x"8c", x"a9", x"86", x"02", x"8d",  -- 0060
    x"2b", x"1f", x"30", x"39", x"33", x"8c", x"a2", x"86", x"02", x"8d", x"21", x"1f", x"30", x"39", x"33", x"8c",  -- 0070
    x"9b", x"86", x"02", x"8d", x"17", x"1f", x"30", x"39", x"33", x"8c", x"94", x"86", x"02", x"8d", x"0d", x"1f",  -- 0080
    x"30", x"39", x"33", x"8c", x"8d", x"86", x"02", x"8d", x"03", x"1f", x"30", x"39", x"c6", x"00", x"34", x"04",  -- 0090
    x"a7", x"8d", x"07", x"34", x"ad", x"c4", x"1f", x"03", x"35", x"04", x"e7", x"8d", x"07", x"2a", x"39", x"17",  -- 00a0
    x"00", x"86", x"0f", x"49", x"17", x"00", x"8c", x"17", x"01", x"0b", x"25", x"50", x"96", x"4e", x"81", x"43",  -- 00b0
    x"10", x"27", x"ff", x"74", x"86", x"02", x"34", x"02", x"0f", x"58", x"0f", x"4a", x"0f", x"4b", x"86", x"01",  -- 00c0
    x"97", x"4c", x"33", x"8d", x"81", x"2a", x"df", x"4f", x"17", x"03", x"8d", x"17", x"00", x"83", x"de", x"4f",  -- 00d0
    x"24", x"08", x"96", x"58", x"26", x"21", x"03", x"58", x"20", x"e0", x"31", x"8d", x"81", x"91", x"34", x"20",  -- 00e0
    x"86", x"55", x"6a", x"c4", x"63", x"c4", x"ab", x"c0", x"11", x"a3", x"e4", x"26", x"f5", x"35", x"20", x"a1",  -- 00f0
    x"c4", x"26", x"09", x"6e", x"8d", x"80", x"f9", x"35", x"02", x"4a", x"26", x"ba", x"0f", x"80", x"6e", x"9f",  -- 0100
    x"00", x"1e", x"34", x"7f", x"8d", x"22", x"8d", x"2b", x"25", x"06", x"8d", x"4e", x"8d", x"43", x"24", x"07",  -- 0110
    x"35", x"02", x"1e", x"8a", x"44", x"35", x"fe", x"96", x"48", x"81", x"01", x"26", x"08", x"96", x"4e", x"81",  -- 0120
    x"43", x"10", x"27", x"fe", x"f8", x"4f", x"20", x"e8", x"1f", x"50", x"84", x"70", x"1f", x"8b", x"30", x"8d",  -- 0130
    x"06", x"8e", x"39", x"96", x"48", x"81", x"01", x"26", x"0e", x"c6", x"01", x"33", x"8d", x"00", x"17", x"a6",  -- 0140
    x"c5", x"a7", x"02", x"97", x"57", x"4f", x"39", x"d6", x"49", x"c1", x"04", x"10", x"24", x"03", x"dd", x"20",  -- 0150
    x"ea", x"86", x"40", x"a7", x"02", x"39", x"41", x"01", x"42", x"02", x"86", x"02", x"34", x"02", x"96", x"48",  -- 0160
    x"31", x"8d", x"00", x"51", x"85", x"01", x"26", x"30", x"31", x"8d", x"02", x"ec", x"85", x"02", x"26", x"28",  -- 0170
    x"31", x"8d", x"00", x"ba", x"85", x"08", x"26", x"20", x"31", x"8d", x"00", x"6f", x"85", x"20", x"26", x"18",  -- 0180
    x"31", x"8d", x"03", x"86", x"85", x"40", x"26", x"10", x"31", x"8d", x"00", x"99", x"85", x"04", x"26", x"08",  -- 0190
    x"31", x"8d", x"00", x"97", x"85", x"10", x"27", x"1a", x"ad", x"a4", x"24", x"17", x"96", x"4e", x"85", x"51",  -- 01a0
    x"26", x"11", x"6a", x"e4", x"27", x"0c", x"0f", x"4e", x"81", x"08", x"27", x"b2", x"8d", x"3d", x"25", x"f2",  -- 01b0
    x"20", x"ac", x"53", x"35", x"82", x"8d", x"34", x"25", x"31", x"86", x"01", x"97", x"4b", x"17", x"03", x"72",  -- 01c0
    x"c6", x"44", x"a6", x"01", x"85", x"08", x"27", x"02", x"c6", x"43", x"d7", x"4e", x"8d", x"1d", x"0f", x"52",  -- 01d0
    x"0f", x"54", x"6f", x"84", x"0f", x"58", x"dc", x"e9", x"93", x"ed", x"2c", x"05", x"43", x"53", x"c3", x"00",  -- 01e0
    x"01", x"4d", x"26", x"05", x"5d", x"2a", x"02", x"03", x"58", x"4f", x"39", x"c6", x"64", x"a6", x"01", x"85",  -- 01f0
    x"08", x"26", x"13", x"96", x"57", x"8a", x"10", x"a7", x"02", x"84", x"ef", x"a7", x"02", x"8d", x"1d", x"5a",  -- 0200
    x"10", x"27", x"03", x"28", x"20", x"e7", x"8d", x"0e", x"17", x"03", x"55", x"6f", x"a4", x"6f", x"06", x"39",  -- 0210
    x"10", x"8e", x"00", x"6c", x"20", x"0a", x"10", x"8e", x"07", x"50", x"20", x"04", x"10", x"8e", x"02", x"ec",  -- 0220
    x"31", x"3f", x"26", x"fc", x"39", x"86", x"ff", x"97", x"58", x"4f", x"39", x"0f", x"58", x"39", x"17", x"02",  -- 0230
    x"d9", x"10", x"25", x"00", x"9e", x"a6", x"01", x"85", x"04", x"27", x"05", x"86", x"01", x"16", x"02", x"ee",  -- 0240
    x"96", x"58", x"10", x"26", x"00", x"92", x"17", x"01", x"bd", x"c6", x"19", x"34", x"01", x"17", x"01", x"4c",  -- 0250
    x"10", x"8e", x"75", x"00", x"31", x"3f", x"10", x"27", x"02", x"9e", x"e6", x"84", x"c5", x"02", x"27", x"f4",  -- 0260
    x"a7", x"03", x"e6", x"84", x"2a", x"fc", x"a7", x"03", x"e6", x"84", x"2a", x"fc", x"c6", x"fb", x"e7", x"03",  -- 0270
    x"4f", x"e6", x"84", x"2a", x"fc", x"e6", x"c0", x"e7", x"03", x"4a", x"26", x"f5", x"e6", x"84", x"c5", x"08",  -- 0280
    x"27", x"fa", x"17", x"ff", x"8b", x"0d", x"48", x"2a", x"4a", x"17", x"02", x"86", x"c6", x"1b", x"17", x"01",  -- 0290
    x"0b", x"86", x"04", x"10", x"8e", x"75", x"00", x"31", x"3f", x"10", x"27", x"00", x"fa", x"e6", x"84", x"c5",  -- 02a0
    x"02", x"27", x"f4", x"e6", x"03", x"4a", x"10", x"27", x"02", x"56", x"e6", x"84", x"2a", x"fc", x"e6", x"03",  -- 02b0
    x"c1", x"fb", x"26", x"f1", x"4f", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e1", x"c0", x"26", x"03", x"4a",  -- 02c0
    x"26", x"f3", x"e6", x"84", x"c5", x"08", x"27", x"fa", x"4d", x"10", x"26", x"00", x"ca", x"c5", x"04", x"10",  -- 02d0
    x"26", x"00", x"c4", x"35", x"01", x"6f", x"84", x"39", x"17", x"01", x"3c", x"17", x"01", x"40", x"34", x"01",  -- 02e0
    x"34", x"06", x"17", x"00", x"ca", x"24", x"05", x"35", x"06", x"16", x"02", x"0c", x"c6", x"ff", x"e7", x"04",  -- 02f0
    x"86", x"06", x"c6", x"24", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"6f", x"03", x"4a", x"26", x"f7", x"e6",  -- 0300
    x"84", x"2a", x"fc", x"cc", x"fb", x"c7", x"ed", x"03", x"c6", x"ff", x"a6", x"84", x"2a", x"fc", x"a6", x"c0",  -- 0310
    x"ed", x"03", x"86", x"7f", x"e6", x"84", x"2a", x"fc", x"e6", x"c0", x"e7", x"03", x"4a", x"26", x"f5", x"e6",  -- 0320
    x"84", x"2a", x"fc", x"35", x"04", x"e7", x"03", x"43", x"26", x"f5", x"e6", x"84", x"2a", x"fc", x"6f", x"03",  -- 0330
    x"e6", x"84", x"2a", x"fc", x"c6", x"20", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"43", x"26",  -- 0340
    x"f7", x"32", x"7e", x"17", x"fe", x"ca", x"0d", x"48", x"2a", x"44", x"17", x"01", x"c5", x"17", x"00", x"5f",  -- 0350
    x"25", x"43", x"c6", x"fb", x"e7", x"03", x"86", x"80", x"c6", x"38", x"e7", x"84", x"10", x"8e", x"01", x"00",  -- 0360
    x"31", x"3f", x"27", x"31", x"e6", x"84", x"c5", x"01", x"27", x"f6", x"e6", x"03", x"c6", x"28", x"e7", x"84",  -- 0370
    x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e1", x"c0", x"26", x"1b", x"4a", x"26", x"f3", x"a6", x"84", x"2a",  -- 0380
    x"fc", x"a6", x"03", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"10", x"a3", x"e4", x"26", x"07", x"35", x"06",  -- 0390
    x"35", x"01", x"6f", x"84", x"39", x"35", x"06", x"86", x"20", x"16", x"01", x"66", x"96", x"4c", x"a7", x"05",  -- 03a0
    x"86", x"0a", x"a7", x"04", x"86", x"a1", x"a7", x"03", x"1a", x"50", x"de", x"4f", x"e7", x"84", x"39", x"86",  -- 03b0
    x"c7", x"a7", x"04", x"86", x"fe", x"a7", x"03", x"86", x"30", x"de", x"4f", x"1a", x"50", x"c6", x"38", x"e7",  -- 03c0
    x"84", x"10", x"8e", x"17", x"00", x"31", x"3f", x"27", x"3a", x"e6", x"84", x"c5", x"01", x"27", x"f6", x"e6",  -- 03d0
    x"03", x"c6", x"28", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"d1", x"4b", x"26", x"21", x"e6",  -- 03e0
    x"84", x"2a", x"fc", x"e6", x"03", x"26", x"19", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"d1", x"4c", x"26",  -- 03f0
    x"0f", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"26", x"07", x"17", x"fe", x"14", x"4f", x"a6", x"84", x"39",  -- 0400
    x"4a", x"26", x"ba", x"53", x"20", x"f7", x"c1", x"39", x"2a", x"05", x"cc", x"9f", x"20", x"20", x"03", x"cc",  -- 0410
    x"1f", x"22", x"a7", x"07", x"e7", x"01", x"39", x"86", x"bf", x"a7", x"07", x"6f", x"01", x"39", x"de", x"4f",  -- 0420
    x"10", x"8e", x"00", x"80", x"cc", x"bf", x"84", x"34", x"06", x"a6", x"e4", x"a8", x"c0", x"34", x"02", x"44",  -- 0430
    x"44", x"44", x"44", x"a8", x"e4", x"a7", x"e4", x"1f", x"89", x"54", x"54", x"54", x"48", x"48", x"48", x"48",  -- 0440
    x"e8", x"62", x"e7", x"62", x"1f", x"89", x"a8", x"62", x"a7", x"61", x"58", x"e8", x"e4", x"e7", x"62", x"32",  -- 0450
    x"61", x"31", x"3f", x"26", x"d4", x"35", x"06", x"39", x"17", x"00", x"af", x"10", x"25", x"00", x"98", x"34",  -- 0460
    x"01", x"96", x"58", x"26", x"43", x"17", x"ff", x"9e", x"c6", x"1b", x"17", x"ff", x"2f", x"86", x"04", x"10",  -- 0470
    x"8e", x"75", x"00", x"31", x"3f", x"10", x"27", x"00", x"7f", x"e6", x"84", x"c5", x"02", x"27", x"f4", x"e6",  -- 0480
    x"03", x"4a", x"10", x"27", x"00", x"7a", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"c1", x"fb", x"26", x"f1",  -- 0490
    x"4f", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e7", x"c0", x"4a", x"26", x"f5", x"e6", x"84", x"c5", x"08",  -- 04a0
    x"27", x"fa", x"c5", x"04", x"26", x"56", x"20", x"4b", x"17", x"ff", x"6c", x"17", x"ff", x"01", x"25", x"48",  -- 04b0
    x"31", x"23", x"17", x"fd", x"6b", x"c6", x"fb", x"e7", x"03", x"86", x"80", x"c6", x"38", x"e7", x"84", x"10",  -- 04c0
    x"8e", x"01", x"00", x"31", x"3f", x"27", x"39", x"e6", x"84", x"c5", x"01", x"27", x"f6", x"e6", x"03", x"c6",  -- 04d0
    x"28", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e7", x"c0", x"4a", x"26", x"f5", x"e6", x"84",  -- 04e0
    x"2a", x"fc", x"e6", x"03", x"34", x"04", x"43", x"26", x"f5", x"17", x"ff", x"32", x"1e", x"89", x"10", x"a3",  -- 04f0
    x"e1", x"26", x"09", x"35", x"01", x"6f", x"84", x"39", x"86", x"04", x"20", x"06", x"86", x"08", x"20", x"02",  -- 0500
    x"86", x"02", x"97", x"4e", x"6f", x"84", x"35", x"01", x"43", x"39", x"8d", x"06", x"25", x"03", x"8d", x"22",  -- 0510
    x"4f", x"39", x"10", x"8e", x"80", x"00", x"d6", x"57", x"ca", x"04", x"e7", x"02", x"c4", x"fb", x"e7", x"02",  -- 0520
    x"31", x"3f", x"27", x"08", x"e6", x"01", x"c4", x"02", x"27", x"ec", x"4f", x"39", x"86", x"10", x"34", x"01",  -- 0530
    x"20", x"d0", x"17", x"fc", x"e7", x"8d", x"29", x"e6", x"a4", x"96", x"57", x"d0", x"4b", x"27", x"18", x"2a",  -- 0540
    x"03", x"8a", x"20", x"50", x"a7", x"02", x"8a", x"14", x"a7", x"02", x"84", x"eb", x"a7", x"02", x"17", x"fc",  -- 0550
    x"cb", x"5a", x"26", x"f2", x"17", x"fc", x"bf", x"8d", x"07", x"d6", x"4b", x"e7", x"06", x"e7", x"a4", x"39",  -- 0560
    x"31", x"8d", x"7a", x"de", x"96", x"49", x"84", x"02", x"31", x"a6", x"39", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0570
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0580
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0590
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 05a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 05b0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 05c0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 05d0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 05e0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 05f0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0600
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0610
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0620
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0630
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0640
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0650
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0660
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0670
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0680
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0690
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 06a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 06b0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 06c0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 06d0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 06e0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 06f0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0700
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0710
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0720
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0730
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0740
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0750
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0760
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0770
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0780
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0790
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 07a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 07b0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 07c0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 07d0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 07e0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 07f0

    x"4d", x"54", x"44", x"3a", x"16", x"00", x"24", x"16", x"00", x"2c", x"16", x"00", x"a2", x"16", x"00", x"3c",  -- 0800
    x"16", x"00", x"43", x"16", x"00", x"4a", x"16", x"00", x"51", x"16", x"00", x"58", x"16", x"00", x"5f", x"16",  -- 0810
    x"00", x"66", x"16", x"00", x"6d", x"16", x"ff", x"fd", x"16", x"ff", x"fd", x"34", x"46", x"33", x"8c", x"d4",  -- 0820
    x"86", x"00", x"8d", x"68", x"35", x"c6", x"34", x"46", x"33", x"8c", x"cc", x"86", x"00", x"8d", x"5d", x"35",  -- 0830
    x"c6", x"34", x"46", x"33", x"8c", x"c4", x"86", x"01", x"8d", x"52", x"35", x"c6", x"33", x"8c", x"be", x"86",  -- 0840
    x"02", x"8d", x"49", x"1f", x"30", x"39", x"33", x"8c", x"b7", x"86", x"02", x"8d", x"3f", x"1f", x"30", x"39",  -- 0850
    x"33", x"8c", x"b0", x"86", x"02", x"8d", x"35", x"1f", x"30", x"39", x"33", x"8c", x"a9", x"86", x"02", x"8d",  -- 0860
    x"2b", x"1f", x"30", x"39", x"33", x"8c", x"a2", x"86", x"02", x"8d", x"21", x"1f", x"30", x"39", x"33", x"8c",  -- 0870
    x"9b", x"86", x"02", x"8d", x"17", x"1f", x"30", x"39", x"33", x"8c", x"94", x"86", x"02", x"8d", x"0d", x"1f",  -- 0880
    x"30", x"39", x"33", x"8c", x"8d", x"86", x"02", x"8d", x"03", x"1f", x"30", x"39", x"c6", x"00", x"34", x"04",  -- 0890
    x"a7", x"8d", x"07", x"34", x"ad", x"c4", x"1f", x"03", x"35", x"04", x"e7", x"8d", x"07", x"2a", x"39", x"34",  -- 08a0
    x"7f", x"8d", x"50", x"8d", x"61", x"17", x"00", x"a3", x"25", x"42", x"17", x"00", x"c7", x"25", x"3b", x"17",  -- 08b0
    x"00", x"b6", x"25", x"36", x"34", x"01", x"1a", x"50", x"17", x"01", x"02", x"86", x"02", x"34", x"02", x"17",  -- 08c0
    x"01", x"2d", x"17", x"01", x"57", x"24", x"0b", x"6a", x"e4", x"26", x"f4", x"35", x"02", x"35", x"01", x"43",  -- 08d0
    x"20", x"18", x"35", x"02", x"35", x"01", x"96", x"4b", x"81", x"4f", x"27", x"05", x"17", x"03", x"44", x"20",  -- 08e0
    x"d3", x"17", x"03", x"56", x"25", x"04", x"86", x"50", x"97", x"4b", x"8d", x"77", x"35", x"02", x"1e", x"8a",  -- 08f0
    x"44", x"35", x"fe", x"1f", x"50", x"84", x"70", x"1f", x"8b", x"96", x"48", x"84", x"80", x"97", x"48", x"30",  -- 0900
    x"8d", x"06", x"bd", x"0f", x"4e", x"39", x"34", x"10", x"ce", x"e9", x"41", x"8e", x"00", x"03", x"c6", x"04",  -- 0910
    x"a6", x"84", x"a1", x"c4", x"27", x"09", x"5c", x"33", x"c5", x"a6", x"c4", x"26", x"ee", x"20", x"10", x"30",  -- 0920
    x"1f", x"26", x"03", x"8e", x"00", x"1a", x"33", x"41", x"5a", x"26", x"e5", x"a6", x"c4", x"97", x"58", x"35",  -- 0930
    x"90", x"52", x"45", x"47", x"6e", x"ff", x"43", x"49", x"50", x"4a", x"ff", x"4c", x"45", x"4d", x"74", x"ff",  -- 0940
    x"4c", x"4f", x"50", x"b5", x"00", x"53", x"45", x"47", x"b6", x"00", x"00", x"33", x"8d", x"00", x"10", x"d6",  -- 0950
    x"49", x"c1", x"04", x"10", x"24", x"00", x"5f", x"a6", x"c5", x"a7", x"02", x"97", x"57", x"4f", x"39", x"41",  -- 0960
    x"01", x"42", x"02", x"86", x"40", x"a7", x"02", x"39", x"a6", x"01", x"85", x"04", x"26", x"02", x"4f", x"39",  -- 0970
    x"86", x"01", x"20", x"44", x"8d", x"26", x"25", x"23", x"c6", x"64", x"a6", x"01", x"85", x"08", x"26", x"14",  -- 0980
    x"96", x"57", x"8a", x"14", x"a7", x"02", x"84", x"eb", x"a7", x"02", x"17", x"03", x"02", x"5a", x"10", x"27",  -- 0990
    x"00", x"24", x"20", x"e6", x"17", x"02", x"f2", x"0f", x"4b", x"6f", x"06", x"39", x"10", x"8e", x"80", x"00",  -- 09a0
    x"d6", x"57", x"ca", x"04", x"e7", x"02", x"c4", x"fb", x"e7", x"02", x"31", x"3f", x"27", x"08", x"e6", x"01",  -- 09b0
    x"c4", x"02", x"27", x"ec", x"4f", x"39", x"86", x"10", x"34", x"01", x"16", x"04", x"16", x"30", x"8d", x"7f",  -- 09c0
    x"02", x"c6", x"10", x"6f", x"85", x"5a", x"26", x"fb", x"30", x"88", x"10", x"34", x"10", x"30", x"8d", x"7e",  -- 09d0
    x"f2", x"86", x"01", x"d6", x"4d", x"a7", x"84", x"30", x"85", x"4c", x"81", x"10", x"22", x"0e", x"ac", x"e4",  -- 09e0
    x"25", x"02", x"30", x"10", x"6d", x"84", x"27", x"ed", x"30", x"01", x"20", x"f2", x"32", x"62", x"39", x"30",  -- 09f0
    x"8d", x"7e", x"d0", x"de", x"4f", x"e6", x"80", x"27", x"1d", x"96", x"4b", x"a7", x"c4", x"6f", x"41", x"e7",  -- 0a00
    x"42", x"10", x"8e", x"00", x"04", x"96", x"58", x"4c", x"a7", x"43", x"27", x"0b", x"cc", x"b2", x"30", x"17",  -- 0a10
    x"03", x"90", x"ed", x"c1", x"20", x"df", x"39", x"cc", x"ef", x"21", x"20", x"f3", x"86", x"10", x"34", x"02",  -- 0a20
    x"de", x"4f", x"30", x"8d", x"05", x"9a", x"96", x"58", x"10", x"26", x"00", x"f6", x"17", x"01", x"d5", x"e6",  -- 0a30
    x"01", x"c5", x"40", x"27", x"fa", x"e6", x"03", x"e6", x"84", x"2a", x"fa", x"e6", x"84", x"2a", x"fc", x"cc",  -- 0a40
    x"4e", x"ff", x"ed", x"03", x"c6", x"04", x"e7", x"84", x"86", x"1e", x"e6", x"84", x"2a", x"fc", x"c6", x"4e",  -- 0a50
    x"e7", x"03", x"4a", x"26", x"f5", x"86", x"0c", x"e6", x"84", x"2a", x"fc", x"6f", x"03", x"4a", x"26", x"f7",  -- 0a60
    x"e6", x"84", x"2a", x"fc", x"cc", x"a1", x"0a", x"ed", x"03", x"e6", x"84", x"2a", x"fc", x"a7", x"03", x"e6",  -- 0a70
    x"84", x"2a", x"fc", x"a7", x"03", x"e6", x"84", x"2a", x"fc", x"cc", x"fe", x"ff", x"ed", x"03", x"86", x"06",  -- 0a80
    x"e6", x"84", x"2a", x"fc", x"e6", x"c0", x"e7", x"03", x"4a", x"26", x"f5", x"86", x"16", x"e6", x"84", x"2a",  -- 0a90
    x"fc", x"c6", x"4e", x"e7", x"03", x"4a", x"26", x"f5", x"86", x"0c", x"e6", x"84", x"2a", x"fc", x"6f", x"03",  -- 0aa0
    x"4a", x"26", x"f7", x"e6", x"84", x"2a", x"fc", x"cc", x"a1", x"0a", x"ed", x"03", x"e6", x"84", x"2a", x"fc",  -- 0ab0
    x"a7", x"03", x"e6", x"84", x"2a", x"fc", x"a7", x"03", x"e6", x"84", x"2a", x"fc", x"cc", x"fb", x"ff", x"ed",  -- 0ac0
    x"03", x"4f", x"e6", x"84", x"2a", x"fc", x"c6", x"e5", x"e7", x"03", x"4a", x"26", x"f5", x"e6", x"84", x"2a",  -- 0ad0
    x"fc", x"c6", x"78", x"e7", x"03", x"e6", x"84", x"2a", x"fc", x"c6", x"27", x"e7", x"03", x"86", x"2c", x"e6",  -- 0ae0
    x"84", x"2a", x"fc", x"c6", x"4e", x"e7", x"03", x"4a", x"26", x"f5", x"6a", x"e4", x"10", x"26", x"ff", x"65",  -- 0af0
    x"a6", x"01", x"85", x"40", x"26", x"08", x"a6", x"84", x"2a", x"fc", x"e7", x"03", x"20", x"f2", x"35", x"02",  -- 0b00
    x"6f", x"84", x"0d", x"48", x"2a", x"1b", x"86", x"e5", x"17", x"01", x"0c", x"33", x"8d", x"7d", x"b4", x"17",  -- 0b10
    x"fe", x"8a", x"a6", x"c0", x"27", x"0b", x"97", x"4c", x"34", x"40", x"17", x"01", x"7b", x"35", x"40", x"24",  -- 0b20
    x"f1", x"39", x"17", x"02", x"6d", x"e6", x"01", x"c5", x"40", x"27", x"fa", x"e6", x"03", x"e6", x"84", x"2a",  -- 0b30
    x"fa", x"e6", x"84", x"2a", x"fc", x"cc", x"ff", x"ff", x"ed", x"03", x"c6", x"24", x"e7", x"84", x"86", x"10",  -- 0b40
    x"e6", x"84", x"2a", x"fc", x"c6", x"ff", x"e7", x"03", x"4a", x"26", x"f5", x"86", x"06", x"e6", x"84", x"2a",  -- 0b50
    x"fc", x"6f", x"03", x"4a", x"26", x"f7", x"e6", x"84", x"2a", x"fc", x"cc", x"fe", x"c7", x"ed", x"03", x"e6",  -- 0b60
    x"84", x"2a", x"fc", x"c6", x"ff", x"a6", x"c0", x"ed", x"03", x"86", x"05", x"e6", x"84", x"2a", x"fc", x"e6",  -- 0b70
    x"c0", x"e7", x"03", x"4a", x"26", x"f5", x"86", x"0c", x"e6", x"84", x"2a", x"fc", x"c6", x"ff", x"e7", x"03",  -- 0b80
    x"4a", x"26", x"f5", x"86", x"06", x"e6", x"84", x"2a", x"fc", x"6f", x"03", x"4a", x"26", x"f7", x"e6", x"84",  -- 0b90
    x"2a", x"fc", x"cc", x"fb", x"c7", x"ed", x"03", x"e6", x"84", x"2a", x"fc", x"cc", x"e5", x"ff", x"ed", x"03",  -- 0ba0
    x"86", x"7f", x"e6", x"84", x"2a", x"fc", x"c6", x"e5", x"e7", x"03", x"4a", x"26", x"f5", x"e6", x"84", x"2a",  -- 0bb0
    x"fc", x"c6", x"5d", x"e7", x"03", x"e6", x"84", x"2a", x"fc", x"c6", x"30", x"e7", x"03", x"86", x"16", x"e6",  -- 0bc0
    x"84", x"2a", x"fc", x"c6", x"ff", x"e7", x"03", x"4a", x"26", x"f5", x"6a", x"e4", x"10", x"26", x"ff", x"7b",  -- 0bd0
    x"a6", x"01", x"85", x"40", x"26", x"08", x"a6", x"84", x"2a", x"fc", x"e7", x"03", x"20", x"f2", x"35", x"02",  -- 0be0
    x"6f", x"84", x"0d", x"48", x"2a", x"1d", x"86", x"e5", x"8d", x"2d", x"33", x"8d", x"7c", x"d5", x"17", x"fd",  -- 0bf0
    x"ab", x"a6", x"c0", x"27", x"0e", x"97", x"4c", x"34", x"40", x"cc", x"5d", x"30", x"17", x"00", x"e7", x"35",  -- 0c00
    x"40", x"24", x"ee", x"39", x"d6", x"4b", x"c1", x"39", x"2a", x"05", x"cc", x"9f", x"20", x"20", x"03", x"cc",  -- 0c10
    x"1f", x"22", x"a7", x"07", x"e7", x"01", x"39", x"de", x"4f", x"d6", x"58", x"c4", x"80", x"a7", x"c0", x"5a",  -- 0c20
    x"26", x"fb", x"39", x"8d", x"6a", x"96", x"57", x"8a", x"20", x"a7", x"02", x"8a", x"14", x"a7", x"02", x"84",  -- 0c30
    x"eb", x"a7", x"02", x"0c", x"4b", x"96", x"4b", x"a7", x"06", x"39", x"c6", x"3b", x"96", x"57", x"84", x"df",  -- 0c40
    x"a7", x"02", x"8a", x"10", x"a7", x"02", x"84", x"ef", x"a7", x"02", x"8d", x"43", x"5a", x"26", x"f3", x"17",  -- 0c50
    x"01", x"95", x"86", x"14", x"a7", x"a4", x"a7", x"06", x"97", x"4b", x"86", x"ff", x"8d", x"b9", x"86", x"10",  -- 0c60
    x"97", x"4c", x"17", x"fd", x"37", x"17", x"01", x"8a", x"25", x"18", x"0a", x"4c", x"26", x"f4", x"de", x"4f",  -- 0c70
    x"6f", x"c4", x"cc", x"fe", x"fe", x"ed", x"c8", x"29", x"86", x"02", x"97", x"4c", x"17", x"01", x"73", x"25",  -- 0c80
    x"01", x"4f", x"39", x"10", x"8e", x"00", x"6c", x"20", x"0a", x"10", x"8e", x"07", x"50", x"20", x"04", x"10",  -- 0c90
    x"8e", x"02", x"ec", x"31", x"3f", x"26", x"fc", x"39", x"c6", x"1b", x"34", x"01", x"17", x"00", x"91", x"86",  -- 0ca0
    x"04", x"10", x"8e", x"75", x"00", x"31", x"3f", x"10", x"27", x"00", x"80", x"e6", x"84", x"c5", x"02", x"27",  -- 0cb0
    x"f4", x"e6", x"03", x"4a", x"10", x"27", x"01", x"2b", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"c1", x"fb",  -- 0cc0
    x"26", x"f1", x"4f", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e1", x"c0", x"26", x"03", x"4a", x"26", x"f3",  -- 0cd0
    x"e6", x"84", x"c5", x"08", x"27", x"fa", x"4d", x"10", x"26", x"00", x"50", x"c5", x"04", x"10", x"26", x"00",  -- 0ce0
    x"4a", x"35", x"01", x"6f", x"84", x"39", x"34", x"01", x"34", x"06", x"8d", x"57", x"25", x"3b", x"c6", x"fb",  -- 0cf0
    x"e7", x"03", x"86", x"80", x"c6", x"38", x"e7", x"84", x"e6", x"84", x"c5", x"01", x"27", x"fa", x"e6", x"03",  -- 0d00
    x"c6", x"28", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e1", x"c0", x"26", x"1b", x"4a", x"26",  -- 0d10
    x"f3", x"a6", x"84", x"2a", x"fc", x"a6", x"03", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"10", x"a3", x"e4",  -- 0d20
    x"26", x"07", x"35", x"06", x"35", x"01", x"6f", x"84", x"39", x"35", x"06", x"86", x"20", x"16", x"00", x"a3",  -- 0d30
    x"96", x"4c", x"a7", x"05", x"86", x"0a", x"a7", x"04", x"86", x"a1", x"a7", x"03", x"1a", x"50", x"de", x"4f",  -- 0d40
    x"e7", x"84", x"39", x"86", x"c7", x"a7", x"04", x"86", x"fe", x"a7", x"03", x"86", x"30", x"de", x"4f", x"1a",  -- 0d50
    x"50", x"c6", x"38", x"e7", x"84", x"e6", x"84", x"c5", x"01", x"27", x"fa", x"e6", x"03", x"c6", x"28", x"e7",  -- 0d60
    x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"d1", x"4b", x"26", x"21", x"e6", x"84", x"2a", x"fc", x"e6",  -- 0d70
    x"03", x"26", x"19", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"d1", x"4c", x"26", x"0f", x"e6", x"84", x"2a",  -- 0d80
    x"fc", x"e6", x"03", x"26", x"07", x"17", x"fe", x"fb", x"4f", x"a6", x"84", x"39", x"4a", x"26", x"c2", x"53",  -- 0d90
    x"20", x"f7", x"86", x"bf", x"a7", x"07", x"6f", x"01", x"39", x"de", x"4f", x"10", x"8e", x"00", x"80", x"cc",  -- 0da0
    x"bf", x"84", x"34", x"06", x"a6", x"e4", x"a8", x"c0", x"34", x"02", x"44", x"44", x"44", x"44", x"a8", x"e4",  -- 0db0
    x"a7", x"e4", x"1f", x"89", x"54", x"54", x"54", x"48", x"48", x"48", x"48", x"e8", x"62", x"e7", x"62", x"1f",  -- 0dc0
    x"89", x"a8", x"62", x"a7", x"61", x"58", x"e8", x"e4", x"e7", x"62", x"32", x"61", x"31", x"3f", x"26", x"d4",  -- 0dd0
    x"35", x"06", x"39", x"97", x"4e", x"6f", x"84", x"35", x"01", x"43", x"39", x"86", x"04", x"20", x"f4", x"86",  -- 0de0
    x"08", x"20", x"f0", x"86", x"02", x"20", x"ec", x"31", x"8d", x"7a", x"57", x"96", x"49", x"84", x"02", x"31",  -- 0df0
    x"a6", x"39", x"96", x"58", x"26", x"47", x"17", x"fe", x"0b", x"c6", x"19", x"34", x"01", x"17", x"ff", x"30",  -- 0e00
    x"10", x"8e", x"75", x"00", x"31", x"3f", x"10", x"27", x"ff", x"d1", x"e6", x"84", x"c5", x"02", x"27", x"f4",  -- 0e10
    x"a7", x"03", x"e6", x"84", x"2a", x"fc", x"a7", x"03", x"e6", x"84", x"2a", x"fc", x"c6", x"fb", x"e7", x"03",  -- 0e20
    x"4f", x"e6", x"84", x"2a", x"fc", x"e6", x"c0", x"e7", x"03", x"4a", x"26", x"f5", x"e6", x"84", x"c5", x"08",  -- 0e30
    x"27", x"fa", x"35", x"01", x"6f", x"84", x"0d", x"48", x"10", x"2b", x"fe", x"5c", x"39", x"17", x"ff", x"52",  -- 0e40
    x"17", x"ff", x"56", x"34", x"01", x"34", x"06", x"17", x"fe", x"f9", x"10", x"25", x"ff", x"8d", x"c6", x"ff",  -- 0e50
    x"e7", x"04", x"86", x"06", x"c6", x"24", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"6f", x"03", x"4a", x"26",  -- 0e60
    x"f7", x"e6", x"84", x"2a", x"fc", x"cc", x"fb", x"c7", x"ed", x"03", x"c6", x"ff", x"a6", x"84", x"2a", x"fc",  -- 0e70
    x"a6", x"c0", x"ed", x"03", x"86", x"7f", x"e6", x"84", x"2a", x"fc", x"e6", x"c0", x"e7", x"03", x"4a", x"26",  -- 0e80
    x"f5", x"e6", x"84", x"2a", x"fc", x"35", x"04", x"e7", x"03", x"43", x"26", x"f5", x"e6", x"84", x"2a", x"fc",  -- 0e90
    x"6f", x"03", x"e6", x"84", x"2a", x"fc", x"c6", x"20", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03",  -- 0ea0
    x"43", x"26", x"f7", x"ec", x"7e", x"35", x"01", x"6f", x"84", x"0d", x"48", x"10", x"2b", x"fe", x"37", x"39",  -- 0eb0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0ec0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0ed0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0ee0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0ef0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f00
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f10
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f20
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f30
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f40
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f50
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f60
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f70
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f80
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0f90
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0fa0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 0fb0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 0fc0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 0fd0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 0fe0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 0ff0

    x"4d", x"54", x"44", x"3a", x"16", x"00", x"24", x"16", x"00", x"2c", x"16", x"00", x"34", x"16", x"01", x"01",  -- 1000
    x"16", x"01", x"84", x"16", x"01", x"63", x"16", x"01", x"3f", x"16", x"01", x"e3", x"16", x"02", x"39", x"16",  -- 1010
    x"02", x"7b", x"16", x"00", x"95", x"16", x"ff", x"fd", x"16", x"ff", x"fd", x"34", x"46", x"33", x"8c", x"d4",  -- 1020
    x"86", x"00", x"8d", x"68", x"35", x"c6", x"34", x"46", x"33", x"8c", x"cc", x"86", x"00", x"8d", x"5d", x"35",  -- 1030
    x"c6", x"34", x"46", x"33", x"8c", x"c4", x"86", x"01", x"8d", x"52", x"35", x"c6", x"33", x"8c", x"be", x"86",  -- 1040
    x"02", x"8d", x"49", x"1f", x"30", x"39", x"33", x"8c", x"b7", x"86", x"02", x"8d", x"3f", x"1f", x"30", x"39",  -- 1050
    x"33", x"8c", x"b0", x"86", x"02", x"8d", x"35", x"1f", x"30", x"39", x"33", x"8c", x"a9", x"86", x"02", x"8d",  -- 1060
    x"2b", x"1f", x"30", x"39", x"33", x"8c", x"a2", x"86", x"02", x"8d", x"21", x"1f", x"30", x"39", x"33", x"8c",  -- 1070
    x"9b", x"86", x"02", x"8d", x"17", x"1f", x"30", x"39", x"33", x"8c", x"94", x"86", x"02", x"8d", x"0d", x"1f",  -- 1080
    x"30", x"39", x"33", x"8c", x"8d", x"86", x"02", x"8d", x"03", x"1f", x"30", x"39", x"c6", x"02", x"34", x"04",  -- 1090
    x"a7", x"8d", x"07", x"34", x"ad", x"c4", x"1f", x"03", x"35", x"04", x"e7", x"8d", x"07", x"2a", x"39", x"53",  -- 10a0
    x"43", x"52", x"41", x"54", x"43", x"48", x"20", x"44", x"4f", x"53", x"d6", x"f0", x"c1", x"02", x"27", x"25",  -- 10b0
    x"0a", x"f0", x"17", x"00", x"d2", x"25", x"31", x"5d", x"27", x"05", x"17", x"00", x"ac", x"25", x"29", x"0c",  -- 10c0
    x"f0", x"17", x"00", x"c3", x"25", x"22", x"c6", x"0a", x"9e", x"e7", x"a6", x"85", x"a7", x"a5", x"5a", x"2c",  -- 10d0
    x"f9", x"8d", x"75", x"25", x"13", x"86", x"02", x"97", x"4c", x"c6", x"14", x"4f", x"dd", x"4a", x"8d", x"4c",  -- 10e0
    x"9f", x"4f", x"8d", x"64", x"25", x"02", x"0f", x"f0", x"39", x"34", x"07", x"9e", x"ed", x"30", x"89", x"00",  -- 10f0
    x"80", x"a6", x"1f", x"e6", x"88", x"7f", x"a7", x"88", x"7f", x"e7", x"82", x"9c", x"ed", x"26", x"f2", x"35",  -- 1100
    x"87", x"dc", x"ed", x"0d", x"55", x"26", x"02", x"dd", x"55", x"93", x"55", x"c1", x"80", x"27", x"04", x"9e",  -- 1110
    x"ed", x"20", x"02", x"9e", x"55", x"9f", x"ed", x"9f", x"4f", x"86", x"02", x"8d", x"31", x"25", x"c9", x"0d",  -- 1120
    x"58", x"26", x"08", x"8d", x"c4", x"30", x"89", x"00", x"80", x"9f", x"ed", x"39", x"9e", x"ed", x"0d", x"58",  -- 1130
    x"26", x"f9", x"30", x"88", x"80", x"8d", x"f2", x"20", x"b0", x"86", x"03", x"9e", x"e9", x"9f", x"4f", x"8d",  -- 1140
    x"0d", x"25", x"e9", x"39", x"8d", x"0f", x"20", x"f9", x"86", x"08", x"8d", x"0b", x"20", x"f3", x"97", x"4c",  -- 1150
    x"c6", x"14", x"4f", x"dd", x"4a", x"86", x"02", x"97", x"48", x"10", x"9e", x"e9", x"17", x"fe", x"95", x"86",  -- 1160
    x"03", x"39", x"8d", x"c8", x"97", x"e5", x"43", x"43", x"39", x"a6", x"2d", x"97", x"f6", x"6f", x"a4", x"8d",  -- 1170
    x"d7", x"25", x"f1", x"10", x"9e", x"ed", x"d6", x"f6", x"5c", x"a6", x"a5", x"6f", x"a5", x"6a", x"a5", x"1f",  -- 1180
    x"89", x"81", x"c0", x"25", x"f3", x"4f", x"39", x"8d", x"b0", x"25", x"d9", x"25", x"d5", x"8d", x"34", x"10",  -- 1190
    x"9e", x"e9", x"de", x"e7", x"d6", x"f0", x"c1", x"03", x"26", x"03", x"ce", x"f0", x"af", x"5f", x"c1", x"0b",  -- 11a0
    x"24", x"2e", x"a6", x"a5", x"81", x"ff", x"27", x"25", x"5c", x"a1", x"c0", x"27", x"f1", x"31", x"a8", x"20",  -- 11b0
    x"30", x"1f", x"26", x"de", x"0c", x"4c", x"96", x"4c", x"81", x"10", x"22", x"11", x"17", x"fe", x"35", x"86",  -- 11c0
    x"03", x"20", x"c8", x"8e", x"00", x"08", x"0d", x"58", x"27", x"02", x"30", x"1c", x"39", x"5f", x"20", x"1b",  -- 11d0
    x"e6", x"2b", x"d1", x"eb", x"26", x"d7", x"e6", x"2c", x"d1", x"ec", x"26", x"d1", x"d6", x"4c", x"a6", x"2d",  -- 11e0
    x"97", x"f6", x"0f", x"f5", x"ae", x"2e", x"9f", x"f7", x"10", x"9f", x"fa", x"d7", x"f9", x"20", x"96", x"10",  -- 11f0
    x"9e", x"ed", x"8d", x"6e", x"25", x"95", x"d7", x"f6", x"17", x"ff", x"3e", x"25", x"8c", x"10", x"9e", x"e9",  -- 1200
    x"8d", x"c1", x"e6", x"a4", x"27", x"21", x"86", x"05", x"c1", x"ff", x"27", x"1b", x"31", x"a8", x"20", x"30",  -- 1210
    x"1f", x"26", x"ef", x"0c", x"4c", x"96", x"4c", x"81", x"10", x"22", x"07", x"17", x"fd", x"d6", x"86", x"03",  -- 1220
    x"20", x"d9", x"86", x"05", x"7e", x"f1", x"72", x"9e", x"e7", x"d6", x"f0", x"c1", x"03", x"26", x"03", x"8e",  -- 1230
    x"f0", x"af", x"c6", x"0a", x"a6", x"85", x"a7", x"a5", x"5a", x"2c", x"f9", x"96", x"eb", x"a7", x"2b", x"96",  -- 1240
    x"ec", x"d6", x"f6", x"ed", x"2c", x"16", x"ff", x"00", x"d6", x"f6", x"c1", x"50", x"22", x"0e", x"5d", x"27",  -- 1250
    x"11", x"a6", x"a5", x"81", x"ff", x"27", x"2f", x"5a", x"c1", x"50", x"23", x"f2", x"cb", x"02", x"c1", x"a1",  -- 1260
    x"20", x"ed", x"c6", x"50", x"86", x"05", x"c1", x"a0", x"10", x"22", x"fe", x"f8", x"a6", x"a5", x"81", x"ff",  -- 1270
    x"27", x"14", x"34", x"04", x"c0", x"50", x"50", x"cb", x"50", x"a6", x"a5", x"81", x"ff", x"27", x"05", x"35",  -- 1280
    x"04", x"5c", x"20", x"e0", x"32", x"61", x"6f", x"a5", x"5a", x"d7", x"f9", x"4f", x"39", x"d6", x"f6", x"4f",  -- 1290
    x"54", x"dd", x"fb", x"4c", x"97", x"f5", x"24", x"02", x"86", x"09", x"97", x"fa", x"39", x"ff", x"ff", x"ff",  -- 12a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 12b0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 12c0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 12d0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 12e0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 12f0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1300
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1310
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1320
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1330
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1340
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1350
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1360
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1370
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1380
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1390
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 13a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 13b0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 13c0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 13d0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 13e0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 13f0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1400
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1410
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1420
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1430
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1440
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1450
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1460
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1470
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1480
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1490
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 14a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 14b0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 14c0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 14d0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 14e0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 14f0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1500
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1510
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1520
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1530
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1540
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1550
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1560
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1570
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1580
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1590
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 15a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 15b0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 15c0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 15d0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 15e0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 15f0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1600
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1610
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1620
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1630
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1640
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1650
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1660
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1670
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1680
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1690
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 16a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 16b0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 16c0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 16d0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 16e0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 16f0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1700
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1710
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1720
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1730
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1740
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1750
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1760
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1770
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1780
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1790
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 17a0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 17b0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 17c0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 17d0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 17e0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 17f0

    x"4d", x"4b", x"43", x"30", x"16", x"00", x"f3", x"16", x"00", x"a5", x"16", x"03", x"a7", x"16", x"05", x"5a",  -- 1800
    x"16", x"05", x"84", x"16", x"06", x"7e", x"16", x"05", x"71", x"16", x"05", x"da", x"16", x"06", x"31", x"16",  -- 1810
    x"06", x"91", x"16", x"05", x"08", x"16", x"00", x"ca", x"16", x"00", x"d4", x"34", x"46", x"33", x"8c", x"d4",  -- 1820
    x"86", x"00", x"8d", x"68", x"35", x"c6", x"34", x"46", x"33", x"8c", x"cc", x"86", x"00", x"8d", x"5d", x"35",  -- 1830
    x"c6", x"34", x"46", x"33", x"8c", x"c4", x"86", x"01", x"8d", x"52", x"35", x"c6", x"33", x"8c", x"be", x"86",  -- 1840
    x"02", x"8d", x"49", x"1f", x"30", x"39", x"33", x"8c", x"b7", x"86", x"02", x"8d", x"3f", x"1f", x"30", x"39",  -- 1850
    x"33", x"8c", x"b0", x"86", x"02", x"8d", x"35", x"1f", x"30", x"39", x"33", x"8c", x"a9", x"86", x"02", x"8d",  -- 1860
    x"2b", x"1f", x"30", x"39", x"33", x"8c", x"a2", x"86", x"02", x"8d", x"21", x"1f", x"30", x"39", x"33", x"8c",  -- 1870
    x"9b", x"86", x"02", x"8d", x"17", x"1f", x"30", x"39", x"33", x"8c", x"94", x"86", x"02", x"8d", x"0d", x"1f",  -- 1880
    x"30", x"39", x"33", x"8c", x"8d", x"86", x"02", x"8d", x"03", x"1f", x"30", x"39", x"c6", x"00", x"34", x"04",  -- 1890
    x"a7", x"8d", x"07", x"34", x"6e", x"c4", x"1f", x"03", x"35", x"04", x"e7", x"8d", x"07", x"2a", x"39", x"17",  -- 18a0
    x"00", x"66", x"0f", x"49", x"17", x"00", x"7a", x"17", x"00", x"ae", x"cc", x"00", x"44", x"dd", x"4c", x"33",  -- 18b0
    x"8d", x"81", x"3d", x"df", x"4f", x"17", x"01", x"dc", x"de", x"4f", x"25", x"20", x"17", x"00", x"7f", x"31",  -- 18c0
    x"8d", x"81", x"ac", x"34", x"20", x"86", x"55", x"6a", x"c4", x"63", x"c4", x"ab", x"c0", x"11", x"a3", x"e4",  -- 18d0
    x"26", x"f5", x"35", x"20", x"a1", x"c4", x"26", x"04", x"6e", x"8d", x"81", x"14", x"0f", x"80", x"6e", x"9f",  -- 18e0
    x"00", x"1e", x"34", x"7f", x"8d", x"22", x"86", x"ff", x"20", x"05", x"34", x"7f", x"8d", x"1a", x"4f", x"97",  -- 18f0
    x"4a", x"dc", x"4b", x"34", x"06", x"8d", x"2a", x"25", x"04", x"8d", x"4c", x"8d", x"41", x"35", x"06", x"dd",  -- 1900
    x"4b", x"35", x"02", x"1e", x"8a", x"44", x"35", x"fe", x"1f", x"50", x"84", x"70", x"1f", x"8b", x"30", x"8d",  -- 1910
    x"06", x"ae", x"0f", x"4e", x"6f", x"84", x"86", x"ce", x"a7", x"07", x"86", x"ff", x"a7", x"04", x"6f", x"01",  -- 1920
    x"39", x"d6", x"49", x"c5", x"fd", x"26", x"12", x"33", x"8d", x"00", x"18", x"a6", x"c5", x"a7", x"02", x"97",  -- 1930
    x"57", x"e6", x"01", x"c5", x"40", x"26", x"02", x"4f", x"39", x"86", x"10", x"16", x"01", x"bd", x"86", x"00",  -- 1940
    x"a7", x"02", x"39", x"01", x"00", x"02", x"00", x"96", x"48", x"85", x"01", x"26", x"0b", x"85", x"08", x"26",  -- 1950
    x"12", x"85", x"02", x"10", x"26", x"01", x"35", x"39", x"86", x"43", x"97", x"4e", x"86", x"ff", x"97", x"58",  -- 1960
    x"6f", x"84", x"39", x"96", x"4a", x"26", x"05", x"17", x"01", x"a3", x"25", x"5a", x"17", x"00", x"5c", x"25",  -- 1970
    x"55", x"17", x"00", x"e3", x"25", x"50", x"34", x"01", x"17", x"00", x"5d", x"25", x"4a", x"c6", x"ff", x"e7",  -- 1980
    x"04", x"86", x"06", x"c6", x"04", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"c6", x"16", x"e7", x"03", x"4a",  -- 1990
    x"26", x"f5", x"e6", x"84", x"2a", x"fc", x"c6", x"5a", x"e7", x"03", x"d7", x"4a", x"86", x"80", x"e6", x"84",  -- 19a0
    x"2a", x"fc", x"e6", x"c0", x"e7", x"03", x"db", x"4a", x"d7", x"4a", x"4a", x"26", x"f1", x"e6", x"84", x"2a",  -- 19b0
    x"fc", x"d6", x"4a", x"e7", x"03", x"e6", x"84", x"2a", x"fc", x"c6", x"16", x"e7", x"03", x"e6", x"84", x"2a",  -- 19c0
    x"fc", x"6f", x"84", x"35", x"01", x"5f", x"39", x"35", x"01", x"43", x"39", x"a6", x"01", x"85", x"04", x"26",  -- 19d0
    x"02", x"4f", x"39", x"86", x"01", x"16", x"01", x"23", x"de", x"4f", x"86", x"02", x"1a", x"50", x"c6", x"e0",  -- 19e0
    x"e7", x"04", x"c6", x"16", x"e7", x"03", x"c6", x"18", x"e7", x"84", x"c1", x"16", x"27", x"0e", x"e6", x"01",  -- 19f0
    x"c5", x"02", x"27", x"47", x"e6", x"84", x"c5", x"01", x"27", x"f4", x"e6", x"03", x"e6", x"01", x"c5", x"02",  -- 1a00
    x"27", x"39", x"e6", x"84", x"2a", x"f6", x"e6", x"03", x"c1", x"a5", x"26", x"de", x"d7", x"4a", x"c6", x"08",  -- 1a10
    x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"d1", x"4c", x"26", x"c6", x"db", x"4a", x"d7", x"4a",  -- 1a20
    x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"d1", x"4d", x"26", x"b8", x"db", x"4a", x"d7", x"4a", x"e6", x"84",  -- 1a30
    x"2a", x"fc", x"e6", x"03", x"d1", x"4a", x"26", x"aa", x"6f", x"84", x"39", x"4d", x"27", x"05", x"4a", x"8d",  -- 1a40
    x"16", x"20", x"ab", x"86", x"04", x"16", x"00", x"b3", x"10", x"8e", x"35", x"b6", x"20", x"04", x"10", x"8e",  -- 1a50
    x"4e", x"20", x"31", x"3f", x"26", x"fc", x"39", x"8d", x"0a", x"25", x"07", x"81", x"12", x"27", x"02", x"8d",  -- 1a60
    x"e7", x"4f", x"39", x"86", x"12", x"d6", x"57", x"ca", x"40", x"e7", x"02", x"e6", x"01", x"c5", x"02", x"26",  -- 1a70
    x"15", x"4a", x"10", x"27", x"fe", x"c3", x"10", x"8e", x"6c", x"80", x"31", x"3f", x"27", x"f3", x"e6", x"01",  -- 1a80
    x"c5", x"02", x"27", x"f6", x"8d", x"c8", x"d6", x"57", x"e7", x"02", x"5f", x"39", x"96", x"4a", x"26", x"04",  -- 1a90
    x"8d", x"7b", x"25", x"72", x"86", x"02", x"34", x"02", x"17", x"ff", x"bc", x"25", x"67", x"34", x"01", x"17",  -- 1aa0
    x"ff", x"36", x"25", x"5d", x"86", x"03", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"4a", x"26", x"f7", x"86",  -- 1ab0
    x"80", x"c6", x"18", x"e7", x"84", x"10", x"8e", x"03", x"00", x"31", x"3f", x"27", x"4a", x"e6", x"84", x"c5",  -- 1ac0
    x"01", x"27", x"f6", x"e6", x"03", x"31", x"3f", x"27", x"3e", x"e6", x"84", x"2a", x"f8", x"e6", x"03", x"c1",  -- 1ad0
    x"5a", x"26", x"f2", x"d7", x"4a", x"c6", x"08", x"e7", x"84", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e7",  -- 1ae0
    x"c0", x"db", x"4a", x"d7", x"4a", x"4a", x"26", x"f1", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"35", x"03",  -- 1af0
    x"6f", x"84", x"d1", x"4a", x"27", x"10", x"4a", x"26", x"9d", x"86", x"08", x"97", x"4e", x"6f", x"84", x"43",  -- 1b00
    x"39", x"35", x"01", x"43", x"35", x"02", x"39", x"35", x"03", x"86", x"02", x"20", x"ee", x"96", x"4c", x"27",  -- 1b10
    x"19", x"81", x"10", x"22", x"15", x"c6", x"04", x"3d", x"dd", x"4c", x"96", x"4b", x"81", x"02", x"23", x"19",  -- 1b20
    x"c6", x"40", x"81", x"14", x"25", x"09", x"81", x"18", x"23", x"4d", x"86", x"40", x"16", x"ff", x"cc", x"81",  -- 1b30
    x"08", x"23", x"5f", x"81", x"0e", x"23", x"52", x"20", x"47", x"81", x"00", x"27", x"12", x"81", x"01", x"27",  -- 1b40
    x"07", x"dc", x"4c", x"83", x"00", x"02", x"20", x"50", x"dc", x"4c", x"c3", x"01", x"3d", x"20", x"49", x"dc",  -- 1b50
    x"4c", x"10", x"83", x"00", x"10", x"23", x"11", x"10", x"83", x"00", x"20", x"23", x"10", x"10", x"83", x"00",  -- 1b60
    x"30", x"23", x"0f", x"c3", x"01", x"50", x"20", x"30", x"c3", x"01", x"7d", x"20", x"2b", x"c3", x"01", x"6f",  -- 1b70
    x"20", x"26", x"c3", x"01", x"5e", x"20", x"21", x"80", x"14", x"8d", x"23", x"83", x"00", x"03", x"20", x"16",  -- 1b80
    x"86", x"14", x"8d", x"18", x"83", x"00", x"02", x"20", x"0d", x"86", x"0e", x"8d", x"0f", x"83", x"00", x"01",  -- 1b90
    x"20", x"04", x"86", x"08", x"8d", x"06", x"d3", x"4a", x"dd", x"4c", x"4f", x"39", x"90", x"4b", x"3d", x"dd",  -- 1ba0
    x"4a", x"dc", x"4c", x"39", x"34", x"7f", x"17", x"fd", x"5f", x"17", x"fd", x"75", x"25", x"22", x"17", x"fe",  -- 1bb0
    x"1a", x"25", x"1d", x"8d", x"25", x"86", x"02", x"34", x"02", x"8d", x"3e", x"25", x"13", x"17", x"00", x"42",  -- 1bc0
    x"17", x"00", x"d1", x"35", x"02", x"24", x"05", x"4a", x"26", x"ed", x"20", x"04", x"86", x"19", x"97", x"4b",  -- 1bd0
    x"17", x"fd", x"6b", x"35", x"02", x"1e", x"8a", x"44", x"35", x"fe", x"de", x"4f", x"cc", x"28", x"ff", x"8d",  -- 1be0
    x"12", x"cc", x"02", x"fe", x"8d", x"0d", x"cc", x"08", x"ff", x"8d", x"08", x"cc", x"4d", x"fe", x"8d", x"03",  -- 1bf0
    x"cc", x"01", x"8c", x"e7", x"c0", x"4a", x"26", x"fb", x"39", x"a6", x"01", x"85", x"02", x"26", x"fa", x"16",  -- 1c00
    x"fe", x"61", x"34", x"01", x"1a", x"50", x"de", x"4f", x"e6", x"03", x"e6", x"84", x"2a", x"fa", x"e6", x"84",  -- 1c10
    x"2a", x"fc", x"c6", x"04", x"e7", x"84", x"10", x"8e", x"0a", x"ec", x"86", x"16", x"8d", x"5e", x"10", x"8e",  -- 1c20
    x"00", x"00", x"31", x"21", x"10", x"9f", x"4c", x"86", x"a5", x"8d", x"4d", x"96", x"4c", x"8d", x"49", x"96",  -- 1c30
    x"4d", x"8d", x"45", x"9b", x"4c", x"8b", x"a5", x"8d", x"3f", x"10", x"8e", x"00", x"07", x"86", x"16", x"8d",  -- 1c40
    x"3b", x"86", x"5a", x"8d", x"33", x"10", x"8e", x"00", x"05", x"10", x"9c", x"4c", x"27", x"39", x"10", x"8e",  -- 1c50
    x"00", x"80", x"86", x"ff", x"8d", x"26", x"86", x"da", x"8d", x"1e", x"10", x"8e", x"00", x"14", x"86", x"16",  -- 1c60
    x"8d", x"1a", x"10", x"9e", x"4c", x"10", x"8c", x"01", x"90", x"26", x"b7", x"8d", x"0b", x"e6", x"01", x"c5",  -- 1c70
    x"02", x"26", x"f8", x"6f", x"84", x"35", x"01", x"39", x"10", x"8e", x"00", x"01", x"e6", x"84", x"2a", x"fc",  -- 1c80
    x"a7", x"03", x"31", x"3f", x"26", x"f6", x"39", x"de", x"4f", x"4f", x"8d", x"ec", x"81", x"8c", x"27", x"ca",  -- 1c90
    x"a6", x"c0", x"20", x"f6", x"10", x"8e", x"00", x"00", x"31", x"21", x"10", x"9f", x"4c", x"de", x"4f", x"17",  -- 1ca0
    x"fd", x"b5", x"25", x"69", x"34", x"01", x"17", x"fd", x"2f", x"25", x"63", x"cc", x"5a", x"80", x"ed", x"03",  -- 1cb0
    x"86", x"80", x"c6", x"18", x"e7", x"84", x"e6", x"84", x"c5", x"01", x"27", x"fa", x"e6", x"03", x"c6", x"ff",  -- 1cc0
    x"e7", x"04", x"c6", x"08", x"e7", x"84", x"10", x"9e", x"4c", x"10", x"8c", x"00", x"05", x"27", x"1e", x"e6",  -- 1cd0
    x"84", x"2a", x"fc", x"e6", x"03", x"c1", x"ff", x"26", x"0f", x"4a", x"26", x"f3", x"e6", x"84", x"2a", x"fc",  -- 1ce0
    x"e6", x"03", x"6f", x"84", x"c1", x"da", x"27", x"1a", x"86", x"20", x"16", x"fe", x"0e", x"e6", x"84", x"2a",  -- 1cf0
    x"fc", x"e6", x"03", x"26", x"f3", x"e6", x"84", x"2a", x"fc", x"e6", x"03", x"e1", x"c0", x"26", x"e9", x"4a",  -- 1d00
    x"26", x"f3", x"35", x"01", x"10", x"9e", x"4c", x"10", x"8c", x"01", x"90", x"26", x"8b", x"39", x"35", x"01",  -- 1d10
    x"43", x"39", x"53", x"43", x"52", x"41", x"54", x"43", x"48", x"20", x"44", x"4f", x"53", x"d6", x"f0", x"c1",  -- 1d20
    x"02", x"27", x"23", x"0a", x"f0", x"8d", x"60", x"25", x"30", x"5d", x"27", x"05", x"17", x"01", x"55", x"25",  -- 1d30
    x"28", x"0c", x"f0", x"8d", x"52", x"25", x"22", x"c6", x"0a", x"9e", x"e7", x"a6", x"85", x"a7", x"a5", x"5a",  -- 1d40
    x"2c", x"f9", x"8d", x"36", x"25", x"13", x"86", x"02", x"97", x"4c", x"c6", x"14", x"4f", x"dd", x"4a", x"dc",  -- 1d50
    x"ed", x"dd", x"4f", x"8d", x"25", x"25", x"02", x"0f", x"f0", x"39", x"9e", x"ed", x"9f", x"4f", x"86", x"02",  -- 1d60
    x"20", x"0d", x"97", x"e5", x"43", x"43", x"39", x"4f", x"39", x"86", x"03", x"9e", x"e9", x"9f", x"4f", x"97",  -- 1d70
    x"4c", x"c6", x"14", x"4f", x"dd", x"4a", x"86", x"02", x"20", x"02", x"86", x"08", x"97", x"48", x"10", x"9e",  -- 1d80
    x"e9", x"17", x"fa", x"70", x"86", x"03", x"39", x"8d", x"e0", x"25", x"d7", x"8e", x"00", x"04", x"10", x"9e",  -- 1d90
    x"e9", x"de", x"e7", x"d6", x"f0", x"c1", x"03", x"26", x"04", x"33", x"8d", x"ff", x"75", x"5f", x"c1", x"0b",  -- 1da0
    x"24", x"24", x"a6", x"a5", x"81", x"ff", x"27", x"1b", x"5c", x"a1", x"c0", x"27", x"f1", x"31", x"a8", x"20",  -- 1db0
    x"30", x"1f", x"26", x"dd", x"0c", x"4c", x"96", x"4c", x"81", x"10", x"22", x"07", x"17", x"fa", x"35", x"86",  -- 1dc0
    x"03", x"20", x"c6", x"5f", x"20", x"1b", x"e6", x"2b", x"d1", x"eb", x"26", x"e1", x"e6", x"2c", x"d1", x"ec",  -- 1dd0
    x"26", x"db", x"d6", x"4c", x"a6", x"2d", x"97", x"f6", x"0f", x"f5", x"ae", x"2e", x"9f", x"f7", x"10", x"9f",  -- 1de0
    x"fa", x"d7", x"f9", x"16", x"ff", x"81", x"10", x"9e", x"ed", x"8d", x"6f", x"25", x"9c", x"d7", x"f6", x"17",  -- 1df0
    x"ff", x"77", x"25", x"f7", x"10", x"9e", x"e9", x"8e", x"00", x"04", x"e6", x"a4", x"27", x"20", x"86", x"05",  -- 1e00
    x"c1", x"ff", x"27", x"1a", x"31", x"a8", x"20", x"30", x"1f", x"26", x"ef", x"0c", x"4c", x"96", x"4c", x"81",  -- 1e10
    x"10", x"22", x"07", x"17", x"f9", x"de", x"86", x"03", x"20", x"d8", x"86", x"05", x"20", x"cd", x"9e", x"e7",  -- 1e20
    x"d6", x"f0", x"c1", x"03", x"26", x"04", x"30", x"8d", x"fe", x"e8", x"c6", x"0a", x"a6", x"85", x"a7", x"a5",  -- 1e30
    x"5a", x"2c", x"f9", x"96", x"eb", x"a7", x"2b", x"96", x"ec", x"d6", x"f6", x"ed", x"2c", x"16", x"ff", x"3a",  -- 1e40
    x"d6", x"f6", x"c1", x"28", x"22", x"0e", x"5d", x"27", x"11", x"a6", x"a5", x"81", x"ff", x"27", x"2d", x"5a",  -- 1e50
    x"c1", x"28", x"23", x"f2", x"cb", x"02", x"c1", x"51", x"20", x"ed", x"5f", x"31", x"a8", x"28", x"86", x"05",  -- 1e60
    x"c1", x"28", x"10", x"22", x"fe", x"fc", x"a6", x"a5", x"81", x"ff", x"27", x"0b", x"50", x"a6", x"a5", x"81",  -- 1e70
    x"ff", x"27", x"04", x"50", x"5c", x"20", x"e7", x"cb", x"28", x"31", x"a8", x"d8", x"6f", x"a5", x"5a", x"d7",  -- 1e80
    x"f9", x"16", x"fe", x"e3", x"a6", x"2d", x"97", x"f6", x"6f", x"a4", x"17", x"fe", x"ed", x"25", x"8d", x"10",  -- 1e90
    x"9e", x"ed", x"d6", x"f6", x"5c", x"a6", x"a5", x"6f", x"a5", x"6a", x"a5", x"1f", x"89", x"81", x"c0", x"25",  -- 1ea0
    x"f3", x"20", x"de", x"d6", x"f6", x"4f", x"54", x"dd", x"fb", x"4c", x"97", x"f5", x"24", x"02", x"86", x"09",  -- 1eb0
    x"97", x"fa", x"39", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1ec0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1ed0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1ee0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1ef0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f00
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f10
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f20
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f30
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f40
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f50
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f60
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f70
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f80
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1f90
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1fa0
    x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff", x"ff",  -- 1fb0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 1fc0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 1fd0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e",  -- 1fe0
    x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e", x"0e"   -- 1ff0
  );
  
  -----------------------------------------------------------------------------    
  FUNCTION calc_crc (
    v     : uv8;
    start : uv16) RETURN unsigned;
    
  -----------------------------------------------------------------------------    

END PACKAGE thmfc1_pack;

--#############################################################################

PACKAGE BODY thmfc1_pack IS

  -----------------------------------------------------------------------------

  FUNCTION calc_crc (
    v     : uv8;
    start : uv16) RETURN unsigned IS
    VARIABLE crc_high, crc_low : uv8;
    VARIABLE c : uv8;
  BEGIN
    crc_high := start(15 DOWNTO 8);
    crc_low  := start(7 DOWNTO 0);
    c        := (crc_high XOR v);
    c        := c XOR ("0000" & c(7 DOWNTO 4));
    crc_low  := crc_low XOR ("000" & c(7 DOWNTO 3));
    crc_high := (c(3 DOWNTO 0) & "0000")  XOR crc_low;
    crc_low  := (c(2 DOWNTO 0) & "00000") XOR c;
    RETURN crc_high & crc_low;
  END FUNCTION;

END PACKAGE BODY thmfc1_pack;

