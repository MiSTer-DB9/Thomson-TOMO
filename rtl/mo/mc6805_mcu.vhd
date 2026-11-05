--------------------------------------------------------------------------------
-- MC6809 MCU
--------------------------------------------------------------------------------
-- DO 10/2026
--------------------------------------------------------------------------------
-- MC6805U2 : ROM = 2K RAM = 64bytes


-- 000      : Port A DATA
-- 001      : Port B DATA
-- 002      : Port C DATA
-- 003      : Port D DATA
-- 004      : Port A DDR
-- 005      : Port B DDR
-- 006      : Port C DDR
-- 007      : Not Used
-- 008      : Timer DATA
-- 009      : Timer CONTROL
-- 00A      : Misc (not implemented)
-- 00B      : Programming Control Register (EPROM)
-- 00C      : Not Used
-- 00D      : Not Used
-- 00E      : A/D CONTROL (not implemented)
-- 00F      : A/D RESULT  (not implemented)
-- 010..07F : RAM
-- 080..FFF : ROM


LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

ENTITY mc6805_mcu IS
  GENERIC (
    -- Memory configuration
    LOGFILE        : string := "trace.log";
    RAM_SIZE       : integer := 64;   -- 64 or 112
    MASK_TIMER     : boolean := true; -- F=Programmabe T=Hardcoded
    MASK_PRESCALER : integer := 8;    -- /1 ... /128
    MASK_TIMER_EXT : boolean := false -- T=Timer input F=Internal
  );
  PORT (
    pa_i   : IN  uv8;
    pb_i   : IN  uv8;
    pc_i   : IN  uv8;
    pd_i   : IN  uv8;
    pa_o   : OUT uv8;
    pb_o   : OUT uv8;
    pc_o   : OUT uv8;
    pa_d   : OUT uv8;
    pb_d   : OUT uv8;
    pc_d   : OUT uv8;

    timer  : IN  std_logic;

    irq_n  : IN  std_logic;
    
    rom_ad : OUT unsigned(11 DOWNTO 0);
    rom_dr : IN  uv8;

    tick       : IN  std_logic;
    clk        : IN  std_logic;
    reset_na   : IN  std_logic
  );
END ENTITY mc6805_mcu;

ARCHITECTURE RTL OF mc6805_mcu IS

  -- CPU signals
  SIGNAL ad           : uv12;
  SIGNAL dr, dw       : uv8;
  SIGNAL req, ack, wr : std_logic;
  SIGNAL reqt : std_logic;

  SIGNAL rom_req, ram_req, io_req : std_logic;
  SIGNAL io_req2, ram_req2 : std_logic;

  SIGNAL pa_r, pa_ddr : uv8;
  SIGNAL pb_r, pb_ddr : uv8;
  SIGNAL pc_r, pc_ddr : uv8;

  SIGNAL timer_delay : std_logic;
  SIGNAL tim_n, tim_in, tim_int, tim_clr : std_logic;
  SIGNAL precount   : uv8;
  SIGNAL precount2  : uv8;
  SIGNAL tim_count  : uv8;
  SIGNAL tim_mask   : std_logic;
  SIGNAL tim_source : std_logic;
  SIGNAL tim_ena    : std_logic;
  SIGNAL prescaler  : uv3;
  
  SIGNAL prescaler_clr : std_logic;
  SIGNAL tick_tim : std_logic;
  SIGNAL timer_pulse : std_logic;

  SIGNAL ram : arr_uv8(0 TO 127);

  SIGNAL ram_dr, io_dr : uv8;
  
  CONSTANT NB_SP : natural := 5;
  
BEGIN

  -- CPU instance
  u_cpu: ENTITY work.mc6805_cpu
    GENERIC MAP (
      LOGFILE => LOGFILE,
      NB_SP => NB_SP
    )
    PORT MAP (
      ad         => ad,
      dw         => dw,
      dr         => dr,
      req        => req,
      ack        => ack,
      wr         => wr,
      tim_n      => tim_n,
      irq_n      => irq_n,
      reset_na   => reset_na,
      clk        => clk);

  CpuTicker:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      IF ack='1' AND req='1' THEN
        reqt <= '0';
      END IF;
      IF req='1' AND tick='1' THEN
        reqt <= '1';
      END IF;
    END IF;
  END PROCESS CpuTicker;

  rom_req  <= reqt AND to_std_logic(ad >= 16#80#);
  ram_req  <= reqt AND to_std_logic(ad >= 16#10# AND ad <= 16#7F#);
  io_req   <= reqt AND to_std_logic(ad <  16#10#);
  ack      <= tick;

  io_req2  <= io_req WHEN rising_edge(clk);
  ram_req2 <= ram_req WHEN rising_edge(clk);

  dr <= io_dr  WHEN io_req2='1' ELSE
        ram_dr WHEN ram_req2='1' ELSE
        rom_dr;

  rom_ad <= ad(11 DOWNTO 0);
  
  -----------------------------------------------------------------------------
  Rames:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      ram_dr <= ram(to_integer(ad(6 DOWNTO 0)));
      IF ram_req='1' AND wr='1' THEN
        ram(to_integer(ad(6 DOWNTO 0))) <= dw;
      END IF;
    END IF;
  END PROCESS Rames;

  -----------------------------------------------------------------------------
  
  -- 00..0F  : IO
  -- 10..7F  : RAM 
  -- 80..FFF : ROM (FF8..FFF : INT/RESET Vectors)

  pa_o <= pa_r;
  pb_o <= pb_r;
  pc_o <= pc_r;
  pa_d <= pa_ddr;
  pb_d <= pb_ddr;
  pc_d <= pc_ddr;
  
  Regs:PROCESS(clk) IS
  BEGIN
    IF reset_na='0' THEN
      prescaler  <= "000";
      tim_mask   <= '1';
      tim_source <= '1';
      tim_ena    <= '1';
      tim_count <= x"FF";
      pa_ddr <= x"00";
      pb_ddr <= x"00";
      pc_ddr <= x"00";
      pa_r <= x"00";
      pb_r <= x"00";
      pc_r <= x"00";

    ELSIF rising_edge(clk) THEN
      -----------------------------------------------------
      prescaler_clr <= '0';
      tim_clr       <= '0';

      -----------------------------------------------------
      case ad(3 DOWNTO 0) IS
        WHEN x"0" => -- Port A DATA
          IF wr='1' AND io_req='1' THEN
            pa_r <= dw;
          END IF;
          io_dr <= (pa_i AND NOT pa_ddr) OR (pa_r AND pa_ddr);

        WHEN x"1" => -- Port B DATA
          IF wr='1' AND io_req='1' THEN
            pb_r <= dw;
          END IF;
          io_dr <= (pb_i AND NOT pb_ddr) OR (pb_r AND pb_ddr);

        WHEN x"2" => -- Port C DATA
          IF wr='1' AND io_req='1' THEN
            pc_r <= dw;
          END IF;
          io_dr <= (pc_i AND NOT pc_ddr) OR (pc_r AND pc_ddr);

        WHEN x"3" => -- Port D DATA : Input only
          io_dr <= pd_i;

        WHEN x"4" => -- Port A DIRECTION
          IF wr='1' AND io_req='1' THEN
            pa_ddr <= dw;
          END IF;
          io_dr <= pa_ddr; -- (DDR regs should be write-only)

        WHEN x"5" => -- Port B DIRECTION
          IF wr='1' AND io_req='1' THEN
            pb_ddr <= dw;
          END IF;
          io_dr <= pb_ddr; -- (DDR regs should be write-only)

        WHEN x"6" => -- Port C DIRECTION
          IF wr='1' AND io_req='1' THEN
            pc_ddr <= dw;
          END IF;
          io_dr <= pc_ddr; -- (DDR regs should be write-only)
        
        WHEN x"8" => -- Timer Data
          IF wr='1' AND io_req='1' THEN

          END IF;
          io_dr  <= tim_count;
        
        WHEN x"9" => -- Timer Control
          --      R          |     W
          -- 7 INT request   | Clear IRQ    (RST=0)
          -- 6            INT MASK          (RST=1)
          -- 5      CLK Source 0=INT 1=EXT  (RST=1)
          -- 4      External Timer pin 0=Disable 1=Enable (RST=1)
          -- 3    0          | Prescaler clear
          -- 2           PRESCALER : /1 ... /128 
          -- 1           PRESCALER : /1 ... /128
          -- 0           PRESCALER : /1 ... /128
          IF wr='1' AND io_req='1' THEN
            prescaler <= dw(2 DOWNTO 0);
            prescaler_clr <= dw(3);
            tim_ena    <= dw(4);
            tim_source <= dw(5);
            tim_mask   <= dw(6);
            tim_clr    <= NOT dw(7);
          END IF;
          io_dr <= tim_int & tim_mask & tim_source & tim_ena & '0' & prescaler;
        WHEN x"A" => -- MISC

        WHEN OTHERS => -- A/D, Reserved => IGNORE
          io_dr <=x"00";
      END CASE;
      -----------------------------------------------------
      -- Mask programmed timer configuration
      IF MASK_TIMER THEN
        prescaler  <= to_unsigned(ilog2(MASK_PRESCALER),3);
        tim_source <= to_std_logic(MASK_TIMER_EXT);
      END IF;

      -----------------------------------------------------
      IF tick_tim = '1' THEN
        tim_count <= tim_count -1;
      END IF;

    END IF;
  END PROCESS Regs;
  
  -----------------------------------------------------------------------------
  TimerCo:PROCESS(clk) IS
  BEGIN
    IF reset_na='0' THEN
      precount <= x"01";
      tick_tim <= '0';
      tim_int  <= '0';
      tim_n <= '1';

    ELSIF rising_edge(clk) THEN
      
      timer_delay <= timer;
      timer_pulse <= (timer AND NOT timer_delay) AND tim_ena;

      tim_in <= mux(tim_source,timer_pulse,tick);

      IF tim_in='1' THEN
        precount <= precount + 2;
      END IF;
      precount(0) <= '1';
      IF prescaler_clr='1' THEN
        precount <= x"01";
      END IF;
      
      IF tim_in='1' THEN
        precount2 <= precount;
      END IF;

      tick_tim <= tim_in AND precount(to_integer(prescaler(2 DOWNTO 0))) AND
                         NOT precount2(to_integer(prescaler(2 DOWNTO 0)));

      IF tim_count=x"00" AND tick_tim='1' THEN
        tim_int <= '1';
      END IF;
      IF tim_clr='1' THEN
        tim_int <= '0';
      END IF;

      tim_n <= NOT (tim_int AND NOT tim_mask);

    END IF;
  END PROCESS TimerCo;

  -----------------------------------------------------------------------------
END ARCHITECTURE rtl;