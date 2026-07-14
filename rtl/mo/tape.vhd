--------------------------------------------------------------------------------
-- Thomson TOx MOx
--------------------------------------------------------------------------------
-- DO 12/2019
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

LIBRARY work;
USE work.base_pack.ALL;
USE work.tomo_pack.ALL;

ENTITY tape IS
  GENERIC (
    SYSFREQ : natural);
  PORT (
    motor_n        : IN std_logic;
    tape_mo_rd     : OUT std_logic;
    tape_mo_wr     : IN  std_logic;

    tape_to_rd     : OUT std_logic;
    tape_to_wr     : IN  std_logic;

    model          : IN type_model;
    
    rewind         : IN std_logic;
    
    tratio         : OUT uv8;
    tshow          : OUT std_logic;

    ioctl_download : IN  std_logic;
    ioctl_wr       : IN  std_logic;
    ioctl_addr     : IN  unsigned(24 DOWNTO 0);
    ioctl_data     : IN  std_logic_vector(7 DOWNTO 0);
    ioctl_wait     : OUT std_logic;
    
    tape_address       : OUT   unsigned(28 DOWNTO 0);
    tape_burstcount    : OUT   unsigned(7 DOWNTO 0);
    tape_waitrequest   : IN    std_logic;
    tape_read          : OUT   std_logic;
    tape_readdata      : IN    std_logic_vector(63 DOWNTO 0);
    tape_readdatavalid : IN    std_logic;
    tape_write         : OUT   std_logic;
    tape_writedata     : OUT   std_logic_vector(63 DOWNTO 0);
    tape_byteenable    : OUT   std_logic_vector(7 DOWNTO 0);

    speed          : IN uv2;
    tick_cpu       : IN std_logic;
    sysclk         : IN std_logic;
    reset_n        : IN std_logic);
    
END tape;

ARCHITECTURE rtl OF tape IS
  SIGNAL head : string(1 TO 4);
  SIGNAL size,filesize  : uv32;
  SIGNAL rpos,wpos : uv32;
  SIGNAL fmt : uv128;
  ALIAS  fmt_audio    : uv16 IS fmt(15 DOWNTO 0);    -- Audio Format 1=PCM
  ALIAS  fmt_chan     : uv16 IS fmt(31 DOWNTO 16);   -- Number of channels
  ALIAS  fmt_freq     : uv32 IS fmt(63 DOWNTO 32);   -- Sampling freq
  ALIAS  fmt_bpsec    : uv32 IS fmt(95 DOWNTO 64);   -- Bytes Per Sample
  ALIAS  fmt_bpbloc   : uv16 IS fmt(111 DOWNTO 96);  -- Bytes Per Bloc
  ALIAS  fmt_bpsample : uv16 IS fmt(127 DOWNTO 112); -- Bits Per Sample
  SIGNAL alt : uint8;

  TYPE enum_state IS (sIDLE,sHEAD,
                      sBLOCK_RIFF,sBLOCK_FMT,sBLOCK_DATA,sBLOCK_SKIP);
  SIGNAL state : enum_state;

  SIGNAL ioctl_wait_l,motor_pre_n : std_logic;
  SIGNAL wsample : std_logic;
  SIGNAL tick_wav : std_logic;
  SIGNAL acc   : integer RANGE -32768*32768 TO 32768*32768-1;
  SIGNAL freq : uint24;
  
  SIGNAL divrun : std_logic;
  SIGNAL vdivr : unsigned(64 DOWNTO 0);
  SIGNAL vdivi : uv32;
  SIGNAL divcpt : uint8;

  SIGNAL tape_write_l,tape_read_l : std_logic;
  SIGNAL wshift,rshift : uv64;
  SIGNAL pushsample,pushsample2,pushlast : std_logic;
  SIGNAL rcpt,wcpt : uint6;
  SIGNAL waddr,raddr : uv29;
  SIGNAL loaded,rsample : std_logic;

  SIGNAL rtsample, rsample2 : std_logic;
  SIGNAL fcpt : natural RANGE 0 TO 15;

  SIGNAL tshow_cpt : natural RANGE 0 TO 4*1000*1000;

BEGIN


-- 00  52 49 46 46 e4 c3 44 01  57 41 56 45 66 6d 74 20  |RIFF....WAVEfmt |
-- 10  10 00 00 00 01 00 01 00  44 ac 00 00 44 ac 00 00  |................|
-- 20  01 00 08 00 64 61 74 61  bf c3 44 01 80 80 80 80  |....data........|

-- 52 49 46 46 "RIFF"
-- E4 C3 44 01 File Length
-- 57 41 56 45 "WAVE"

-- 66 6d 74 20 "fmt "
-- 10 00 00 00 Block size
-- 01 00       Audioformat
-- 01 00       Channels
-- 44 AC 00 00 Freq
-- 44 AC 00 00 Bytes per second
-- 01 00       Bytes per Bloc
-- 08 00       Bits per sample


-- 64 61 74 61 "data"
-- BF C3 44 01 Block size
  
  tape_mo_rd<=rsample WHEN motor_n='0' ELSE '1';
  
  PROCESS(sysclk) IS
    VARIABLE t : uint8;
  BEGIN
    IF rising_edge(sysclk) THEN
      --------------------------------------------
      pushsample <= '0';
      pushlast   <= '0';

      --------------------------------------------
      CASE state IS
        WHEN sIDLE =>
          IF ioctl_download='1' THEN
            state<=sHEAD;
          END IF;
          wpos<=x"00000000";
          ioctl_wait_l<='0';
          tape_write_l<='0';          
          
        WHEN sHEAD =>
          loaded<='0';
          -- Block header
          IF ioctl_wr='1' AND ioctl_wait_l='0' THEN
            t:=to_integer(unsigned(ioctl_data));
            IF wpos=0 THEN head(1)<=character'val(t); END IF;
            IF wpos=1 THEN head(2)<=character'val(t); END IF;
            IF wpos=2 THEN head(3)<=character'val(t); END IF;
            IF wpos=3 THEN head(4)<=character'val(t); END IF;
            IF wpos=4 THEN size( 7 DOWNTO 0) <=unsigned(ioctl_data); END IF;
            IF wpos=5 THEN size(15 DOWNTO 8) <=unsigned(ioctl_data); END IF;
            IF wpos=6 THEN size(23 DOWNTO 16)<=unsigned(ioctl_data); END IF;
            IF wpos=7 THEN size(31 DOWNTO 24)<=unsigned(ioctl_data); END IF;
            
            wpos<=wpos+1;
            IF wpos=7 THEN
              wpos<=x"00000000";
              IF head="RIFF" THEN
                state<=sBLOCK_RIFF;
              ELSIF head="fmt " THEN
                state<=sBLOCK_FMT;
              ELSIF head="data" THEN
                state<=sBLOCK_DATA;
              ELSE
                state<=sBLOCK_SKIP;
              END IF;
            END IF;
          END IF;
          
        WHEN sBLOCK_RIFF =>
          filesize<=size;
          IF ioctl_wr='1' AND ioctl_wait_l='0' THEN
            wpos<=wpos+1;
            IF wpos=3 THEN
              wpos<=x"00000000";
              state<=sHEAD;
            END IF;
          END IF;
          
        WHEN sBLOCK_FMT =>
          IF ioctl_wr='1' AND ioctl_wait_l='0' THEN
            fmt(to_integer(wpos)*8+7 DOWNTO
                to_integer(wpos)*8)<=unsigned(ioctl_data);
            wpos<=wpos+1;
            IF wpos=size-1 THEN
              wpos<=x"00000000";
              state<=sHEAD;
            END IF;
          END IF;
          
        WHEN sBLOCK_SKIP =>
          IF ioctl_wr='1' AND ioctl_wait_l='0' THEN
            wpos<=wpos+1;
            IF wpos=size-1 THEN
              wpos<=x"00000000";
              state<=sHEAD;
            END IF;
          END IF;
          
        WHEN sBLOCK_DATA =>
          IF ioctl_wr='1' AND ioctl_wait_l='0' THEN
            wpos<=wpos+1;
            IF alt=0 AND fmt_bpsample=8 THEN
              wsample<=ioctl_data(7);
              pushsample<='1';
            END IF;
            IF alt=1 AND fmt_bpsample=16 THEN
              wsample<=ioctl_data(7);
              pushsample<='1';
            END IF;
            
            IF alt=fmt_bpbloc-1 THEN
              alt<=0;
            ELSE
              alt<=alt+1;
            END IF;
          END IF;
          IF ioctl_download='0' THEN
            pushlast<='1';
            loaded<='1';
          END IF;
          
      END CASE;
      
      --------------------------------------------
      IF ioctl_download='0' THEN
        state<=sIDLE;
      END IF;
      
      --------------------------------------------
      IF state=sIDLE THEN
        wcpt<=0;
        waddr<=(OTHERS =>'0');
      ELSIF pushsample='1' THEN
        wshift(wcpt)<=wsample;
        wcpt<=(wcpt+1) MOD 64;
      END IF;

      pushsample2<=pushsample;
      IF ((pushsample2='1' AND wcpt=0) OR pushlast='1') AND tape_write_l='0' THEN
        tape_write_l<='1';
        tape_writedata<=std_logic_vector(wshift);
        tape_address<=waddr;
        waddr<=waddr+1;
      END IF;
      
      --------------------------------------------
      motor_pre_n<=motor_n;
      
      IF loaded='0' OR rewind='1' THEN
        raddr<=(OTHERS =>'0');
        rcpt<=0;
        tape_read_l<='0';
        
        rpos <= x"00000000";
        rsample <= '0';
        
      ELSIF motor_n='0' AND motor_pre_n='1' THEN
        IF rpos>206 THEN
          rpos <= rpos - 206;
        END IF;
        
      ELSIF tick_wav='1' AND motor_n='0' THEN
        IF rcpt=0 THEN
          tape_read_l <= '1';
          tape_address <= raddr;
          raddr <= raddr + 1;
        END IF;
        rcpt <= (rcpt + 1) MOD 64;
        rsample <= rshift((rcpt+63) MOD 64);
        rpos <= rpos+1;
        
      END IF;
      
      IF tape_readdatavalid='1' THEN
        rshift<=unsigned(tape_readdata);
      END IF;
      
      --------------------------------------------
      IF tape_write_l='1' AND tape_waitrequest='0' THEN
        tape_write_l<='0';
      END IF;
      IF tape_read_l='1' AND tape_waitrequest='0' THEN
        tape_read_l<='0';
      END IF;
      
      --------------------------------------------
      tape_address(28 DOWNTO 25)<=x"3";
      
      --------------------------------------------
      IF reset_n='0' THEN
        ioctl_wait_l<='0';
        state<=sIDLE;
        loaded <= '0';
      END IF; 
    
    END IF;
  END PROCESS;

  -------------------------------------------------
  -- TO : Detect frequency
  -- 4.5kHz / 6.3kHz
  ToTape:PROCESS(sysclk) 
  BEGIN
    IF rising_edge(sysclk) THEN
      IF tick_wav='1' THEN
        rsample2 <= rsample;

        IF rsample2='0' AND rsample='1' THEN
          fcpt <= 0;
          IF fcpt < 9 AND freq = 44100 THEN
            rtsample <= '1'; -- High freq
          ELSE
            rtsample <= '0'; -- Low freq
          END IF;

        ELSIF fcpt < 15 THEN
          fcpt <= fcpt + 1;

        END IF;
      END IF;
    END IF;
  END PROCESS ToTape;

  tape_to_rd <= rtsample AND loaded;
  
  -------------------------------------------------
  ClockGen:PROCESS (sysclk)
  BEGIN
    IF rising_edge(sysclk) THEN
      IF speed=SPEED_2x THEN
        freq<=to_integer(fmt_freq)*2;
      ELSIF speed=SPEED_4x THEN
        freq<=to_integer(fmt_freq)*4;
      ELSE -- SPEED 1x
        freq<=to_integer(fmt_freq);
      END IF;

      IF acc>0 THEN
        acc<=acc - freq;
        tick_wav <= '0';
      ELSE
        acc<=acc - freq + SYSFREQ;
        tick_wav <= '1';
      END IF;

      IF reset_n='0' THEN
        acc <= 0;
        tick_wav <= '0';
      END IF;
    END IF;
  END PROCESS ClockGen;
  
  -------------------------------------------------
  ioctl_wait<=ioctl_wait_l;
  
  tape_burstcount <= x"01";
  tape_byteenable <= x"FF";

  tape_read  <= tape_read_l;
  tape_write <= tape_write_l;
  
  -----------------------------------------------------------------------------
  -- 32 / 32 --> 32
  Dividers:PROCESS (sysclk) IS
  BEGIN
    IF rising_edge(sysclk) THEN
      vdivi<=size(30 DOWNTO 0) & '0';
      vdivr<=rpos(31 DOWNTO 0) & '0' & x"00000000";
      
      ------------------------------------------------------
      IF tick_cpu='1' THEN
        divcpt<=0;
        divrun<='1';
        
      ELSIF divrun='1' THEN
        ----------------------------------------------------
        IF divcpt=8 THEN
          divrun<='0';
          tratio<=vdivr(6 DOWNTO 0) & NOT vdivr(64);
        ELSE
          divcpt<=divcpt+1;
        END IF;
        
        IF vdivr(64)='0' THEN
          vdivr(64 DOWNTO 32)<=vdivr(63 DOWNTO 31) - vdivi;
        ELSE
          vdivr(64 DOWNTO 32)<=vdivr(63 DOWNTO 31) + vdivi;
        END IF;
        vdivr(15 DOWNTO 0)<=vdivr(14 DOWNTO 0) & NOT vdivr(64);
        
        ----------------------------------------------------
      END IF;
    END IF;
  END PROCESS Dividers;
  
  -------------------------------------------------------------------------------
  -- Show progress bar when motor is running + 3 sec
  BarShow:PROCESS(sysclk) IS
  BEGIN
    IF rising_edge(sysclk) THEN
      IF tick_cpu='1' THEN
        IF tshow_cpt < 3 *1000*1000 THEN
          tshow_cpt <= tshow_cpt + 1;
          tshow <= '1';
        ELSE
          tshow <= '0';
        END IF;
      END IF;
      IF motor_n='0' THEN
        tshow_cpt <= 0;
      END IF;
    END IF;
  END PROCESS BarShow;

END ARCHITECTURE rtl;


-- MGT :
--  Lancer : run "

-- Le moteur démarre/arrête une première fois avec "FOUND MGT.BAS",
--   puis une seconde fois avec  "Erreur 53"

-------------------------------------------------------------
-- TO7 
-- 1.1ms/bit : 5 périodes à 4.5kHz ou 7 périodes à 6.3kHz
-- 4.5kHz = 0  6.3kHz = 1
-- démodulation en lecture dans le lecteur cassette.

-- MO5
-- 833µs/bit
-- 0=demi-période à 1.2kHz, 1=période à 1.2kHz
-- pas de démodulation dans le lecteur.
