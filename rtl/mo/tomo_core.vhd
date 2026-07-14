--------------------------------------------------------------------------------
-- Thomson TOx MOx
--------------------------------------------------------------------------------
-- DO 12/2019
--------------------------------------------------------------------------------

-- - Touches spéciales clavier. Revoir mapping clavier
-- - Crayon optique. Compteur & curseur
-- - Joysticks
-- - Souris
-- - Cassette
-- - LED clavier

--------------------------------------------------------------------------------

----------------------------------------------------------
-- GEN1
-- TO7 (1982)
--  * RAM 8k + 2*8k vidéo + 16k option
--  * ROM 6k + 16k CART
--  * TIMER/ROM 6846
--  * PIA 6821  CLAVIER, position crayon
--  * Circuits MSI, pas d'ASIC.
--  * Video fixe. Pas de palette
----------------------------------------------------------
-- GEN2
-- TO7/70 (1984)
--  * TIMER/ROM 6846
--  * PIA 6821  CLAVIER, video,crayon
--  * Gate Array MCA 1300 ALS ou EFGJ 03
--  * Video fixe. Pas de palette

-- MO5 (1984)
--  * RAM 48k : 32k + 2*8k vidéo
--  * ROM 16k
--  * PIA 6821  SYSTEME : clavier, crayon, cassette, couleur bord
--  * PIA 6821  JEUX (option)
--  * Gate Array EFGJ 033E / MA4Q 1200
--  * Video fixe. Pas de palette  

-- MC6852 = SSDA = QDD

-- TO9 (1985)
--  * TIMER/ROM 6846
--  * PIA 6821  JEUX
--  * 3 ASICs
--  * Gate Array + Palette
--  * Floppy WD1770 ou WD2793. (ROM différentes. WD2793 mieux)
--  * ACIA 6850 port série clavier
--  * Microcontrôleur clavier 6805
----------------------------------------------------------
-- GEN3
-- MO6 (1986)
--  * RAM 128k : 8*16k
--  * ROM 
--  * PIA 6821  SYSTEME : clavier, crayon, cassette, banque mémoire
--  * PIA 6821  JEUX (option)
--  * Gate Mode Page + Palette

-- TO8 / TO8D (1986) / (1987)
--  * TIMER/ROM 6846 cassette, port série clavier, 
--  * PIA 6821  JEUX
--  * PIA 6821  crayon, cassette, imprimante
--  * Gate Mode Page + Palette
--  * Floppy/QDD THMFC 01
--  * 6804 : Microprocesseur clavier, liaison série

-- TO9+ (1986)
--  * TIMER/ROM 6846 cassette, crayon
--  * PIA 6821  JEUX
--  * PIA 6821  crayon, cassette, imprimante
--  * ACIA 6850 Port série clavier
--  * Gate Mode Page + Palette
--  * Floppy/QDD THMFC 01
----------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

LIBRARY work;
USE work.base_pack.ALL;
USE work.tomo_pack.ALL;
USE work.thmfc1_pack.ALL;

USE std.textio.ALL;

ENTITY tomo_core IS
  PORT (
    -- Master input clock
    sysclk            : IN  std_logic;
    pll_locked        : IN  std_logic;
    
    reset             : IN  std_logic;
    menureset         : IN  std_logic;
    
    cputype           : IN  std_logic; -- 0=VHDL 1=Verilog

    modsel            : IN  unsigned(2 DOWNTO 0);
    kbdsel            : IN  unsigned(1 DOWNTO 0);
    kbdmode           : IN  unsigned(1 DOWNTO 0);
    flopex            : IN  std_logic;
    mouse             : IN  std_logic;
    
    nobord            : IN  std_logic; -- Disable borders
    cursor            : IN  uv2; -- Show light pen position
    bar               : IN  std_logic;
    rewind            : IN  std_logic;
    speed             : IN  uv2;
    capslock          : OUT std_logic;
    
    -- Base video clock. Usually equals to CLK_SYS.
    clk_video         : OUT std_logic;
    
    -- Multiple resolutions are supported using different CE_PIXEL rates.
    -- Must be based on CLK_VIDEO
    ce_pixel          : OUT std_logic;
    
    -- VGA
    vga_r             : OUT unsigned(7 DOWNTO 0);
    vga_g             : OUT unsigned(7 DOWNTO 0);
    vga_b             : OUT unsigned(7 DOWNTO 0);
    vga_hs            : OUT std_logic; -- positive pulse!
    vga_vs            : OUT std_logic; -- positive pulse!
    vga_de            : OUT std_logic; -- = not (VBlank or HBlank)
    
    -- AUDIO
    audio_l           : OUT std_logic_vector(15 DOWNTO 0);
    audio_r           : OUT std_logic_vector(15 DOWNTO 0);
    
    ps2_key           : IN  std_logic_vector(10 DOWNTO 0);
    ps2_mouse         : IN  std_logic_vector(24 DOWNTO 0);
    joystick_0        : IN  std_logic_vector(31 DOWNTO 0);
    joystick_1        : IN  std_logic_vector(31 DOWNTO 0);
    --joystick_analog_0 : IN  std_logic_vector(15 DOWNTO 0);
    --joystick_analog_1 : IN  std_logic_vector(15 DOWNTO 0);
    
    ddram_clk           : OUT std_logic;
    ddram_waitrequest   : IN  std_logic;
    ddram_burstcount    : OUT unsigned(7 DOWNTO 0);
    ddram_address       : OUT unsigned(28 DOWNTO 0);
    ddram_readdata      : IN  std_logic_vector(63 DOWNTO 0);
    ddram_readdatavalid : IN  std_logic;
    ddram_read          : OUT std_logic;
    ddram_writedata     : OUT std_logic_vector(63 DOWNTO 0);
    ddram_byteenable    : OUT std_logic_vector(7 DOWNTO 0);
    ddram_write         : OUT std_logic;

    sdram_dq          : INOUT std_logic_vector(15 DOWNTO 0);
    sdram_a           : OUT   std_logic_vector(12 DOWNTO 0);
    sdram_dqml        : OUT   std_logic;
    sdram_dqmh        : OUT   std_logic;
    sdram_ba          : OUT   std_logic_vector(1 DOWNTO 0);
    sdram_ncs         : OUT   std_logic;
    sdram_nwe         : OUT   std_logic;
    sdram_nras        : OUT   std_logic;
    sdram_ncas        : OUT   std_logic;
    sdram_cke         : OUT   std_logic;
    sdram_clk         : OUT   std_logic;

    ioctl_download    : IN  std_logic;
    ioctl_index       : IN  std_logic_vector(7 DOWNTO 0);
    ioctl_wr          : IN  std_logic;
    ioctl_addr        : IN  unsigned(24 DOWNTO 0);
    ioctl_dout        : IN  std_logic_vector(7 DOWNTO 0);
    ioctl_wait        : OUT std_logic
    );
END tomo_core;

-------------------------------------------------------------------------------

ARCHITECTURE struct OF tomo_core IS
  
  ----------------------------------------
  SIGNAL ps2_mouse_delay : std_logic_vector(24 DOWNTO 0);
  
  ----------------------------------------
  SIGNAL mhpos : integer RANGE 0 TO 2047 := 500;
  SIGNAL mvpos : integer RANGE 0 TO 2047 := 300;
  SIGNAL hpos  : integer RANGE 0 TO 511;
  SIGNAL vpos  : integer RANGE 0 TO 511;
  
  ----------------------------------------
  SIGNAL hwreset_n : std_logic;
  SIGNAL reset_n  : std_logic;

  SIGNAL video_run : std_logic;
  
  SIGNAL divclk : uint6;
  SIGNAL tick_cpu : std_logic;
  SIGNAL cpu_reset, cpu_wake : std_logic;
  SIGNAL cpu_reset_delay : natural RANGE 0 TO 31;
  SIGNAL down_reset : std_logic;
  
  ----------------------------------------
  SIGNAL cpu_a : uv16;
  SIGNAL cpu_dw,cpu_dr : uv8;
  SIGNAL cpu_req,cpu_ack,cpu_wr : std_logic;
  SIGNAL cpu_irq,cpu_firq,cpu_nmi : std_logic;
  SIGNAL cpu_fast : std_logic;
  SIGNAL cput_req : std_logic;
  SIGNAL gmp_firq : std_logic;
  SIGNAL cpu_halt : std_logic;

  -- DECODE
  SIGNAL model : type_model;
  SIGNAL kbd   : natural RANGE 0 TO 3;
  SIGNAL sel, sel2 : enum_sel;
  SIGNAL mad : uv20;
  SIGNAL mwr : std_logic;
  SIGNAL nomap_ack : std_logic;
  
  -- PIA MO
  SIGNAL adpia : uv2;
  SIGNAL pia_mo_req,  pia_mo_ack : std_logic;
  SIGNAL pia_mo_pa_i, pia_mo_pa_o, pia_mo_pb_i, pia_mo_pb_o, pia_mo_pa_d, pia_mo_pb_d   : uv8;
  SIGNAL pia_mo_irqa, pia_mo_irqb : std_logic;
  SIGNAL pia_mo_dr : uv8;
  SIGNAL pia_mo_ca2_o : std_logic;
  SIGNAL pia_mo_ca1, pia_mo_cb1 : std_logic;

  -- PIA TO
  SIGNAL pia_to_req,  pia_to_ack : std_logic;
  SIGNAL pia_to_pa_i, pia_to_pa_o, pia_to_pb_i, pia_to_pb_o, pia_to_pa_d, pia_to_pb_d   : uv8;
  SIGNAL pia_to_irqb : std_logic;
  SIGNAL pia_to_dr : uv8;
  SIGNAL pia_to_ca1, pia_to_ca2_o, pia_to_cb1, pia_to_cb2_o : std_logic;

  -- PIA JEUX
  SIGNAL pia_jeux_req,pia_jeux_ack : std_logic;
  SIGNAL pia_jeux_pa_i,pia_jeux_pa_o,pia_jeux_pb_i,pia_jeux_pb_o,pia_jeux_pa_d,pia_jeux_pb_d : uv8;
  SIGNAL pia_jeux_irqa,pia_jeux_irqb : std_logic;
  SIGNAL pia_jeux_dr : uv8;

  SIGNAL mo_forme, to_forme : std_logic;

  SIGNAL to_mute, to_buzz : std_logic;

  -- TO TIMER
  SIGNAL tim_dr    : uv8;
  SIGNAL tim_req   : std_logic;
  SIGNAL tim_ack   : std_logic;
  SIGNAL tim_irq   : std_logic;
  SIGNAL tim_cto   : std_logic;
  SIGNAL tim_ctg_n : std_logic;
  SIGNAL tim_ctc_n : std_logic;
  SIGNAL tim_pp_i  : uv8;
  SIGNAL tim_pp_o  : uv8;
  SIGNAL tim_pp_d  : uv8;
  SIGNAL tim_cp1   : std_logic;
  SIGNAL tim_cp2_i : std_logic;
  SIGNAL tim_cp2_o : std_logic;

  -- TO9 / TO9+ ACIA
  SIGNAL acia_dr  : uv8;
  SIGNAL acia_req : std_logic;
  SIGNAL acia_ack : std_logic;
  SIGNAL acia_irq : std_logic;

  -- COLOUR PALETTE
  SIGNAL pal_dr,pal_dw : uv8;
  SIGNAL pal_wr : std_logic;
  SIGNAL pal_a : uv5;
  SIGNAL pia_border : uv4; -- MO5 border colour
  SIGNAL gmp_border : uv4; -- TO7/770 border
  SIGNAL tim_border : uv4; -- MO6 / TO8 / TO9P
  
  -- THMFC1
  SIGNAL thmfc1_dr : uv8;
  SIGNAL thmfc1_req, thmfc1_ack : std_logic;
  SIGNAL thmfc1_unload : std_logic;
  SIGNAL dmotor, dbaren, dshow : std_logic;
  SIGNAL dratio : uv8;
  SIGNAL fdbank : uv2;
  SIGNAL romfd_req, romfd_ack : std_logic;
  SIGNAL romfd_dr : uv8;

  ----------------------------------------
  SIGNAL rambank_gmp : uv5;
  SIGNAL piabanksel : std_logic;
  SIGNAL gagmp_dr : uv8;
  SIGNAL rombank_mo6 : std_logic;
  SIGNAL rambank_pia : uv5;
  SIGNAL gagmp_req, gagmp_ack : std_logic;
  SIGNAL gagmp_fdd_ext : std_logic;
  SIGNAL cart_rambank : uv5;
  SIGNAL cart_ram     : std_logic;
  SIGNAL cart_we      : std_logic;
  SIGNAL cart_loaded  : std_logic;
  SIGNAL cart_to89p   : std_logic; -- TO8/TO9+
  SIGNAL cart_size    : uv2;       -- 00=16k 01=32k 11=64k
  SIGNAL monsel_to89p : std_logic; -- TO8
  SIGNAL slot_to9     : uv2;

  SIGNAL basic_mo6,cart_gmp,video_trame : std_logic;
  SIGNAL video_mode : uv7;
  SIGNAL video_page : uv2;
  SIGNAL lpen_button : std_logic;
  SIGNAL vid_vin,  vid_hin,  vid_hlr : std_logic;
  SIGNAL vid_vin2, vid_hin2, vid_hlr2 : std_logic;
  SIGNAL lpen_align : std_logic;
  SIGNAL lpen_align2 : std_logic;
  SIGNAL sh_align : unsigned(127 DOWNTO 0);
  SIGNAL h_align  : unsigned(47 DOWNTO 0);

  SIGNAL vid_hpos, vid_vpos : uint11;
  SIGNAL vid_ta, vid_ta2 : uv13;
  SIGNAL vid_h , vid_h2  : uv3;
  
  SIGNAL vid_latch_ta : uv13;
  --SIGNAL vid_latch_h  : uv3;
  SIGNAL vid_latch_hin : std_logic;
  SIGNAL vid_latch_vin : std_logic;

  SIGNAL kbd_to8_ktest : std_logic;
  SIGNAL kbd_to8_ack, kbd_to8_data, kbd_to9_data : std_logic;

  SIGNAL kbd_to9_ktest : std_logic;
  SIGNAL kbd_to9_txd, kbd_to9_rxd, kbd_to9_ce : std_logic;
  SIGNAL acia_cts_n, acia_dcd_n : std_logic;

  SIGNAL kbd_to7_i, kbd_to7_o : uv8;
  SIGNAL kbd_led : std_logic;
  SIGNAL capslock_to89 : std_logic;

  SIGNAL joy1_en, joy2_en : std_logic;

  SIGNAL diffx, diffy : integer RANGE -2048 TO 2047;
  SIGNAL phasex, phasey : natural RANGE 0 TO 3;
  SIGNAL mouse_xi, mouse_xq, mouse_yi, mouse_yq : std_logic;
  SIGNAL tick_mouse : std_logic;
  SIGNAL cpt_mouse : natural RANGE 0 TO 256;
  SIGNAL mouse_b1,mouse_b2 : std_logic;

  SIGNAL tape_motor_n : std_logic;
  SIGNAL tape_loaded : std_logic;
  SIGNAL tshow : std_logic;

  SIGNAL tape_mo_rd, tape_mo_wr : std_logic;
  SIGNAL tape_to_rd, tape_to_wr : std_logic;

  SIGNAL tbaren : std_logic;
  SIGNAL mo_tape_motor_n, to_tape_motor_n : std_logic;
  SIGNAL tratio : uv8;
  
  SIGNAL vid_ce  : std_logic;
  SIGNAL vid_ceh : std_logic;
  SIGNAL vga_vs_l : std_logic;
  
  CONSTANT Z15 : unsigned(14 DOWNTO 0):=(OTHERS =>'0');

  -------------------------------------
  SIGNAL dd_motor  : std_logic;
  SIGNAL dd_finish : std_logic;
  SIGNAL dd_track  : uv8;
  SIGNAL dd_sector : uv8;
  SIGNAL dd_head   : std_logic;

  SIGNAL trig : std_logic;

  FUNCTION ocode(CONSTANT v : IN std_logic) RETURN unsigned IS
  BEGIN
    IF v = '1' THEN
      RETURN "10010"; -- +
    ELSE
      RETURN "10011"; -- -
    END IF;
  END FUNCTION ocode;
  FUNCTION pcode(CONSTANT v : IN std_logic) RETURN unsigned IS
  BEGIN
    IF v = '1' THEN
      RETURN "11111"; -- #
    ELSE
      RETURN "11011"; -- .
    END IF;
  END FUNCTION pcode;

  -------------------------------------
  -- VIDEO
  SIGNAL vram_a      : uv16;
  SIGNAL vram_dr     : uv16;
  SIGNAL vram_req    : std_logic;
  SIGNAL vram_ack    : std_logic;

  -------------------------------------
  -- SDRAM
  SIGNAL sdram_init  : std_logic;
  SIGNAL sdram_req   : std_logic;
  SIGNAL sdram_ack   : std_logic;
  SIGNAL sdram_wtbt  : std_logic_vector(1 DOWNTO 0);
  SIGNAL sdram_addr  : std_logic_vector(24 DOWNTO 0);
  SIGNAL sdram_dout  : std_logic_vector(15 DOWNTO 0);
  SIGNAL sdram_din   : std_logic_vector(15 DOWNTO 0);
  SIGNAL sdram_wr    : std_logic;
  SIGNAL sdram_rd    : std_logic;
  SIGNAL sdram_ready : std_logic;
  SIGNAL sdram_dr    : uv8;
  SIGNAL sdram_hilo  : std_logic;
  TYPE enum_sdram_state IS (sIDLE,sDOWN,sCPU,sVRAM);
  SIGNAL sdram_state  : enum_sdram_state;
  SIGNAL sdram_state2 : enum_sdram_state;
  SIGNAL sdram_state3 : enum_sdram_state;

  COMPONENT sdram IS
    PORT (
      init       : IN    std_logic;
      clk        : IN    std_logic;
      SDRAM_DQ   : INOUT std_logic_vector(15 DOWNTO 0);
      SDRAM_A    : OUT   std_logic_vector(12 DOWNTO 0);
      SDRAM_DQML : OUT   std_logic;
      SDRAM_DQMH : OUT   std_logic;
      SDRAM_BA   : OUT   std_logic_vector(1 DOWNTO 0);
      SDRAM_nCS  : OUT   std_logic;
      SDRAM_nWE  : OUT   std_logic;
      SDRAM_nRAS : OUT   std_logic;
      SDRAM_nCAS : OUT   std_logic;
      SDRAM_CKE  : OUT   std_logic;
      SDRAM_CLK  : OUT   std_logic;
      wtbt       : IN    std_logic_vector(1 DOWNTO 0);
      addr       : IN    std_logic_vector(24 DOWNTO 0);
      dout       : OUT   std_logic_vector(15 DOWNTO 0);
      din        : IN    std_logic_vector(15 DOWNTO 0);
      wr         : IN    std_logic;
      rd         : IN    std_logic;
      ready      : OUT   std_logic
    );
  END COMPONENT;

  ----------------------------------------
  SIGNAL cpu1_a   : uv16;
  SIGNAL cpu1_dw  : uv8;
  SIGNAL cpu1_req : std_logic;
  SIGNAL cpu1_wr  : std_logic;

  SIGNAL emu_inst, emu_ilatch : std_logic;

  SIGNAL cpu2_ack2 : std_logic;
  SIGNAL cpu2_E,cpu2_Q,cpu2_irq_n,cpu2_firq_n,cpu2_nmi_n : std_logic;
  SIGNAL cpu2_dw,cpu2_dr : uv8;
  SIGNAL cpu2_a : uv16;
  SIGNAL cpu2_lic,cpu2_halt_n,cpu2_rnw : std_logic;
  SIGNAL cpu2_avma,cpu2_busy : std_logic;
  SIGNAL cpu2_ndmabreq : std_logic;
  SIGNAL cpu2_reset_n : std_logic;
  SIGNAL cpu2_rstcpt : natural RANGE 0 TO 64;
  
  COMPONENT mc6809i
    PORT (
      D        : IN uv8;
      DOut     : OUT uv8;
      ADDR     : OUT uv16;
      RnW      : OUT std_logic;
      E        : IN std_logic;
      Q        : IN std_logic;
      BS       : OUT std_logic;
      BA       : OUT std_logic;
      nIRQ     : IN std_logic;
      nFIRQ    : IN std_logic;
      nNMI     : IN std_logic;
      AVMA     : OUT std_logic;
      BUSY     : OUT std_logic;
      LIC      : OUT std_logic;
      nHALT    : IN std_logic;
      nRESET   : IN std_logic;
      nDMABREQ : IN std_logic;
      RegData  : OUT unsigned(111 DOWNTO 0)
      );
  END COMPONENT mc6809i;
  
  -------------------------------------
  -- DOWNLOAD
  SIGNAL ioctl_download2 : std_logic;
  SIGNAL ioctl_wait_l, ioctl_wr2 : std_logic;
  SIGNAL down_dw : uv8;
  SIGNAL down_req, down_ack : std_logic;
  TYPE enum_down_state IS (sINIT,sINIT2,sINIT3,sINIT4,
                           sCLEAR,sCLEAR2,sCLEAR3,
                           sIDLE,
                           sDOWN_ROM,sDOWN_ROM2,
                           sRESET);
  SIGNAL down_idle : std_logic;
  SIGNAL down_state : enum_down_state;
  SIGNAL down_badrs, down_adrs : uv20;
  SIGNAL crc, xcrc : uv32;
  SIGNAL romcpt : natural RANGE 0 TO ROMS'length;
  SIGNAL search, found : std_logic;

  SIGNAL ioctl_download_tape, ioctl_wait_tape : std_logic;
  SIGNAL ioctl_download_disk, ioctl_wait_disk : std_logic;

  -------------------------------------  
  -- AVALON
  SIGNAL disk_address,       tape_address       : unsigned(28 DOWNTO 0);
  SIGNAL disk_burstcount,    tape_burstcount    : unsigned(7 DOWNTO 0);
  SIGNAL disk_waitrequest,   tape_waitrequest   : std_logic;
  SIGNAL disk_read,          tape_read          : std_logic;
  SIGNAL disk_readdata,      tape_readdata      : std_logic_vector(63 DOWNTO 0);
  SIGNAL disk_readdatavalid, tape_readdatavalid : std_logic;
  SIGNAL disk_write,         tape_write         : std_logic;
  SIGNAL disk_writedata,     tape_writedata     : std_logic_vector(63 DOWNTO 0);
  SIGNAL disk_byteenable,    tape_byteenable    : std_logic_vector(7 DOWNTO 0);

  -------------------------------------  

BEGIN
  -----------------------------------------------------------------------------
  -- CPU
  i_cpu : ENTITY work.mc6809
    PORT MAP (
      ad       => cpu1_a,   -- O
      dw       => cpu1_dw,  -- O
      dr       => cpu_dr,
      req      => cpu1_req, -- O
      ack      => cpu_ack,
      wr       => cpu1_wr,  -- O
      ph       => OPEN,
      emu_inst => emu_inst,
      irq      => cpu_irq,
      firq     => cpu_firq,
      nmi      => cpu_nmi,
      reset    => cpu_reset,
      wake     => cpu_wake,
      fast     => cpu_fast,
      clk      => sysclk,
      reset_na => reset_n);
  
  cpu_wake<='0';
  cpu_fast<='0';

  cpu_reset <= NOT reset_n;

  -----------------------------------------------------------------------------
  i_cpv: mc6809i
    PORT MAP (
      D      => cpu2_dr,
      DOut   => cpu2_dw,
      ADDR   => cpu2_a,
      RnW    => cpu2_rnw,
      E      => cpu2_E,
      Q      => cpu2_Q,
      BS     => OPEN,
      BA     => OPEN,
      nIRQ   => cpu2_irq_n,
      nFIRQ  => cpu2_firq_n,
      nNMI   => cpu2_nmi_n,
      AVMA   => cpu2_avma, -- OUT
      BUSY   => cpu2_busy, -- OUT
      LIC    => cpu2_lic, -- OUT
      nHALT  => cpu2_halt_n,
      nRESET => cpu2_reset_n,
      nDMABREQ => cpu2_ndmabreq);

  cpu2_halt_n   <= '1';
  cpu2_ndmabreq <= '1';
  cpu2_irq_n    <= NOT cpu_irq;
  cpu2_firq_n   <= NOT cpu_firq;
  cpu2_nmi_n    <= NOT cpu_nmi;

  cpu_a   <= mux(cputype, cpu2_a,       cpu1_a);
  cpu_wr  <= mux(cputype, NOT cpu2_rnw, cpu1_wr);
  cpu_dw  <= mux(cputype, cpu2_dw,      cpu1_dw);
  cpu_req  <=mux(cputype, '1',          cpu1_req);

  PROCESS(sysclk) IS
    CONSTANT C_TICK  : uv64 :="0000000000000000000000000000000000000000000100000000000000000000";
    CONSTANT C_TICK2 : uv64 :="0000000000010000000000000000000000000000000100000000000000000000";
    CONSTANT C_TICK4 : uv64 :="0000000000010000000000000001000000000000000100000000000000010000";
    CONSTANT C_E     : uv64 :="1111111111111111111111111111111100000000000000000000000000000000";
    CONSTANT C_Q     : uv64 :="0000000000000000111111111111111111111111111111110000000000000000";
  BEGIN
    IF rising_edge(sysclk) THEN

      divclk<=(divclk+1) MOD 64;
      
      -- 1MHz / 2MHz / 4MHz base CPU frequency
      IF speed=SPEED_2x THEN
        tick_cpu <= C_TICK2(divclk);
      ELSIF speed=SPEED_4x THEN
        tick_cpu <= C_TICK4(divclk);
      ELSE
        tick_cpu <= C_TICK(divclk);
      END IF;

      cpu2_E  <=C_E(divclk);
      cpu2_Q  <=C_Q(divclk);

      cpu2_ack2 <= cpu_ack;

      IF cpu2_ack2='1' THEN
        cpu2_dr<=cpu_dr;
      END IF;
      
      IF reset_n='0' THEN
        cpu2_reset_n <= '0';
        cpu2_rstcpt <= 0;
      ELSIF divclk=24 AND cpu2_rstcpt>=64 THEN
        cpu2_reset_n <= '1';
      END IF;

      IF cpu2_rstcpt<64 THEN
        cpu2_rstcpt <= cpu2_rstcpt + 1;
      END IF;

      -----------------------------------------------------
      emu_ilatch <= ((emu_ilatch OR emu_inst) AND reset_n) AND NOT cputype;

      -----------------------------------------------------
      IF ioctl_download='1' OR reset_n='0' THEN
        divclk <= 1;
        tick_cpu <= '0';
      END IF;
      
      -----------------------------------------------------
    END IF;
  END PROCESS;

  -----------------------------------------------------------------------------
  -- MO5 :
  --     FIRQ    MC6821 système IRQA (CA1 relié à LPEN)
  --     IRQ     MC6821 système IRQB
  -- 
  -- MO6 :
  --     FIRQ    IRQA MC6821 système
  --           + GAGMP
  --     IRQ     MC6821 système IRQB
  --           + MC6821 manettes IRQA+IRQB    
  -- 
  -- TO7 :
  --     FIRQ    MC6821 système IRQB (CB1 relié à LPEN)
  --     IRQ     MC6846
  -- 
  -- TO770
  --     FIRQ    MC6821 système IRQB (CB1 relié à LPEN)
  --     IRQ     MC6846
  -- 
  -- TO9
  --     FIRQ    MC6821 système IRQB (CB1 relié à LPEN)
  --     IRQ     MC6846
  --           + MC6850
  -- 
  -- TO8
  --     FIRQ    MC6821 système IRQB
  --           + GMP
  --     IRQ     MC6846
  --           + MC6821 manettes IRQA+IRQB
  -- 
  -- TO9+
  --     FIRQ    MC6821 système IRQB
  --           + GMP
  --     IRQ     MC6846
  --           + MC6850
  --           + MC6821 manettes IRQA+IRQB


  GenIRQ:PROCESS(model,pia_mo_irqa,pia_mo_irqb,
                 pia_jeux_irqa,pia_jeux_irqb,
                 pia_to_irqb,
                 tim_irq,acia_irq,gmp_firq) IS
  BEGIN
    CASE model IS
      WHEN T_MO5 =>
        cpu_firq <= pia_mo_irqa;
        cpu_irq  <= pia_mo_irqb OR
                    pia_jeux_irqa OR pia_jeux_irqb;

      WHEN T_MO6 =>
        cpu_firq <= pia_mo_irqa OR gmp_firq;
        cpu_irq  <= pia_mo_irqb OR
                    pia_jeux_irqa OR pia_jeux_irqb;

      WHEN T_TO7 | T_TO770 =>
        cpu_firq <= pia_to_irqb;
        cpu_irq  <= tim_irq OR 
                    pia_jeux_irqa OR pia_jeux_irqb;

      WHEN T_TO9 =>
        cpu_firq <= pia_to_irqb;
        cpu_irq  <= tim_irq OR acia_irq OR
                    pia_jeux_irqa OR pia_jeux_irqb;

      WHEN T_TO8 =>
        cpu_firq <= pia_to_irqb OR gmp_firq;
        cpu_irq  <= tim_irq OR 
                    pia_jeux_irqa OR pia_jeux_irqb;

      WHEN T_TO9P =>
        cpu_firq <= pia_to_irqb OR gmp_firq;
        cpu_irq  <= tim_irq OR acia_irq OR
                    pia_jeux_irqa OR pia_jeux_irqb;

      WHEN OTHERS =>
        cpu_firq <= '0';
        cpu_irq  <= '0';
    END CASE;
  END PROCESS GenIRQ;

  cpu_nmi <='0';

  -----------------------------------------------------------------------------
  -- DECODE
  i_decode : ENTITY work.decode
    PORT MAP (
      ad            => cpu_a,
      dw            => cpu_dw,
      wr            => cpu_wr,
      req           => cpu_req,
      sel           => sel,
      mad           => mad,
      mwr           => mwr,
      model         => model,
      to_forme      => to_forme,
      mo_forme      => mo_forme,
      rambank_gmp   => rambank_gmp,
      basic_mo6     => basic_mo6,
      cart_gmp      => cart_gmp,
      rombank_mo6   => rombank_mo6,
      rambank_pia   => rambank_pia,
      cart_rambank  => cart_rambank,
      cart_ram      => cart_ram,
      cart_we       => cart_we,
      cart_to89p    => cart_to89p,
      cart_size     => cart_size,
      cart_loaded   => cart_loaded,
      monsel_to89p  => monsel_to89p,
      slot_to9      => slot_to9,
      piabanksel    => piabanksel,
      reset_n       => reset_n,
      clk           => sysclk);

  cpu_dr<=sdram_dr    WHEN sel2 = RAM        ELSE
          sdram_dr    WHEN sel2 = ROM        ELSE
          sdram_dr    WHEN sel2 = CARTO      ELSE
          pia_mo_dr   WHEN sel2 = PIA_MO     ELSE
          pia_to_dr   WHEN sel2 = PIA_TO     ELSE
          tim_dr      WHEN sel2 = TIM        ELSE
          acia_dr     WHEN sel2 = ACIA       ELSE
          pia_jeux_dr WHEN sel2 = PIA_JEUX   ELSE
          gagmp_dr    WHEN sel2 = GAGMP      ELSE
          thmfc1_dr   WHEN sel2 = FDD_THMFC1 ELSE
          romfd_dr    WHEN sel2 = ROM_THMFC1 AND flopex='1' ELSE
          x"00";

  sel2 <= sel WHEN rising_edge(sysclk);

  cputicko:PROCESS(sysclk) IS
  BEGIN
    IF rising_edge(sysclk) THEN
      IF cpu_ack='1' AND cput_req='1' THEN
        cput_req <= '0';
      END IF;
      IF cpu_req='1' AND tick_cpu='1' THEN
        cput_req <= '1';
      END IF;
    END IF;
  END PROCESS cputicko;

  sdram_req    <= cput_req AND to_std_logic(sel = RAM OR sel = ROM OR sel = CARTO);
  gagmp_req    <= cput_req AND to_std_logic(sel = GAGMP);  -- GA / GMP + PALETTE
  pia_mo_req   <= cput_req AND to_std_logic(sel = PIA_MO); -- MO PIA
  pia_to_req   <= cput_req AND to_std_logic(sel = PIA_TO); -- TO PIA
  pia_jeux_req <= cput_req AND to_std_logic(sel = PIA_JEUX);
  tim_req      <= cput_req AND to_std_logic(sel = TIM);
  acia_req     <= cput_req AND to_std_logic(sel = ACIA);
  thmfc1_req   <= cput_req AND to_std_logic(sel = FDD_THMFC1);
  romfd_req    <= cput_req AND to_std_logic(sel = ROM_THMFC1);

  nomap_ack    <= cput_req AND NOT (sdram_req OR gagmp_req OR pia_mo_req OR pia_to_req OR pia_jeux_req OR tim_req OR acia_req OR thmfc1_ack OR romfd_ack);
  
  cpu_ack <= cput_req AND 
    (sdram_ack OR gagmp_ack OR pia_mo_ack OR pia_to_ack OR pia_jeux_ack OR tim_ack OR acia_ack OR thmfc1_ack OR romfd_ack OR nomap_ack OR NOT reset_n)
    AND NOT cpu_halt;

  -----------------------------------------------------------------------------
  -- SDRAM
  -- Stores RAM, ROM, Cartridge
  -- 16bits SDRAM : A13 selects HI/LO byte to allow simultaneous access to POINT and COULEUR video RAM.
  i_sdram : sdram
    PORT MAP (
      init       => sdram_init,
      clk        => sysclk,
      SDRAM_DQ   => sdram_dq,
      SDRAM_A    => sdram_a,
      SDRAM_DQML => sdram_dqml,
      SDRAM_DQMH => sdram_dqmh,
      SDRAM_BA   => sdram_ba,
      SDRAM_nCS  => sdram_ncs,
      SDRAM_nWE  => sdram_nwe,
      SDRAM_nRAS => sdram_nras,
      SDRAM_nCAS => sdram_ncas,
      SDRAM_CKE  => sdram_cke,
      SDRAM_CLK  => sdram_clk,
      wtbt       => sdram_wtbt,
      addr       => sdram_addr,
      dout       => sdram_dout,
      din        => sdram_din,
      wr         => sdram_wr,
      rd         => sdram_rd,
      ready      => sdram_ready);
    
  SDRAM_ALT:PROCESS(sysclk) IS
  BEGIN
    IF rising_edge(sysclk) THEN
      sdram_ack <= '0';
      down_ack  <= '0';
      vram_ack  <= '0';
      sdram_wr  <= '0';
      sdram_rd  <= '0';
      
      sdram_state2 <= sdram_state;
      sdram_state3 <= sdram_state2;

      CASE sdram_state IS
        WHEN sIDLE =>
          IF sdram_ready='1' THEN
            -- SDRAM controller is ready to accept new command
            IF down_req='1' AND down_ack='0' THEN
              -- Download ROM / Cartridge
              sdram_wr    <= '1';
              sdram_wtbt  <= down_adrs(13) & NOT down_adrs(13);
              sdram_addr  <= std_logic_vector("00000" & down_adrs(19 DOWNTO 14) & down_adrs(12 DOWNTO 0) & '0');
              sdram_din   <= std_logic_vector(down_dw) & std_logic_vector(down_dw);
              sdram_state <= sDOWN;
              
            ELSIF sdram_req='1' AND sdram_ack='0' THEN
              -- CPU Access
              sdram_rd    <= NOT mwr;
              sdram_wr    <= mwr;
              sdram_wtbt  <= mad(13) & NOT mad(13);
              sdram_addr  <= std_logic_vector("00000" & mad(19 DOWNTO 14) & mad(12 DOWNTO 0) & '0');
              sdram_hilo  <= mad(13);
              sdram_din   <= std_logic_vector(cpu_dw) & std_logic_vector(cpu_dw);
              sdram_state <= sCPU;

            ELSIF vram_req='1' AND vram_ack='0' THEN
              -- Video Access
              sdram_rd    <= down_idle;
              sdram_wtbt  <= "11";
              sdram_addr  <= std_logic_vector("000000000" & vram_a(15 DOWNTO 14) & vram_a(12 DOWNTO 0) & '0');
              sdram_state <= sVRAM;
            END IF;
          END IF;

        WHEN sDOWN =>
          IF sdram_ready='1' AND sdram_wr='0' AND sdram_rd='0' AND sdram_state2=sDOWN THEN
            down_ack    <= '1';
            sdram_state <= sIDLE;
          END IF;

        WHEN sCPU =>
          IF sdram_ready='1' AND sdram_wr='0' AND sdram_rd='0' AND sdram_state2=sCPU THEN
            sdram_dr    <= mux(sdram_hilo,unsigned(sdram_dout(15 DOWNTO 8)),unsigned(sdram_dout(7 DOWNTO 0)));
            sdram_ack   <= '1';
            sdram_state <= sIDLE;
          END IF;

        WHEN sVRAM =>
          IF sdram_ready='1' AND sdram_wr='0' AND sdram_rd='0'  AND sdram_state2=sVRAM THEN
            vram_dr     <= unsigned(sdram_dout);
            vram_ack    <= '1';
            sdram_state <= sIDLE;
          END IF;
      END CASE;
    END IF;
  END PROCESS;
  
  -----------------------------------------------------------------------------
  -- VIDEO
  i_video : ENTITY work.video
    PORT MAP (
      vram_req     => vram_req,
      vram_ack     => vram_ack,
      vram_a       => vram_a,
      vram_dr      => vram_dr,
      pal_a        => pal_a,
      pal_dw       => pal_dw,
      pal_dr       => pal_dr,
      pal_wr       => pal_wr,
      model        => model,
      video_mode   => video_mode,
      video_trame  => video_trame,
      video_page   => video_page,
      pia_border   => pia_border,
      tim_border   => tim_border,
      gmp_border   => gmp_border,
      nobord       => nobord,
      divclk       => divclk,
      cursor       => cursor,
      hpos         => hpos,
      vpos         => vpos,
      tbaren       => tbaren,
      tratio       => tratio,
      tmotor_n     => tape_motor_n,
      dbaren       => dbaren,
      dratio       => dratio,
      dmotor       => dmotor,
      emu_ilatch   => emu_ilatch,

      vga_r        => vga_r,
      vga_g        => vga_g,
      vga_b        => vga_b,
      vga_hs       => vga_hs,
      vga_vs       => vga_vs_l,
      vga_de       => vga_de,

      vga_ce       => vid_ce,
      vga_ceh      => vid_ceh,
      vid_hpos     => vid_hpos,
      vid_vpos     => vid_vpos,
      vid_ta       => vid_ta,
      vid_h        => vid_h,
      vid_vin      => vid_vin,
      vid_hin      => vid_hin,
      vid_hlr      => vid_hlr,

      video_run    => video_run,
      speed        => speed,
      clk          => sysclk,
      hwreset_n    => hwreset_n);
  
  ce_pixel  <= vid_ceh; --vid_ce;
  clk_video <= sysclk;
  
  -----------------------------------------------------------------------------
  -- Gate Array / Gate Mode Page
  i_gagmp : ENTITY work.gagmp
    port map (
      ad           => mad(7 DOWNTO 0),
      dw           => cpu_dw,
      dr           => gagmp_dr,
      req          => gagmp_req,
      ack          => gagmp_ack,
      wr           => cpu_wr,
      pal_a        => pal_a,
      pal_dw       => pal_dw,
      pal_dr       => pal_dr,
      pal_wr       => pal_wr,
      model        => model,
      basic_mo6    => basic_mo6,
      rambank_gmp  => rambank_gmp,
      rambank_pia  => rambank_pia,
      cart_gmp     => cart_gmp,
      piabanksel   => piabanksel,
      fdd_ext      => gagmp_fdd_ext,
      cart_rambank => cart_rambank,
      cart_ram     => cart_ram, 
      cart_we      => cart_we,
      video_mode   => video_mode,
      video_page   => video_page,
      gmp_border   => gmp_border,
      video_trame  => video_trame,
      lpen_align   => lpen_align,
      gmp_firq     => gmp_firq,
      vid_ta       => vid_ta2,
      vid_h        => vid_h2,
      vid_vin      => vid_vin2,
      vid_hin      => vid_hin2,
      vid_hlr      => vid_hlr2,
      clk          => sysclk,
      reset_n      => reset_n);
  
  --       VIDEO | CPU
  --       ------+-----
  --   15   BE1  | RA15
  --   14   BE0  | RA14
  --   13   Q    | RA13
  --   12   TA12 | A12
  --   11   TA11 | A11
  --   10   TA10 | A10
  --   9    TA9  | A9
  --   8    TU8  | A8
  --   7    TA7  | A7
  --   6    TA6  | A6
  --   5    TA5  | A5
  --   4    TA4  | A4
  --   3    TA3  | A3
  --   2    TA2  | A2
  --   1    TA1  | A1
  --   0    TA0  | A0
  

  -- PIA MO : MO5 / MO6 "SYSTEM"

  -- PORT |          MO5                      |         MO6                       |
  ---------------------------------------------------------------------------------
  -- PA0  | O Video Page FORME                                                    |
  -- PA1  | O Bordure R                       | I Bouton Crayon Optique           |
  -- PA2  | O Bordure V                       | O Mute Souris                     |
  -- PA3  | O Bordure B                       | O Clavier ligne 9                 |
  -- PA4  | O Bordure P                       | O Clavier LED majuscules          |
  -- PA5  | I Bouton Crayon Optique           | O Switch bank ROM                 |
  -- PA6  | O Cassette OUT                                                        |
  -- PA7  | I Cassette IN                                                         |

  -- PB0  | O Son                                                                 |
  -- PB1  | O Clavier Mux OUT A                                                   |
  -- PB2  | O Clavier Mux OUT B                                                   |
  -- PB3  | O Clavier Mux OUT C                                                   |
  -- PB4  | O Clavier Mux IN  A                                                   |
  -- PB5  | O Clavier Mux IN  B                                                   |
  -- PB6  | O Clavier Mux IN  C                                                   |
  -- PB7  | I Clavier IN                                                          |

  -- CA1  | I Crayon optique                  | I Crayon optique code barre       |
  -- CA2  | O Cassette Moteur ON/OFF          | O Cassette Moteur ON/OFF          |
  -- CB1  | I INIT                            | I INIT                            |
  -- CB2  | O Incruste                        | O CLTV. Commutation lente Péritel |

  -- IRQA | FIRQ                              | FIRQ                            
  -- IRQB | IRQ                               | IRQ                            

  i_pia_mo : ENTITY work.mc6821
    PORT MAP (
      ad      => adpia,
      dw      => cpu_dw,
      dr      => pia_mo_dr,
      req     => pia_mo_req,
      ack     => pia_mo_ack,
      wr      => cpu_wr,
      pa_i    => pia_mo_pa_i,
      pa_o    => pia_mo_pa_o,
      pa_d    => pia_mo_pa_d,
      pb_i    => pia_mo_pb_i,
      pb_o    => pia_mo_pb_o,
      pb_d    => pia_mo_pb_d,
      ca1     => pia_mo_ca1,
      ca2_i   => '0',
      ca2_o   => pia_mo_ca2_o,
      cb1     => pia_mo_cb1,
      cb2_i   => '0',
      cb2_o   => OPEN, -- Péritel commutation
      irqa    => pia_mo_irqa,
      irqb    => pia_mo_irqb,
      clk     => sysclk,
      reset_n => reset_n);
 
  pia_mo_pa_i(0)<=pia_mo_pa_o(0) OR NOT pia_mo_pa_d(0);
  pia_mo_pa_i(1)<=lpen_button;
  pia_mo_pa_i(6 DOWNTO 2)<=pia_mo_pa_o(6 DOWNTO 2) OR NOT pia_mo_pa_d(6 DOWNTO 2);

  pia_mo_pa_i(7) <= tape_mo_rd;
  tape_mo_wr     <= pia_mo_pa_o(6) OR NOT pia_mo_pa_d(6);
  
  mo_tape_motor_n <= pia_mo_ca2_o;
  mo_forme <= pia_mo_pa_o(0) OR NOT pia_mo_pa_d(0);

  pia_mo_ca1 <= lpen_align AND to_std_logic(model = T_MO5); -- LPEN CLOCK
  pia_mo_pb_i(6 DOWNTO 0)<=pia_mo_pb_o(6 DOWNTO 0);
  
  -- Pull-up inside MC6821 port A : OUT or not DIRECTION
  rombank_mo6 <= pia_mo_pa_o(5) OR NOT pia_mo_pa_d(5);

  adpia <=cpu_a(0) & cpu_a(1);

  -- CB1 : MO5 : Monostable 10k 47n = T = 0.7 R.C = 330µs
  pia_mo_cb1 <= vga_vs_l;

  vga_vs <= vga_vs_l;
  
  pia_border <= pia_mo_pa_o(4 DOWNTO 1) OR NOT pia_mo_pa_d(4 DOWNTO 1); -- MO5 border colour


  -----------------------------------------------------------------------------
  -- PIA MC6821 : JOYSTICK / SOUND : TOUS

  -- 
  -- PORT |  MO5 EXTENSION |     TO7 EXT  |         MO6         |  TO 8 / 9+
  -------------------------------------------------------------------------------
  -- PA0  |                |   I JOY0_N   | I JOY0_N + O IMP_D0 |
  -- PA1  |                |   I JOY0_S   | I JOY0_S + O IMP_D1 |
  -- PA2  |                |   I JOY0_L   | I JOY0_L            |
  -- PA3  |                |   I JOY0_R   | I JOY0_R            |
  -- PA4  |                |   I JOY1_N   | I JOY1_N + O IMP_D4 |
  -- PA5  |                |   I JOY1_S   | I JOY1_S + O IMP_D5 |
  -- PA6  |                |   I JOY1_L   | I JOY1_L + O IMP_D6 |
  -- PA7  |                |   I JOY1_R   | I JOY1_R + O IMP_D7 |
  -- PB0  |                |   O SON      | O SON + O JOY0_/EN  |
  -- PB1  |                |   O SON      | O SON + O JOY1_/EN  |
  -- PB2  |                |   O SON      | O SON + I JOY0_BTN2 |
  -- PB3  |                |   O SON      | O SON + I JOY1_BTN2 |
  -- PB4  |                |   O SON      | O SON  + O IMP_D2   |
  -- PB5  |                |   O SON      | O SON_ + O IMP_D3   |
  -- PB6  |                |   I JOY0_BTN | I JOY0_BTN1         |
  -- PB7  |                |   I JOY1_BTN | I JOY1_BTN1         |
  -- CA1  |                |   I JOY0_BTN | = PB2               | = PB2
  -- CA2  |                |   I JOY1_BTN | = PB6               | = PB6
  -- CB1  |                |              |   IMP_BUSY          | = PB3
  -- CB2  |                |              |   IMP_STROBE        | = PB7
  -- IRQA |                |              |   IRQ               |   IRQ
  -- IRQB |                |              |   IRQ               |   IRQ

  i_pia_jeux : ENTITY work.mc6821
    PORT MAP (
      ad      => adpia,
      dw      => cpu_dw,
      dr      => pia_jeux_dr,
      req     => pia_jeux_req,
      ack     => pia_jeux_ack,
      wr      => cpu_wr,
      pa_i    => pia_jeux_pa_i,
      pa_o    => pia_jeux_pa_o,
      pa_d    => pia_jeux_pa_d,
      pb_i    => pia_jeux_pb_i,
      pb_o    => pia_jeux_pb_o,
      pb_d    => pia_jeux_pb_d,
      ca1     => pia_jeux_pb_i(2), -- = PB2 Joystick XA
      ca2_i   => pia_jeux_pb_i(6), -- = PB6 Joystick YA
      ca2_o   => OPEN,
      cb1     => pia_jeux_pb_i(3), -- = PB3 Joystick 
      cb2_i   => pia_jeux_pb_i(7),
      cb2_o   => OPEN, -- STROBE
      irqa    => pia_jeux_irqa,
      irqb    => pia_jeux_irqb,
      clk     => sysclk,
      reset_n => reset_n); -- Péritel commutation

  pia_jeux_pb_i(0)<='0'; --pia_jeux_pb_o(0);
  pia_jeux_pb_i(1)<='0'; --pia_jeux_pb_o(1); 
  pia_jeux_pb_i(4)<=pia_jeux_pb_o(4);
  pia_jeux_pb_i(5)<=pia_jeux_pb_o(5);

  audio_l<=std_logic_vector((pia_jeux_pb_o(5 DOWNTO 0) & "0000000000") XOR
                            (pia_mo_pb_o(0) & Z15) XOR (tape_mo_rd & Z15));
  audio_r<=std_logic_vector((pia_jeux_pb_o(5 DOWNTO 0) & "0000000000") XOR
                            (pia_mo_pb_o(0) & Z15) XOR (tape_mo_rd & Z15));

  -- <TODO> RAJOUTER Buzzer, Mute TO
    
  joy1_en <= pia_jeux_pb_o(0) OR NOT pia_jeux_pb_d(0) OR to_std_logic(model=T_TO7 OR model=T_TO770);
  joy2_en <= pia_jeux_pb_o(1) OR NOT pia_jeux_pb_d(1) OR to_std_logic(model=T_TO7 OR model=T_TO770);
  
  -- Joystick 1 + Mouse
  pia_jeux_pa_i(0)<=mux(mouse, NOT mouse_b1 ,NOT joystick_0(3) OR NOT joy1_en); -- UP    + MOUSE B1
  pia_jeux_pa_i(1)<=mux(mouse, NOT mouse_b2 ,NOT joystick_0(2) OR NOT joy1_en); -- DOWN  + MOUSE B2
  pia_jeux_pa_i(2)<=mux(mouse, mouse_xq     ,NOT joystick_0(1) OR NOT joy1_en); -- RIGHT + MOUSE XB
  pia_jeux_pa_i(3)<=mux(mouse, mouse_yq     ,NOT joystick_0(0) OR NOT joy1_en); -- LEFT  + MOUSE YB
  pia_jeux_pb_i(6)<=mux(mouse, mouse_yi     ,NOT joystick_0(4) OR NOT joy1_en); -- B1    + MOUSE XA
  pia_jeux_pb_i(2)<=mux(mouse, mouse_xi     ,NOT joystick_0(5) OR NOT joy1_en); -- B2    + MOUSE XB

  -- Joystick 2
  pia_jeux_pa_i(4)<=NOT joystick_1(3) OR NOT joy2_en; -- UP
  pia_jeux_pa_i(5)<=NOT joystick_1(2) OR NOT joy2_en; -- DOWN
  pia_jeux_pa_i(6)<=NOT joystick_1(1) OR NOT joy2_en; -- RIGHT
  pia_jeux_pa_i(7)<=NOT joystick_1(0) OR NOT joy2_en; -- LEFT
  pia_jeux_pb_i(7)<=NOT joystick_1(4) OR NOT joy2_en; -- B1
  pia_jeux_pb_i(3)<=NOT joystick_1(5) OR NOT joy2_en; -- B2
  
  --  pia_pa_o(2) : MUTE SOURIS

  -----------------------------------------------------------------------------
  -- PIA MC6821 : TO7 / 770 / 8 / 9 / 9+

  -- PORT |          TO7                               |      TO7/70                    |
  ---------------------------------------------------------------------------------------
  -- PA0  | I Clavier Colonne 8 + LPEN T8 (+pullup)    | I Clavier Colonne 8            |
  -- PA1  | I Clavier Colonne 7 + LPEN T9 (+pullup)    | I Clavier Colonne 7            |
  -- PA2  | I Clavier Colonne 6 + LPEN T10 (+pullup)   | I Clavier Colonne 6            |
  -- PA3  | I Clavier Colonne 5 + LPEN T11 (+pullup)   | I Clavier Colonne 5            |
  -- PA4  | I Clavier Colonne 4 + LPEN T12 (+pullup)   | I Clavier Colonne 4            |
  -- PA5  | I Clavier Colonne 3 + LPEN T13 (+pullup)   | I Clavier Colonne 3            |
  -- PA6  | I Clavier Colonne 2 + LPEN /INIL (+pullup) | I Clavier Colonne 2            |
  -- PA7  | I Clavier Colonne 1 + LPEN /INIT (+pullup) | I Clavier Colonne 1            |

  -- PB0  | O Clavier Ligne 8   + LPEN L0              | O Clavier Démux Adrs 0         |
  -- PB1  | O Clavier Ligne 7   + LPEN L1              | O Clavier Démux Adrs 1         |
  -- PB2  | O Clavier Ligne 6   + LPEN L2              | O Clavier Démux Adrs 2         |
  -- PB3  | O Clavier Ligne 5   + LPEN T3              | O Banque mémoire 0             |
  -- PB4  | O Clavier Ligne 4   + LPEN T4              | O Banque mémoire 1             |
  -- PB5  | O Clavier Ligne 3   + LPEN T5              | O Banque mémoire 2             |
  -- PB6  | O Clavier Ligne 2   + LPEN T6              | O Banque mémoire 3             |
  -- PB7  | O Clavier Ligne 1   + LPEN T7              | O Banque mémoire 4             |
  
  -- CA1  | I INIT                                     | I /CLRG ???                    |
  -- CA2  | O Cassette commande moteur                 | O Cassette commande moteur     |
  -- CB1  | I CK LP  -> Clock buffers LPEN, INTR       | I CLKP                         |
  -- CB2  | O /OE LP  -> /OE buffers LPEN              | O Incrustation video           |

  -- IRQA |  NC ?                                      | NC ?                           |
  -- IRQB |  /FIRQ                                     | /FIRQ                          |

  -- PORT |          TO9               |            TO8 / TO9+          |
  -----------------------------------------------------------------------
  -- PA0  | I Clavier KTEST            | I Clavier KTEST                |
  -- PA1  | O CENTRONICS D1            | O CENTRONICS D1                |
  -- PA2  | O CENTRONICS D2            | O CENTRONICS D2                |
  -- PA3  | O CENTRONICS D3            | O CENTRONICS D3                |
  -- PA4  | O CENTRONICS D4            | O CENTRONICS D4                |
  -- PA5  | O CENTRONICS D5            | O CENTRONICS D5                |
  -- PA6  | O CENTRONICS D6            | O CENTRONICS D6                |
  -- PA7  | O CENTRONICS D7            | O CENTRONICS D7                |

  -- PB0  | O CENTRONICS D0            | O CENTRONICS D0                |
  -- PB1  | O CENTRONICS STROBE        | O CENTRONICS STROBE            |
  -- PB2  | O CLTV Commutation péritel | O CLTV Commutation péritel     |
  -- PB3  | O BANQUE RAM               |  (EMULATION BANQUE RAM)        |
  -- PB4  | O BANQUE RAM               |  (EMULATION BANQUE RAM)        |
  -- PB5  | O BANQUE RAM               |  (EMULATION BANQUE RAM)        |
  -- PB6  | O BANQUE RAM               |  (EMULATION BANQUE RAM)        |
  -- PB7  | O BANQUE RAM               |  (EMULATION BANQUE RAM)        |

  -- CA1  | I /CLRG                    | I /CLRG (connecteur extension) |
  -- CA2  | O Moteur Cassette          | O Moteur Cassette              |
  -- CB1  | I Code Barre               | I Code Barre                   |
  -- CB2  |   N.C.                     |   N.C.                         |
  
  -- IRQA |   N.C.                     |   N.C.                         |
  -- IRQB | O /FIRQ                    | O /FIRQ                        |

  -- TO7 : Latch Lpen = 74LS374 : Octal D-Type Positive-Edge-Triggered Flip-Flops

  i_pia_to : ENTITY work.mc6821
    PORT MAP (
      ad      => adpia,
      dw      => cpu_dw,
      dr      => pia_to_dr,
      req     => pia_to_req,
      ack     => pia_to_ack,
      wr      => cpu_wr,
      pa_i    => pia_to_pa_i,
      pa_o    => pia_to_pa_o,
      pa_d    => pia_to_pa_d,
      pb_i    => pia_to_pb_i,
      pb_o    => pia_to_pb_o,
      pb_d    => pia_to_pb_d,
      ca1     => pia_to_ca1,
      ca2_i   => pia_to_ca2_o,
      ca2_o   => pia_to_ca2_o,
      cb1     => pia_to_cb1,
      cb2_i   => pia_to_cb2_o,
      cb2_o   => pia_to_cb2_o,
      irqa    => OPEN,
      irqb    => pia_to_irqb,
      clk     => sysclk,
      reset_n => reset_n);
  
  -- Outputs
  rambank_pia <= (NOT pia_to_pb_d(7 DOWNTO 3)) OR pia_to_pb_o(7 DOWNTO 3); -- TO770 + TO9 + TO8 + TO9+
  kbd_to7_i     <= pia_to_pb_o;

  -- <TODO> Centronics...

  to_tape_motor_n <= pia_to_ca2_o;
  

  --pia_to_pa_i <= pia_to_pa_i_to

--DDR=1 => sortie PR
--DDR=0 => sortie à 1

  PIATO:PROCESS(model,kbd_to7_o,kbd_to8_ktest,kbd_to9_ktest,
                pia_to_cb2_o,vid_vin,pia_to_pb_o,
                vid_latch_vin,vid_latch_hin,vid_latch_ta,lpen_align) IS
  BEGIN
    CASE model IS
      WHEN T_TO7 =>
        IF pia_to_cb2_o='1' THEN
          -- KBD
          pia_to_pa_i <= kbd_to7_o;
          pia_to_pb_i <= x"00"; -- Only used as output
        ELSE
          -- LPEN
          pia_to_pa_i <= vid_latch_vin & vid_latch_hin & '0' & vid_latch_ta(12 DOWNTO 8); -- /INIT /INIL 
          pia_to_pb_i <= vid_latch_ta(7 DOWNTO 0);
        END IF;
        pia_to_ca1  <= NOT vid_vin; -- INIT
        pia_to_cb1  <= lpen_align; -- CK LP
        
      WHEN T_TO770 =>
        pia_to_pa_i <= kbd_to7_o;
        pia_to_pb_i <= pia_to_pb_o; -- Only used as output : KBD + RAMBANK
        pia_to_ca1  <= '1'; -- CLRG Incrustation ?
        pia_to_cb1  <= lpen_align; -- /ITLP Gate Array

      WHEN T_TO8 | T_TO9P =>
        pia_to_pa_i <= "0000000" & kbd_to8_ktest;
        pia_to_pb_i <= x"00"; -- Only used as output
        pia_to_ca1  <= '1'; -- CLRG Incrustation ?
        pia_to_cb1  <= '0'; -- Barcode READ ?

      WHEN OTHERS => -- TO9
        pia_to_pa_i <= "0000000" & kbd_to9_ktest;
        pia_to_pb_i <= x"00"; -- Only used as output
        pia_to_ca1  <= '1'; -- CLRG Incrustation ?
        pia_to_cb1  <= lpen_align; -- Light Pen + Barcode

    END CASE;
  END PROCESS;

  -----------------------------------------------------------------------------
  -- TIM MC6846 : Timer/ROM  : TO7 / TO8 / TO9 / TO9+
  -- ROM Interne au MC6846
  --  - Utilisée sur     TO7, TO770, TO9
  --  - Non utilisée sur TO8, TO9+
  --  => Mapping avec les autres ROM

  -- PORT |          TO7  (U1)           |            TO770 (I33)       |
  -----------------------------------------------------------------------
  -- PP0  | O FORME
  -- PP1  | I Bouton crayon optique
  -- PP2  | O COL                        | TPASTEL
  -- PP3  | O LED Clavier
  -- PP4  | O Bordure RT
  -- PP5  | O Bordure GT
  -- PP6  | O Bordure BT
  -- PP7  | I Lecture Cassette

  -- CTO  | O Ècriture Cassette
  -- CP2  | O Buzzer
  -- CP1  | I Extension IRQ
  -- CTG  | 0
  -- CTC  | 0

  -- PORT |          TO8  (IW29)         |            TO9+ (IW11)       |
  -----------------------------------------------------------------------
  -- PP0  | O FORME
  -- PP1  | I Bouton crayon optique
  -- PP2  | O Sélection cartouche : 1=BASIC 0=CART
  -- PP3  |   N.C
  -- PP4  | O A13 PROM DISQUE            |  Selection ROM
  -- PP5  | O PA2 Clavier ACK            |  ????
  -- PP6  |   BUSY Print
  -- PP7  | I Lecture Cassette

  -- CTO  | O Ècriture Cassette
  -- CP2  | O MUTE
  -- CP1  | I KBD DATA                   |  0
  -- CTG  | 0
  -- CTC  | 0

  -- TO8 / TO9+ : Emulated TO7/770/9 FORME bit inside the "Gate Mode Page" at same address (Manuel technique page 183)

-----------------------------------------
  -- PORT |          TO9  (I41)         |
  ---------------------------------------
  -- PP0  | O FORME
  -- PP1  | I Bouton crayon optique
  -- PP2  | ? Connecteur extension mémoire
  -- PP3  |   ????
  -- PP4  | O ROM SLOT1
  -- PP5  | O ROM SLOT0
  -- PP6  | ? Connecteur extension mémoire ?
  -- PP7  | I Lecture Cassette

  -- CTO  | O Ècriture Cassette
  -- CP2  | O Buzzer
  -- CP1  | I ???
  -- CTG  | 0
  -- CTC  | 0

  i_tim : ENTITY work.mc6846
    PORT MAP (
      ad       => cpu_a(2 DOWNTO 0),
      dw       => cpu_dw,
      dr       => tim_dr,
      req      => tim_req,
      ack      => tim_ack,
      wr       => cpu_wr,
      irq      => tim_irq, -- CPU IRQ
      cto      => tim_cto,
      ctg_n    => tim_ctg_n,
      ctc_n    => tim_ctc_n,
      pp_i     => tim_pp_i,
      pp_o     => tim_pp_o,
      pp_d     => tim_pp_d,
      cp1      => tim_cp1,
      cp2_i    => tim_cp2_i,
      cp2_o    => tim_cp2_o,
      tick_cpu => tick_cpu,
      clk      => sysclk,
      reset_n  => reset_n);

  tim_ctg_n <= '0'; -- N.C.
  tim_ctc_n <= '0'; -- N.C.

  tim_cp1     <= kbd_to8_data AND to_std_logic(model=T_TO8); -- TO8 : Data clavier. TO7/T770 : IRQ ext. TO9/9+ : NC
  kbd_to8_ack <= tim_pp_o(5);
  
  tim_cp2_i <= tim_cp2_o; -- Output only
  to_mute <= tim_cp2_o WHEN model=T_TO8 OR model=T_TO9P ELSE '0';       -- TO8, TO9+ : MUTE
  to_buzz <= tim_cp2_o WHEN model=T_TO7 OR model=T_TO770 OR model=T_TO9 ELSE '0';   -- TO7, TO770 TO9 : SON, buzzer

  tim_pp_i(0) <= to_forme;    -- O
  tim_pp_i(1) <= lpen_button; -- I : Bouton Crayon Optique
  tim_pp_i(2) <= tim_pp_o(2);
  tim_pp_i(3) <= tim_pp_o(3);
  tim_pp_i(4) <= tim_pp_o(4); -- O : TO8 : Select Monitor / Disk CTRL
  tim_pp_i(5) <= tim_pp_o(5); -- O : TO8 : KBD ACK
  tim_pp_i(6) <= '0'; -- I : TO8 / TO9+ : Printer BUSY / TO9 : RAM Extension conn. / 
  tim_pp_i(7) <= tape_to_rd; -- I Tape Read
  
  tape_to_wr <= tim_cto;

  cart_to89p <= tim_pp_o(2); -- TO8 / TO9+ : CART = 0  BASIC = 1
  monsel_to89p <= tim_pp_o(4); -- Select Monitor/Disk CTRL TO8

  to_forme   <= tim_pp_o(0); -- TO* : FORME
  tim_border <= tim_pp_o(2) & tim_pp_o(6 DOWNTO 4); -- TO7/TO770 border colour

  -- tim_pp_o(3); -- TO7/770 : Keyboard LED
  -- tim_pp_o(4); -- TO7/770 : Border colour R
  -- tim_pp_o(5); -- TO7/770 : Border colour G
  -- tim_pp_o(6); -- TO7/770 : Border colour B

  slot_to9 <= tim_pp_o(5 DOWNTO 4);


  -- Keyboard CapsLock LED
  kbd_led <= tim_pp_o(3)    WHEN model = T_TO7 OR model = T_TO770 ELSE
             pia_mo_pa_o(6) WHEN model = T_MO6 ELSE
             capslock_to89  WHEN model = T_TO8 OR model= T_TO9 OR model = T_TO9P ELSE
             '0';

  -----------------------------------------------------------------------------
  -- MC6850 : ACIA : TO9 / TO9+
  
  -- TO9   TO9+
  -- K
  -- PORT   |          TO9                 |            TO9+           |
  ----------------------------------------------------------------------
  -- TXCLK  | RXCLK = TXCLK                | RXCLK = TXCLK             |
  -- RXCLK  |  div 16MHz / 208 / 16 = 4808 |                           |
  -- RXD    | CLAVIER                      | CLAVIER                   |
  -- RXD    | CLAVIER                      | CLAVIER                   |
  -- /DCD   |  = GND                       | = GND                     |
  -- /CTS   |  = RTS & BUSY imprimant  r   | = GND                     |
  -- /RTS   |  Relié à CTS                 | No Connect                |
  
  --  CR    |    x99 = 1 00 110 01         |   xD0 = 1 10 100 00       |
  --        |    /16, 8bits, even, 1stop   |  /1, 8bits 2stop          |
  --        |    /RTS=0, TXINT Disable     |  /RTS=1, TXINT Disable    |
  --        |            RXINT Enable      |          RXINT Enable     |

  -- KTEST : PIA PA0                       | PIA PA0                    |
  i_mc6850: ENTITY work.mc6850
    PORT MAP (
      ad      => cpu_a(0),
      dw      => cpu_dw,
      dr      => acia_dr,
      req     => acia_req,
      ack     => acia_ack,
      wr      => cpu_wr,
      rx_clk  => sysclk,
      rx_ce   => kbd_to9_ce,
      rx_d    => kbd_to9_txd,
      tx_clk  => sysclk,
      tx_ce   => kbd_to9_ce,
      tx_d    => kbd_to9_rxd,
      rts_n   => OPEN,-- Request To Send
      cts_n   => acia_cts_n, -- Clear To Send
      dcd_n   => acia_dcd_n, -- Data Carrier Detect
      irq     => acia_irq,
      clk     => sysclk,
      reset_n => reset_n);

    acia_cts_n <= '0';
    acia_dcd_n <= '0';

  -----------------------------------------------------------------------------
  -- WD1770 : Floppy : TO9
  
  -----------------------------------------------------------------------------
  -- THMFC 01 : Floppy/QDD : TO8 / TO9+
  i_thmfc1: ENTITY work.thmfc1
    PORT MAP (
      ad                => cpu_a(3 DOWNTO 0),
      dw                => cpu_dw,
      dr                => thmfc1_dr,
      req               => thmfc1_req,
      ack               => thmfc1_ack,
      wr                => cpu_wr,
      unload            => thmfc1_unload,
      fdbank            => fdbank,
      ioctl_download    => ioctl_download_disk,
      ioctl_wr          => ioctl_wr,
      ioctl_addr        => ioctl_addr,
      ioctl_data        => ioctl_dout,
      ioctl_wait        => ioctl_wait_disk,
      avl_address       => disk_address,
      avl_write         => disk_write,
      avl_writedata     => disk_writedata,
      avl_byteenable    => disk_byteenable,
      avl_read          => disk_read,
      avl_burstcount    => disk_burstcount,
      avl_readdata      => disk_readdata,
      avl_readdatavalid => disk_readdatavalid,
      avl_waitrequest   => disk_waitrequest,
      dmotor            => dmotor,
      dratio            => dratio,
      dshow             => dshow,
      dd_motor          => dd_motor,
      dd_finish         => dd_finish,
      dd_track          => dd_track,
      dd_sector         => dd_sector,
      dd_head           => dd_head,
      tick_cpu          => tick_cpu,
      clk               => sysclk,
      reset_n           => reset_n,
      hwreset_n         => hwreset_n);

  dbaren <= bar AND dshow;

  -- ROM FDD Controller extension : 4 pages * 2kB
  FDROM:PROCESS(sysclk) IS
  BEGIN
    IF rising_edge(sysclk) THEN
      romfd_dr <= ROM_CD90_351(to_integer(fdbank & cpu_a(10 DOWNTO 0)));
    END IF;
  END PROCESS FDROM;
  
  romfd_ack <= romfd_req;

  -----------------------------------------------------------------------------
  -- Keyboard MO5 / MO6
  i_kbd: ENTITY work.kbd
    PORT MAP (
      model         => model,
      kbd           => kbd,
      kbdmode       => kbdmode,
      capslock      => capslock_to89,
      ps2_key       => ps2_key,
      pia_mo_pa_o   => pia_mo_pa_o,
      pia_mo_pa_d   => pia_mo_pa_d,
      pia_mo_pb_o   => pia_mo_pb_o,
      pia_mo_pb_i7  => pia_mo_pb_i(7),
      kbd_to7_o     => kbd_to7_o,
      kbd_to7_i     => kbd_to7_i,
      kbd_to8_ktest => kbd_to8_ktest,
      kbd_to8_data  => kbd_to8_data,
      kbd_to8_ack   => kbd_to8_ack,
      kbd_to9_ktest => kbd_to9_ktest,
      kbd_to9_txd   => kbd_to9_txd,
      kbd_to9_rxd   => kbd_to9_rxd,
      kbd_to9_ce    => kbd_to9_ce,
      tick_cpu      => tick_cpu,
      sysclk        => sysclk,
      reset_n       => reset_n);

  -- Keyboard MO5   : Mux + Demux + Matrix to PIA
  -- Keyboard MO6   : Mux + Demux + Matrix to PIA
  -- Keyboard TO7   : Direct matrix to PIA
  -- Keyboard TO770 : Mux + Direct matrix to PIA
  -- Keyboard TO8   : Protocole spécial bits durée variable
  -- Keyboard TO9   : ACIA 6850
  -- Keyboard TO9+  : ACIA 6850
  
  capslock <= capslock_to89;

  -----------------------------------------------------------------------------
  -- Light Pen mapped to PS2 mouse
  -- PS2_MOUSE(0)     : LEFT
  -- PS2_MOUSE(1)     : RIGHT
  -- PS2_MOUSE(2)     : MIDDLE
  -- PS2_MOUSE(4)     : X sign
  -- PS2_MOUSE(5)     : Y sign
  -- PS2_MOUSE(15:8)  : X diff
  -- PS2_MOUSE(23:16) : Y diff
  -- PS2_MOUSE(24)    : Toggle

  -- Compteur : (16 + 16 + 320) * 4
  -- 320 * 200 screen size
  -- *4 mouse resolution
  -- 16 pixels borders

  PROCESS(sysclk) IS
    VARIABLE tmp : integer RANGE -2048 TO 2047;
    VARIABLE halign, valign : boolean;
  BEGIN
    IF rising_edge(sysclk) THEN
      ps2_mouse_delay<=ps2_mouse;
      
      IF ps2_mouse(24)/=ps2_mouse_delay(24) THEN
        tmp:=mhpos+to_integer(signed(ps2_mouse(15 DOWNTO 8)));
        IF tmp<0 THEN tmp:=0; END IF;
        IF tmp>=(320+32)*4 -4 THEN tmp:=(320+32)*4 -4; END IF;
        mhpos <= tmp;
        
        tmp:=mvpos-to_integer(signed(ps2_mouse(23 DOWNTO 16)));
        IF tmp<0 THEN tmp:=0; END IF;
        IF tmp>=(200+32)*4 -4 THEN tmp:=(200+32)*4 -4; END IF;
        mvpos <= tmp;
      END IF;

      hpos <= mhpos/4;
      vpos <= mvpos/4;
      
      --VID_HPOS   80..95     96..415     416..431   < VIDEO
      --HPOS        0..15     16..335     336..351   < SOURIS
      halign := (vid_hpos = hpos + 80);
      
      --VID_VPOS    40..55    56..255     256..271   < VIDEO
      --VPOS         0..15    16..215     216..231   < SOURIS
      valign := (vid_vpos = vpos + 39) OR
                (vid_vpos = vpos + 40) OR
                (vid_vpos = vpos + 41) OR
                (vid_vpos = vpos + 42);
      
      lpen_align2 <= to_std_logic(halign AND valign);
      sh_align    <= lpen_align2 & sh_align(127 DOWNTO 1);

      IF model = T_TO9 THEN
        lpen_align <= sh_align(64) AND NOT mouse;
      ELSE
        lpen_align <= sh_align(0)  AND NOT mouse;
      END IF;

      lpen_button <= ps2_mouse(0);
      
      -- 1 cycle delay
      vid_ta2  <= vid_ta;
      vid_hin2 <= vid_hin;
      vid_vin2 <= vid_vin;
      vid_hlr2 <= vid_hlr;
      
      h_align <= vid_h & h_align(16*3-1 DOWNTO 3);

      CASE model IS
        WHEN T_TO770 | T_MO5 | T_TO9 =>
          vid_h2 <= vid_h;
        WHEN OTHERS =>
          vid_h2 <= h_align(2 DOWNTO 0);
      END CASE;

      -- TO7 Light Pen
      IF lpen_align = '1' THEN
        vid_latch_ta  <= vid_ta2;
        vid_latch_hin <= vid_hin2;
        vid_latch_vin <= vid_vin2;
      END IF;
      
    END IF;
  END PROCESS;


  -----------------------------------------------------------------------------
  MouseCalc:PROCESS(sysclk) IS
    VARIABLE diffx_v, diffy_v : integer RANGE -2048 TO 2047;
    CONSTANT EI : std_logic_vector(0 TO 3) := "0110";
    CONSTANT EQ : std_logic_vector(0 TO 3) := "0011";

  BEGIN
    IF rising_edge(sysclk) THEN
      -----------------------------------------------------------------------------      
      -----------------------------------------------------
      diffx_v := diffx;
      IF ps2_mouse(24)/=ps2_mouse_delay(24) THEN
        diffx_v := diffx_v + to_integer(signed(ps2_mouse(15 DOWNTO 8)));
      END IF;
      IF tick_mouse='1' THEN
        IF diffx_v > 0 THEN
          phasex <= (phasex+1) MOD 4;
          diffx_v := diffx_v - 1;
        ELSIF diffx_v < 0 THEN
          phasex <= (phasex-1 + 4) MOD 4;
          diffx_v := diffx_v + 1;
        END IF;
      END IF;

      diffx <= diffx_v;
      mouse_xi <= EI(phasex);
      mouse_xq <= EQ(phasex);

      -----------------------------------------------------
      diffy_v := diffy;
      IF ps2_mouse(24)/=ps2_mouse_delay(24) THEN
        diffy_v := diffy_v - to_integer(signed(ps2_mouse(23 DOWNTO 16)));
      END IF;
      IF tick_mouse='1' THEN
        IF diffy_v > 0 THEN
          phasey <= (phasey+1) MOD 4;
          diffy_v := diffy_v - 1;
        ELSIF diffy_v < 0 THEN
          phasey <= (phasey-1 + 4) MOD 4;
          diffy_v := diffy_v + 1;
        END IF;
      END IF;

      diffy <= diffy_v;
      mouse_yi <= EI(phasey);
      mouse_yq <= EQ(phasey);

      mouse_b1 <= ps2_mouse(0);
      mouse_b2 <= ps2_mouse(1);

      -----------------------------------------------------
      tick_mouse <= '0';
      IF tick_cpu='1' THEN
        cpt_mouse <= (cpt_mouse + 1) MOD 256;
      END IF;
      tick_mouse <= to_std_logic(cpt_mouse = 0) AND tick_cpu;

      -----------------------------------------------------
      IF reset_n='0' THEN
        diffx <= 0;
        diffy <= 0;
      END IF;
    END IF;
  END PROCESS MouseCalc;

  -----------------------------------------------------------------------------
  -- ROM Donwload
  Download:PROCESS(sysclk) IS
    VARIABLE wr_v : std_logic;
  BEGIN
    IF rising_edge(sysclk) THEN
      ioctl_wr2<=ioctl_wr;
      wr_v:=ioctl_wr AND NOT ioctl_wait_l;
      
      sdram_init <= '0';
      down_req <= '0';
      thmfc1_unload <= '0';
      
      -----------------------------------------------------
      down_reset <= '0';

      IF down_reset='1' OR hwreset_n='0' OR menureset='1' THEN
        cpu_reset_delay <= 31;
      ELSIF cpu_reset_delay > 0 THEN
        cpu_reset_delay <= cpu_reset_delay - 1;
      END IF;
      
      reset_n <= NOT to_std_logic(cpu_reset_delay >= 1 AND cpu_reset_delay <= 4);
      
      -----------------------------------------------------
      ioctl_download_tape <= '0';
      ioctl_download_disk <= '0';
      
      cpu_halt <= ioctl_download;
      
      -----------------------------------------------------
      CASE down_state IS
        ---------------------------------------------------
        -- SDRAM INIT
        WHEN sINIT =>
          down_state <= sINIT2;
          ioctl_wait_l <= '1';
          sdram_init <= '0';

        WHEN sINIT2 =>
          down_state <= sINIT3;
          ioctl_wait_l <= '1';
          sdram_init <= '1';

        WHEN sINIT3 =>
          IF sdram_ready='0' THEN
            down_state <= sINIT4;
          END IF;

        WHEN sINIT4 =>
          IF sdram_ready='1' THEN
            down_state <= sCLEAR;
          END IF;
          ioctl_wait_l <= '1';
          sdram_init <= '0';
        
        ---------------------------------------------------
        WHEN sCLEAR =>
          ioctl_wait_l <= '1';
          down_adrs <= (OTHERS =>'0');
          down_dw   <= x"00"; --FF";
          down_state <= sCLEAR2;
          tape_loaded <= '0';

        WHEN sCLEAR2 =>
          ioctl_wait_l <= '1';
          down_req <= '1';
          down_state <= sCLEAR3;

        WHEN sCLEAR3 =>
          ioctl_wait_l <= '1';
          down_req <= '1';
          IF down_ack='1' THEN
            down_req <= '0';
            down_state <= sCLEAR2;
            down_adrs <= down_adrs + 1;
            IF (NOT down_adrs) = 0 THEN
              --down_state <= sIDLE;
              down_state <= sDOWN_ROM;
            END IF;
          END IF;

        ---------------------------------------------------
        WHEN sIDLE =>
          ioctl_wait_l <= '0';
          IF ioctl_download='1' THEN
            ioctl_wait_l <= '1';
            IF sdram_ready='1' THEN
              CASE ioctl_index(1 DOWNTO 0) IS
                WHEN "00" => 
                  -- ROM (SDRAM)
                  --down_state <= sDOWN_ROM; --sSDRAM_INIT;
                  down_state <= sINIT;
                  down_badrs <= BASE_ROM;
                  cart_loaded <= '0';
                  thmfc1_unload <= '1';

                WHEN "01" =>
                  -- Cartridge (SDRAM)
                  down_state <= sDOWN_ROM;
                  down_badrs <= BASE_CART;
                  cart_loaded <= '1';

                WHEN "10" =>
                  --  TAPE (DDRAM)
                  ioctl_download_tape <= '1';
                  tape_loaded <= '1';
                  ioctl_wait_l <= ioctl_wait_tape;
          
                WHEN "11" =>
                  --  Floppy (DDRAM)
                  ioctl_download_disk <= '1';
                  ioctl_wait_l <= ioctl_wait_disk;

                WHEN OTHERS =>

              END CASE;
            END IF;
          END IF;
          
        ---------------------------------------------------
        WHEN sDOWN_ROM =>
          ioctl_wait_l <= '0';
          down_adrs <= ioctl_addr(19 DOWNTO 0) + down_badrs;
          down_dw   <= unsigned(ioctl_dout);
          IF ioctl_index(1 DOWNTO 0)="01" AND ioctl_wr='1' THEN
            -- Cartridge. Get size
            cart_size <= ioctl_addr(15 DOWNTO 14);
          END IF;
          IF ioctl_wr='1' AND ioctl_wr2='0' THEN
            down_req <= '1';
            ioctl_wait_l <= '1';
            down_state <= sDOWN_ROM2;
          END IF;
          IF ioctl_download='0' THEN
            down_state <= sRESET;
          END IF;

        WHEN sDOWN_ROM2 =>
          down_req <= '1';
          ioctl_wait_l <= '1';
          IF down_ack='1' THEN
            down_req <= '0';
            ioctl_wait_l <= '0';
            down_state <= sDOWN_ROM;
          END IF;

        WHEN sRESET =>
          down_reset <= '1';
          down_state <= sIDLE;
         
        ---------------------------------------------------
      END CASE;
      
      down_idle <= NOT ioctl_download; --to_std_logic(down_state = sIDLE);

      -----------------------------------------------------
      IF hwreset_n='0' THEN
        down_state <= sIDLE;
        
      END IF;

      -----------------------------------------------------
    END IF;
  END PROCESS Download;
    
  hwreset_n<=NOT reset AND pll_locked;

  -----------------------------------------------------------------------------
  -- Autoselect model from ROM CRC
  CRCCalc:PROCESS(sysclk) IS
  BEGIN
    IF rising_edge(sysclk) THEN
      IF ioctl_wr='1' AND ioctl_wr2='0' THEN
        crc<=crc8(unsigned(ioctl_dout),
                  mux(to_integer(unsigned(ioctl_addr))=0,x"FFFFFFFF",crc));
      END IF;
      
      FOR i IN 0 TO 31 LOOP
        xcrc(i)<=NOT crc(31-i);
      END LOOP;

      video_run <= '1';

      ioctl_download2 <= ioctl_download;
      
      IF search='0' THEN
        IF ioctl_download='0' AND ioctl_download2='1' AND ioctl_index(1 DOWNTO 0)="00" THEN
          search <= '1';
          found  <= '0';
        END IF;
        romcpt<=0;
      ELSE
        romcpt<=romcpt+1;
        IF xcrc=ROMS(romcpt).crc THEN
          model<=ROMS(romcpt).m;
          kbd  <=ROMS(romcpt).kb;
          found<='1';
        END IF;
        IF romcpt=ROMS'length-1 THEN
          search<='0';
        END IF;
        CASE modsel IS
          WHEN "000" => NULL; -- Keep detected value
          WHEN "001" => model <= T_MO5;
          WHEN "010" => model <= T_MO6;
          WHEN "011" => model <= T_TO7;
          WHEN "100" => model <= T_TO770;
          WHEN "101" => model <= T_TO8;
          WHEN "110" => model <= T_TO9;
          WHEN "111" => model <= T_TO9P;
          WHEN OTHERS => NULL;
        END CASE;
        CASE kbdsel IS
          WHEN "00" => NULL;
          WHEN "01" => kbd <= KB_FR;
          WHEN "10" => kbd <= KB_IT;
          WHEN "11" => kbd <= KB_DE;
          WHEN OTHERS => NULL;
        END CASE;
      END IF;
    END IF;
  END PROCESS CRCCalc;

  ioctl_wait<=ioctl_wait_l;
  
  -----------------------------------------------------------------------------
  -- Tape interface
  i_motape: ENTITY work.tape
    GENERIC MAP (SYSFREQ => 64000000)
    PORT MAP (
      motor_n            => tape_motor_n,
      tape_mo_rd         => tape_mo_rd,
      tape_mo_wr         => tape_mo_wr,
      tape_to_rd         => tape_to_rd,
      tape_to_wr         => tape_to_wr,
      model              => model,
      rewind             => rewind,
      tratio             => tratio,
      tshow              => tshow,
      ioctl_download     => ioctl_download_tape,
      ioctl_wr           => ioctl_wr,
      ioctl_addr         => ioctl_addr,
      ioctl_data         => ioctl_dout,
      ioctl_wait         => ioctl_wait_tape,
      tape_address       => tape_address,
      tape_write         => tape_write,
      tape_writedata     => tape_writedata,
      tape_byteenable    => tape_byteenable,
      tape_read          => tape_read,
      tape_burstcount    => tape_burstcount,
      tape_readdata      => tape_readdata,
      tape_readdatavalid => tape_readdatavalid,
      tape_waitrequest   => tape_waitrequest,
      speed              => speed,
      tick_cpu           => tick_cpu,
      sysclk             => sysclk,
      reset_n            => reset_n);

  tape_motor_n <= mux(isto(model),to_tape_motor_n,mo_tape_motor_n);

  -- Show tape progress bar
  tbaren <= bar AND tape_loaded AND tshow;
  
  -----------------------------------------------------------------------------
  -- AVALON MUX : FLOPPY / TAPE

  i_mux: entity work.avl_mux
    generic map (
      DATA_WIDTH => 64,
      ADDR_WIDTH => 29)
    port map (      
      s0_address       => tape_address,
      s0_burstcount    => tape_burstcount,
      s0_waitrequest   => tape_waitrequest,
      s0_read          => tape_read,
      s0_readdata      => tape_readdata,
      s0_readdatavalid => tape_readdatavalid,
      s0_write         => tape_write,
      s0_writedata     => tape_writedata,
      s0_byteenable    => tape_byteenable,
      
      s1_address       => disk_address,
      s1_burstcount    => disk_burstcount,
      s1_waitrequest   => disk_waitrequest,
      s1_read          => disk_read,
      s1_readdata      => disk_readdata,
      s1_readdatavalid => disk_readdatavalid,
      s1_write         => disk_write,
      s1_writedata     => disk_writedata,
      s1_byteenable    => disk_byteenable,
      
      m_address        => ddram_address,
      m_burstcount     => ddram_burstcount,
      m_waitrequest    => ddram_waitrequest,
      m_read           => ddram_read,
      m_readdata       => ddram_readdata,
      m_readdatavalid  => ddram_readdatavalid,
      m_write          => ddram_write,
      m_writedata      => ddram_writedata,
      m_byteenable     => ddram_byteenable,
      clk              => sysclk,
      reset_n          => reset_n);

  ddram_clk <= sysclk;
  
END ARCHITECTURE struct;
