LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.NUMERIC_STD.ALL;

ENTITY avl_mux IS
  GENERIC (
    DATA_WIDTH : integer := 64;
    ADDR_WIDTH : integer := 32
    );
  PORT (
    -- Slave 0
    s0_address       : IN  unsigned(ADDR_WIDTH-1 DOWNTO 0);
    s0_burstcount    : IN  unsigned(7 DOWNTO 0);
    s0_waitrequest   : OUT std_logic;
    s0_read          : IN  std_logic;
    s0_readdata      : OUT std_logic_vector(DATA_WIDTH-1 DOWNTO 0);
    s0_readdatavalid : OUT std_logic;
    s0_write         : IN  std_logic;
    s0_writedata     : IN  std_logic_vector(DATA_WIDTH-1 DOWNTO 0);
    s0_byteenable    : IN  std_logic_vector(DATA_WIDTH/8-1 DOWNTO 0);

    -- Slave 1
    s1_address       : IN  unsigned(ADDR_WIDTH-1 DOWNTO 0);
    s1_burstcount    : IN  unsigned(7 DOWNTO 0);
    s1_waitrequest   : OUT std_logic;
    s1_read          : IN  std_logic;
    s1_readdata      : OUT std_logic_vector(DATA_WIDTH-1 DOWNTO 0);
    s1_readdatavalid : OUT std_logic;
    s1_write         : IN  std_logic;
    s1_writedata     : IN  std_logic_vector(DATA_WIDTH-1 DOWNTO 0);
    s1_byteenable    : IN  std_logic_vector(DATA_WIDTH/8-1 DOWNTO 0);

    -- Master
    m_address       : OUT unsigned(ADDR_WIDTH-1 DOWNTO 0);
    m_burstcount    : OUT unsigned(7 DOWNTO 0);
    m_waitrequest   : IN  std_logic;
    m_read          : OUT std_logic;
    m_readdata      : IN  std_logic_vector(DATA_WIDTH-1 DOWNTO 0);
    m_readdatavalid : IN  std_logic;
    m_write         : OUT std_logic;
    m_writedata     : OUT std_logic_vector(DATA_WIDTH-1 DOWNTO 0);
    m_byteenable    : OUT std_logic_vector(DATA_WIDTH/8-1 DOWNTO 0);
    
    clk             : IN std_logic;
    reset_n         : IN std_logic
    );
END avl_mux;

ARCHITECTURE rtl OF avl_mux IS

  TYPE enum_state IS (sIDLE,sREAD,sWRITE);
  SIGNAL state, state_c : enum_state;

  SIGNAL sel0, sel0_c : std_logic;
  SIGNAL sel1, sel1_c : std_logic;
  SIGNAL count, count_c : unsigned(7 DOWNTO 0);
  
BEGIN

  s0_readdata      <= m_readdata;
  s1_readdata      <= m_readdata;
  s0_readdatavalid <= m_readdatavalid AND sel0;
  s1_readdatavalid <= m_readdatavalid AND sel1;

  Moxo:PROCESS(
    s0_address, s0_burstcount, s0_read, s0_write, s0_writedata, s0_byteenable,
    s1_address, s1_burstcount, s1_read, s1_write, s1_writedata, s1_byteenable,
    m_waitrequest, m_readdatavalid, sel0, sel1, state, count) IS

  BEGIN
    -------------------------------------------------------
    m_address      <= s0_address;
    m_burstcount   <= s0_burstcount;
    m_read         <= s0_read;
    m_write        <= s0_write;
    m_writedata    <= s0_writedata;
    m_byteenable   <= s0_byteenable;
    s0_waitrequest <= '1';
    s1_waitrequest <= '1';

    state_c <= state;
    count_c <= count;
    sel0_c  <= sel0;
    sel1_c  <= sel1;

    CASE state IS
      -----------------------------------------------------
      WHEN sIDLE =>
        sel0_c <= '0';
        sel1_c <= '0';
        
        IF s0_read='1' AND m_waitrequest='0' THEN
          state_c        <= sREAD;
          count_c        <= s0_burstcount;
          sel0_c         <= '1';
          sel1_c         <= '0';
          s0_waitrequest <= m_waitrequest;

        ELSIF s0_write='1' THEN
          IF m_waitrequest='0' AND s0_burstcount > 1 THEN
            state_c        <= sWRITE;
          END IF;
          sel0_c         <= '1';
          sel1_c         <= '0';
          count_c        <= s0_burstcount;
          s0_waitrequest <= m_waitrequest;

        ELSIF s1_read='1' AND m_waitrequest='0' THEN
          state_c        <= sREAD;
          count_c        <= s1_burstcount;
          sel0_c         <= '0';
          sel1_c         <= '1';
          s1_waitrequest <= m_waitrequest;
          m_address      <= s1_address;
          m_burstcount   <= s1_burstcount;
          m_read         <= s1_read;
          m_write        <= s1_write;
          m_writedata    <= s1_writedata;
          m_byteenable   <= s1_byteenable;

        ELSIF s1_write='1' THEN
          IF m_waitrequest='0' AND s1_burstcount > 1 THEN
            state_c        <= sWRITE;
          END IF;
          sel0_c         <= '0';
          sel1_c         <= '1';
          count_c        <= s1_burstcount;
          s1_waitrequest <= m_waitrequest;
          m_address      <= s1_address;
          m_burstcount   <= s1_burstcount;
          m_read         <= s1_read;
          m_write        <= s1_write;
          m_writedata    <= s1_writedata;
          m_byteenable   <= s1_byteenable;

        END IF;

      -----------------------------------------------------
      WHEN sREAD =>
        m_read  <= '0';
        m_write <= '0';
        IF m_readdatavalid='1' THEN
          count_c <= count - 1;
          IF count=1 THEN
            sel0_c <= '0';
            sel1_c <= '0';
            state_c <= sIDLE;
          END IF;
        END IF;

      -----------------------------------------------------
      WHEN sWRITE =>
        m_read  <= '0';
        IF sel1='1' THEN
          m_write        <= s1_write;
          m_writedata    <= s1_writedata;
          m_byteenable   <= s1_byteenable;
        END IF;
        s0_waitrequest <= m_waitrequest OR NOT sel0;
        s1_waitrequest <= m_waitrequest OR NOT sel1;
        
        IF m_waitrequest='0' AND
          ((sel1='1' AND s1_write='1') OR 
           (sel0='1' AND s0_write='1')) THEN
          count_c <= count - 1;
          IF count=2 THEN
            sel0_c <= '0';
            sel1_c <= '0';
            state_c <= sIDLE;
          END IF;
        END IF;

      -----------------------------------------------------
    END CASE;
  END PROCESS Moxo;

  ---------------------------------------------------------
  Seq:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN
      state <= state_c;
      count <= count_c;
      
      sel0  <= sel0_c;
      sel1  <= sel1_c;

      IF reset_n='0' THEN
        state <= sIDLE;
      END IF;

    END IF;
  END PROCESS Seq;

  ---------------------------------------------------------

END rtl;
