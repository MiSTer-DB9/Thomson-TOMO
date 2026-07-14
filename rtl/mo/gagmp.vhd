--------------------------------------------------------------------------------
-- Thomson MO / TO
--------------------------------------------------------------------------------
-- DO 4/2025
--------------------------------------------------------------------------------
-- MSI Chips            TO7
-- Gate Array           MO5 TO770 TO9
-- Gate Mode Page       MO6 TO8   TO9+

--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

LIBRARY work;
USE work.base_pack.ALL;
USE work.tomo_pack.ALL;

ENTITY gagmp IS
  PORT (
    -----------------------------------
    -- CPU
    ad  : IN  uv8;
    dw  : IN  uv8;
    dr  : OUT uv8;
    req : IN  std_logic;
    ack : OUT std_logic;
    wr  : IN  std_logic;

    -----------------------------------
    -- Palette
    pal_a   : OUT uv5;
    pal_dw  : OUT uv8;
    pal_dr  : IN  uv8;
    pal_wr  : OUT std_logic;
    
    -----------------------------------
    model   : IN  type_model;

    basic_mo6    : OUT std_logic; -- MO6 : Basic Select
    rambank_gmp  : OUT uv5;       -- RAM Bank
    rambank_pia  : IN  uv5;       -- RAM Bank, PIA compat mode
    cart_gmp     : OUT std_logic; -- MO6 : Show/Hide cartridge
    piabanksel   : OUT std_logic; -- 0=PIA for bank select 1=GMP
    fdd_ext      : OUT std_logic; -- TO8 / TO9+ : 0=Internal FDD controller 1=External
    cart_rambank : OUT uv5;       -- TO8 / TO9+ : Cartridge area as RAM
    cart_ram     : OUT std_logic; -- TO8 / TO9+ : Cartridge area as RAM
    cart_we      : OUT std_logic; -- TO8 / TO9+ : Cartridge area as RAM
    
    -- Video configuration
    video_mode   : OUT uv7; -- GMP
    video_page   : OUT uv2; -- GMP
    gmp_border   : OUT uv4; -- GMP
    video_trame  : OUT std_logic; -- 0=625 1=525

    -- Light Pen
    lpen_align : IN  std_logic;
    gmp_firq  : OUT std_logic;
    
    vid_ta   : IN uv13;
    vid_h    : IN uv3;
    vid_vin  : IN std_logic; -- INIT
    vid_hin  : IN std_logic; -- INIL
    vid_hlr  : IN std_logic;

    ------------------------------------
    clk     : IN std_logic;
    reset_n : IN std_logic
  );
END gagmp;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF gagmp IS

  SIGNAL l_ta : uv13;
  SIGNAL l_h : uv3;

  SIGNAL l_vin,l_hin,l_hlr : std_logic;
  SIGNAL acc_dc : std_logic;
  SIGNAL palette : boolean; -- Programmable palette
  SIGNAL gmp : boolean;     -- Gate Mode Page chip
  SIGNAL pal_rd_l, pal_wr_l : std_logic;
  SIGNAL reg_drp : uv8;
  SIGNAL read_lpreg : std_logic;
  SIGNAL ena_sys1 : std_logic;

  SIGNAL rambank_gmp_l : uv5;

  SIGNAL video_mode_l : uv7;
  SIGNAL video_page_l : uv2;
  SIGNAL pal_a_l : uv5;
  SIGNAL basic_mo6_l : std_logic;
  SIGNAL cart_gmp_l  : std_logic;
  SIGNAL cart_rambank_l : uv5;
  SIGNAL cart_ram_l : std_logic;
  SIGNAL cart_we_l  : std_logic;
  SIGNAL gmp_border_l : uv4;
  SIGNAL piabanksel_l : std_logic;

  SIGNAL lpen_align2 : std_logic;

  SIGNAL ack_l : std_logic;

  SIGNAL gmp_drp, ga_drp, palette_drp : uv8;
  SIGNAL lpen_firq, lpen_iclr : std_logic;

BEGIN
  
  ack <= ack_l;
  video_mode  <= video_mode_l;
  video_page  <= video_page_l;
  gmp_border  <= gmp_border_l;
  pal_a       <= pal_a_l;
  basic_mo6   <= basic_mo6_l;
  cart_gmp    <= cart_gmp_l;
  rambank_gmp <= rambank_gmp_l;
  piabanksel  <= piabanksel_l;

  pal_wr <= pal_wr_l;


  cart_rambank <= cart_rambank_l;
  cart_ram     <= cart_ram_l;
  cart_we      <= cart_we_l;

  gmp     <= (model = T_MO6 OR model = T_TO8 OR model = T_TO9P)                  WHEN rising_edge(clk); -- Gate Mode Page
  palette <= (model = T_MO6 OR model = T_TO8 OR model = T_TO9 OR model = T_TO9P) WHEN rising_edge(clk);

  -----------------------------------------------------------------------------
  -- PALETTE
  -- 16 couleurs => 32 entrées palette
  
  --           7     6     5     4     3     2     1     0
  -- DA     : [              PALETTE DATA                 ]
  -- DB     :  0     0     0     [    PALETTE ADRESS      ]

  palette_drp <= pal_dr          WHEN ad(7 DOWNTO 0)=x"DA" ELSE
                 "000" & pal_a_l WHEN ad(7 DOWNTO 0)=x"DB" ELSE
                 x"00";

  -----------------------------------------------------------------------------
  -- GATE MODE PAGE : MO6, TO8, TO9+
  --           7     6     5     4     3     2     1     0
  -- DC   W :  <res>  <VIDMEM>    <VIDFREQ>  < VID MODE   >

  -- DD   W : [ DISP PAGE  ] CART BASIC  < BORDER COLOUR  >
    
  -- E4 : W :  0     0     0     0     0     0     0   RSEL
  --      R :  <DISP PAGE> CART  BASIC 0     0     0     0   <= RSEL=0
  --      R :  TA12  TA11  TA10  TA9   TA8   TA7   TA6   TA5 <= RSEL=1

  -- E5 : W :  WEDC   0     0    [      RAM BANK SELECT    ]
  --      R :  0      0     0    [      RAM BANK SELECT    ]  <= RSEL=0
  --      R :  TA4    TA3   TA2   TA1  TA0   H1    H2    H4   <= RSEL=1

  -- E6   W :  0      WP   RAM  [    RAM BANK SELECT CART  ]
  --      R :  ??? <= RSEL=0
  --      R :  L_LT3  L_INIL

  -- E7   W :  EXTFDD <res> M525  PIAS  <MODEL  >  <RAMTYPE >
  --      R :  /INIT   /L_INIT /INIL  0     0    0   LPEN  LPREG
  --           vertical

  gmp_drp<='0' & video_mode_l
             WHEN ad(7 DOWNTO 0)=x"DC" ELSE -- Lecture Seule ????

           video_page_l & cart_gmp_l & basic_mo6_l & gmp_border_l -- Lecture Seule ????
             WHEN ad(7 DOWNTO 0)=x"DD" ELSE

           mux(read_lpreg,
             l_ta(12 DOWNTO 5),
             video_page_l & cart_gmp_l & basic_mo6_l & "0000")
             WHEN ad(7 DOWNTO 0)=x"E4" ELSE

           mux(read_lpreg,
             l_ta(4 DOWNTO 0) & l_h,
             "000" & rambank_gmp_l)
             WHEN ad(7 DOWNTO 0)=x"E5" ELSE

           mux(read_lpreg,
             l_hlr & l_hin & "000000",
             '0' & cart_we_l & cart_ram_l & cart_rambank_l)
             WHEN ad(7 DOWNTO 0)=x"E6" ELSE

           mux(read_lpreg,
              vid_vin &   l_vin & vid_hin & "000" & lpen_firq & read_lpreg,
              vid_vin & vid_vin & vid_hin & "000" & lpen_firq & read_lpreg)
             WHEN ad(7 DOWNTO 0)=x"E7" ELSE

           x"00";

  -----------------------------------------------------------------------------
  -- GATE ARRAY : MO5, TO770, TO9
  --           7     6     5     4     3     2     1     0

  -- E4 : W :  0     0     0     0     0     0     0   RSEL
  --      R :  T12   T11   T10   T9    T8    T7    T6   T5

  -- E5 : W :  WEDC   0     0    [      RAM BANK SELECT    ]
  --      R :  TA4    TA3   TA2   TA1  TA0   H1    H2    H4

  -- E6   W :  0      WP   RAM  [    RAM BANK SELECT CART  ]
  --      R :  L_LT3  /L_INIL   0    0    0    0    0    0

  -- E7   W :  EXTFDD <res> M525  PIAS  <MODEL  >  <RAMTYPE >
  --      R :  /INIT  /L_INIT   0    0    0    0    0    1

  ga_drp<=l_ta(12 DOWNTO 5)           WHEN ad(7 DOWNTO 0)=x"E4" ELSE
          l_ta(4 DOWNTO 0) & l_h      WHEN ad(7 DOWNTO 0)=x"E5" ELSE
          l_hlr & l_hin    & "000000" WHEN ad(7 DOWNTO 0)=x"E6" ELSE
          vid_vin & l_vin  & "000001" WHEN ad(7 DOWNTO 0)=x"E7" ELSE
          x"00";

  -----------------------------------------------------------------------------

  reg_drp <= mux(palette,palette_drp,x"00") OR mux(gmp,gmp_drp,ga_drp);

  dr<=reg_drp WHEN ack_l='1' AND rising_edge(clk);

-- VIN   :                              : 0=Top or bottom of screen  1=In screen vertical
-- HIN   :                              : 0=Left or right border     1=In screen² horizontal
-- L_HLR : Latched on lightpen position : 0=Left of screen           1=Right of screen²
-- L_HIN : Latched on lightpen position : 0=Left or right border     1=In screen horizontal
-- L_VIN : Latched on lightpen position : 0=Top or bottom of screen  1=In screen vertical

-- INILN / INITN = Inhibition ligne/trame, logique négative => 1=Zone affichée

  -----------------------------------------------------------------------------
  ack_l <= req;

  PROCESS (clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      -----------------------------------------------------
      lpen_align2 <= lpen_align;

      IF lpen_align='1' AND lpen_align2='0' THEN
        l_ta  <= vid_ta;
        l_h   <= vid_h;
        l_hin <= vid_hin;
        l_vin <= vid_vin;
        l_hlr <= vid_hlr;
      END IF;
      
      lpen_iclr <= to_std_logic(ad=x"E5" AND ack_l='1' AND wr='0' AND read_lpreg='1');
      
      IF lpen_align='1' AND lpen_align2='0'  AND read_lpreg='1' THEN
        lpen_firq <= '1';
      ELSIF lpen_iclr='1' THEN
        lpen_firq <= '0';
      END IF;

      gmp_firq <= lpen_firq;

      -----------------------------------------------------
      IF ad=x"DA" AND wr='1' AND ack_l='1' THEN
        -- Palette Data
        pal_dw<=dw;
      END IF;

      pal_wr_l<=to_std_logic(ad=x"DA" AND wr='1' AND ack_l='1');
      pal_rd_l<=to_std_logic(ad=x"DA" AND wr='0' AND ack_l='1');

      IF pal_wr_l='1' OR pal_rd_l='1' THEN
        pal_a_l <= pal_a_l + 1;
      END IF;

      IF ad=x"DB" AND wr='1' AND ack_l='1' THEN
        -- Palette Address
        pal_a_l <= dw(4 DOWNTO 0);
      END IF;

      IF ad=x"DC" AND wr='1' AND ack_l='1' AND acc_dc='0' THEN -- "AFFICHAGE"
        --  Video modes
        video_mode_l <= dw(6 DOWNTO 0);
      END IF;

      IF ad=x"DD" AND wr='1' AND ack_l='1' THEN -- "SYSTEME 2"
        -- TODO : Alias floppy controller
        gmp_border_l   <= dw(3 DOWNTO 0); -- Border colour : TO9 + TO8 + TO9+
        basic_mo6_l    <= dw(4); -- 0=Basic 1 1=Basic 128 : MO6
        cart_gmp_l     <= dw(5); -- Cartrdige mapping     : Pour TO9+ et MO6, pas TO8
        video_page_l   <= dw(7 DOWNTO 6); -- Video page 0...3
      END IF;

      -----------------------------------------------------
      IF ad=x"E4" AND wr='1' AND ack_l='1' THEN
        read_lpreg <= dw(0); -- Reg. read select / LPEN interrupt enable
      END IF;
      
      IF ad=x"E5" AND wr='1' AND ack_l='1' THEN
        IF piabanksel_l='1' THEN
          rambank_gmp_l <= dw(4 DOWNTO 0); -- Ram bank 0..5 on MO6, 0..31 on TO8/9+
        END IF;
        acc_dc        <= dw(7); -- Enable access to A7DC regs.
      END IF;

      IF ad=x"E6" AND wr='1' AND ack_l='1' THEN
        cart_rambank_l <= dw(4 DOWNTO 0);
        cart_ram_l     <= dw(5); -- Enable RAM mapping in cartridge area
        cart_we_l      <= dw(6); -- Write Enable in cartridge area
      END IF;

      IF ad=x"E7" AND wr='1' AND ack_l='1' THEN  -- "SYSTEME 1"
        piabanksel_l <= dw(4); -- PIA / GMP RAM BANK SELECT
        video_trame  <= dw(5); -- 625 / 525
        fdd_ext      <= dw(7); -- TO8 : 0=Internal FDD 1=External FDD/QDD
      END IF;

      -----------------------------------------------------
      IF reset_n='0' THEN
        gmp_border_l  <= "0000";
        rambank_gmp_l  <= "00000";
        cart_rambank_l <= "00000";
        acc_dc        <= '0';
        video_mode_l  <= "0000000";
        video_page_l  <= "00";
        read_lpreg    <= '0';
        piabanksel_l  <= '0';
        basic_mo6_l   <= '0';
        cart_gmp_l    <= '0';
        video_trame   <= '0';
        fdd_ext       <= '0';
        l_vin         <= '0';
        lpen_firq     <= '0';
        gmp_firq      <= '0';
      END IF;

      -----------------------------------------------------      
    END IF;
  END PROCESS;


END ARCHITECTURE rtl;




-- 
-- ===========================================================
-- A7DD WRITE Systeme 2
-- 
-- 7   6   5   4   3   2   1   0
-- ^   ^                         Page écran    (MO6, TO9+, )
--         ^                     Masquage cartouche, mode MO 0=Visible, 1=Masquée
--             ^                 Sélection BASIC 1 / 128 (MO6)
--                 ^   ^   ^   ^ Couleur tour
-- 
--                 
-- ===========================================================
-- A7E4 WRITE Crayon Optique
-- 
-- 7   6   5   4   3   2   1   0
--                             ^ Sélection lecture 1=Crayon optique 0=Traitement : READ_LPREG
-- 
--      READ Systeme 2 (READ_LPREG=0)
-- 
-- ^   ^                         Numéro page écran
--         ^                     Masquage cartouche, mode MO 0=Visible, 1=Masquée
--             ^                 Sélection BASIC 1 / 128 (MO6)
--                 0   0   0   0
-- 
-- 
--      READ Crayon Optique 1 (READ_LPREG=1)
-- T12 T11 T10 T9  T8  T7  T6  T5 Position crayon optique
-- 
-- ===========================================================
-- A7E5 WRITE RAM DONNEES (SI Systeme1(D4)=1 ))
-- 
-- 7   6   5   4   3   2   1   0
-- ^                             Autorisation accès A7DC si D7 A7E7 = 1
--     0   0                     "00"
--             ^   ^   ^   ^   ^ Numéro de page RAM si mode GAGMP
-- 
--     READ (READ_LPREG=0)
-- 0   0   0   ^   ^   ^   ^   ^ Numéro de page RAM si mode GAGMP
-- 
--      READ Crayon Optique 2 (READ_LPREG=1)
-- T4  T3  T2  T1  T0  E   H2  H4 Position crayon optique
-- 
-- 
-- ===========================================================
-- A7E6 WRITE Cartouche
-- 
-- 7   6   5   4   3   2   1   0
-- 0
--     ^                          Protection en écriture page RAM 1=Ecriture autorisée
--         ^                      RAM zone cartouche
--             ^   ^   ^   ^   ^  Numéro de page RAM espace cartouche
-- 
--      READ (READ_LPREG=0)           > Relecture à l'identique
--      READ Crayon Optique 3 (READ_LPREG=1)
-- ^                              0=A gauche 1=A droite
--     ^                          INILN    LATCH  1=Zone affichage
--         0   0   0   0   0   0
-- 
-- 
-- ===========================================================
-- A7E7 WRITE Système 1
-- 
-- 7   6   5   4   3   2   1   0
-- ^                             Contrôleur disque : 0=Interne 1=Externe
--     ^                         RAM espace cartouche 0= Compatible Nanoréseau 1= Registre A7E6
--         ^                     Affichage 0=625 1=525
--             ^                 RAM dans espace données 0=PIA (émulation) 1= Ecriture registre A7E5
--                 ^   ^         Type ordinateur MO/TO9/TO
--                         ^   ^ Type DRAM
--      READ Crayon Optique 4
-- ^                             INITN En direct
--     ^                         INITN LATCH
--         ^                     INILN LATCH
--             0   0   0
--                         ^     Interruption FIRQN
--                             ^ Copie READ_LPREG
-- 
-- ===========================================================
