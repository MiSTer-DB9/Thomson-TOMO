--------------------------------------------------------------------------------
-- Thomson TOx MOx
--------------------------------------------------------------------------------
-- DO 1/2026
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY mc6850 IS
  PORT (
    ------------------------------------
    ad     : IN  std_logic; -- Register Select
    dw     : IN  uv8;
    dr     : OUT uv8;
    req    : IN  std_logic;
    ack    : OUT std_logic;
    wr     : IN  std_logic;
    
    ------------------------------------
    rx_clk  : IN  std_logic;
    rx_ce   : IN  std_logic; -- Clock Enable
    rx_d    : IN  std_logic;

    tx_clk  : IN  std_logic;
    tx_ce   : IN  std_logic; -- Clock Enable
    tx_d    : OUT std_logic;

    rts_n   : OUT std_logic; -- Request To Send
    cts_n   : IN  std_logic; -- Clear To Send
    dcd_n   : IN  std_logic; -- Data Carrier Detect

    ------------------------------------
    irq     : OUT std_logic;

    ------------------------------------
    clk     : IN std_logic;
    reset_n : IN std_logic
   );
END mc6850;

ARCHITECTURE rtl OF mc6850 IS

  SIGNAL cr : uv8; -- Control Register
  SIGNAL tdata, rdata : uv8;

  SIGNAL tnew : std_logic;
  SIGNAL tbusy, tbusy2, rfull : std_logic;
  SIGNAL rirq, rover  : std_logic;
  SIGNAL rnew, rnew2  : std_logic;
  SIGNAL tend0, tend1 : std_logic;
  SIGNAL irq_l : std_logic; 
  SIGNAL dcd2_n : std_logic;


  SIGNAL tstart, tend : std_logic;

  -------------------------------------
  -- TX
  SIGNAL tx_cr : uv8;
  SIGNAL tx_divclk : uint6;
  SIGNAL tx_tick : std_logic;
  SIGNAL tx_len, tx_cnt : uint4;
  SIGNAL tx_data : uv8;
  SIGNAL tx_shreg : uv11;
  SIGNAL tx_busy : std_logic;
  SIGNAL tx_new, tx_new_clr : std_logic;
  SIGNAL tx_new_sync, tx_new_sync2 : std_logic;
  SIGNAL tx_newl : std_logic;
  SIGNAL tx_end : std_logic;
  SIGNAL tx_reset_n : std_logic;

  -------------------------------------
  -- RX
  SIGNAL rx_cr : uv8;
  SIGNAL rx_divclk : uint6;
  SIGNAL rx_tick : std_logic;
  SIGNAL rx_reset_n : std_logic;
  SIGNAL rx_data : uv8;
  
  SIGNAL rx_busy : std_logic;
  SIGNAL rx_shreg : uv11;
  SIGNAL rx_cpt, rx_len : uint4;
  SIGNAL rx_new : std_logic;
  
  -------------------------------------
  FUNCTION par(d : uv8) RETURN std_logic IS
  BEGIN
    RETURN d(0) XOR d(1) XOR d(2) XOR d(3) XOR
           d(4) XOR d(5) XOR d(6) XOR d(7);
  END FUNCTION par;

  -------------------------------------

BEGIN
  
  ack<=req;

  irq <= irq_l;

  tx_reset_n <= reset_n WHEN rising_edge(tx_clk);
  rx_reset_n <= reset_n WHEN rising_edge(rx_clk);
  
  Reg:PROCESS(clk) IS
    
  BEGIN
    IF rising_edge(clk) THEN
      --------------------------------------------
      tstart <= '0';

      --------------------------------------------
      IF req='1' THEN
        IF ad = '1' THEN
          IF wr='1' THEN
            -- TDR : Trnsmit Data Register
            tdata  <= dw;
            tstart <= NOT tbusy;
            irq_l  <='0';
          ELSE
            -- RDR : Receive Data Register
            dr <= rdata;
            rover <= '0';
            rfull <= '0';
            irq_l <= '0';
          END IF;
          
        ELSE
          IF wr='1' THEN
            -- Control Register
            -- 1:0 = Counter Divide
            -- 4:2 = Word Select
            -- 6:5 = Tramit Control
            -- 7   = Receive Interrupt enable
            cr <= dw;
          ELSE
            -- Status Register
            dr(0) <= rfull;     -- Recive Data Register Full
            dr(1) <= NOT tbusy; -- Transmit Data Register Empty
            dr(2) <= dcd_n;     -- Data Carrier Detect
            dr(3) <= cts_n;     -- Clear To Send
            dr(4) <= '0';       -- Framing Error <TODO>
            dr(5) <= rover;     -- Receiver Overrun
            dr(6) <= '0';       -- Parity Error <TODO>
            dr(7) <= irq_l;     -- Interrupt Request
          END IF;
        END IF;
      END IF;

      --------------------------------------------
      tbusy  <= (tbusy OR tstart) AND NOT tend;
      tbusy2 <= tbusy;
      
      tnew <= tnew XOR tstart;

      tend0 <= tx_end; -- <ASYNC>
      tend1 <= tend0;

      tend <= tend0 XOR tend1;
      
      --------------------------------------------
      -- TX IRQ
      IF tbusy2='1' AND tbusy='0' AND cr(6 DOWNTO 5)="01" THEN
        irq_l <= '1';
      END IF;
      -- RX IRQ
      IF cr(7)='1' AND (rnew /=rnew2 OR (dcd2_n='0' AND dcd_n='1')) THEN
        irq_l <= '1';
      END IF;
      
      rnew  <= rx_new; -- <ASYNC>
      rnew2 <= rnew;
      IF rnew /= rnew2 THEN
        rfull <= '1';
        IF rfull='1' THEN
          rover <= '1';
        END IF;
        rdata <= rx_data; -- <ASYNC>
      END IF;

      rts_n <= cr(6) AND NOT cr(5); --"01"
      
      --------------------------------------------
      IF reset_n='0' OR cr(1 DOWNTO 0)="11" THEN
        tbusy <= '0';
        rover <= '0';
        tnew <= '0';
        irq_l <= '0';
      END IF;
    END IF;
  END PROCESS Reg;

  ---------------------------------------------------------
  -- TX
  Tx:PROCESS(tx_clk) IS
  BEGIN
    IF rising_edge(tx_clk) THEN
      tx_cr <= cr; -- <ASYNC>

      tx_data <= tdata; -- <ASYNC>
      tx_new_sync  <= tnew; -- <ASYNC>
      tx_new_sync2 <= tx_new_sync;
      tx_new <= tx_new_sync XOR tx_new_sync2;

      tx_newl <= (tx_newl OR tx_new) AND NOT tx_new_clr;

      -----------------------------------------------------
      tx_new_clr <= '0';
      IF tx_ce='1' THEN
        -- DIV
        tx_tick <= '0';
        tx_divclk <= (tx_divclk + 1) MOD 64;
        CASE tx_cr(1 DOWNTO 0) IS
          WHEN "00"   => tx_tick <= '1';
          WHEN "01"   => tx_tick <= to_std_logic(tx_divclk MOD 16 = 0);
          WHEN "10"   => tx_tick <= to_std_logic(tx_divclk = 0);
          WHEN OTHERS => tx_tick <= '0';
        END CASE;

        -- Transmit/Serialize
        IF tx_busy = '0' THEN
          tx_shreg(8 DOWNTO 0) <= tx_data & "0";
          CASE tx_cr(4 DOWNTO 2) IS
            WHEN "000"  => tx_len <= 11; tx_shreg(9 DOWNTO 8) <= "1" &     par("0" & tx_data(6 DOWNTO 0)); -- 7 EVEN 2
            WHEN "001"  => tx_len <= 11; tx_shreg(9 DOWNTO 8) <= "1" & NOT par("0" & tx_data(6 DOWNTO 0)); -- 7 ODD  2
            WHEN "010"  => tx_len <= 10; tx_shreg(9 DOWNTO 8) <= "1" &     par("0" & tx_data(6 DOWNTO 0)); -- 7 EVEN 1
            WHEN "011"  => tx_len <= 10; tx_shreg(9 DOWNTO 8) <= "1" & NOT par("0" & tx_data(6 DOWNTO 0)); -- 7 ODD  1
            WHEN "100"  => tx_len <= 11; tx_shreg(9)          <= '1';                                      -- 8 NO   2
            WHEN "101"  => tx_len <= 10; tx_shreg(9)          <= '1';                                      -- 8 NO   1
            WHEN "110"  => tx_len <= 11; tx_shreg(9)          <=     par(tx_data);                         -- 8 EVEN 1
            WHEN OTHERS => tx_len <= 11; tx_shreg(9)          <= NOT par(tx_data);                         -- 8 ODD  1
          END CASE;
          tx_cnt <= 0;
          
          IF tx_newl='1' THEN
            tx_busy <= '1';
            tx_new_clr <= '1';
          END IF;
        ELSE
          IF tx_tick = '1' THEN
            tx_d <= tx_shreg(0);
            tx_shreg(9 DOWNTO 0) <= "1" & tx_shreg(9 DOWNTO 1);
            tx_cnt <= tx_cnt + 1 ;
            IF tx_cnt + 1 = tx_len THEN
              tx_busy <= '0';
              tx_end  <= NOT tx_end;
            END IF;
          END IF;
        END IF;
      END IF;

      -----------------------------------------------------
      IF tx_reset_n='0' OR tx_cr(1 DOWNTO 0)="11" THEN
        tx_new  <= '0';
        tx_newl <= '0';
        tx_end  <= '0';
        tx_busy <= '0';
        tx_d <= '1';
      END IF;

      -----------------------------------------------------
    END IF;
  END PROCESS Tx;

  ---------------------------------------------------------

  ---------------------------------------------------------
  Rx:PROCESS(rx_clk) IS
  BEGIN
    IF rising_edge(rx_clk) THEN
      rx_cr <= cr; -- <ASYNC>

      -----------------------------------------------------
      IF rx_ce='1' THEN
        rx_tick <= '0';
        rx_divclk <= (rx_divclk + 1) MOD 64;
        CASE rx_cr(1 DOWNTO 0) IS
          WHEN "00"   => rx_tick <= '1'; -- /1
          WHEN "01"   => rx_tick <= to_std_logic(rx_divclk MOD 16 = 0); -- / 16;
          WHEN "10"   => rx_tick <= to_std_logic(rx_divclk = 0);        -- / 64;
          WHEN OTHERS => rx_tick <= '0';
        END CASE;

        -----------------------------------------------------
        IF rx_busy = '0' THEN
          rx_cpt <= 0;
          CASE rx_cr(4 DOWNTO 2) IS
            WHEN "000"  => rx_len <= 12; -- 7 EVEN 2
            WHEN "001"  => rx_len <= 12; -- 7 ODD  2
            WHEN "010"  => rx_len <= 11; -- 7 EVEN 1
            WHEN "011"  => rx_len <= 11; -- 7 ODD  1
            WHEN "100"  => rx_len <= 12; -- 8 NO   2
            WHEN "101"  => rx_len <= 11; -- 8 NO   1
            WHEN "110"  => rx_len <= 12; -- 8 EVEN 1
            WHEN OTHERS => rx_len <= 12; -- 8 ODD  1
          END CASE;
          CASE rx_cr(1 DOWNTO 0) IS
            WHEN "01"   => rx_divclk <= 8;
            WHEN "10"   => rx_divclk <= 32;
            WHEN OTHERS => rx_divclk <= 0;
          END CASE;
          IF rx_d = '0' THEN
            rx_busy <= '1';
          END IF;

        ELSE
          IF rx_tick ='1' THEN
            rx_shreg<=rx_d & rx_shreg(10 DOWNTO 1);
            CASE rx_cr(4 DOWNTO 2) IS
              WHEN "000"  => rx_data <= rx_shreg(7 DOWNTO 0); -- 7 EVEN 2
              WHEN "001"  => rx_data <= rx_shreg(7 DOWNTO 0); -- 7 ODD  2
              WHEN "010"  => rx_data <= rx_shreg(8 DOWNTO 1); -- 7 EVEN 1
              WHEN "011"  => rx_data <= rx_shreg(8 DOWNTO 1); -- 7 ODD  1
              WHEN "100"  => rx_data <= rx_shreg(7 DOWNTO 0); -- 8 NO   2
              WHEN "101"  => rx_data <= rx_shreg(8 DOWNTO 1); -- 8 NO   1
              WHEN "110"  => rx_data <= rx_shreg(7 DOWNTO 0); -- 8 EVEN 1
              WHEN OTHERS => rx_data <= rx_shreg(7 DOWNTO 0); -- 8 ODD  1
            END CASE;            
            rx_cpt <= rx_cpt + 1;
            IF (rx_cpt+1 = rx_len AND rx_cr(1 DOWNTO 0) ="00") OR
               (rx_cpt   = rx_len AND rx_cr(1 DOWNTO 0)/="00") THEN
              rx_busy <= '0';
              rx_new <= NOT rx_new;
            END IF;
          END IF;

        END IF;
      END IF;
      -----------------------------------------------------
      IF rx_reset_n='0' OR rx_cr(1 DOWNTO 0)="11" THEN
        rx_new <= '0';
        rx_busy <= '0';
      END IF;

      -----------------------------------------------------

    END IF;
  END PROCESS Rx;

  ---------------------------------------------------------
  
END rtl;

-- TO9+ : CR = D0 = 11010000
--                  ^          1 = Receive interrupt enable
--                   ^^       10 = TX IRQ Disable. /RTS=1
--                     ^^^   100 = 8bits + 2 STOR
--                        ^^  00 = /1
