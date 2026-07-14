--------------------------------------------------------------------------------
-- Thomson TOx MOx
--------------------------------------------------------------------------------
-- DO 3/2025
--------------------------------------------------------------------------------
-- THMFC1

-- Floppy / QDD TO8 // TO9+

--------------------------------------------------------------------------------
-- BASED ON TEO Emulator
--------------------------------------------------------------------------------

-- Accès registres

-- Commandes intelligentes

-- Lecture et encodage disque

--------------------------------------------------------------------------------

LIBRARY IEEE;
USE IEEE.std_logic_1164.all;
USE IEEE.numeric_std.all;

USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.thmfc1_pack.ALL;

ENTITY thmfc1 IS
  PORT (
    ------------------------------------
    ad     : IN  uv4;
    dw     : IN  uv8;
    dr     : OUT uv8;
    req    : IN  std_logic;
    ack    : OUT std_logic;
    wr     : IN  std_logic;

    unload : IN std_logic;

    fdbank : OUT uv2;

    ------------------------------------
    ioctl_download : IN  std_logic;
    ioctl_wr       : IN  std_logic;
    ioctl_addr     : IN  unsigned(24 DOWNTO 0);
    ioctl_data     : IN  std_logic_vector(7 DOWNTO 0);
    ioctl_wait     : OUT std_logic;
    
    ------------------------------------
    avl_address       : OUT unsigned(28 DOWNTO 0);
    avl_write         : OUT std_logic;
    avl_writedata     : OUT std_logic_vector(63 DOWNTO 0);
    avl_byteenable    : OUT std_logic_vector(7 DOWNTO 0);
    avl_read          : OUT std_logic;
    avl_burstcount    : OUT unsigned(7 DOWNTO 0);
    avl_readdata      : IN  std_logic_vector(63 DOWNTO 0);
    avl_readdatavalid : IN  std_logic;
    avl_waitrequest   : IN  std_logic;
    
    -- Overlay bar
    dmotor         : OUT std_logic;
    dratio         : OUT uv8;
    dshow          : OUT std_logic;

    -- Debug overlay
    dd_motor  : OUT std_logic;
    dd_finish : OUT std_logic;
    dd_track  : OUT uv8;
    dd_sector : OUT uv8;
    dd_head   : OUT std_logic;

    ------------------------------------
    tick_cpu  : IN  std_logic; -- 1MHz

    ------------------------------------
    clk       : IN std_logic;
    reset_n   : IN std_logic;
    hwreset_n : IN std_logic
   );
END thmfc1;

ARCHITECTURE rtl OF thmfc1 IS

  --               |   7   |   6   |   5   |   4   |   3   |   2   |   1   |   0   |
  -- 0 : W  CMD0       0       0     FM/MFM  SYNCHRO SYNCH   WGN      [ OPERATION ]
  -- 1 : W  CMD1    COMPAT   [ LEN SECT  ]   FACE     [  PRECOMPENSATION ]   INHIBIT
  -- 2 : W  CMD2      n.u.  Motor   Mot Dir Pas      n.u.    Motor    [ Select drive]
  
  -- 0 : R  STAT0   DRQ      0        0     END_OP  END_OP  CRC_ERR  CLK    OK
  -- 1 : R  STAT1    0      index   change  motor   piste0  protwr   ready      0

  -- 3 : W  WDATA
  -- 3 : R  RDATA

  -- 4 : W  CLOCK  Config horloge data / sync

  -- 5 : W  WSECT  Numéro secteur cherché

  -- 6 : W  WTRCK  Numéro de piste

  ---7 : W  WCELL  séparateur [        Compteur séparateur                      ]

  CONSTANT INTL_RESET        : uv2 := "00";
  CONSTANT INTL_WRITE_SECTOR : uv2 := "01";
  CONSTANT INTL_READ_ADDRESS : uv2 := "10";
  CONSTANT INTL_READ_SECTOR  : uv2 := "11";
  
  SIGNAL intl_sector_size : uv2;
  SIGNAL intl_side : std_logic;

  SIGNAL stat0, stat1      : uv8;
  SIGNAL wclk, wsect, wtrk : uv8;

  SIGNAL reg_wclk,    reg_wdata : uv8;
  SIGNAL reg_wclk_up, reg_wdata_up : std_logic;
  SIGNAL disk_wclk,   disk_wdata : uv8;
  SIGNAL disk_wdata_up : std_logic;

  ---------------------------------------------------------

  SIGNAL tick_disk, tick_disk2 : std_logic;
  SIGNAL tick_cpt  : natural RANGE 0 TO 63;

  SIGNAL intl_start : std_logic;
  SIGNAL intl_cmd   : unsigned(1 DOWNTO 0);
  SIGNAL data_ready, data_ready_clr : std_logic;
  SIGNAL intl_finished, intl_finished_set, intl_finished_clr : std_logic;
  SIGNAL disk_write, disk_write_set, disk_write_clr : std_logic;
  SIGNAL crc_error, crc_error_set, crc_error_clr : std_logic;

  SIGNAL dreq, dreq_clr : std_logic;

  SIGNAL wdata : uv8;
  SIGNAL crc : uv16;

  SIGNAL track : natural RANGE 0 TO 127;

  SIGNAL motor_on, motor_start : std_logic;
  CONSTANT MOTOR_ON_DELAY : natural := 2_000_000; -- 2 seconds until stop
  SIGNAL motor_cpt : natural RANGE 0 TO MOTOR_ON_DELAY;

  SIGNAL auto_count : natural RANGE 0 TO 1024;

  CONSTANT TRACK_LEN      : natural := 8192;
  CONSTANT SIZE_PER_SIDE  : natural := TRACK_LEN * 128; -- 2*8kB/track * 128 tracks

  CONSTANT BASE_DISK_DATA : natural := 4 * 1024 * 1024; -- Raw

  SIGNAL waddr,raddr  : natural RANGE 0 TO 2*2*2*SIZE_PER_SIDE - 1;
  SIGNAL avl_addressb : unsigned(31 DOWNTO 0); -- Byte address
  SIGNAL avl_writedatab : uv16;

  SIGNAL select_drive : std_logic; -- <TODO> 2 DRIVES...
  SIGNAL select_head  : std_logic;
  SIGNAL disk_loaded : std_logic;
  SIGNAL write_protect : std_logic := '0'; -- <TODO> Write Protect ?

  SIGNAL file_size     : unsigned(21 DOWNTO 0);

  SIGNAL dshow_cpt : natural RANGE 0 TO 4*1000*1000;

  ---------------------------------------------------------
  -- Intelligent commands
  TYPE enum_istate IS (
    sIDLE,

    sCHECK_SYNCHRO,
    sCHECK_SYNCHRO2,
    sCHECK_SYNCHRO3,
    sCHECK_INFO_ID,
    sCHECK_TRACK,
    sCHECK_HEAD,
    sCHECK_SECTOR,
    sCHECK_SIZE,
    sCHECK_CRC_HIGH_REWIND,
    sCHECK_CRC_LOW_REWIND,

    -- READ
    sREAD_SKIP_27,
    sREAD_WAIT_42,
    sREAD_WAIT_SECTOR_ID,
    sREAD_DATA,
    sCHECK_CRC_HIGH,
    sCHECK_CRC_LOW,
    
    -- READ_ADDRESS
    sREAD_ADDRESS_WAIT_FOR_ID,

    -- WRITE
    sWRITE_SKIP_22,
    sWRITE_PRE_SYNCHRO,
    sWRITE_READY,
    sWRITE_WAIT_SECTOR_ID,
    sWRITE_DATA,
    sWRITE_CRC_HIGH,
    sWRITE_CRC_LOW,
    
    -- END
    sFINISHED
    );

  SIGNAL istate : enum_istate;

  SIGNAL process_cpt : natural RANGE 0 TO 63;


  ---------------------------------------------------------
  -- Disk image load / access
  TYPE enum_dstate IS (sIDLE,
    sREAD,sREAD2,sTRANS,
    sLOAD,sLOAD_WLO,
    sLOAD_CONV,sLOAD_SIDE,sLOAD_TRACK,sLOAD_SECTOR,
    sLOAD_CODE,sLOAD_DECODE,
    sLOAD_READ,sLOAD_READ2,sLOAD_READ3,sLOAD_READ4,
    sLOAD_WRITE,sLOAD_LOOP_POS,
    sLOAD_FILL,sLOAD_FILL2,
    sLOAD_DONE  
    );
  SIGNAL dstate : enum_dstate;

  -- Disk image properties
  SIGNAL side_count  : natural RANGE 1   TO 4;
  SIGNAL track_count : natural RANGE 25  TO 80;
  SIGNAL sector_size : natural RANGE 128 TO 256;
  SIGNAL disk_density : boolean;
  SIGNAL track_size   : natural RANGE 0 TO TRACK_SIZE_MAX;

  -- Disc rotation, access
  SIGNAL pos_rotation : natural RANGE 0 TO TRACK_SIZE_MAX + 1;

  SIGNAL rawcode : uv8;
  
  SIGNAL ardata : uv64;
  SIGNAL scpt : natural RANGE 0 TO 3;

  -- Load Image
  SIGNAL cpt_track : natural RANGE 0 TO 127;
  SIGNAL cpt_sec   : natural RANGE 0 TO 15; -- Numéro de secteur
  SIGNAL cpt_seci  : natural RANGE 0 TO 15; -- Numéro de secteur entrelacé
  SIGNAL cpt_side  : natural RANGE 0 TO 2;
  SIGNAL cpt_form  : natural RANGE 0 TO DD_RAW_SECTOR_SIZE+1; -- Position dans ROM format
  SIGNAL sec_pos   : natural RANGE 0 TO DD_SECTOR_SIZE; -- Position dans secteur
  
  ---------------------------------------------------------
  FILE fil : text OPEN write_mode IS "thmfc1.log";

BEGIN
  
  ack<=req;

  -----------------------------------------------------------------------------
  -- REGISTERS

  Reg:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN

      -------------------------------------------------------------------------
      -- Defaults
      motor_start  <= '0';
      intl_start   <= '0';
      dreq_clr     <= '0';
      reg_wclk_up  <= '0';
      reg_wdata_up <= '0';
      
      disk_write_set  <= '0';
      disk_write_clr  <= '0';
      data_ready_clr  <= '0';
      intl_finished_clr <= '0';

      -------------------------------------------------------------------------
      intl_finished <= (intl_finished OR intl_finished_set) AND NOT intl_finished_clr;
      crc_error     <= (crc_error     OR crc_error_set)     AND NOT crc_error_clr;

      IF intl_finished_set='1' THEN
        intl_cmd <= INTL_RESET;
      END IF;

      -------------------------------------------------------------------------
      CASE ad(3 DOWNTO 0) IS
        ---------------------------------------------------
        WHEN "0000" => -- CMD0 / STAT0
          -- CMD0
          --   7 : 0
          --   6 : 0
          --   5 : 0=MFM 1=FM (ignore)
          --   4 : ENSYM : Validation détection mots de synchro
          --   3 : NOMCK : Validation/Inhibition synchro séparateur (ignore)
          --   2 : WGC : Write enable pour formatage : DISK_WRITE = WRITE_DOOR
          --  10 : IFRW IFDA : 00 = RESET
          --                   01 = DATA WRITE
          --                   10 = INFO READ
          --                   11 = DATA READ

          -- STAT0
          --  7 : character clock 0 = WDATA not ready or RDATA not sent 1 = WDATA ready or RDATA sent (transmission completed)
          --  6 : 0
          --  5 : 0
          --  4 : Last Operation (ignore)
          --  3 : Finished
          --  2 : CRC ERROR
          --  1 : DREQ : Character clock
          --  0 : Etat RR4 = synchro
          IF wr='1' AND req='1' THEN
            -- CMD0
            disk_write_set <= dw(2); -- Ecriture disque. Pour formatage polling
            disk_write_clr <= NOT dw(2);
            intl_cmd   <= dw(1 DOWNTO 0);
            intl_start <= '1'; -- Start new
            intl_finished_clr <= '1';
          END IF;
          
          -- STAT0
          dr <= x"00";
          dr(7) <= data_ready;
          dr(4) <= '0';           -- (STAT0_LAST_OPERATION)
          dr(3) <= intl_finished; -- (STAT0_FINISHED)
          dr(2) <= '0'; --crc_error;
          dr(1) <= dreq; 
          dr(0) <= '0'; -- <TODO>
          -- 7 : Actif à l'état 1, ce bit est l'image de l'horloge caractères, il est positionné à 1 lorsqu'un mot
          --     est assemblé dans le registre RDATA en mode lecture et lorsqu'un nouveau caractère est demandé
          --     dans le registre WDATA en mode écriture.
          --     Ce bit est repositionné à 0 par une lecture ou une écriture des registres RDATA et WDATA.

          -- 4 : END  : Actif à l'état 1, indique que le contrôleur a terminé l'opération en cours.
          -- 3 : FREE : Actif à l'état 1, indique que le contrôleur a terminé l'opération.
          -- 1 : DREQ : Actif à l'état 1, indique qu'un caractère est assemblé en mode lecture ou qu'un caractère
          --            est demandé en mode écriture.
          --            Ce bit est repositionné à 0 par une lecture ou une écriture des registres RDATA et WDATA.
          --            L'information DREQ est active uniquement lorsque le contrôleur exécute une opération dite
          --            "intelligente" (lecture adresse, secteur ou écriture secteur), alors que l'information BYTE
          --            est active quelque soit le mode de travail du contrôleur (ex: mode POLLING en formatage).

          -- 0 : SYNC : Actif à l'état1, indique une détection synchro. Les contenus des registres RDATA et WCLK sont
          --            mélangés et comparés à la configuration synchro. Ce bit est positionné lorsque le résultat
          --            de cette comparaison est vrai.

        ---------------------------------------------------
        WHEN "0001" => -- CMD1 / STAT1
          -- CMD1
          --   7 : Compatibility        (ignore)
          --  65 : Sector Size
          --   4 : Side 0/1             Valeur comparée par les commandes AUTO
          -- 321 : Precompensation      (ignore)
          --   0 : Inhibit when READY=0 (ignore)
          
          IF wr='1' AND req='1' THEN
            intl_sector_size <= dw(6 DOWNTO 5);
            intl_side        <= dw(4);
          END IF;

          -- STAT1
          --   7 : 0
          --   6 : FLOPPY : Index | QDD : Inserted
          --   5 : FLOPPY : Disk Change
          --   4 : Motor ON inversed
          --   3 : FLOPPY : Track 0 | QDD : Detected
          --   2 : Write Protection
          --   1 : READY
          --   0 : 0
          dr(7) <= '0';
          dr(6) <= to_std_logic((pos_rotation < 5) OR (pos_rotation = track_size-1));
          dr(5) <= '0'; -- <TODO> floppy_disk_change;
          dr(4) <= NOT motor_on;
          dr(3) <= motor_on AND to_std_logic(track=0) AND disk_loaded;
          dr(2) <= motor_on AND (write_protect OR NOT disk_loaded);
          dr(1) <= disk_loaded;
          dr(0) <= '0';

        ---------------------------------------------------
        WHEN "0010" => -- CMD2
          -- CMD2
          --   7 : unused
          --   6 : SISELB : FLOPPY : FACE0/1  | QDD : 0=Motor ON    SIDE = Sélection données à accéder
          --   5 : DIRECB : FLOPPY : 0=vers extérieur, piste 0 | 1=vers intérieur
          --   4 : STEP : FLOPPY : 1=Step motor
          --   3 : unused
          --   2 : MTON : FLOPPY : 1=Motor ON
          --   1 : DRS1 : Sélection drive
          --   0 : DRS0 : Sélection drive

          -- Read ? zero ?
          dr <= x"00";

          IF wr='1' AND req='1' THEN
            IF dw(1 DOWNTO 0) = "00" THEN
              -- <Disk LED OFF>
              NULL;
            ELSIF dw(1 DOWNTO 0) = "10" THEN
              select_drive <= '1'; -- Drive 1
            ELSE
              select_drive <= '0'; -- Drive 0
            END IF;
            select_head  <= NOT dw(6);

            -- Activate motor
            motor_start<= dw(2); -- MOTOR ON
            
            -- Manage head moving
            IF dw(4)='1' AND track < track_count THEN -- STEP MOTOR
              IF dw(5)='1' THEN -- STEP DIRECTION
                track <= track + 1;
              ELSIF track > 0 THEN
                track <= track - 1;
              END IF;
            END IF;
          END IF;

        ---------------------------------------------------
        WHEN "0011" => -- WDATA/RDATA
          IF wr='1' AND req='1' THEN
            -- WDATA
            reg_wdata <= dw;
            reg_wdata_up <='1';
          END IF;

          -- RDATA
          dr <= wdata;

          IF req='1' THEN
            data_ready_clr <= '1';
            dreq_clr <= '1';
          END IF;

        ---------------------------------------------------
        WHEN "0100" => -- WCLK / CLCK
          IF wr='1' AND req='1' THEN
            -- WCLK
            reg_wclk <= dw;
            reg_wclk_up <='1';
        
          END IF;
          dr <= wdata;
          IF req='1' THEN
            data_ready_clr <= '1';
          END IF;


        ---------------------------------------------------
        WHEN "0101" => -- WSECT
          IF wr='1' AND req='1' THEN
            -- WSECT
            wsect <= dw;
          END IF;
          -- Read = WSECT
          dr <= wsect;

        ---------------------------------------------------
        WHEN "0110" => -- WTRK
          IF wr='1' AND req='1' THEN
            -- WTRK
            wtrk <= dw;
          END IF;
          -- Read 
          dr <= wtrk;

        ---------------------------------------------------
        WHEN "0111" => -- WCELL
          IF wr='1' AND req='1' THEN
            -- WTRK
            --wcell <= dw; -- Ignored
          END IF;
          -- Read
          dr <= x"00"; -- Bug read ?
          
        ---------------------------------------------------
        WHEN "1000" => -- Bank select on CD 90-351
          IF wr='1' AND req='1' THEN
            fdbank <= dw(1 DOWNTO 0);
          END IF;
          -- Read
          dr <= x"00"; -- No readback ?

        ---------------------------------------------------
        WHEN OTHERS => NULL;
        -- REG8 = Lecture = REG0. Ecriture = Null
        -- REG9 = Lecture = REG1. Ecriture = Null

      END CASE;

      -------------------------------------------------------------------------
      -- Motor ON/OFF
      -- Keep motor running for 2 more seconds
      -- Monostable 74LS122.
      -- Cext = 47µF : 47*1000*1000 Rext=82k : 82
      -- T = 0.33 * 82 * 47000000 = 1.27 s

      IF tick_cpu='1' THEN
        IF motor_cpt > 0 THEN
          motor_cpt <= motor_cpt - 1;
          motor_on <= '1';
        ELSE
          motor_on <= '0';
        END IF;
      END IF;
      IF motor_start='1' THEN
        motor_cpt <= MOTOR_ON_DELAY;
      END IF;
      
      -------------------------------------------------------------------------
      IF reset_n='0' THEN
        stat1 <= x"20"; --STAT1_DISK_CHANGE;
        motor_cpt <= 0;
        motor_on  <= '0';
        dreq_clr  <= '1';
        intl_cmd <= INTL_RESET;
        intl_finished <= '0';
        fdbank <= "00";
      END IF;

    END IF;
    
  END PROCESS;
  
  --###########################################################################
  -- INTELLIGENT COMMANDS

  Intelligent:PROCESS(clk) IS
  BEGIN
    IF rising_edge(clk) THEN

      -----------------------------------------------------
      -- Defaults
      intl_finished_set <= '0';

      crc_error_set <= '0';

      -----------------------------------------------------
      IF disk_wdata_up='1' THEN
        -- Update from disk rotation
        wclk       <= disk_wclk;
        wdata      <= disk_wdata;
        
        CASE istate IS
          -------------------------------------------------
          WHEN sIDLE =>
            -- New command
            IF intl_cmd /= INTL_RESET THEN
              istate <= sCHECK_SYNCHRO;
            END IF;
            
            process_cpt <= 0;
            data_ready<='1';

          -------------------------------------------------
          WHEN sCHECK_SYNCHRO => -- READ_SECTOR + READ_ADRS + WRITE_SECTOR
            IF disk_wclk /= MFM_DATA_CLOCK_VALUE THEN
              istate <= sCHECK_SYNCHRO2;
            END IF;
            data_ready <= '0';

          WHEN sCHECK_SYNCHRO2 =>
            IF disk_wclk /= MFM_DATA_CLOCK_VALUE THEN
              istate <= sCHECK_SYNCHRO3;
            ELSE
              istate <= sCHECK_SYNCHRO;
            END IF;    
            data_ready <= '0';

          WHEN sCHECK_SYNCHRO3 =>
            IF disk_wclk /= MFM_DATA_CLOCK_VALUE THEN
              IF intl_cmd = INTL_READ_ADDRESS THEN 
                istate <= sREAD_ADDRESS_WAIT_FOR_ID;
              ELSE
                istate <= sCHECK_INFO_ID;
              END IF;  
            ELSE
              istate <= sCHECK_SYNCHRO;
            END IF;    
            data_ready <= '0';

          -------------------------------------------------
          WHEN sCHECK_INFO_ID => -- READ_SECTOR + WRITE_SECTOR
            IF disk_wdata = MFM_INFO_ID THEN
              crc <= MFM_CRC_INFO_INIT;
              istate <= sCHECK_TRACK;
            ELSE
              istate <= sCHECK_SYNCHRO;
            END IF;
  
            data_ready <= '0';

          WHEN sCHECK_TRACK => -- READ_SECTOR + WRITE_SECTOR
            IF disk_wdata = wtrk THEN
                istate <= sCHECK_HEAD;
            ELSE
                istate <= sCHECK_SYNCHRO;
            END IF;

            crc <= calc_crc(disk_wdata,crc);
            data_ready <= '0';

          WHEN sCHECK_HEAD => -- READ_SECTOR + WRITE_SECTOR
            -- Check that side/head match
            -- Toujours à 0 dans la génération de l'image!
            IF disk_wdata = "0000000" & intl_side THEN
                istate <= sCHECK_SECTOR;
            ELSE
                istate <= sCHECK_SYNCHRO;
            END IF;

            crc <= calc_crc(disk_wdata,crc);
            data_ready <= '0';

          WHEN sCHECK_SECTOR => -- READ_SECTOR + WRITE_SECTOR
            -- Check that sector num match
            IF disk_wdata = wsect THEN
                istate <= sCHECK_SIZE;
            ELSE
                istate <= sCHECK_SYNCHRO;
            END IF;
          
            crc <= calc_crc(disk_wdata,crc);
            data_ready <= '0';
          
          WHEN sCHECK_SIZE => -- READ_SECTOR + WRITE_SECTOR
            -- Check that sector size match. Set transfer size.
            IF disk_wdata = "000000" & intl_sector_size THEN
                istate <= sCHECK_CRC_HIGH_REWIND;
            ELSE
                istate <= sCHECK_SYNCHRO;
            END IF;
        
            crc <= calc_crc(disk_wdata,crc);
            data_ready <= '0';

          WHEN sCHECK_CRC_HIGH_REWIND => -- READ_SECTOR + WRITE_SECTOR
            --IF disk_wdata = crc(15 DOWNTO 8) THEN
                istate <= sCHECK_CRC_LOW_REWIND;
            --ELSE
            --    istate <= sCHECK_SYNCHRO;
            --END IF;
            data_ready <= '0';

          WHEN sCHECK_CRC_LOW_REWIND => -- READ_SECTOR + WRITE_SECTOR
            --IF disk_wdata = crc(7 DOWNTO 0) THEN
                IF intl_cmd = INTL_READ_SECTOR THEN
                  istate <= sREAD_SKIP_27;
                ELSE -- auto_write
                  istate <= sWRITE_SKIP_22;
                END IF;
            --ELSE
            --    istate <= sCHECK_SYNCHRO;
            --END IF;
            data_ready <= '0';
        
          -------------------------------------------------
          WHEN sREAD_SKIP_27 => -- READ_SECTOR
            IF process_cpt = 26 THEN
                istate <= sREAD_WAIT_42;
                process_cpt <= 0;
            END IF;

            process_cpt <= process_cpt+1;
            data_ready <= '0';
          
          WHEN sREAD_WAIT_42 => -- READ_SECTOR
            IF process_cpt = 41 THEN
                istate <= sCHECK_SYNCHRO;
                process_cpt <= 0;
            END IF;

            process_cpt <= process_cpt+1;
          
            IF disk_wclk /= MFM_DATA_CLOCK_VALUE THEN
                process_cpt <= 0;
                dreq <= '1';
                istate <= sREAD_WAIT_SECTOR_ID;
            END IF;
            data_ready <= '0';
          
          WHEN sREAD_WAIT_SECTOR_ID => -- READ_SECTOR
            IF disk_wdata = MFM_SECTOR_ID THEN
                crc <= MFM_CRC_DATA_INIT;
                -- Sector byte count
                auto_count <= SECTOR_SIZES(to_integer(intl_sector_size));
                istate <= sREAD_DATA;
            END IF;
            data_ready <= '1'; -- EMU : Pas de CLR DRQ

          -------------------------------------------------
          WHEN sREAD_DATA => -- READ_SECTOR + READ_ADRS
            crc <= calc_crc(disk_wdata,crc);
          
            auto_count <= auto_count - 1;
            IF auto_count = 1 THEN
              istate <= sCHECK_CRC_HIGH;
            END IF;
            data_ready <= '1';

          WHEN sCHECK_CRC_HIGH => -- READ_SECTOR + READ_ADRS
            IF disk_wdata /= crc(15 DOWNTO 8) THEN
              crc_error_set <= '1';
            END IF;
            istate <= sCHECK_CRC_LOW;
            data_ready <= '0';

          WHEN sCHECK_CRC_LOW => -- READ_SECTOR + READ_ADRS
            IF disk_wdata /= crc(7 DOWNTO 0) THEN
              crc_error_set <= '1';
            END IF;

            istate <= sFINISHED;
            data_ready <= '0';

          -------------------------------------------------
          WHEN sREAD_ADDRESS_WAIT_FOR_ID => -- READ_ADDRESS
            IF disk_wdata = MFM_INFO_ID THEN
                crc <= MFM_CRC_INFO_INIT;
                auto_count <= 4;
                dreq <= '1';
                istate <= sREAD_DATA;
            ELSE
                istate <= sCHECK_SYNCHRO;
            END IF;
            data_ready <= '0';

          -------------------------------------------------
          WHEN sWRITE_SKIP_22 => -- WRITE_SECTOR
            IF process_cpt = 21 THEN
                wdata <= MFM_PRE_SYNC_DATA_VALUE;
                wclk  <= MFM_DATA_CLOCK_VALUE;
                disk_write <= '1';
                istate <= sWRITE_PRE_SYNCHRO;
                process_cpt <= 0;
            END IF;

            process_cpt <= process_cpt + 1;
            data_ready <= '0';
          
          WHEN sWRITE_PRE_SYNCHRO => -- WRITE_SECTOR
            IF process_cpt = 11 THEN
                wdata <= MFM_SYNCHRO_DATA_VALUE;
                wclk  <= MFM_SYNCHRO_CLOCK_VALUE;
                istate <= sWRITE_READY;
            END IF;

            process_cpt <= process_cpt + 1;
            data_ready <= '0';
            
          WHEN sWRITE_READY => -- WRITE_SECTOR
            dreq <= '1';
            istate <= sWRITE_WAIT_SECTOR_ID;
            data_ready <= '0';
          
          WHEN sWRITE_WAIT_SECTOR_ID => -- WRITE_SECTOR
            IF disk_wdata = MFM_SECTOR_ID THEN
                wclk <= MFM_DATA_CLOCK_VALUE;
                crc  <= MFM_CRC_DATA_INIT;
                auto_count <= SECTOR_SIZES(to_integer(intl_sector_size));
                istate <= sWRITE_DATA;
            END IF;
            data_ready <= '1'; -- EMU : Pas de CLR DRQ
          
          WHEN sWRITE_DATA => -- WRITE_SECTOR
            crc <= calc_crc(disk_wdata,crc);
            auto_count <= auto_count - 1;
            IF  auto_count = 1 THEN
              istate <= sWRITE_CRC_HIGH;
            END IF;
            data_ready <= '1';

          WHEN sWRITE_CRC_HIGH => -- WRITE_SECTOR
            wdata  <= crc(15 DOWNTO 8);
            wclk   <= MFM_DATA_CLOCK_VALUE;
            istate <= sWRITE_CRC_LOW;
            data_ready <= '0';
          
          WHEN sWRITE_CRC_LOW => -- WRITE_SECTOR
            wdata  <= crc(7 DOWNTO 0);
            wclk   <= MFM_DATA_CLOCK_VALUE;
            istate <= sFINISHED;
            data_ready <= '0';
          
          -------------------------------------------------
          -- END
          WHEN sFINISHED => -- READ_SECTOR + READ_ADRS + WRITE_SECTOR
            intl_finished_set <= '1';
            --istate <= sCHECK_SYNCHRO;
            istate <= sIDLE;
            process_cpt <= 0;
            disk_write <= '0';
            data_ready <= '1';

          -------------------------------------------------
        END CASE;
      END IF; -- if tick_cpu

      ----------------------------------------------------
      -- Update from reg access
      IF reg_wclk_up='1' THEN
        wclk <= reg_wclk;
      END IF;
      IF reg_wdata_up='1' THEN
        wdata <= reg_wdata;
      END IF;

      IF disk_write_set='1' THEN
        disk_write <= '1';
      END IF;
      IF disk_write_clr='1' THEN
        disk_write <= '0';
      END IF;
      
      -- Clear after register read
      IF data_ready_clr='1' THEN
        data_ready <= '0';
      END IF;
      IF dreq_clr='1' THEN
        dreq <= '0';
      END IF;
      
      ----------------------------------------------------
      IF intl_start ='1' OR reset_n='0' THEN
        istate <= sIDLE;
        auto_count <= 0;

        disk_write <= '0';
        data_ready <= '1';

      END IF;

      ----------------------------------------------------

    END IF; -- rising_edge()

  END PROCESS Intelligent;

  --###########################################################################
  --###########################################################################
  -----------------------------------------------------------------------------
  -- DISK IMAGE

-------------------------------------------------------------------------------
-- Fichier brut en DDR
--Machine à états :
-- 1 Mode lecture disque
--   * Lecture séquencielle DDR octet par octet => Rotation disque
-- 2 Recopie DDR => DDR
--   * Conversion format disque, formattage secteurs
--   * Identifie type disque d'après la taille de l'image
--   * Toutes les pistes
--   * Tous les secteurs
--   * écriture mémoire

-- Tailles image source
--rd_start <= read_sd(base_adrs,track,sector,format) => position lecture fichier SD en mémoire

--wr_start <= write_raw(base_adrs,track)  => position lecture 

--Encodage 16bits par donnée piste : 8bits valeur + bit SYNCHRO_CLOCK

--  read : 1 cycle : adress
--  write : maintenu pendant toute l'écriture
 
avl_address(23 DOWNTO 0)  <= avl_addressb(26 DOWNTO 3);
avl_address(28 DOWNTO 24) <= "00111"; -- BASE_DISK_DATA = x38000000

avl_burstcount <= x"01"; -- No burst
avl_writedata  <= std_logic_vector(avl_writedatab) & std_logic_vector(avl_writedatab) & 
                  std_logic_vector(avl_writedatab) & std_logic_vector(avl_writedatab);

-- Format FD  : Données formattées => conversion avec ajout données brutes

-- ===================================
-- ROTATION DISQUE
-- track        : piste en train d'être lue
-- pos_rotation : rotation dique en cours
-- intl_side    : face à comparer dans entête secteur
-- 
-- scpt         : alternance lecture 64bits 0..3
-- 
-- 
-- disk_dvalid : pulse données <= tick_disk
-- 
-- ===================================
-- 
-- file_size
-- =>
-- track_size
-- side_count
-- track_count
-- sector_size
-- disk_density
-- 
-- ===================================
-- CHARGEMENT IMAGE
-- 
-- cpt_sec
-- cpt_seci
-- cpt_track
-- cpt_side
-- 
-- cpt_form : chargement depuis ROM formattage
-- 
-- pos_rotation

Disk:PROCESS(clk) IS
  VARIABLE lout : line;
  VARIABLE sizecheck_v : boolean;
BEGIN
  IF rising_edge(clk) THEN
    -------------------------------------------------------
    avl_write   <= '0';
    avl_read    <= '0';
    disk_wdata_up <= '0';

    -------------------------------------------------------
    CASE dstate IS
      --===================================================
      WHEN sIDLE =>
        IF ioctl_download = '1' THEN
          -- Convert disk image to raw format
          dstate <= sLOAD;
          
        ELSIF motor_on='1' THEN
          -- Disk turning
          dstate <= sREAD;
        END IF;

      --===================================================
      -- Motor running, Read track
      WHEN sREAD =>
        IF select_head='0' THEN
          avl_addressb <= to_unsigned(BASE_DISK_DATA + ((track * TRACK_LEN) + pos_rotation) * 2,32);
        ELSE
          avl_addressb <= to_unsigned(BASE_DISK_DATA + ((track * TRACK_LEN) + pos_rotation + SIZE_PER_SIDE) * 2,32);
        END IF;
        avl_read <= '1';
        dstate <=sREAD2;
        -- <TODO> IF disk_write='1' AND write_protect='0' THEN => DISK_WRITE
      
      WHEN sREAD2 =>
        IF avl_waitrequest='0' THEN
          avl_read <= '0';
        END IF;
        IF avl_readdatavalid='1' THEN
          ardata <= unsigned(avl_readdata);
          dstate <= sTRANS;
        END IF;
        scpt <= 0;

      WHEN sTRANS =>
        IF tick_disk='1' THEN
          disk_wdata    <= ardata(7 DOWNTO 0);
          disk_wclk     <= ardata(15 DOWNTO 8);
          disk_wdata_up <= '1';

          ardata(47 DOWNTO 0) <= ardata(63 DOWNTO 16);

          scpt <= (scpt + 1) MOD 4;
          IF scpt = 3 THEN
            dstate <= sREAD;
          END IF;

          pos_rotation <= pos_rotation + 1;
          IF pos_rotation + 1 >= track_size THEN -- 6252 / 3126
            pos_rotation <= 0;
            dstate <= sREAD; -- Partial access : 3126 non divisible par 4
          END IF;
  
        END IF;
        IF motor_on='0' THEN
          dstate <= sIDLE;
        END IF;
        IF ioctl_download='1' THEN
          dstate <= sLOAD;
        END IF;
      
      --===================================================
      -- Copy image to DDRAM
      WHEN sLOAD =>
        ioctl_wait <= '0';
        avl_addressb   <= resize(ioctl_addr,32);
        avl_byteenable <= std_logic_vector(BE8_64(to_integer(ioctl_addr(2 DOWNTO 0))));
        avl_writedatab <= unsigned(ioctl_data) & unsigned(ioctl_data);

        IF ioctl_wr = '1' THEN
          avl_write <= '1';
          dstate <= sLOAD_WLO;
          file_size <= ioctl_addr(21 DOWNTO 0);
        END IF;

        IF ioctl_download = '0' THEN
          dstate <= sLOAD_CONV;
        END IF;

      WHEN sLOAD_WLO =>
        avl_write <= '1';
        IF avl_waitrequest='0' THEN
          avl_write <= '0';
        END IF;
        IF ioctl_wr = '0' THEN
          dstate <= sLOAD;
        END IF;
        -- <TODO> Check access time <=> wait states

      --===================================================
      -- Convert disk image to raw tracks
      WHEN sLOAD_CONV =>
        ioctl_wait <= '1';
        cpt_side   <= 0;
        raddr <= 0;
        sizecheck_v := false;
        FOR i IN 0 TO 4 LOOP
          IF file_size = FD_LIST(i).file_size - 1 THEN
            side_count    <= FD_LIST(i).side_count;
            track_count   <= FD_LIST(i).track_count;
            sector_size   <= FD_LIST(i).sector_size;
            disk_density  <= FD_LIST(i).density;
            track_size    <= FD_LIST(i).track_size;
            sizecheck_v := true;
          END IF;
        END LOOP;
        
        IF NOT sizecheck_v THEN
          -- Wrong size, no match. Ignore.
          disk_loaded <= '0';
          dstate <= sIDLE;
        ELSE
          dstate <= sLOAD_SIDE;
        END IF;

      WHEN sLOAD_SIDE =>
        -- Start of new side
        cpt_track <= 0;
        dstate <= sLOAD_TRACK;

      WHEN sLOAD_TRACK =>
        -- Start of new track
        cpt_sec  <= 0;
        cpt_seci <= 0; -- Interleaved sector number
        pos_rotation <= 0;
        IF cpt_side=0 THEN
          waddr <= BASE_DISK_DATA + (cpt_track * TRACK_LEN) * 2;
        ELSE
          waddr <= BASE_DISK_DATA + (cpt_track * TRACK_LEN + SIZE_PER_SIDE) * 2;
        END IF;
        dstate <= sLOAD_SECTOR;

      WHEN sLOAD_SECTOR =>
        -- Start of new sector
        cpt_form <= 0;
        sec_pos  <= 0;
        dstate <= sLOAD_CODE;

      WHEN sLOAD_CODE =>
        IF sector_size = SD_SECTOR_SIZE THEN
          rawcode <= SD_RAW_SECTOR(cpt_form);
        ELSE
          rawcode <= DD_RAW_SECTOR(cpt_form);
        END IF;
        dstate <= sLOAD_DECODE;

      WHEN sLOAD_DECODE =>
        avl_addressb   <= to_unsigned(waddr + pos_rotation * 2,32);
        avl_byteenable <= std_logic_vector(BE16_64(pos_rotation MOD 4));
        avl_writedatab <= DATA_CLOCK_MARK & rawcode;
        write(lout,cpt_form,right,4);
        write(lout,string'(" : "));

        CASE rawcode IS
          WHEN E_DATA   => 
            -- Read from avalon bus data to copy before write
            dstate <= sLOAD_READ;
            avl_write <= '0';
            
            -- Generate data
          WHEN E_CRC_LO =>
            dstate <= sLOAD_WRITE;
            avl_writedatab <= DATA_CLOCK_MARK & crc(7 DOWNTO 0);
            avl_write <= '1';
            write(lout,string'("E_CRC_LO : DATA xx")); 

          WHEN E_CRC_HI =>
            dstate <= sLOAD_WRITE;
            avl_writedatab <= DATA_CLOCK_MARK & crc(15 DOWNTO 8);
            avl_write <= '1';
            write(lout,string'("E_CRC_HI : DATA xx"));
        
          WHEN E_TRACK  =>
            dstate <= sLOAD_WRITE;
            avl_writedatab <= DATA_CLOCK_MARK & to_unsigned(cpt_track,8);
            avl_write <= '1';
            write(lout,string'(" E_TRACK : DATA "));
            write(lout,cpt_track);
        
          WHEN E_SECTOR =>
            dstate <= sLOAD_WRITE;
            avl_writedatab <= DATA_CLOCK_MARK & to_unsigned(cpt_seci + 1,8);
            avl_write <= '1';
            write(lout,string'("E_SECTOR : DATA ")); 
            write(lout,cpt_seci+1);
        
          WHEN FM_INFO_ID | FM_SECTOR_ID | MFM_SYNCHRO_DATA_VALUE =>
            dstate <= sLOAD_WRITE;
            avl_writedatab <= SYNCHRO_CLOCK_MARK & rawcode;
            avl_write <= '1';
            write(lout,string'("      ID : SYNC ")); 
            write(lout,to_hstring(rawcode));
        
          WHEN OTHERS   =>
            dstate <= sLOAD_WRITE;
            avl_writedatab <= DATA_CLOCK_MARK & rawcode;
            avl_write <= '1';
            write(lout,string'("  OTHERS : DATA "));
            write(lout,to_hstring(rawcode));
        
        END CASE;
        IF rawcode /= E_DATA THEN
          write(lout,string'("  ["));
          write(lout,to_hstring(to_unsigned(waddr + pos_rotation * 2,32)));
          writeline(fil,lout);
        END IF;

        --<Initialisation CRC>
      WHEN sLOAD_READ =>
        -- Read from disk image
        avl_addressb <= to_unsigned(raddr + cpt_seci * sector_size + sec_pos,32);
        avl_read <= '1';
        dstate <=sLOAD_READ2;
        
      WHEN sLOAD_READ2 =>
        IF avl_waitrequest='0' THEN
          avl_read <= '0';
          dstate <= sLOAD_READ3;
        END IF;

      WHEN sLOAD_READ3 =>
        IF avl_readdatavalid='1' THEN
          dstate <= sLOAD_READ4;
          write(lout,string'("    COPY : DATA "));
          write(lout,to_hstring(unsigned(avl_readdata((sec_pos MOD 8)*8+7 DOWNTO (sec_pos MOD 8)*8))));
          write(lout,string'("  ["));
          write(lout,to_hstring(to_unsigned(waddr + pos_rotation * 2,32)));
          writeline(fil,lout);
        END IF;
        avl_writedatab <= DATA_CLOCK_MARK & 
                 unsigned(avl_readdata((sec_pos MOD 8)*8+7 DOWNTO (sec_pos MOD 8)*8));

      WHEN sLOAD_READ4 =>
        sec_pos <= sec_pos + 1;
        avl_addressb <= to_unsigned(waddr + pos_rotation * 2,32);
        avl_write <= '1';
        dstate <= sLOAD_WRITE;

      WHEN sLOAD_WRITE =>
        -- Write 16bits to DDR
        avl_write <= '1';
        IF avl_waitrequest='0' THEN
          avl_write <= '0';
          dstate <= sLOAD_LOOP_POS;
        END IF;

      WHEN sLOAD_LOOP_POS =>
        IF (sector_size = SD_SECTOR_SIZE AND cpt_form >= SD_RAW_SECTOR_SIZE-1) OR 
           (sector_size = DD_SECTOR_SIZE AND cpt_form >= DD_RAW_SECTOR_SIZE-1) THEN
          cpt_sec  <= (cpt_sec  + 1) MOD 16;
          cpt_seci <= (cpt_seci + 7) MOD 16; -- Interleaved + 7
          IF cpt_sec = 15 THEN
            dstate <= sLOAD_FILL; 
          ELSE
            dstate <= sLOAD_SECTOR;
          END IF;
        ELSE
          cpt_form <= cpt_form + 1;
          dstate <= sLOAD_CODE;
        END IF;
        pos_rotation <= pos_rotation + 1;

      WHEN sLOAD_FILL =>
        -- Fill rest of the track
        avl_addressb   <= to_unsigned(waddr + pos_rotation * 2,32);
        avl_byteenable <= std_logic_vector(BE16_64(pos_rotation MOD 4));
        IF sector_size = SD_SECTOR_SIZE THEN
          avl_writedatab <= DATA_CLOCK_MARK & FM_GAP_DATA_VALUE;
        ELSE
          avl_writedatab <= DATA_CLOCK_MARK & MFM_GAP_DATA_VALUE;
        END IF;
        avl_write <= '1';
        dstate <= sLOAD_FILL2;
        
      WHEN sLOAD_FILL2 =>
        avl_write <= '1';
        IF avl_waitrequest='0' THEN
          avl_write <= '0';
          pos_rotation <= pos_rotation + 1;
          IF pos_rotation < TRACK_SIZE_MAX-1 THEN
            dstate <= sLOAD_FILL;
          ELSE
            raddr <= raddr + sector_size * 16;
            cpt_track <= cpt_track + 1;
            IF cpt_track + 1 >= track_count THEN
              cpt_side <= cpt_side + 1;
              IF cpt_side + 1 >= side_count THEN
                dstate <= sLOAD_DONE;
              ELSE
                dstate <= sLOAD_SIDE;
              END IF;
            ELSE
              dstate <= sLOAD_TRACK;
            END IF;
          END IF;
        END IF;
      
      WHEN sLOAD_DONE =>
        -- Disk load and decode done
        dstate <= sIDLE;
        disk_loaded <= '1';
        ioctl_wait  <= '0';
        
      -----------------------------------------------------

    END CASE;

    -----------------------------------------------------
    -- Clock for disk access
    tick_disk <= '0';
    IF tick_cpu = '1' THEN
      tick_cpt <= (tick_cpt + 1) MOD 64;
      IF disk_density AND tick_cpt = 4 * 8 - 1 THEN
        -- DD / MFM : 250kbps / 8 bits = 32µs per byte
        tick_disk <= '1';
        tick_cpt <= 0;
      ELSIF NOT disk_density AND tick_cpt = 8 * 8 - 1 THEN
        -- SD / FM  : 125kbps / 8 bits = 64µs per byte
        tick_disk <= '1';
        tick_cpt <= 0;
      END IF;
    END IF;

    tick_disk2 <= tick_disk;

    -----------------------------------------------------
    IF hwreset_n ='0' OR unload='1' THEN
      disk_loaded <= '0';
      dstate <= sIDLE;
    END IF;
    IF reset_n ='0' THEN
      dstate <= sIDLE;
    END IF;

  END IF;
END PROCESS Disk;

-------------------------------------------------------------------------------
-- Show progress bar when motor is running + 3 sec
BarShow:PROCESS(clk) IS
BEGIN
  IF rising_edge(clk) THEN
    IF tick_cpu = '1' THEN
      IF dshow_cpt < 3 *1000*1000 THEN
        dshow_cpt <= dshow_cpt + 1;
        dshow <= '1';
      ELSE
        dshow <= '0';
      END IF;
    END IF;
    IF motor_on='1' THEN
      dshow_cpt <= 0;
    END IF;
  END IF;
END PROCESS BarShow;

-------------------------------------------------------------------------------
Trace:PROCESS(clk) IS
    VARIABLE lout : line;
    TYPE arr_str IS array(natural range <>) OF string(1 TO 7);
    CONSTANT INTL_TXT : arr_str(0 TO 3) :=
         ("RESET  ",
          "WRITE  ",
          "ADDRESS",
          "READ   ");
  
BEGIN
  IF rising_edge(clk) THEN
    IF tick_disk='1' THEN
      write(lout,pos_rotation,right,5);
      write(lout,string'(" : "));
      write(lout," " & to_hstring(wclk) & " " & to_hstring(wdata) & " : ");
      write(lout, INTL_TXT(to_integer(intl_cmd)) & " : ");
      write(lout, enum_istate'image(istate) & " ");

      writeline(fil,lout);
    END IF;
  END IF;
END PROCESS Trace;

  -------------------------------------------------------------------------------
  dmotor <= motor_on;
  dratio <= to_unsigned(track,7) & select_head;

  dd_motor  <= motor_on;
  dd_finish <= intl_finished;
  dd_track  <= wtrk;
  dd_sector <= wsect;
  dd_head   <= select_head;

END rtl;
