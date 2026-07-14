--------------------------------------------------------------------------------
-- Thomson TOx MOx
--------------------------------------------------------------------------------
-- DO 3/2025
--------------------------------------------------------------------------------
-- MC6846 PIA / TIMER

-- (pas de ROM)
-- Modes Frequency Comparison / Pulse Width Comparison not implemented.

--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY mc6846 IS
  PORT (
    ------------------------------------
    ad     : IN  uv3;
    dw     : IN  uv8;
    dr     : OUT uv8;
    req    : IN  std_logic;
    ack    : OUT std_logic;
    wr     : IN  std_logic;
    
    irq    : OUT std_logic;
    ------------------------------------
    -- Timer
    cto    : OUT std_logic;
    ctg_n  : IN  std_logic;
    ctc_n  : IN  std_logic;

    -- Parallel port
    pp_i   : IN  uv8;
    pp_o   : OUT uv8;
    pp_d   : OUT uv8;

    cp1    : IN  std_logic;
    cp2_i  : IN  std_logic;
    cp2_o  : OUT std_logic;

    ------------------------------------
    tick_cpu : IN std_logic; -- 1MHz

    ------------------------------------
    clk     : IN std_logic;
    reset_n : IN std_logic
   );
END mc6846;

ARCHITECTURE rtl OF mc6846 IS

  -- IO
  SIGNAL pcr, pdr, ddrp : uv8;
  SIGNAL pp_in : uv8;
  SIGNAL pp_latch : std_logic;
  SIGNAL cp1_delay,cp1_trans : std_logic;
  SIGNAL cp2_delay,cp2_trans : std_logic;
  SIGNAL ctc_delay_n, ctg_delay_n, ctg_fe : std_logic;
  SIGNAL irqp1,irqp2 : std_logic;
  SIGNAL rd_ora_delay,rd_orb_delay,rw_orp_delay : boolean;
  SIGNAL csr_read : std_logic;

  -- TIMER
  SIGNAL irqt, irqt_set : std_logic;
  SIGNAL tcr : uv8;  -- Timer Control Reg
  SIGNAL tlr  : uv16; -- Timer Latch Reg
  SIGNAL count : uv16;
  SIGNAL tbh : uv8;
  SIGNAL tout : std_logic;
  SIGNAL sync, synco : std_logic;
  SIGNAL sync_cpt : uv3;
  SIGNAL mono : std_logic;

BEGIN
  
  ack<=req;
  
  pp_o <= pdr;
  pp_d <= ddrp;
  cto  <= tout;
  
  -----------------------------------------------------------------------------
  PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      --------------------------------------------
      cp1_delay<=cp1;
      cp2_delay<=cp2_i;
      
      cp1_trans <= (cp1   XNOR pcr(1)) AND (cp1_delay XOR pcr(1));
      cp2_trans <= (cp2_i XNOR pcr(4)) AND (cp2_delay XOR pcr(4));
      
      IF pcr(7)='1' OR reset_n='0' THEN
        cp1_trans <= '0';
        cp2_trans <= '0';
      END IF;
      -------------------------------------------
    END IF;
  END PROCESS;

  irq <= (irqt AND tcr(6)) OR (irqp1 AND pcr(0)) OR (irqp2 AND pcr(3));

  -----------------------------------------------------------------------------
  PROCESS(clk) IS
    VARIABLE rd_pdr_v, rw_pdr_v, wr_tlr_v : boolean;
  BEGIN
    IF rising_edge(clk) THEN
      rd_pdr_v := false;
      rw_pdr_v := false;
      wr_tlr_v := false;
      
      -------------------------------------------------------------------------
      CASE ad IS
        WHEN "000" | "100" => -- Composite Status Register
          dr(0) <= irqt;  -- Timer IRQ
          dr(1) <= irqp1; -- CP1 IRQ
          dr(2) <= irqp2; -- CP2 IRQ
          dr(6 DOWNTO 3) <= "0000";
          dr(7) <= (irqt AND tcr(6)) OR (irqp1 AND pcr(0)) OR (irqp2 AND pcr(3));
          IF wr='0' AND req='1' THEN
            csr_read <= '1';
          END IF;

        WHEN "001"         => -- Periperal Control Register (IO)
          IF wr='1' AND req='1' THEN
            pcr <= dw;
          END IF;
          dr<=pcr;

        WHEN "010"         => -- Data Direction Register (IO)
          IF wr='1' AND req='1' THEN
            ddrp <= dw;
          END IF;
          dr <= ddrp;
          
        WHEN "011"         => -- Peripheral Data Register (IO)
          IF wr='1' AND req='1' THEN
            pdr <= dw;
          END IF;
          dr <= (pp_i AND NOT ddrp) OR (pdr AND ddrp);
          rd_pdr_v := (wr='0' AND req='1');
          rw_pdr_v := (req='1' AND csr_read='1');
          
          IF req='1' THEN
            csr_read <= '0';
          END IF;

        WHEN "101"         => -- Timer Control Register
          IF wr='1' AND req='1' THEN
            tcr <= dw;
          END IF;
          dr <= tcr;

        WHEN "110"         => -- Timer MSB Register
          IF wr='1' AND req='1' THEN
            tbh <= dw;
          END IF;
          dr <= count(15 DOWNTO 8);
          --dr <= tbh; -- Timer buffer high

        WHEN "111"         => -- Timer LSB Register
          IF wr='1' AND req='1' THEN
            tlr <= tbh & dw;
            wr_tlr_v := true;
          END IF;
          dr <= count(7 DOWNTO 0);
          --dr <= tlr(7 DOWNTO 0);

        WHEN OTHERS => NULL;

      END CASE;
      
      -------------------------------------------------------------------------
      -- PARALLEL IO
      IF pcr(2)='1' THEN
        -- Latch Mode
        IF cp1_trans='1' AND pp_latch='0' THEN
          pp_in <= pp_i;
          pp_latch <= '1';
        END IF;
      ELSE
        pp_in <= pp_i;
        pp_latch <= '0';
      END IF;
      IF rd_pdr_v THEN
        pp_latch <= '0';
      END IF;

      -------------------------------------------
      rw_orp_delay<=rw_pdr_v;
      
      -------------------------------------------
      -- CSR1 is cleared after Peripheral Port reset or RD or WR PDR after read CSR.
      irqp1<=(irqp1 AND NOT to_std_logic(rw_pdr_v)) OR cp1_trans;
      irqp2<=(irqp2 AND NOT to_std_logic(rw_pdr_v)) OR (cp2_trans AND NOT pcr(5));
      
      -------------------------------------------
      IF pcr(5)='1' THEN
        -- CP2 as output
        IF pcr(4)='0' THEN
          -- Handshake
          -- <TODO> Probably wrong. Unused on TO
          IF rw_orp_delay THEN
            cp2_o<='0';
          END IF;
          IF pcr(3)='0' THEN
            IF cp1_trans='1' THEN
              cp2_o<='1';
            END IF;
          ELSE
            IF rw_orp_delay THEN
              cp2_o<='1';
            END IF;
          END IF;
        ELSE
          -- Simple output
          cp2_o <= pcr(3);
        END IF;
      END IF;

      IF (pcr(7)='1' AND req='0') OR reset_n='0' THEN
        -- RESET
        ddrp  <= x"00";
        pdr   <= x"00";
        irqp1 <= '0';
        irqp2 <= '0';
        pcr   <= x"80";
        csr_read <= '0';
      END IF;

      -------------------------------------------------------------------------
      -- TIMER
      
      -- Clock select/divider
      ctc_delay_n <= ctc_n; -- CTC forcé à zéro sur TO7 / TO8...

      IF tcr(1)='0' THEN -- Clock source
        synco <= ctc_n AND NOT ctc_delay_n;
      ELSE
        synco <= tick_cpu;
      END IF;

      IF synco = '1' THEN
        sync_cpt <= sync_cpt+1;
      END IF;

      IF tcr(2)='0' THEN -- Prescaler
        sync <= synco;
      ELSE
        sync <= to_std_logic(sync_cpt="111") AND synco;
      END IF;

      IF (tcr(0)='1' AND req='0') OR reset_n = '0' THEN
        tcr   <= x"01";
        sync_cpt <= "000";
        sync <='0';
      END IF;

      IF reset_n = '0' THEN
        tlr <= x"FFFF";
        tbh <= x"FF";
      END IF;
      -------------------------------------------
      irqt <= irqt OR irqt_set;

      irqt_set  <= '0'; -- INT

      ctg_delay_n <= ctg_n;
      ctg_fe <= ctg_delay_n AND NOT ctg_n; -- /CTG falling edge
      
      CASE tcr(5 DOWNTO 3) IS
        ---------------------------------------------------
        -- Continuous
        WHEN "000" | "010" =>
          --init : 000 CTG_falling or write_latches or (tcr=1 or reset=0)
          --init : 010 CTG_falling                  or (tcr=1 or reset=0)
          --int  : counter timeout
          -- continu. sortie initialisée à zéro, puis toggle tous les N+1 cycles
          
          IF sync='1' THEN
            count <= count - 1;
            IF count = x"0000" THEN
              count <= tlr;
              tout  <= NOT tout;
              irqt_set <= '1';
            END IF;
          END IF;

          IF (reset_n='0' OR tcr(0)='0') OR ctg_fe='1' OR
             (wr_tlr_v AND tcr(5 DOWNTO 3)="000") THEN
            count <= tlr;
            tout  <= '0';
            irqt  <= '0';
          END IF;

        ---------------------------------------------------
        -- Cascaded single shot
        WHEN "100" =>
          --init : CTG_falling or reset
          --int  : timeout
          -- la sortie est positionnée à 1 ou 0 selon l'état de TCR(7) à chaque timeout
          -- Le comptage continue après le pulse. Peut déclencher interruptions périodiques à chaque timeout.

          IF sync='1' THEN
            count <= count - 1;
            IF count = x"0000" THEN
              count <= tlr;
              tout  <= tcr(7);
              irqt_set <= '1';
            END IF;
          END IF;

          IF (reset_n='0' OR tcr(0)='1') OR ctg_fe='1' THEN
            count <= tlr;
            tout  <= '0';
            irqt  <= '0';
          END IF;

        ---------------------------------------------------
        -- Normal single shot
        WHEN "110" =>
          --init : CTG_falling or reset
          --int  : timeout
          -- sortie à 1 pendant N cycles, 
          -- avec 1 cycle de retard après l'activation. puis reste en bas.
          -- Le comptage continue après le pulse. Peut déclencher interruptions périodiques à chaque timeout.
          IF sync='1' THEN
            count <= count - 1;
            IF count = x"0000" THEN
              count <= tlr;
              tout  <= NOT mono;
              mono  <= '0';
              irqt_set <= '1';
            END IF;
          END IF;

          IF (reset_n='0' OR tcr(0)='1') OR ctg_fe='1' THEN
            count <= tlr;
            tout  <= '0';
            mono  <= '1';
            irqt  <= '0';
          END IF;

        -- !!! MODES 001 / 101 / 110 / 111 non implémentés dans MAME !!!
        -- Entrées CTG / CTC forcées à zéro => Inutilisables

        ---------------------------------------------------
        -- Frequency comparison
        --WHEN "001" =>
        
        -- Frequency comparison
        --WHEN "101" =>
        
        -- Pulse width comparison
        --WHEN "011" =>
        --  NULL;

        -- Pulse width comparison
        --WHEN "111" =>
        --  NULL;

       ---------------------------------------------------
        WHEN OTHERS =>
          IF (reset_n = '0' OR tcr(0)='1') OR ctg_fe='1' THEN
            count <= tlr;
            tout  <= '0';
            mono  <= '1';
            irqt  <= '0';
          END IF;


      END CASE;

      -------------------------------------------------------------------------

    END IF;
  END PROCESS;
  
  
END rtl;
