--------------------------------------------------------------------------------
-- Thomson MO5/MO6 Video
--------------------------------------------------------------------------------
-- DO 12/2019
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------

--------------------------------------------------------------------------------

-- WEDC : Enable A7DC write
-- TA[12:0] : Light pen position
-- H1,H2,H4 :
-- LT3  : Light pen : 0= Left border 1=Right border
-- INIL : Light pen : 0=Offscreen 1=On screen
-- 

-- 40 µs / 64 µs.   40µs *  8MHz = 320
--                  40µs * 16MHz = 640

-- 13 ms / 20 ms 
-- Horloge base 16MHz = Fréquence max pixels
-- Accès RAM

--------------------------------------------------------------------------------
-- HORIZONTAL
--   0 :  9 = Blank     0 :  79
--  10 : 11 = Border   80 :  95
--  12 : 51 = Image    96 : 415
--  52 : 53 = Border  416 : 431
--  54 : 63 = Blank   432 : 511
--  59 ; 63 = HSYNC

-- VERTICAL
--   0 :  39 = Blank
--  40 :  55 = Border
--  56 : 255 = Image
-- 256 : 271 = Border
-- 272 : 311 = Blank

----------------------------------------------------------------------------------

--200 lignes * 64µs = 12.8 ms
--7.2 ms reste  = 112.5 lignes
--
--300 lignes avec cadre
--
--x1F40 = 8000 = 320/8 *200
--x26C0 = 9920 = 320/8 *248 => abec bordures haut/bas
--
--
--
--  0...199 = Affichage
--248...250 = vsync0
--

--------------------------------------------------------------------------------
LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.tomo_pack.ALL;

ENTITY video IS
  PORT (
    ------------------------------------
    vram_req : OUT std_logic;
    vram_ack : IN  std_logic;
    vram_a   : OUT uv16;
    vram_dr  : IN  uv16;
    
    ------------------------------------
    -- Palette
    pal_a    : IN  uv5;
    pal_dw   : IN  uv8;
    pal_dr   : OUT uv8;
    pal_wr   : IN  std_logic;
    
    ------------------------------------
    model      : IN type_model;
    
    video_mode   : IN  uv7;
    video_trame  : IN  std_logic; -- 0=625 1=525
    video_page   : IN  uv2;  -- Video bank BE1/BE0
    pia_border   : IN  uv4; -- MO5 border colour
    tim_border   : IN  uv4; -- TO7/770 border
    gmp_border   : IN  uv4; -- MO6 / TO8 / TO9P
    nobord       : IN  std_logic; -- Hide border

    divclk    : IN uint6;

    ------------------------------------
    -- Light Pen Cursor
    cursor : IN  uv2; -- Show light pen position
    hpos   : IN integer RANGE 0 TO 511;
    vpos   : IN integer RANGE 0 TO 511;
  
    ------------------------------------
    -- Cassette progress bar
    tbaren   : IN std_logic; -- Show tape progress bar
    tratio   : IN uv8;       -- Progress bar position
    tmotor_n : IN std_logic; -- Motor ON/OFF

    -- Floppy progress bar
    dbaren   : IN std_logic; -- Show floppy progress bar
    dratio   : IN uv8;       -- Track/Head : 0..159
    dmotor   : IN std_logic;

    -- Invalid instruction
    emu_ilatch : IN std_logic;

    ------------------------------------
    -- Video out
    vga_r  : OUT uv8;
    vga_g  : OUT uv8;
    vga_b  : OUT uv8;
    vga_hs : OUT std_logic;
    vga_vs : OUT std_logic;
    vga_de : OUT std_logic;
    vga_ce : OUT std_logic;
    vga_ceh : OUT std_logic;
    
    -- For Light Pen / frame sync
    vid_hpos : OUT uint11;
    vid_vpos : OUT uint11;
    vid_ta   : OUT uv13; -- Address
    vid_h    : OUT uv3;  -- 8 pixels
    vid_vin  : OUT std_logic;
    vid_hin  : OUT std_logic;
    vid_hlr  : OUT std_logic;
    
    ------------------------------------
    video_run : IN std_logic;
    speed     : IN uv2;

    ------------------------------------
    clk       : IN std_logic; -- 32MHz
    hwreset_n : IN std_logic
    );
END ENTITY video;

-- 0000:1FFF : Color MEM
-- 2000:3FFF : Pixel MEM

--------------------------------------------------------------------------------

ARCHITECTURE rtl OF video IS
  FUNCTION sel_bm2(col : uv8; pix : uv8; pos : natural) RETURN uv IS
  BEGIN
    IF    pos<8  THEN RETURN mux(pix(7),col(7 DOWNTO 4),col(3 DOWNTO 0));
    ELSIF pos<16 THEN RETURN mux(pix(6),col(7 DOWNTO 4),col(3 DOWNTO 0));
    ELSIF pos<24 THEN RETURN mux(pix(5),col(7 DOWNTO 4),col(3 DOWNTO 0));
    ELSIF pos<32 THEN RETURN mux(pix(4),col(7 DOWNTO 4),col(3 DOWNTO 0));
    ELSIF pos<40 THEN RETURN mux(pix(3),col(7 DOWNTO 4),col(3 DOWNTO 0));
    ELSIF pos<48 THEN RETURN mux(pix(2),col(7 DOWNTO 4),col(3 DOWNTO 0));
    ELSIF pos<56 THEN RETURN mux(pix(1),col(7 DOWNTO 4),col(3 DOWNTO 0));
    ELSE              RETURN mux(pix(0),col(7 DOWNTO 4),col(3 DOWNTO 0));
    END IF;
  END FUNCTION;

  FUNCTION sel_bm4(col : uv8; pix : uv8; pos : natural) RETURN uv IS
    VARIABLE i : natural := pos / 8;
  BEGIN
    RETURN "00" & col(7-i) & pix(7-i);
  END FUNCTION;
  
  FUNCTION sel_80c(col : uv8; pix : uv8; pos : natural) RETURN uv IS
    VARIABLE t : uv16 := pix & col;
    VARIABLE i : natural := pos / 4;
  BEGIN
    RETURN "000" & t(15-i);
  END FUNCTION;

  FUNCTION sel_80c_to9(col : uv8; pix : uv8; pos : natural) RETURN uv IS
    VARIABLE t : uv16 := pix & col;
    VARIABLE i : natural := pos / 4;
  BEGIN
    RETURN mux(t(15-i),"1110","1000");
  END FUNCTION;
  
  FUNCTION sel_bm16(col : uv8; pix : uv8; pos : natural) RETURN uv IS
    VARIABLE i : natural := pos / 16;
    VARIABLE t : uv16 := pix & col;
  BEGIN
    RETURN t((3-i)*4+3 DOWNTO (3-i)*4);
  END FUNCTION;
  
  FUNCTION sel_2col(col : uv8; pos : natural) RETURN uv IS
    VARIABLE i : natural := pos / 8;
  BEGIN
    RETURN "000" & col(7-i);
  END FUNCTION;
  
  FUNCTION sel_over2(col : uv8; pix : uv8; pos : natural) RETURN uv IS
    VARIABLE i : natural := pos / 8;
  BEGIN
    RETURN "000" & (col(7-i) AND pix(7-i));
  END FUNCTION;
  
  FUNCTION sel_over4(col : uv8; pix : uv8; pos : natural) RETURN uv IS
    VARIABLE i : natural := pos / 16;
  BEGIN
    IF    col(7-i)='1'   THEN RETURN "0001";
    ELSIF col(7-i-4)='1' THEN RETURN "0010";
    ELSIF pix(7-i)='1'   THEN RETURN "0011";
    ELSE
      RETURN "000" & pix(i+4);
    END IF;
  END FUNCTION;
  

  ---------------------------------------------------------
  -- Palette MO5
  -- 0 : 00 00 00 : Noir
  -- 1 : 01 01 11 : Rouge
  -- 2 : 00 11 00 : Vert
  -- 3 : 00 11 11 : Jaune
  -- 4 : 11 01 01 : Bleu
  -- 5 : 11 00 11 : Magenta
  -- 6 : 11 11 01 : Cyan
  -- 7 : 11 11 11 : Blanc
  -- 8 : 10 10 10 : Gris
  -- 9 : 10 10 11 : Rose
  -- A : 10 11 10 : Vert clair
  -- B : 10 11 11 : Jaune clair
  -- C : 11 10 01 : Bleu clair
  -- D : 11 10 11 : Rose parme
  -- E : 11 11 10 : Cyan clair
  -- F : 01 10 11 : Orange

  CONSTANT PAL_MO5_B : arr_uv8(0 TO 15) := (
    x"00",x"55",x"00",x"00",x"FF",x"FF",x"FF",x"FF",
    x"AA",x"AA",x"AA",x"AA",x"FF",x"FF",x"FF",x"55");
  
  CONSTANT PAL_MO5_V : arr_uv8(0 TO 15) := (
    x"00",x"55",x"FF",x"FF",x"55",x"00",x"FF",x"FF",
    x"AA",x"AA",x"FF",x"FF",x"AA",x"AA",x"FF",x"AA");
    
  CONSTANT PAL_MO5_R : arr_uv8(0 TO 15) := (
    x"00",x"FF",x"00",x"FF",x"55",x"FF",x"55",x"FF",
    x"AA",x"FF",x"AA",x"FF",x"55",x"FF",x"AA",x"FF");

  -- Palette TO7
  -- 0 : 0000 : 00 00 00 : Noir
  -- 1 : 0001 : 00 00 11 : Rouge
  -- 2 : 0010 : 00 11 00 : Vert
  -- 3 : 0011 : 00 11 11 : Jaune
  -- 4 : 0100 : 11 00 00 : Bleu
  -- 5 : 0101 : 11 00 11 : Magenta
  -- 6 : 0110 : 11 11 00 : Cyan
  -- 7 : 0111 : 11 11 11 : Blanc
  -- 8 : 1000 : 00 00 00 : Noir
  -- 9 : 1001 : 00 00 11 : Rouge
  -- A : 1010 : 00 11 00 : Vert
  -- B : 1011 : 00 11 11 : Jaune
  -- C : 1100 : 11 00 00 : Bleu
  -- D : 1101 : 11 00 11 : Magenta
  -- E : 1110 : 11 11 00 : Cyan
  -- F : 1111 : 11 11 11 : Blanc

  CONSTANT PAL_TO7_B : arr_uv8(0 TO 15) := (
    x"00",x"00",x"00",x"00",x"FF",x"FF",x"FF",x"FF",
    x"00",x"00",x"00",x"00",x"FF",x"FF",x"FF",x"FF");
  
  CONSTANT PAL_TO7_V : arr_uv8(0 TO 15) := (
    x"00",x"00",x"FF",x"FF",x"00",x"00",x"FF",x"FF",
    x"00",x"00",x"FF",x"FF",x"00",x"00",x"FF",x"FF");
    
  CONSTANT PAL_TO7_R : arr_uv8(0 TO 15) := (
    x"00",x"FF",x"00",x"FF",x"00",x"FF",x"00",x"FF",
    x"00",x"FF",x"00",x"FF",x"00",x"FF",x"00",x"FF");

  CONSTANT PAL_TO770_B : arr_uv8(0 TO 15) := (
    x"00",x"00",x"00",x"00",x"7F",x"7F",x"7F",x"7F",
    x"7F",x"00",x"00",x"00",x"FF",x"FF",x"FF",x"FF");
  
  CONSTANT PAL_TO770_V : arr_uv8(0 TO 15) := (
    x"00",x"00",x"7F",x"7F",x"00",x"00",x"7F",x"7F",
    x"7F",x"00",x"FF",x"FF",x"00",x"00",x"FF",x"FF");
    
  CONSTANT PAL_TO770_R : arr_uv8(0 TO 15) := (
    x"00",x"7F",x"00",x"7F",x"00",x"7F",x"00",x"7F",
    x"7F",x"FF",x"00",x"FF",x"00",x"FF",x"00",x"FF");
  
  ---------------------------------------------------------
  
--  SIGNAL pal_lo : arr_uv8(0 TO 15) :=(
--    x"00",x"5F",x"F0",x"FF",x"55",x"0F",x"F5",x"FF",
--    x"AA",x"AF",x"FA",x"FF",x"A5",x"AF",x"FA",x"AF");
--  SIGNAL pal_hi : arr_uv8(0 TO 15) :=(
--    x"00",x"05",x"00",x"00",x"0F",x"0F",x"0F",x"0F",
--    x"0A",x"0A",x"0A",x"0A",x"0F",x"0F",x"0F",x"05");
  
  SIGNAL pal_lo : arr_uv8(0 TO 15) :=(
    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00");
  SIGNAL pal_hi : arr_uv8(0 TO 15) :=(
    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00",
    x"00",x"00",x"00",x"00",x"00",x"00",x"00",x"00");
      
  ---------------------------------------------------------
  -- GAMMA
  --  0,   96,  122,  142,
  --158,  170,  183,  193,
  --204,  211,  219,  226,
  --234,  242,  249,  255,

  ---------------------
  SIGNAL col, col2 : uv4;
  SIGNAL plo,phi : uv8;
  SIGNAL hcpt, hcpt8, vcpt : uint11;
  SIGNAL hcptu : unsigned(10 DOWNTO 0);

  SIGNAL gpl : uint16;

  SIGNAL pos, pos2 : uv13 := (OTHERS =>'0');

  SIGNAL lp_hcpt, lp_hcpt8, lp_vcpt : uint11;
  SIGNAL lp_pos : uv13;
  
  TYPE enum_state IS (sIDLE, sREAD, sWAIT, sEND);
  SIGNAL state : enum_state;
  SIGNAL mem_col, mem_pix : uv8;
  SIGNAL dr_pix,  dr_pix2, dr_col : uv8;
  
  SIGNAL hsync0, vsync0, de0, dis0, disa : std_logic;
  SIGNAL hsync,  vsync,  de,  dis  : std_logic;
  SIGNAL hsync2, vsync2, de2, dis2 : std_logic;

  SIGNAL ovl0, ovr0, ovg0, ovb0 : std_logic;
  SIGNAL ovl2, ovr2, ovg2, ovb2 : std_logic;
  SIGNAL shl,  shr,  shg,  shb : uv15;

  SIGNAL ce, ce2 : std_logic;
  SIGNAL ceh, ceh2 : std_logic;

  CONSTANT TAPE_LINE  : natural := 56 + 184; -- Tape load line
  CONSTANT DISK_LINE  : natural := 56 + 190; -- Disk load line  
  CONSTANT EMUOP_LINE : natural := 56 + 196; -- Invalid instruction line

  SIGNAL gen1 : std_logic;

BEGIN

  -- First generation, fixed video mode.
  gen1 <= '1' WHEN model = T_MO5 OR
                   model = T_TO7 OR
                   model = T_TO770
              ELSE '0';
  
  -----------------------------------------------------------------------------
  Palette:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      -----------------------------------
      IF pal_wr='1' AND pal_a(0)='0' THEN
        pal_lo(to_integer(pal_a(4 DOWNTO 1)))<=pal_dw;
      END IF;
      IF pal_wr='1' AND pal_a(0)='1' THEN
        pal_hi(to_integer(pal_a(4 DOWNTO 1)))<=pal_dw;
      END IF;
      
      IF pal_a(0)='0' THEN
        pal_dr<=pal_lo(to_integer(pal_a(4 DOWNTO 1)));
      ELSE
        pal_dr<=pal_hi(to_integer(pal_a(4 DOWNTO 1)));
      END IF;
      -----------------------------------
    END IF;
  END PROCESS Palette;

  -----------------------------------------------------------------------------
  Video:PROCESS(clk) IS
    VARIABLE divtick_v, duvtick_v : boolean;
  BEGIN
    IF rising_edge(clk) THEN
      -----------------------------------
      -- 24 : R
      -- 25 : V
      -- 26 : B
      -- 27 : Pastel
      
      -- CA : 5 => 1 => 16 : R
      -- CB : 6 => 4 => 13 : V
      -- CC : 4 => 6 => 11 : B
      
      -----------------------------------
      -- PIXCLK * 32 :
      -- - 2 accès mémoire par 32 cycles
      -- - mémorise valeurs pour période suivante de0 32 cycles


      -- RAM accesses => mem_pix / mem_col

      -- 1) divclk

      -- 2) Video sweep, mem access

      -- 3) Pixel generation. 1 period delay sweep

      -----------------------------------------------------
      -- Video sweep for light pen
      IF speed=SPEED_2x THEN
        divtick_v := ((divclk MOD 32) =0);
        duvtick_v := ((divclk MOD 2) = 0);
      ELSIF speed=SPEED_4x THEN
        divtick_v := ((divclk MOD 16) =0);
        duvtick_v := ((divclk MOD 4) = 0);
      ELSE
        divtick_v := (divclk = 0);
        duvtick_v := ((divclk MOD 8) = 0);
      END IF;
      
      IF divtick_v AND lp_hcpt = 63 THEN
        lp_hcpt8 <= 0;
      ELSIF duvtick_v THEN
        lp_hcpt8 <=lp_hcpt8 + 1;
      END IF;

      IF divtick_v THEN
        IF lp_hcpt = 63 THEN
          lp_hcpt <= 0;
          IF lp_vcpt = 311 THEN
            lp_vcpt <= 0;
            lp_pos  <= (OTHERS =>'0');
          ELSE
            lp_vcpt <= lp_vcpt + 1;
          END IF;
        ELSE
          lp_hcpt <= lp_hcpt + 1;
          IF lp_hcpt >= 12 AND lp_hcpt <= 51 AND lp_vcpt >= 56 THEN
            lp_pos  <= lp_pos  + 1;
          END IF;
        END IF;
      END IF;

      IF divclk = 0 THEN
        IF hcpt = 63 THEN
          lp_hcpt <= 0;
          IF vcpt = 311 THEN
            lp_vcpt <= 0;
            lp_pos  <= (OTHERS =>'0');
          END IF;
        END IF;
      END IF;

      IF hwreset_n='0' THEN
        lp_hcpt <= 0;
        lp_vcpt <= 0;
        lp_pos  <= (OTHERS =>'0');
      END IF;
      
      -----------------------------------------------------
      -- Video sweep
      IF divclk = 0 AND hcpt = 63 THEN
        hcpt8 <= 0;
      ELSIF divclk MOD 8 = 0 THEN
        hcpt8 <= hcpt8 + 1;
      END IF;

      IF divclk = 0 THEN
        IF hcpt = 63 THEN
          hcpt <= 0;
          IF vcpt = 311 THEN
            vcpt <= 0;
            pos  <= (OTHERS =>'0');
          ELSE
            vcpt <= vcpt + 1;
          END IF;
        ELSE
          hcpt <= hcpt + 1;
          IF hcpt >= 12 AND hcpt <= 51 AND vcpt >= 56 THEN
            pos  <= pos  + 1;
          END IF;
        END IF;

        hsync0 <= to_std_logic(hcpt >= 59);

        vsync0 <= to_std_logic(vcpt >= 308 OR
                               (vcpt = 307 AND hcpt >= 59));

        de0    <= to_std_logic((hcpt >= 10 AND hcpt <= 53) AND -- Active + Borders
                               (vcpt >= 40 AND vcpt <= 271));
        
        dis0   <= to_std_logic((hcpt >= 12 AND hcpt <= 51) AND -- Active
                               (vcpt >= 56 AND vcpt <= 255));
        
        pos2  <= pos;
      END IF;

      IF divclk MOD 8 = 0 THEN
        -- HCPT8 : 0 à 511

        --          HCPT             HCPT8
        --                           
        --          0 : 9            0  : 79
        --         10 : 11          80  : 95     = Bord
        --         12 : 51          96  : 415    = Active
        --         52 : 53          416 : 431    = Bord

        -- HPOS  :
        --          0 :  15 = bord
        --         16 : 335 = image
        --        336 : 4


      -- HORIZONTAL : 96 : 415 = Image
      -- VERTICAL   : 56 : 255 = Image
        ovl0 <= '0';
        -- CURSOR OVERLAY
        IF (((hcpt8  >= hpos + 80 AND hcpt8 < hpos + 80 + 4) OR
             (hcpt8  <= hpos + 80 AND hcpt8 > hpos + 80 - 4)) AND
            (vcpt = vpos + 40)) OR
           (((vcpt >= vpos + 40 AND vcpt < vpos + 40 + 4) OR
             (vcpt <= vpos + 40 AND vcpt > vpos + 40 - 4)) AND 
            (hcpt8 = hpos + 80)) THEN
          ovl0 <= cursor(0) OR cursor(1);
          CASE cursor IS
            WHEN "10"   => ovr0 <= '0';  ovg0 <= '0'; ovb0 <= '0'; -- BLACK
            WHEN "11"   => ovr0 <= '1';  ovg0 <= '0'; ovb0 <= '0'; -- RED
            WHEN OTHERS => ovr0 <= '1';  ovg0 <= '1'; ovb0 <= '1'; -- WHITE
          END CASE;
        END IF;
        -- TAPE PROGRESS BAR OVERLAY
        -- Rectangle
        IF ((((vcpt  = TAPE_LINE) OR  (vcpt =  TAPE_LINE + 5))) AND (hcpt8 >= 96 + 31) AND (hcpt8 <= 96 + 31 + 257)) OR
            (((vcpt >= TAPE_LINE) AND (vcpt <= TAPE_LINE + 5))  AND ((hcpt8 = 96 + 31) OR  (hcpt8 =  96 + 31 + 257))) THEN
          ovl0 <= tbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;
        -- Motor on square
        IF ((((vcpt  = TAPE_LINE) OR  (vcpt =  TAPE_LINE + 5))) AND (hcpt8 >= 96 + 24) AND (hcpt8 <= 96 + 29)) OR
            (((vcpt >= TAPE_LINE) AND (vcpt <= TAPE_LINE + 5))  AND ((hcpt8 = 96 + 24) OR  (hcpt8 =  96 + 29))) THEN
          ovl0 <= tbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;
        -- Progress bar
        IF (vcpt >= TAPE_LINE + 1) AND (vcpt <= TAPE_LINE + 4) AND (hcpt8 >= 96 + 32) AND (hcpt8 < resize(tratio,11) + 96 + 32) THEN
          ovl0 <= tbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;
        -- Motor on 
        IF (vcpt >= TAPE_LINE + 1) AND (vcpt <= TAPE_LINE + 4) AND (hcpt8 >= 96 + 25) AND (hcpt8 < 96 + 29) THEN
          ovl0 <= NOT tmotor_n AND tbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;

        -- DISK PROGRESS BAR OVERLAY
        -- Rectangle
        IF ((((vcpt  = DISK_LINE) OR  (vcpt =  DISK_LINE + 5))) AND (hcpt8 >= 96 + 31) AND (hcpt8 <= 96 + 31 + 161)) OR
            (((vcpt >= DISK_LINE) AND (vcpt <= DISK_LINE + 5))  AND ((hcpt8 = 96 + 31) OR  (hcpt8 =  96 + 31 + 161))) THEN
          ovl0 <= dbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;
        -- Motor on square
        IF ((((vcpt  = DISK_LINE) OR  (vcpt =  DISK_LINE + 5))) AND (hcpt8 >= 96 + 24) AND (hcpt8 <= 96 + 29)) OR
            (((vcpt >= DISK_LINE) AND (vcpt <= DISK_LINE + 5))  AND ((hcpt8 = 96 + 24) OR  (hcpt8 =  96 + 29))) THEN
          ovl0 <= dbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;
        -- Position
        IF (vcpt >= DISK_LINE + 1) AND (vcpt <= DISK_LINE + 4) AND (hcpt8 = resize(dratio,11) + 32 + 96) THEN
          ovl0 <= dbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;
        -- Motor on 
        IF (vcpt >= DISK_LINE + 1) AND (vcpt <= DISK_LINE + 4) AND (hcpt8 >= 96 + 25) AND (hcpt8 < 96 + 29) THEN
          ovl0 <= dmotor AND dbaren;
          ovr0 <= '1';
          ovg0 <= '1';
          ovb0 <= '1';
        END IF;

        -- INVALID INSTRUCTION OVERLAY
        IF ((((vcpt >= EMUOP_LINE) AND (vcpt <= EMUOP_LINE + 5))) AND (hcpt8 >= 96 + 31) AND (hcpt8 <= 96 + 31 + 257)) THEN
          ovl0 <= emu_ilatch;
          ovr0 <= '1';
          ovg0 <= '0';
          ovb0 <= '0';
        END IF;
      END IF;

      IF hwreset_n='0' THEN
        hcpt <= 0;
        vcpt <= 0;
        pos  <= (OTHERS =>'0');
      END IF;
      
      -----------------------------------------------------
      -- Memory access
      CASE state IS
        WHEN sIDLE =>
          IF dis0 ='1' THEN
            state <= sREAD;
          END IF;

        WHEN sREAD =>
          vram_a(13 DOWNTO 0) <= '0' & pos2;
          vram_req <= '1';
          state <=sWAIT;
          
        WHEN sWAIT =>
          IF vram_ack ='1' THEN
            vram_req<='0';
            mem_col <= vram_dr(7 DOWNTO 0);  -- COULEUR
            mem_pix <= vram_dr(15 DOWNTO 8); -- POINT
            state   <= sEND;
          END IF;

        WHEN sEND =>
          NULL;
      END CASE;

      IF divclk=0 OR video_run='0' THEN
        state <= sIDLE;
        vram_req <= '0';
      END IF;      

      IF gen1='1' THEN
        vram_a(15 DOWNTO 14) <= "00";
      ELSE
        vram_a(15 DOWNTO 14) <= video_page;
      END IF;
            
      IF divclk=63 THEN
        dr_pix2 <= mem_col;
        dr_pix  <= mem_pix;
        IF isto(model) THEN
          -- Shuffle for TO7 compatibility
          dr_col <= NOT mem_col(6) & mem_col(5 DOWNTO 3) & NOT mem_col(7) & mem_col(2 DOWNTO 0);
        ELSE
          dr_col <= mem_col;
        END IF;
        disa <= dis0;

      END IF;

      -----------------------------------------------------
      -- Pixel draw
      -----------------------------------
      CASE video_mode(2 DOWNTO 0) IS
        ------------------------------------
        WHEN "000" => -- 40 cols 2 x 8 bits 320x200 2col [palette] 8MHz
          col<=sel_bm2(dr_col,dr_pix,divclk);
          ce <=to_std_logic(divclk MOD 8=0);
          ceh<=to_std_logic(divclk MOD 8=0);
          
        WHEN "001" => -- Bit map 4,  2 x 8 bits 320x200 4col 8MHz
          col<=sel_bm4(dr_pix2,dr_pix,divclk);
          ce <=to_std_logic(divclk MOD 8=0);
          ceh<=to_std_logic(divclk MOD 8=0);
          
        WHEN "010" => -- 80 cols 16bits 640x200 2col 16MHz
          IF model=T_TO9 THEN
            col<=sel_80c_to9(dr_pix2,dr_pix,divclk);
          ELSE
            col<=sel_80c(dr_pix2,dr_pix,divclk);
          END IF;
          ce <=to_std_logic(divclk MOD 4=0);
          ceh<=to_std_logic(divclk MOD 4=0);
          
        WHEN "011" => -- Bit map 16, 4 x 4 bits 160x200 16col 4MHz
          col<=sel_bm16(dr_pix2,dr_pix,divclk);
          ce <=to_std_logic(divclk MOD 16=0);
          ceh<=to_std_logic(divclk MOD 8=0);
          
        WHEN "100" => -- Page 1, 8bits 2col 320x200 8MHz
          col<=sel_2col(dr_pix2,divclk);
          ce <=to_std_logic(divclk MOD 8=0);
          ceh<=to_std_logic(divclk MOD 8=0);
          
        WHEN "101" => -- Page 2, 8bits 2col 320x200 8MHz
          col<=sel_2col(dr_pix,divclk);
          ce <=to_std_logic(divclk MOD 8=0);
          ceh<=to_std_logic(divclk MOD 8=0);
          
        WHEN "110" => -- Surimpression 2 x 8 bits 320x200 2col + 2c 8MHz
          col<=sel_over2(dr_pix2,dr_pix,divclk);
          ce <=to_std_logic(divclk MOD 8=0);
          ceh<=to_std_logic(divclk MOD 8=0);
          
        WHEN OTHERS => -- Surimpression 4 x 4 bits 160x200 2col +2c+2c+2c 8MHz
          col<=sel_over4(dr_pix2,dr_pix,divclk);
          ce <=to_std_logic(divclk MOD 16=0);
          ceh<=to_std_logic(divclk MOD 8=0);
          
        ------------------------------------
      END CASE;

      -- Border
      IF disa='0' AND nobord='0' THEN
        IF model = T_MO5 THEN
          col <= pia_border;
        ELSIF model = T_TO7 OR model = T_TO770 THEN
          col <= tim_border XOR "1000";
        ELSIF model = T_TO9 THEN
          col <= gmp_border XOR "1000";
        ELSE
          col <= gmp_border;
        END IF;
      END IF;

      plo<=pal_lo(to_integer(col));
      phi<=pal_hi(to_integer(col));
      
      -----------------------------------
      IF divclk = 0 THEN
        hsync <= hsync0;
        vsync <= vsync0;
        de    <= de0;
        dis   <= dis0;
      END IF;
      IF divclk MOD 8 = 0 THEN
        shl   <= shl(13 DOWNTO 0) & ovl0;
        shr   <= shr(13 DOWNTO 0) & ovr0;
        shg   <= shg(13 DOWNTO 0) & ovg0;
        shb   <= shb(13 DOWNTO 0) & ovb0;
      END IF;

      hsync2 <= hsync;
      vsync2 <= vsync;
      de2    <= de;
      dis2   <= dis;
      ce2    <= ce;
      ceh2   <= ceh;
      
      ovl2   <= shl(14);
      ovr2   <= shr(14);
      ovg2   <= shg(14);
      ovb2   <= shb(14);

      vga_hs <= hsync2;
      vga_vs <= vsync2;
      vga_de <= de2;
      vga_ce <= ce2;
      vga_ceh <= ceh2;

      col2 <= col;
      -----------------------------------
      vga_r<=plo(3 DOWNTO 0) & plo(3 DOWNTO 0);
      vga_g<=plo(7 DOWNTO 4) & plo(7 DOWNTO 4);
      vga_b<=phi(3 DOWNTO 0) & phi(3 DOWNTO 0);
      
      IF gen1='1' THEN
        ce  <= to_std_logic(divclk MOD 8=0);
        ceh <= to_std_logic(divclk MOD 8=0);
      END IF;

      IF model = T_MO5 THEN
        vga_r<=PAL_MO5_R(to_integer(col2));
        vga_g<=PAL_MO5_V(to_integer(col2));
        vga_b<=PAL_MO5_B(to_integer(col2));

      ELSIF model = T_TO7 THEN
        vga_r<=PAL_TO7_R(to_integer(col2));
        vga_g<=PAL_TO7_V(to_integer(col2));
        vga_b<=PAL_TO7_B(to_integer(col2));

      ELSIF model = T_TO770 THEN
        vga_r<=PAL_TO770_R(to_integer(col2));
        vga_g<=PAL_TO770_V(to_integer(col2));
        vga_b<=PAL_TO770_B(to_integer(col2));

      END IF;

      IF dis2='0' AND nobord='1' THEN
        vga_r <= x"00"; --border_r;
        vga_g <= x"00"; --border_g;
        vga_b <= x"00"; --border_b;
      END IF;

      -- Overlay : Lpen, Tape...
      IF ovl2='1' THEN
        vga_r <= (OTHERS => ovr2);
        vga_g <= (OTHERS => ovg2);
        vga_b <= (OTHERS => ovb2);
      END IF;
            
      -----------------------------------
    END IF;
    
  END PROCESS;

  -----------------------------------------------------------------------------
  -- Spot position for light pen
  vid_hpos  <= lp_hcpt8;
  vid_vpos  <= lp_vcpt;
  vid_ta    <= lp_pos;
  vid_h     <= to_unsigned(lp_hcpt8 MOD 8,3);

  vid_vin <= NOT to_std_logic(   -- INIT
    (lp_vcpt < 56) OR
    (lp_vcpt = 56  AND lp_hcpt < 12) OR   
    (lp_vcpt = 255 AND lp_hcpt > 53) OR
    (lp_vcpt > 255));
    
  vid_hin <= to_std_logic(lp_hcpt >= 12 AND lp_hcpt <= 53);   -- INIL

  hcptu <= to_unsigned(lp_hcpt,11) - 12;
  vid_hlr <= hcptu(3);
  

END ARCHITECTURE rtl;
