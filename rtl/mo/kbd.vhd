--------------------------------------------------------------------------------
-- Thomson
--------------------------------------------------------------------------------
-- DO 3/2025
--------------------------------------------------------------------------------

-- Clavier MO5 / MO6

--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

LIBRARY work;
USE work.base_pack.ALL;
USE work.tomo_pack.ALL;
USE work.kbd_pack.ALL;

ENTITY kbd IS
  PORT (
    model      : IN type_model;
    kbd        : IN natural RANGE 0 TO 3;
    kbdmode    : IN unsigned(1 DOWNTO 0);
    capslock   : OUT std_logic;

    ps2_key    : IN  std_logic_vector(10 DOWNTO 0);
    
    -- MO5/MO6 : Matrix
    pia_mo_pa_o   : IN  uv8;
    pia_mo_pa_d   : IN  uv8;
    pia_mo_pb_o   : IN  uv8;
    pia_mo_pb_i7  : OUT std_logic;

    -- TO7 / TO770 : Matrix
    kbd_to7_o  : OUT uv8;
    kbd_to7_i  : IN  uv8; -- 8 bits TO7, 3bits demux TO770 +1bit data


    -- TO8 : Special Protocol
    kbd_to8_ktest : OUT std_logic;
    kbd_to8_data  : OUT std_logic;
    kbd_to8_ack   : IN  std_logic;
    
    -- TO9 / TO9+ : Uart
    kbd_to9_ktest : OUT std_logic;
    kbd_to9_txd   : OUT std_logic;
    kbd_to9_rxd   : IN  std_logic;
    kbd_to9_ce    : OUT std_logic;
    
    tick_cpu   : IN std_logic;
    sysclk     : IN std_logic;
    reset_n    : IN std_logic
    );
END kbd;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF kbd IS
  SIGNAL pia_mo_pa : uv8;

  SIGNAL ps2_key_delay, ps2_key_delay2, ps2_key_delay3 : std_logic_vector(10 DOWNTO 0);

  SIGNAL ckey : uv7;
  
  SIGNAL ps2_mat : std_logic_vector(127 DOWNTO 0);

  SIGNAL kcpt : natural RANGE 0 TO 127;
  
  SIGNAL pressed : std_logic;

  SIGNAL mo5_xy   : unsigned(7 DOWNTO 0); -- 0 <ligne> 0 <colonne>
  SIGNAL mo6_xy   : unsigned(7 DOWNTO 0); -- < ligne > 0 <colonne>
  SIGNAL to7_xy   : unsigned(7 DOWNTO 0); -- 0 <ligne> 0 <colonne>
  SIGNAL to8_code : unsigned(7 DOWNTO 0); -- ScanCode
  SIGNAL to8_az   : std_logic;            -- A...Z

  SIGNAL mat_mo5 : unsigned(63 DOWNTO 0);    -- MO5 Matrix
  SIGNAL mat_mo6 : unsigned(127 DOWNTO 0);   -- MO6 Matrix
  SIGNAL mat_to7 : unsigned(8*8-1 DOWNTO 0); -- TO7/TO770 Matrix

  SIGNAL to7_cpt : natural RANGE 0 TO 7;
  SIGNAL to7_acc : uv8;

  -------------------------------------
  SIGNAL mat_to8 : unsigned(127 DOWNTO 0);   -- Accumulated scancodes
  SIGNAL to8_req,to8_ack : std_logic;
  
  SIGNAL to8_lshift, to8_rshift : std_logic;
  SIGNAL to8_ctrl : std_logic;
  SIGNAL to8_caps : std_logic;
  SIGNAL kbd_to8_ack2 : std_logic;
  SIGNAL to8_ktest0, to8_ktest1, to8_ktest2, to8_ktest3 : std_logic;
  
  CONSTANT TO8_LENGTH_START : natural := 225;
  CONSTANT TO8_LENGTH_ONE   : natural := 56;
  CONSTANT TO8_LENGTH_ZERO  : natural := 38;
  CONSTANT TO8_LENGTH_GAP   : natural := 80;
  
  CONSTANT TO8_DELAY_START  : natural := 225;
  CONSTANT TO8_DELAY_INIT   : natural := 670;
  CONSTANT TO8_DELAY_UPPER  : natural := 1300; -- Caps Lock ON
  CONSTANT TO8_DELAY_LOWER  : natural := 1900; -- Caps Lock OFF
  CONSTANT TO8_DELAY_MAX    : natural := 2500;

  CONSTANT TO8_DELAY_INIT_START : natural := 100;
  CONSTANT TO8_DELAY_INIT_END   : natural := 69;
  CONSTANT TO8_DELAY_INIT_GAP   : natural := 214;
  
  -- From TEO Emulator
  CONSTANT TO8_MIN_DELAY_LOWER : natural := TO8_DELAY_LOWER - 300;
  CONSTANT TO8_MIN_DELAY_MAX   : natural := TO8_DELAY_MAX - 300;
  

  TYPE enum_to8_state IS (sIDLE,sPRE_WAIT,
                          sWAIT_ACK,sPRE_DELAY,sTRANS,sGAP,sEND,
                          sWAIT_REQ,sTEMPO,sTEMPO2,sTEMPO3,sTEMPO4);
  SIGNAL to8_state : enum_to8_state;
  SIGNAL to8_delay : natural RANGE 0 TO 4095;
  SIGNAL bcnt  : natural RANGE 0 TO 15;
  SIGNAL to8_shreg : unsigned(8 DOWNTO 0);

  -------------------------------------
  SIGNAL to9_treq, to9_ack : std_logic;
  SIGNAL to9_ctrl, to9_shift, to9_caps : std_logic;
  
  SIGNAL to9_div  : natural RANGE 0 TO 1023;
  SIGNAL to9_tdiv : natural RANGE 0 TO 15;
  SIGNAL to9_tick : std_logic;
  SIGNAL to9_rshreg, to9_tshreg : uv10;
  SIGNAL to9_rbitcount, to9_tbitcount : natural RANGE 0 TO 11;
  TYPE enum_to9_state IS (sIDLE, sTRANS);
  SIGNAL to9_tstate, to9_rstate : enum_to9_state;
  SIGNAL to9_acc : natural RANGE 0 TO 255;
  SIGNAL to9_tcode, to9_rcode : uv8;
  SIGNAL to9_rreq, to9_rreq_delay, to9_rreq_done : std_logic;
  SIGNAL to9_delcnt : natural RANGE 0 TO 4095;

BEGIN

  -- PS2(7:0) : Keycode
  -- PS2(8)   : E0 keycode
  -- PS2(9)   : 1=KeyON / 0=KeyOFF
  -- PS2(10)  : Toggle

  -- PS2 keycode to compressed keycodes
  -- Matrix of all pressed keys
  -- scan matrix => activate corresponding MO/TO keys in TOMO matrix
  capslock <= to8_caps;
  
  -----------------------------------------------------------------------------
  KeyCodes:PROCESS (sysclk) IS
    CONSTANT TO8_CODE_LSHIFT  : uv8 := x"51";
    CONSTANT TO8_CODE_RSHIFT  : uv8 := x"52";
    CONSTANT TO8_CODE_CTRL    : uv8 := x"53";
    CONSTANT TO9_CODE_SHIFT   : uv8 := x"A0";
    CONSTANT TO9_CODE_CONTROL : uv8 := x"A1";
    CONSTANT TO9_CODE_CAPS    : uv8 := x"A2";
  BEGIN
    IF rising_edge(sysclk) THEN
      -----------------------------------------------------
      ps2_key_delay  <= ps2_key;
      ps2_key_delay2 <= ps2_key_delay;
      ps2_key_delay3 <= ps2_key_delay2;

      ckey <= map_ps2k(to_integer(unsigned(ps2_key(8 DOWNTO 0))))(6 DOWNTO 0);

      IF ps2_key_delay2(10)/=ps2_key_delay(10) THEN
        ps2_mat(to_integer(ckey)) <= ps2_key_delay(9);
      END IF;

      -----------------------------------------------------
      -- MO5, MO6, TO7, TO770
      kcpt <= (kcpt + 1) MOD 128;

      mo5_xy <= map_mo5(kcpt);
      mo6_xy <= map_mo6(kcpt);
      to7_xy <= map_to7(kcpt);
      
      pressed <= ps2_mat(kcpt);

      IF mo5_xy /= x"FF" THEN mat_mo5(to_integer(mo5_xy(2 DOWNTO 0)) + to_integer(NOT mo5_xy(6 DOWNTO 4)) * 8) <= pressed; END IF;
      IF mo6_xy /= x"FF" THEN mat_mo6(to_integer(mo6_xy(2 DOWNTO 0)) + to_integer(NOT mo6_xy(7 DOWNTO 4)) * 8) <= pressed; END IF;
      IF to7_xy /= x"FF" THEN mat_to7(to_integer(to7_xy(2 DOWNTO 0)) + to_integer(NOT to7_xy(6 DOWNTO 4)) * 8) <= pressed; END IF;

      -----------------------------------------------------
      -- TO8
      to8_code <= map_to8(to_integer(ckey));
      to8_az   <= map_to8_caps(to_integer(ckey));

      to8_req <= '0';
      IF ps2_key_delay2(10)/=ps2_key_delay3(10) THEN
        IF to8_code = TO8_CODE_CTRL THEN
          to8_ctrl  <= ps2_key_delay2(9);
        ELSIF to8_code = TO8_CODE_LSHIFT THEN
          to8_lshift <= ps2_key_delay2(9);
        ELSIF to8_code = TO8_CODE_RSHIFT THEN
          to8_rshift <= ps2_key_delay2(9);
        ELSIF to8_code/=x"FF" THEN
          mat_to8(to_integer(to8_code(6 DOWNTO 0))) <= ps2_key_delay2(9);
          IF ps2_key_delay2(9)='1' THEN
            to8_req <= '1';
          END IF;
        END IF;
      END IF;

      to8_ktest0 <= to_std_logic(mat_to8(31 DOWNTO 0)   /= x"0000_0000");
      to8_ktest1 <= to_std_logic(mat_to8(63 DOWNTO 32)  /= x"0000_0000");
      to8_ktest2 <= to_std_logic(mat_to8(95 DOWNTO 64)  /= x"0000_0000");
      to8_ktest3 <= to_std_logic(mat_to8(127 DOWNTO 96) /= x"0000_0000");

      kbd_to8_ktest <= to8_ktest0 OR to8_ktest1 OR to8_ktest2 OR to8_ktest3;

      -----------------------------------------------------
      -- TO9+
      to9_tcode <= map_to9p(to_integer(ckey & to9_ctrl & (to9_shift XOR to9_caps)));

      to9_treq <= '0';
      IF ps2_key_delay2(10)/=ps2_key_delay3(10) THEN
        IF to9_tcode = TO9_CODE_CAPS THEN
          to9_caps  <= to9_caps XOR ps2_key_delay2(9);
        ELSIF to9_tcode = TO9_CODE_SHIFT THEN
          to9_shift <= ps2_key_delay2(9);
        ELSIF to9_tcode = TO9_CODE_CONTROL THEN
          to9_ctrl  <= ps2_key_delay2(9);
        ELSIF to9_tcode /= x"FF" THEN
          IF ps2_key_delay2(9)='1' THEN
            to9_acc <= to9_acc + 1;
          ELSIF to9_acc > 0 THEN
            to9_acc <= to9_acc - 1;
          END IF;
          IF ps2_key_delay2(9)='1' THEN
            to9_treq <= '1';
          END IF;
        END IF;
      END IF;

      IF to9_rreq_delay='1' THEN
        to9_treq <= '1';
        to9_tcode <= x"B4";
      END IF;

      kbd_to9_ktest <= to_std_logic(to9_acc > 0);

      -----------------------------------------------------
      IF reset_n='0' THEN
        ps2_mat <= (OTHERS =>'0');
        mat_mo5 <= (OTHERS =>'0');
        mat_mo6 <= (OTHERS =>'0');
        mat_to7 <= (OTHERS =>'0');
        mat_to8 <= (OTHERS =>'0');
        to8_ctrl   <='0';
        to8_lshift <= '0';
        to8_rshift <= '0';
        to8_req <= '0';
        to9_acc <= 0;
        to9_caps  <= '0';
        to9_shift <= '0';
        to9_ctrl  <= '0';
      END IF;
      -----------------------------------------------------
    END IF;
  END PROCESS KeyCodes;

  --------------------------------------------------------------------------
  -- SCAN MO5 / MO6 / TO7 / TO770
  scan_mo:PROCESS(sysclk) IS
    VARIABLE acc : uv8;
  BEGIN
    IF rising_edge(sysclk) THEN
      -- MO5 / MO6
      -- 74LS156 DEMUX => matrix => 74LS151 MUX : Negative logic : 0=pressed
      IF model = T_MO5 THEN
        pia_mo_pb_i7 <= NOT mat_mo5(to_integer(pia_mo_pb_o(6 DOWNTO 1)));
      ELSE
        --pia_mo_pb_i7 <= NOT mat_mo6(to_integer(pia_mo_pa(3) & pia_mo_pb_o(6 DOWNTO 4)  & pia_mo_pb_o(3 DOWNTO 1)));
        pia_mo_pb_i7 <= NOT mat_mo6(to_integer(pia_mo_pa(3) & NOT pia_mo_pb_o(3 DOWNTO 1)  & pia_mo_pb_o(6 DOWNTO 4)));
      END IF;
      
      -- TO7
      -- Direct port B => matrix => port A. Pull-ups. Negative logic.
      to7_cpt <= (to7_cpt + 1) MOD 8;
      acc := to7_acc;
      IF to7_cpt = 0 THEN
        acc := x"00";
      END IF;
      IF kbd_to7_i(7-to7_cpt)='0' THEN
        acc := acc OR mat_to7(to7_cpt*8+7 DOWNTO to7_cpt*8);
      END IF;
      to7_acc <= acc;
      IF to7_cpt = 7 AND model = T_TO7 THEN
        kbd_to7_o <= NOT acc;
      END IF;

      -- TO 770
      -- 74LS156 DEMUX => matrix => port A. Pull-ups. Negative logic.
      IF model = T_TO770 THEN
        kbd_to7_o <= NOT mat_to7(to_integer(kbd_to7_i(2 DOWNTO 0))*8+7 DOWNTO to_integer(kbd_to7_i(2 DOWNTO 0))*8);
      END IF;

    END IF;
  END PROCESS scan_mo;

  pia_mo_pa <= pia_mo_pa_o OR NOT pia_mo_pa_d; -- Internal pull-up in MC6821 port A.

  --------------------------------------------------------------------------
  -- TO8 serial protocol
  -- 9 bits :
  --  * 1 CNT (control)
  --  * 1 SHIFT / CAPSLOCK ON
  --  * 7 Keycode
    
  to8:PROCESS(sysclk) IS
    CONSTANT TO8_CODE_CAPS    : uv8 := x"40";
  BEGIN
    IF rising_edge(sysclk) THEN
      -----------------------------------------------------
      IF tick_cpu = '1' THEN
        to8_delay <= (to8_delay + 1) MOD 4096;
      END IF;
      to8_ack <= '0';

      kbd_to8_ack2 <= kbd_to8_ack;

      CASE to8_state IS
        ---------------------------------------------------      
        WHEN sIDLE =>
          kbd_to8_data <= '1';
          bcnt <= 0;
          to8_shreg(8)          <= to8_ctrl;
          to8_shreg(7)          <= to8_lshift OR to8_rshift OR (to8_caps AND to8_az);
          to8_shreg(6 DOWNTO 0) <= to8_code(6 DOWNTO 0);
          IF to8_code = TO8_CODE_CAPS THEN
            to8_shreg(8 DOWNTO 7) <= "00";
            to8_caps <= to8_caps XOR to8_req;
          END IF;

          to8_delay <= 0;

          -- Send keycode
          IF to8_req = '1' THEN
            to8_state <= sPRE_WAIT;
            to8_ack <= '1';
          END IF;

          IF kbd_to8_ack='0' AND kbd_to8_ack2='1' THEN
            to8_state <= sWAIT_REQ;
          END IF;

        ---------------------------------------------------
        WHEN sPRE_WAIT =>
          kbd_to8_data <= '1';
          IF to8_delay >= TO8_DELAY_START THEN
            to8_state <= sWAIT_ACK;
          END IF;
          
        WHEN sWAIT_ACK =>
          to8_delay <= 0;
          kbd_to8_data <= '0';
          IF kbd_to8_ack='0' THEN
            to8_state <= sPRE_DELAY;
          END IF;
          
        WHEN sPRE_DELAY =>
          IF to8_delay >= TO8_LENGTH_START THEN
            to8_state <= sTRANS;
            to8_delay <= 0;
          END IF;

        WHEN sTRANS =>
          kbd_to8_data <= '1';
          IF (to8_shreg(8)='1' AND to8_delay >= TO8_LENGTH_ONE) OR
             (to8_shreg(8)='0' AND to8_delay >= TO8_LENGTH_ZERO) THEN
            to8_delay <= 0;
            to8_state <= sGAP;
          END IF;

        WHEN sGAP =>
          kbd_to8_data <= '0';
          IF to8_delay >= TO8_LENGTH_GAP THEN
            to8_delay <= 0;
            to8_shreg <= to8_shreg(7 DOWNTO 0) & '0';
            bcnt <= bcnt + 1;
            IF bcnt < 8 THEN
              to8_state <= sTRANS;
            ELSE
              to8_state <= sEND;
            END IF;
          END IF;
          
        WHEN sEND =>
          IF kbd_to8_ack ='1' THEN
            to8_state <= sIDLE;
          END IF;

        ---------------------------------------------------
        WHEN sWAIT_REQ =>
          IF to8_delay >= TO8_DELAY_INIT_START *3 THEN
            to8_state <= sTEMPO;
            to8_delay <= 0;
          END IF;

        WHEN sTEMPO =>
          kbd_to8_data <= '0';
          -- <TODO> Vérifier sur un vrai TO8 !!!
          IF to8_delay >= 120 THEN
            to8_state <= sTEMPO2;
          END IF;

        WHEN sTEMPO2 =>
          IF kbd_to8_ack='1' THEN
            to8_delay <= 0;
            IF to8_delay < TO8_MIN_DELAY_LOWER OR
               to8_delay > TO8_MIN_DELAY_MAX   THEN
              to8_caps <= '1';
            ELSE
              to8_caps <= '0';
            END IF;
            to8_state <= sTEMPO3;
          END IF;
          -- NO ACK. Bug in TO8 ROM?
          IF to8_delay > TO8_DELAY_MAX THEN
            to8_state <= sTEMPO3;
            to8_shreg <= "001001000";
            to8_state <= sWAIT_ACK;
          END IF;

        WHEN sTEMPO3 =>
          IF to8_delay >= TO8_DELAY_INIT_END THEN
            kbd_to8_data <= '1';
            to8_delay <= 0;
            to8_state <= sTEMPO4;
          END IF;

        WHEN sTEMPO4 =>
          IF to8_delay >= TO8_DELAY_INIT_GAP THEN
            to8_shreg <= "001001000";
            to8_state <= sWAIT_ACK;
          END IF;
        ---------------------------------------------------

      END CASE;

      -----------------------------------------------------
      IF reset_n='0' THEN
        to8_state <= sIDLE;
        to8_caps  <= '0';
      END IF;
      -----------------------------------------------------

    END IF;
  END PROCESS;

  --------------------------------------------------------------------------
  -- TO9+ : Réception code clavier : 3 bits utiles:
  -- F8 = 000 = RESET
  --            Attente 4ms
  --            
  -- F9 = 001 = CAPS=1
  -- FA = 010 = CAPS=0
  -- FB = 011 = VT100=1 ???
  -- FC = 100 = VT100=0 ???
  -- FD = 101 = 
  -- FE = 110 = 
  -- FF = 111 = 

  -- 9600 bauds = 4M / 417 = 64M / 16 / 417
  
  DivClk:PROCESS(sysclk) IS
  BEGIN
    IF rising_edge(sysclk) THEN
      to9_tick <= '0';
      kbd_to9_ce <= '0';

      IF to9_div < 80 THEN --16 * 417 THEN
        to9_div <= to9_div + 1;
      ELSE
        kbd_to9_ce <= '1';
        to9_div <= 0;
        to9_tdiv <= (to9_tdiv + 1) MOD 16;
        -- TO9  : ACIA /16 mode
        -- TO9+ : ACIA /1  mode
        IF (to9_tdiv=0 AND model = T_TO9) OR model /= T_TO9 THEN
          to9_tick <= '1';
        END IF;

      END IF;
    END IF;
  END PROCESS DivClk;

  ----------------------------------------------------------
  -- TO9 & TO9+ : UART
  to9p:PROCESS(sysclk) IS
    FUNCTION par(d : uv8) RETURN std_logic IS
    BEGIN
      RETURN d(0) XOR d(1) XOR d(2) XOR d(3) XOR d(4) XOR d(5) XOR d(6) XOR d(7);
    END FUNCTION;
  BEGIN
    IF rising_edge(sysclk) THEN
      -----------------------------------------------------
      CASE to9_tstate IS
        WHEN sIDLE =>
          kbd_to9_txd <= '1';
          IF model = T_TO9P THEN
            -- TO9+ : 8bits      2stop
            to9_tshreg  <= '1' & to9_tcode & '0';
          ELSE
            -- TO9  : 8bits even 1stop
            to9_tshreg  <= par(to9_tcode) & to9_tcode & '0';
          END IF;
          to9_tbitcount <= 0;
          IF to9_treq ='1' THEN
            to9_tstate <= sTRANS;
          END IF;

        WHEN sTRANS =>
          IF to9_tick='1' THEN
            kbd_to9_txd <= to9_tshreg(0);
            to9_tshreg  <= '1' & to9_tshreg(9 DOWNTO 1);
            to9_tbitcount <= to9_tbitcount + 1;
            IF to9_tbitcount = 9 THEN
              to9_tstate <= sIDLE;
            END IF;
          END IF;
      END CASE;

      -----------------------------------------------------
      to9_rreq <='0';

      IF to9_tick='1' THEN
        to9_rshreg <= kbd_to9_rxd & to9_rshreg(9 DOWNTO 1);
      END IF;

      CASE to9_rstate IS
        WHEN sIDLE =>
          to9_rbitcount <= 0;
          IF to9_tick='1' THEN
            IF kbd_to9_rxd='0' THEN
              to9_rstate <= sTRANS;
            END IF;
          END IF;

        WHEN sTRANS =>
          IF to9_tick='1' THEN
            to9_rbitcount <= to9_rbitcount + 1;
            IF to9_rbitcount = 9 THEN
              to9_rcode <= to9_rshreg(7 DOWNTO 0);
              to9_rstate <= sIDLE;
              to9_rreq <='1';
            END IF;
          END IF;

      END CASE;

      -----------------------------------------------------
      to9_rreq_delay <= '0';
      IF tick_cpu='1' THEN
        IF to9_delcnt < 4000 THEN
          to9_delcnt <= to9_delcnt + 1;
          to9_rreq_done <= '0';
        ELSE
          IF to9_rreq_done='0' THEN
            to9_rreq_delay <= '1';
            to9_rreq_done <= '1';
          END IF;
        END IF;
      END IF;
      IF to9_rreq='1' THEN
        to9_delcnt <= 0;
      END IF;

      IF reset_n='0' THEN
        to9_rstate <= sIDLE;
        to9_tstate <= sIDLE;
        to9_delcnt <= 0;
        to9_rreq_done <= '0';
      END IF;
      -----------------------------------------------------
    END IF;
  END PROCESS;

  --------------------------------------------------------------------------

END ARCHITECTURE rtl;
