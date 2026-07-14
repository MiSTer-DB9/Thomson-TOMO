--------------------------------------------------------------------------------
-- Thomson MO / TO
--------------------------------------------------------------------------------
-- DO 4/2025
--------------------------------------------------------------------------------
-- DECODE

--------------------------------------------------------------------------------


LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

LIBRARY work;
USE work.base_pack.ALL;
USE work.tomo_pack.ALL;

ENTITY decode IS
  PORT (
    ---------------------------------------------
    -- CPU
    ad    : IN uv16;
    dw    : IN uv8;
    wr    : IN std_logic;
    req   : IN std_logic;

    ---------------------------------------------
    -- DECODE outputs
    sel    : OUT enum_sel;  -- mselect Area
    mad    : OUT uv20;      -- RAM ADRS
    mwr    : OUT std_logic; -- Enable write mem / not RO

    ---------------------------------------------
    model       : IN type_model;
    
    to_forme      : IN std_logic; -- VRAM mselect forme/couleurs
    mo_forme      : IN std_logic; -- VRAM mselect forme/couleurs
    rambank_gmp   : IN uv5;       -- RAM BANK
    basic_mo6     : IN std_logic; -- 0=BASIC1 1=BASIC128 : MO6 seulement
    cart_gmp      : IN std_logic; -- Show/Hide cartridge
    rombank_mo6   : IN std_logic;
    rambank_pia   : IN uv5;       -- TO770 + TO9 : PIA PB[7:3], emulation TO8/TO9+

    cart_rambank : IN uv5;
    cart_ram     : IN std_logic;
    cart_we      : IN std_logic;
    cart_to89p   : IN std_logic;
    cart_size    : IN uv2; -- 00=16k 01=32k 11=64k
    cart_loaded  : IN std_logic;
    monsel_to89p : IN std_logic;
    slot_to9     : IN uv2;
    
    piabanksel   : IN std_logic;  -- 0=RAM BANK From PIA (emulate TO770, TO9) 1=GMP
    reset_n      : IN std_logic;
    clk          : IN std_logic

    ---------------------------------------------
  );
END ENTITY decode;

-- MAD : 
-- 512 M RAM  0 xxx xxxx xxxx xxxx xxxx
-- 256 M ROM  1 0xx xxxx xxxx xxxx xxxx
-- 256 M cart_gmp 1 1xx xxxx xxxx xxxx xxxx

ARCHITECTURE rtl OF decode IS

  SIGNAL rombank_to    : uv2;
  SIGNAL cartbank : uv2; -- MEMO7 bank

  CONSTANT ZERO14 : uv14 := "00000000000000";

BEGIN

  ToSelection:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      ---------------------------------
      -- Bascule D sélection chip ROM : TO8 & TO9 & TO9+
      IF ad < x"2000" AND wr='1' AND req='1' THEN
        rombank_to <= ad(1 DOWNTO 0);
      END IF;
      -- Zone 2000-3FFF ???

      ---------------------------------
      -- Commutation banques cartouches
      IF model = T_MO5 OR model = T_MO6 THEN
        -- Ecriture $BFFC-$BFFF : Commutation page cartouche
        -- Lecture seule ???
        IF cart_size="01" AND (cart_gmp='0' OR model = T_MO5) AND ad >=x"BFFC" AND ad < x"C000" AND req='1' AND wr='0' THEN
          -- MEMO5 32k
          cartbank <= ad(1 DOWNTO 0);
        END IF;
        IF cart_size="11" AND ad = x"A7CB" AND req='1' AND wr='1' THEN 
          -- MEMO5 64k : JANE "Utilise le même système de commutation que l'extension mémoire 64K, par l'octet $A7CB"
          cartbank <= dw(1 DOWNTO 0); --   b0-b1 Numéro de banque (0, 1, 2 ou 3)
        END IF;

      ELSIF model = T_TO7 OR model = T_TO770 OR model = T_TO9 THEN
        -- Écriture 0x0 ... 0xx3 : Commutation banque cartouche
        IF ad < x"0004" AND wr='1' AND req='1' THEN
          cartbank <= ad(1 DOWNTO 0);
        END IF;

      ELSIF model = T_TO8 OR model = T_TO9P THEN
        IF ad < x"0004" AND wr='1' AND req='1' AND cart_ram='0' AND cart_to89p='0' THEN
          cartbank <= ad(1 DOWNTO 0);
        END IF;
      END IF;
      ---------------------------------
      IF reset_n='0' THEN 
        rombank_to <= "00";
        cartbank   <= "00";
      END IF;
    END IF;
  END PROCESS ToSelection;

  Decodus:PROCESS(ad,wr,model,
            mo_forme, rambank_gmp, basic_mo6, rombank_mo6, 
            cart_gmp, cartbank, cart_loaded, piabanksel,
            to_forme, rambank_pia, 
            cart_ram, cart_rambank, cart_to89p, cart_we, rombank_to, monsel_to89p, slot_to9) IS
    BEGIN
      ---------------------------------
      sel <= NOSEL;
      mad <= "0000" & ad;
      mwr <= wr;

      ---------------------------------
      CASE model IS

        ---------------------------------------------------
        WHEN T_MO5 =>
          IF ad < x"2000" THEN
            -- RAM ECRAN 8k : 2 pages de 8k : forme / col
            mad <= "000000" & mo_forme & ad(12 DOWNTO 0);
            sel <= RAM;

          ELSIF ad < x"A000" THEN
            -- 2000:5FFF : RAM 16k
            -- 6000:9FFF : EXTENSION RAM 16k
            mad <= resize(ad - 16#2000#,20) + ("000001" & ZERO14);
            sel <= RAM;

          ELSIF ad < x"A7C0" THEN
            -- Moniteur Contrôleur Disque
            sel <= ROM_THMFC1;

          ELSIF ad < x"A7C4" THEN
            -- PIA 6821 : KBD + Tape + LPEN
            sel <= PIA_MO;

          ELSIF ad < x"A7CC" THEN
            -- FREE
            sel <= NOSEL;

          ELSIF ad < x"A7D0" THEN
            -- PIA Extension Musique / Jeux
            sel <= PIA_JEUX;

          ELSIF ad < x"A7E0" THEN
            -- FDD
            sel <= FDD_THMFC1;

          ELSIF ad < x"A7E4" THEN
            -- PIA 6821. Parallel/Centronics option
            sel <= NOSEL;

          ELSIF ad < x"A7E8" THEN
            -- Gate Array / Lignt Pen
            sel <= GAGMP;

          ELSIF ad < x"A800" THEN
            -- FREE. Extension PIA / ACIA
            sel <= NOSEL;

          ELSIF ad < x"B000" THEN
            -- A800:AFFF : FREE
            sel <= NOSEL;

          ELSIF ad < x"C000" THEN
            -- B000:EFFF : Cartouche 16k
            -- Sélection automatique si cartouche enfoncée : "PRCART"
            IF cart_loaded='1' THEN
              mad <= BASE_CART + (ad(13 DOWNTO 0) + "01000000000000") + (cartbank & ZERO14);
              sel <= CARTO;
              mwr <= '0';
            END IF;
          ELSE
            -- ROM : BASIC 12k + SYSTEM MONITOR 4k
            mad <= BASE_ROM + ad(13 DOWNTO 0);
            sel <= ROM;
            mwr <= '0';

            IF cart_loaded='1' AND ad < x"F000" THEN
              mad <= BASE_CART + (ad(13 DOWNTO 0) + "01000000000000") + (cartbank & ZERO14);
              sel <= CARTO;
            END IF;
          END IF;

        ---------------------------------------------------
        WHEN T_MO6 =>
          IF ad < x"2000" THEN
            -- RAM ECRAN 16k : 2 pages de 8k : forme / col
            -- 000x xxxx xxxx xxxx 8k COLO
            -- 001x xxxx xxxx xxxx 8k POINT
            mad <= "000000" & mo_forme & ad(12 DOWNTO 0);
            sel <= RAM;
               
          ELSIF ad < x"6000" THEN
            -- RAM 16k
            --  0010 xxxx xxxx xxxx xxxx : 2000
            --  0011 xxxx xxxx xxxx xxxx : 3000
            --  0100 xxxx xxxx xxxx xxxx : 4000
            --  0101 xxxx xxxx xxxx xxxx : 5000
            mad <= "000001" & (ad(13 DOWNTO 0) - 16#2000#);
            sel <= RAM;

          ELSIF ad < x"A000" THEN
            -- EXTENSION 6 * 16k
            --  0110 xxxx xxxx xxxx xxxx : 6000
            --  0111 xxxx xxxx xxxx xxxx : 7000
            --  1000 xxxx xxxx xxxx xxxx : 8000
            --  1001 xxxx xxxx xxxx xxxx : 9000
            mad <= x"08000" + resize(ad - 16#6000#,20) + (rambank_gmp(2 DOWNTO 0) & ZERO14);
            sel <= RAM;
            IF rambank_gmp < 4 THEN
              sel <= RAM;
            END IF;

          ELSIF ad < x"A7C0" THEN
            -- Moniteur Contrôleur Disque
            sel <= ROM_THMFC1;
            -- <TODO> Option activation FDD MO5

          ELSIF ad < x"A7C4" THEN
            -- PIA 6821 : KBD + Tape + LPEN
            sel <= PIA_MO;

          ELSIF ad < x"A7CC" THEN
            -- FREE
            sel <= NOSEL;

          ELSIF ad < x"A7D0" THEN
            -- PIA Extension Musique / Jeux
            sel <= PIA_JEUX;

          ELSIF ad < x"A7DA" THEN
            -- Disk Controller
            sel <= FDD_THMFC1;

          ELSIF ad < x"A7DE" THEN
            -- Gate Mode Page
            sel <= GAGMP;

          ELSIF ad < x"A7E4" THEN
            -- Free
            sel <= NOSEL;

          ELSIF ad < x"A7E8" THEN
            -- Gate Mode Page
            sel <= GAGMP;

          ELSIF ad < x"A7EC" THEN
            -- RF90932
            sel <= NOSEL;

          ELSIF ad < x"A7F0" THEN
            -- FREE
            sel <= NOSEL;

          ELSIF ad < x"A7F8" THEN
            -- IEEE Extension
            sel <= NOSEL;

          ELSIF ad < x"B000" THEN
            -- FREE
            sel <= NOSEL;

          ELSE
            -- 80000 = BASIC 1     BANK 1 : C000:EFFF : 12k
            -- 83000 = MONITOR     BANK 1 : F000:FFFF : 4k
            -- 84000 = BASIC 1     BANK 0 : C000:EFFF : 12k
            -- 87000 = MONITOR     BANK 0 : F000:FFFF : 4k
            -- 88000 = BASIC 128   BANK 1 : B000:EFFF : 16k
            -- 8C000 = BASIC 128   BANK 0 : B000:EFFF : 16k
            -- Cartouche                  : B000:EFFF : 16k
            -- Inverted bank select signal in ROM DUMP ?
            IF basic_mo6 = '0' THEN
              -- BASIC 1 + MONITOR C000:FFFF
              -- Aliasing monitor  B000:BFFF ???
              sel <= ROM;
              mad <= BASE_ROM + mux(rombank_mo6,x"4000",x"0000") + ad(13 DOWNTO 0);
            ELSE 
              IF ad < x"F000" THEN
                -- BASIC 128 B000:EFFF
                sel <= ROM;
                mad <= BASE_ROM + x"8000" + mux(rombank_mo6,x"4000",x"0000") + (ad(13 DOWNTO 0) + "01000000000000");
              ELSE
                -- MONITOR F000:FFFF
                sel <= ROM;
                mad <= BASE_ROM + mux(rombank_mo6,x"4000",x"0000") + ad(13 DOWNTO 0);
              END IF;
            END IF;
            -- Cartridge
            IF cart_gmp='0' AND ad >=x"B000" AND ad < x"F000" THEN
              mad <= BASE_CART + (ad(13 DOWNTO 0) + "01000000000000") + (cartbank & ZERO14);
              sel <= CARTO;
            END IF;
            mwr <= '0'; -- Read-only

          END IF;

        ---------------------------------------------------
        WHEN T_TO7 =>
          IF ad < x"4000" THEN
            -- MEMO7 Cartridge
            mad <= BASE_CART + ad(13 DOWNTO 0) + (cartbank & ZERO14);
            sel <= CARTO;
            mwr <= '0';
            
          ELSIF ad < x"6000" THEN
            -- Video RAM
            mad <=  "000000" & to_forme & (ad(12 DOWNTO 0));
            sel <= RAM;

          ELSIF ad < x"C000" THEN
            -- RAM 8k + EXTENSION 16k
            mad <= resize(ad - 16#6000#,20) + x"4000";
            sel <= RAM;

          ELSIF ad < x"E000" THEN
            -- RAM / UNUSED
            sel <= NOSEL;

          ELSIF ad < x"E7C0" THEN
            -- Moniteur Contrôleur Disque
            sel <= ROM_THMFC1;

          ELSIF ad < x"E7C8" THEN
            -- MC6846 Timer/PIA/ROM
            sel <= TIM;

          ELSIF ad < x"E7CC" THEN
            sel <= PIA_TO;

          ELSIF ad < x"E7D0" THEN
            sel <= PIA_JEUX;

          ELSIF ad < x"E7E0" THEN
            -- Contrôleur disque
            sel <= FDD_THMFC1;

          ELSIF ad < x"E800" THEN
            -- Série, parallèle...
            sel <= NOSEL;

          ELSE
            -- ROM Système - Moniteur 
            sel <= ROM;
            mad <= BASE_ROM + ad - x"E800";
            mwr <= '0';
          END IF;

        ---------------------------------------------------
        WHEN T_TO770 =>
          -- RAM : Ecran : 2*8k   00000 01FFF  02000 03FFF
          --       BASE  ; 16k    04000 07FFF
          --       PAGES : 6*16k  08000 0BFFF .... 
          IF ad < x"4000" THEN
            -- MEMO7 Cartridge
            mad <= BASE_CART + ad(13 DOWNTO 0) + (cartbank & ZERO14);
            sel <= CARTO;
            mwr <= '0';

          ELSIF ad < x"6000" THEN
            -- Video RAM 2 * 8k
            mad <=  "000000" & to_forme & (ad(12 DOWNTO 0));
            sel <= RAM;

          ELSIF ad < x"A000" THEN
            -- RAM 16k
            mad <= resize(ad - 16#6000#,20) + x"4000";
            sel <= RAM;

          ELSIF ad < x"E000" THEN
            -- Paged RAM : 2*16k base  [+4*16k extension option]

            --      PSHS D,X,U      
            --      LDU  #$E7C0     
            --      LDB  11,U       
            --      ANDB #$FB       
            --      STB  1,U        E7CB &= 0xFB => Sélection Data Direction
            --      LDX  #TAB       
            --      LDA  A,X        
            --      STA  9,U        E7C9 = TAB[A]
            --      ORB  #$04       
            --      STB  11,U       E7CB |= 4 => Sélection Output Reg
            --      PULS D,X,U,PC   
            --
            --  TAB:
            --      EQU $0F
            --      EQU $17
            --      EQU $E7
            --      EQU $67
            --      EQU $A7
            --      EQU $27
            --  Collecteur ouvert, pullups => Logique négative.
            
            -- PB7:3
            -- 11110   Bank 0         
            -- 11101   Bank 1         
            -- 00011   Bank 2 (option)
            -- 10011   Bank 3 (option)
            -- 01011   Bank 4 (option)
            -- 11011   Bank 5 (option)
            sel <= RAM;
            CASE rambank_pia IS
              -- <TODO> Vérifier inversion 10011 / 01011 TO770 / TO9 !!
              WHEN "11110" => mad <= resize(ad - 16#A000#,20) + x"08000"; -- Bank 0
              WHEN "11101" => mad <= resize(ad - 16#A000#,20) + x"0C000"; -- Bank 1
              WHEN "00011" => mad <= resize(ad - 16#A000#,20) + x"10000"; -- Bank 2 (extension 64k)
              WHEN "10011" => mad <= resize(ad - 16#A000#,20) + x"14000"; -- Bank 3 (extension 64k)
              WHEN "01011" => mad <= resize(ad - 16#A000#,20) + x"18000"; -- Bank 4 (extension 64k)
              WHEN "11011" => mad <= resize(ad - 16#A000#,20) + x"1C000"; -- Bank 5 (extension 64k)
              WHEN OTHERS  => mad <= resize(ad - 16#A000#,20) + x"08000"; -- Invalid. No map ?
                              sel <= NOSEL;
            END CASE;

          ELSIF ad < x"E7C0" THEN
            -- Moniteur Contrôleur Disque
            sel <= ROM_THMFC1;

          ELSIF ad < x"E7C8" THEN
            -- MC6846 Timer/PIA/ROM
            sel <= TIM;

          ELSIF ad < x"E7CC" THEN
            sel <= PIA_TO;

          ELSIF ad < x"E7D0" THEN
            sel <= PIA_JEUX;

          ELSIF ad < x"E7E0" THEN
            -- Contrôleur disque
            sel <= FDD_THMFC1;

          ELSIF ad < x"E7E4" THEN
            -- Série, parallèle...
            sel <= NOSEL;

          ELSIF ad < x"E7E8" THEN
            sel <= GAGMP;

          ELSIF ad < x"E800" THEN
            -- Teletel, libre ...
            sel <= NOSEL;

          ELSE
            -- ROM Système - Moniteur 
            sel <= ROM;
            mad <= BASE_ROM + ad - x"E800";
            mwr <= '0';
          END IF;

        ---------------------------------------------------
        WHEN T_TO9 =>
          -- ROM : 136k
          -- 32k ROM Basic 128 / Extra Monitor     00000
          -- 32k ROM Basic 1 / DOS Iconique        08000
          -- 32k ROM Paragraphe                    10000
          -- 32k ROM Fiches et Dossiers            18000
          --  8k Monitor    E000 ... FFFF

          -- [16k/64k cartridge]
 
          -- SLOT = PP(5:0)  LATCH A[1]
          --  00                   0        BASIC1
          --  00                   1        BASIC128
          --  01                   0        FICHES
          --  01                   1        
          --  10                   0        PARAG
          --  10                   1        
          --  11                            CARTRIGNE

          -- 136k = 128 + 8 k
          --  0000 : 1FFF   = 8k
          --  2000 : 11FFFF = 64k = BAsIC 1/128
          -- 12000 : 19FFFF = 64k = Paragraphe / Fiches
          -- A0 = HI/LO 32k
          IF ad < x"4000" THEN
            -- Cartridge / ROM : 4 * 16k
            sel <= ROM;
            mwr <= '0';

            CASE slot_to9 IS
              WHEN "00" =>
                mad <= BASE_ROM + (rombank_to & ad(13 DOWNTO 0)); --  BASIC 1 / 128
              WHEN "01" =>
                mad <= BASE_ROM + (rombank_to(0) & ad(13 DOWNTO 0)) + x"10000"; -- PARAG
              WHEN "10" =>
                mad <= BASE_ROM + (rombank_to(0) & ad(13 DOWNTO 0)) + x"18000"; -- FICHES
              WHEN OTHERS =>
                mad <= BASE_CART + ad(13 DOWNTO 0); -- CARTOUCHE
                sel <= CARTO;
            END CASE;

          ELSIF ad < x"6000" THEN
            -- Video RAM 2 * 8k
            mad <=  "000000" & to_forme & (ad(12 DOWNTO 0));
            sel <= RAM;

          ELSIF ad < x"A000" THEN
            -- RAM 16k
            mad <= resize(ad - 16#6000#,20) + x"4000";
            sel <= RAM;

          ELSIF ad < x"E000" THEN
            sel <= RAM;
            CASE rambank_pia IS
              WHEN "11110" => mad <= resize(ad - 16#A000#,20) + x"08000"; -- Bank 0
              WHEN "11101" => mad <= resize(ad - 16#A000#,20) + x"0C000"; -- Bank 1
              WHEN "00011" => mad <= resize(ad - 16#A000#,20) + x"10000"; -- Bank 2
              WHEN "10011" => mad <= resize(ad - 16#A000#,20) + x"14000"; -- Bank 3
              WHEN "01011" => mad <= resize(ad - 16#A000#,20) + x"18000"; -- Bank 4
              WHEN "11011" => mad <= resize(ad - 16#A000#,20) + x"1C000"; -- Bank 5
              WHEN OTHERS  => mad <= resize(ad - 16#A000#,20) + x"08000"; -- Invalid. No map ?
                              sel <= NOSEL;
            END CASE;

          ELSIF ad < x"E7B0" THEN
            -- Moniteur Contrôleur Disque FLOPPY/QDD
            sel <= ROM;
            mwr <= '0';
            mad <= BASE_ROM + ad - x"E000" + x"20000";
            
          ELSIF ad < x"E7C0" THEN
            -- Free
            sel <= NOSEL;

          ELSIF ad < x"E7C8" THEN
            -- TIMER 6846
            sel <= TIM;
          
          ELSIF ad < x"E7CC" THEN
            -- PIA 6821 SYS/PRINT
            sel <= PIA_TO;

          ELSIF ad < x"E7D0" THEN
            sel <= PIA_JEUX;

          ELSIF ad < x"E7DA" THEN
            sel <= NOSEL; -- Floppy TO9
            
          ELSIF ad < x"E7DE" THEN
            sel <= GAGMP;

          ELSIF ad < x"E7E0" THEN
            -- ACIA 6850
            sel <= ACIA;
            
          ELSIF ad < x"E7E8" THEN
            sel <= GAGMP;

          ELSIF ad < x"E800" THEN
            -- RS232, IEEE, MODEM Option
            sel <= NOSEL;
            
          ELSE
            -- Moniteur Contrôleur Disque FLOPPY/QDD
            sel <= ROM;
            mwr <= '0';
            mad <= BASE_ROM + ad - x"E000" + x"20000";
            
          END IF;

        ---------------------------------------------------
        WHEN T_TO8 | T_TO9P =>
          -- RAM : Ecran : 2*8k   00000 01FFF  02000 03FFF (page 0)
          --       BASE  : 16k    04000 07FFF              (page 1)
          --       PAGES :        08000 0BFFF ....         (pages 2 ... 31)

          -- 32k ROM Basic 1 & DOS iconique
          -- 32k ROM Basic 512
          -- 16k ROM Moniteur et Gestion Disque

          -- ROM TO8
          --  0000 :  3FFF 16k = BASIC 512
          --  4000 :  7FFF 16k = EXTRAMON
          --  8000 :  BFFF 16k = BASIC 1
          --  C000 :  FFFF 16k = EXPL
          -- 10000 : 11FFF  8k = MONITOR 1
          -- 12000 : 13FFF  8k = MONITOR 2
          

          -- ROM : x0000 ...        = BASIC 512 Microsoft 1.0    16k
          -- ROM : x4000 ... x7FFF  = BASIC 512 Microsoft 1.0    16k
          -- ROM : x8000 ... xBFFF  = BASIC Microsoft 1.0        16k
          -- ROM : xC000 ... x13FFF = "Exploitation de fichiers" 32k
          
          -- A13 = 0
          -- A0 : Page basic 2*16k : hi/lo
          -- A1 : Sélection basic 1 / 512

          IF ad < x"4000" THEN
            IF cart_ram='1' THEN
              -- RAM in Cartridge area. 8k blocs swapped.
              mad <=  "0" & cart_rambank & NOT ad(13) & ad(12 DOWNTO 0);
              sel <= RAM;
              IF cart_we='0' THEN
                mwr <= '0';
              END IF;

            ELSIF cart_to89p='0' THEN
              -- Cartridge
              mad <= BASE_CART + (rombank_to & ZERO14) + ad(13 DOWNTO 0);
              sel <= ROM;
              mwr <= '0';
            ELSE
              -- BASIC
              mad <= BASE_ROM + (rombank_to & ad(13 DOWNTO 0));
              sel <= ROM;
              mwr <= '0';
            END IF;

          ELSIF ad < x"6000" THEN
            -- Video RAM 2 * 8k (page 0)
            mad <=  "000000" & to_forme & (ad(12 DOWNTO 0));
            sel <= RAM;

          ELSIF ad < x"A000" THEN
            -- RAM 16k (page 1)
            mad <= resize(ad - 16#6000#,20) + x"4000";
            sel <= RAM;

          ELSIF ad < x"E000" THEN
            sel <= RAM;
            IF piabanksel='0' THEN
              -- PIA mode, TO770/TO9 emulation on TO8/TO9+
              CASE rambank_pia IS
                WHEN "11110" => mad <= resize(ad - 16#A000#,20) + x"08000"; -- Bank 0 => 2
                WHEN "11101" => mad <= resize(ad - 16#A000#,20) + x"0C000"; -- Bank 1 => 3
                WHEN "00011" => mad <= resize(ad - 16#A000#,20) + x"10000"; -- Bank 2 => 4
                WHEN "01011" => mad <= resize(ad - 16#A000#,20) + x"14000"; -- Bank 3 => 5
                WHEN "10011" => mad <= resize(ad - 16#A000#,20) + x"18000"; -- Bank 4 => 6
                WHEN "11011" => mad <= resize(ad - 16#A000#,20) + x"1C000"; -- Bank 5 => 7
                WHEN OTHERS  => mad <= resize(ad - 16#A000#,20) + x"08000"; -- Invalid. No map ?
                                sel <= NOSEL;
              END CASE;

            ELSE
              -- GMP mode
              mad <= resize(ad - 16#A000#,20) + (rambank_gmp & ZERO14);
            END IF;

          ELSIF ad < x"E7B0" THEN
            -- Moniteur Contrôleur Disque FLOPPY/QDD
            sel <= ROM;
            mwr <= '0';
            IF monsel_to89p='0' THEN
              mad <= BASE_ROM + ad - x"E000" + x"10000";
            ELSE
              mad <= BASE_ROM + ad - x"E000" + x"12000";
            END IF;

          ELSIF ad < x"E7C0" THEN
            -- Free
            sel <= NOSEL;

          ELSIF ad < x"E7C8" THEN
            -- TIMER 6846
            sel <= TIM;
          
          ELSIF ad < x"E7CC" THEN
            -- PIA 6821 SYS/PRINT
            sel <= PIA_TO;

          ELSIF ad < x"E7D0" THEN
            sel <= PIA_JEUX;

          ELSIF ad < x"E7DA" THEN
            sel <= FDD_THMFC1;
            
          ELSIF ad < x"E7DE" THEN
            sel <= GAGMP;

          ELSIF ad < x"E7E0" THEN
            -- ACIA 6850 TO9+
            IF model = T_TO9P THEN
              sel <= ACIA;
            ELSE
              sel <= NOSEL;
            END IF;

          ELSIF ad < x"E7E8" THEN
            sel <= GAGMP;

          ELSIF ad < x"E800" THEN
            -- RS232, IEEE, MODEM Option
            sel <= NOSEL;
            
          ELSE
            -- Moniteur Contrôleur Disque FLOPPY/QDD
            sel <= ROM;
            mwr <= '0';
            IF monsel_to89p='0' THEN
              mad <= BASE_ROM + ad - x"E000" + x"10000";
            ELSE
              mad <= BASE_ROM + ad - x"E000" + x"12000";
            END IF;
          END IF;

        ---------------------------------------------------
        WHEN OTHERS =>
          NULL;
        
        ---------------------------------------------------

      END CASE;
    END PROCESS;



END ARCHITECTURE rtl;

-------------------------------------------------------------------------------
