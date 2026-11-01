--------------------------------------------------------------------------------
-- MC6805 CPU
--------------------------------------------------------------------------------
-- DO 10/2026
--------------------------------------------------------------------------------

--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

USE std.textio.ALL;

LIBRARY work;
USE work.base_pack.ALL;
USE work.mc6805_pack.ALL;

ENTITY mc6805_cpu IS
  GENERIC (
    LOGFILE : string := "trace.log";
    NB_SP : natural := 5   -- SP SIZE
  );
  PORT (
    ad       : OUT uv12; -- Address bus
    dw       : OUT uv8;  -- Data write
    dr       : IN  uv8;  -- Data read
    req      : OUT std_logic;
    ack      : IN  std_logic;
    wr       : OUT std_logic;

    tim_n    : IN  std_logic; -- Timer interrupt
    irq_n    : IN  std_logic; -- External interrupt
    reset_na : IN  std_logic;
    clk      : IN std_logic
    );
END ENTITY mc6805_cpu;

-------------------------------------------------------------------------------

ARCHITECTURE rtl OF mc6805_cpu IS
  ------------------------------------------------
  SIGNAL req_l : std_logic;
  SIGNAL dw_l  : uv8;
  SIGNAL ad_l  : uv12;
  SIGNAL wr_l  : std_logic;

  SIGNAL dr_mem : uv8;
  SIGNAL ack_delay : std_logic;

  ------------------------------------------------
  SIGNAL ra  : uv8;
  SIGNAL rx  : uv8;
  SIGNAL rcc : type_ccr;
  SIGNAL rpc : uv12;
  SIGNAL rsp : unsigned(NB_SP-1 DOWNTO 0);

  ------------------------------------------------
  SIGNAL op  : uv8;
  SIGNAL dec : type_op;
  SIGNAL ea  : uv12;

  ------------------------------------------------
  SIGNAL rts   : uv8;  -- Temporary source
  SIGNAL rtd   : uv8;  -- Temporary destination
  SIGNAL rup   : std_logic; -- Update result
  SIGNAL rel   : sv8;  -- Branch rel
  SIGNAL cond  : std_logic; -- Branch condition
  SIGNAL cycle : natural RANGE 0 TO 31; -- Cycle counter inside a state
  SIGNAL vec   : unsigned(2 DOWNTO 1);  -- Vector : RST, INT, TIM, SWI

  TYPE enum_state IS (
    sFETCH, sINHERENT, sIMMEDIATE, sDIRECT, sEXTENDED,
    sIX, sIX1, sIX2, sREADMEM, sWRITEMEM,
    sALU, sUNARY, sUNARY_WRITE, sSETCLR, sSETCLR2,
    sWRITEPUSH, sREADPOP, sDISPATCH, sBSR, sBCOND, sBRANCH,
    sBRTEST, sVECTOR, sTURN, sSTOP_WAIT, sINVALID);

  SIGNAL state : enum_state;

  TYPE enum_phase IS (PH_CODE, PH_POST, PH_DATA, PH_STACK, PH_VOID);
  SIGNAL ph_l : enum_phase;

BEGIN
  ------------------------------------------------------------------------------
  Machine:PROCESS(clk,reset_na) IS
    VARIABLE dr_v  : uv8;
    VARIABLE rs_v  : uv8;
    VARIABLE rd_v  : uv8;
    VARIABLE cc_v  : type_ccr;
    VARIABLE up_v  : std_logic;
    VARIABLE dec_v : type_op;
    VARIABLE ea_v  : uv12;
    VARIABLE idx_v : natural RANGE 0 TO 7;
  BEGIN
    IF reset_na='0' THEN
      -- Reset sequence : read reset vector
      state <= sVECTOR;
      cycle <= 0;
      rpc   <= (OTHERS => '1');
      rpc(2 DOWNTO 0) <= VEC_RESET & '0';
      rsp   <= (OTHERS => '1');
      rcc.i <= '1';
      vec <= VEC_RESET;

    ELSIF rising_edge(clk) THEN
      -----------------------------------------------------
      ack_delay<=ack;

      IF ack='1' AND ack_delay='0' THEN
        dr_v:=dr_mem;
      ELSE
        dr_v:=dr;
      END IF;
      
      IF ack_delay='1' THEN
        dr_mem<=dr;
      END IF;

      
      -----------------------------------------------------
      IF ack='1' OR req_l='0' THEN
        dr_v := dr;

        CASE state IS
          ---------------------------------------------------
          WHEN sFETCH =>
            op     <= dr_v;
            dec_v  := opcodes(to_integer(dr_v));
            dec    <= dec_v;
            cycle  <= 0;
            ea     <= (OTHERS => '0');
            vec    <= VEC_SWI;

            IF irq_n='0' AND rcc.i='0' THEN --IRQ
              dec.admode <= A_INH;
              dec.op     <= OP_INT;
              dec.len    <= 1;
              dec.cy     <= 11;
              vec        <= VEC_IRQ;
              state      <= sINHERENT;

            ELSIF tim_n='0' AND rcc.i='0' THEN -- Timer IRQ
              dec.admode <= A_INH;
              dec.op     <= OP_INT;
              dec.len    <= 1;
              dec.cy     <= 11;
              vec        <= VEC_TIM;
              state      <= sINHERENT;

            ELSE
              rpc <= rpc + 1;
              IF dec_v.op=OP_INVALID THEN
                state <= sINVALID;
              ELSIF dec_v.op=OP_JSR OR dec_v.op=OP_BSR THEN
                -- Push PC before address mode dispatch
                state <= sWRITEPUSH;
              ELSE
                CASE dec_v.admode IS
                  WHEN A_BRSC => state <= sDIRECT;
                  WHEN A_INH  => state <= sINHERENT;
                  WHEN A_IMM  => state <= sIMMEDIATE;
                  WHEN A_DIR  => state <= sDIRECT;
                  WHEN A_EXT  => state <= sEXTENDED;
                  WHEN A_IX   => state <= sIX;
                  WHEN A_IX1  => state <= sIX1;
                  WHEN A_IX2  => state <= sIX2;
                END CASE;
              END IF;
            END IF;

          ---------------------------------------------------
          -- Inherent
          WHEN sINHERENT =>
            rts <= mux(op(4)='1',rx,ra); -- Inherent Unary on A or X reg
            CASE dec.op IS
              WHEN OP_UNARY => -- 4 cycles
                state <= sUNARY;

              WHEN OP_CONTROL => -- 2 cycles
                state <= sFETCH;
                CASE op IS
                  WHEN x"97" => -- TAX
                    rx <= ra;
                  WHEN x"98" => -- CLC
                    rcc.c <= '0';
                  WHEN x"99" => -- SEC
                    rcc.c <= '1';
                  WHEN x"9A" => -- CLI
                    rcc.i <= '0';
                  WHEN x"9B" => -- SEI
                    rcc.i <= '1';
                  WHEN x"9C" => -- RSP
                    rsp <= (OTHERS => '1');
                  WHEN x"9F" => -- TXA
                    ra <= rx;
                  WHEN OTHERS => -- NOP, invalid
                    NULL;
                END CASE;

              WHEN OP_RTI | OP_RTS =>
                state <= sREADPOP;

              WHEN OP_INT => -- SWI or interrupt entry
                state <= sWRITEPUSH;

              WHEN OP_STOP | OP_WAIT =>
                rcc.i <= '0';
                state <= sSTOP_WAIT;

              WHEN OTHERS =>
                state <= sINVALID;
            END CASE;

          ---------------------------------------------------
          -- Immediate value : Operand / branch rel
          WHEN sIMMEDIATE =>
            rpc <= rpc + 1;
            rs_v := mux(to_std_logic(
              op(3 DOWNTO 0)="0011" OR op(3 DOWNTO 0)="1110"),rx,ra); -- LDX, CPX
            CASE dec.op IS
              WHEN OP_ALU =>
                alu(op,rs_v,dr_v,rcc,rd_v,up_v,cc_v);
                IF up_v='1' THEN
                  IF op(3 DOWNTO 0)="1110" THEN -- LDX
                    rx <= rd_v; 
                  ELSE
                    ra <= rd_v;
                  END IF;
                END IF;    
                rcc   <= cc_v;
                state <= sFETCH;

              WHEN OP_BCOND =>
                rel <= signed(dr_v);
                state  <= sBCOND;

              WHEN OP_BSR =>
                rel <= signed(dr_v);
                cond   <= '1';
                state  <= sBRANCH;

              WHEN OP_BRSETCLR =>
                rel <= signed(dr_v);
                state  <= sBRANCH;

              WHEN OTHERS =>
                state <= sINVALID;
            END CASE;

          ---------------------------------------------------
          -- Direct (page zero) : EA = imm8
          WHEN sDIRECT =>
            rpc <= rpc + 1;
            ea  <= ea(11 DOWNTO 8) & dr_v;
            CASE dec.op IS
              WHEN OP_ALU | OP_UNARY | OP_BSETCLR | OP_BRSETCLR => 
                state <= sREADMEM;
              WHEN OP_STORE        => 
                state <= sALU;
              WHEN OP_JMP | OP_JSR => 
                state <= sBRANCH;
              WHEN OTHERS => 
                state <= sINVALID;
            END CASE;

          ---------------------------------------------------
          -- Extended EA = imm16
          WHEN sEXTENDED =>
            rpc   <= rpc + 1;
            ea    <= dr_v(3 DOWNTO 0) & ea(7 DOWNTO 0);
            state <= sDIRECT;

          ---------------------------------------------------
          -- X index EA = X
          WHEN sIX =>
            ea <= ea + rx;
            CASE dec.op IS
              WHEN OP_ALU | OP_UNARY | OP_BSETCLR | OP_BRSETCLR => 
                state <= sREADMEM;
              WHEN OP_STORE => 
                state <= sALU;
              WHEN OP_JMP | OP_JSR => 
                state <= sBRANCH;
              WHEN OTHERS => 
                state <= sINVALID;
            END CASE;

          ---------------------------------------------------
          -- X index EA = X + imm8
          WHEN sIX1 =>
            rpc   <= rpc + 1;
            ea    <= (ea(11 DOWNTO 8) & dr_v);
            state <= sIX;

          ---------------------------------------------------
          -- X index EA = X + imm16
          WHEN sIX2 =>
            rpc   <= rpc + 1;
            ea    <= dr_v(3 DOWNTO 0) & x"00";
            state <= sIX1;

          ---------------------------------------------------
          WHEN sREADMEM =>
            rts <= dr_v;
            cycle <= 0;
            CASE dec.op IS
              WHEN OP_ALU      => state <= sALU;
              WHEN OP_UNARY    => state <= sUNARY;
              WHEN OP_BSETCLR  => state <= sSETCLR;
              WHEN OP_BRSETCLR => state <= sBRTEST;
              WHEN OTHERS      => state <= sINVALID;
            END CASE;

          ---------------------------------------------------
          WHEN sALU =>
            rs_v := mux(to_std_logic(
              op(3 DOWNTO 0)="0011" OR 
              op(3 DOWNTO 0)="1110" OR 
              op(3 DOWNTO 0)="1111"),rx,ra); -- LDX, CPX , STX
            alu(op,rs_v,rts,rcc,rd_v,up_v,cc_v);
            IF up_v='1' THEN
              IF op(3 DOWNTO 0)="1110" THEN -- LDX
                rx <= rd_v; 
              ELSE
                ra <= rd_v;
              END IF;
            END IF;
            rtd <= rd_v;
            rcc <= cc_v;
            IF dec.op=OP_STORE THEN
              state <= sWRITEMEM;
            ELSE
              state <= sFETCH;
            END IF;

          ---------------------------------------------------
          WHEN sUNARY =>
            unary(op,rts,rcc,rd_v,up_v,cc_v);
            rtd <= rd_v;
            rup <= up_v;
            rcc <= cc_v;
            IF dec.admode=A_INH THEN
              state <= sUNARY_WRITE;
            ELSE
              state <= sWRITEMEM;
            END IF;

          ---------------------------------------------------
          WHEN sUNARY_WRITE =>
            IF rup='1' THEN
              IF op(4)='0' THEN
                ra <= rtd;
              ELSE
                rx <= rtd;
              END IF;
            END IF;
            state <= sFETCH;

          ---------------------------------------------------
          WHEN sWRITEMEM =>
            state <= sTURN;

          ---------------------------------------------------
          WHEN sTURN =>
            state <= sFETCH;

          ---------------------------------------------------
          -- BSET / BCLR
          WHEN sSETCLR =>
            bsetclr(op,rts,rd_v);
            rtd   <= rd_v;
            rup   <= '1';
            state <= sSETCLR2;

          WHEN sSETCLR2 =>
            state <= sWRITEMEM;

          ---------------------------------------------------
          -- BRSET / BRCLR : bit test (5 cycles), C <= tested bit
          WHEN sBRTEST =>
            idx_v := to_integer(op(3 DOWNTO 1));
            IF cycle=0 THEN
              cond  <= to_std_logic(rts(idx_v) = NOT op(0));
              rcc.c <= rts(idx_v);
            END IF;
            IF cycle=3 THEN
              state <= sIMMEDIATE;
            ELSE
              cycle   <= cycle+1;
            END IF;

          ---------------------------------------------------
          -- Conditional branch
          WHEN sBCOND =>
            cond  <= to_std_logic(bcond(op,rcc,irq_n));
            state <= sBRANCH;

          ---------------------------------------------------
          -- Branch / Jump
          WHEN sBRANCH =>
            IF dec.op=OP_JMP OR dec.op=OP_JSR THEN
              rpc <= ea(11 DOWNTO 0);
            ELSIF cond='1' THEN
              rpc <= rpc + unsigned(resize(rel,12));
            END IF;
            IF dec.op=OP_BRSETCLR THEN
              state <= sTURN;
            ELSE
              state <= sFETCH;
            END IF;

          ---------------------------------------------------
          -- Push registers on stack
          -- SWI / Interrupt : PCL PCH X A CC    JSR / BSR : PCL PCH
          WHEN sWRITEPUSH =>
            IF cycle>0 THEN
              rsp <= rsp - 1;
            END IF;
            IF (cycle = 5 AND dec.op=OP_INT)  OR
               (cycle = 2 AND dec.op/=OP_INT) THEN
              cycle <= 0;
              IF dec.op=OP_INT THEN
                rcc.i <= '1';
                state <= sVECTOR;
              ELSE
                state <= sDISPATCH;
              END IF;
            ELSE
              cycle <= cycle + 1;
            END IF;

          ---------------------------------------------------
          -- After JSR / BSR push : go to the target calculation
          WHEN sDISPATCH =>
            IF dec.op=OP_BSR THEN
              state <= sBSR;
            ELSE
              CASE dec.admode IS
                WHEN A_BRSC => state <= sDIRECT;
                WHEN A_INH  => state <= sINHERENT;
                WHEN A_IMM  => state <= sIMMEDIATE;
                WHEN A_DIR  => state <= sDIRECT;
                WHEN A_EXT  => state <= sEXTENDED;
                WHEN A_IX   => state <= sIX;
                WHEN A_IX1  => state <= sIX1;
                WHEN A_IX2  => state <= sIX2;
              END CASE;
            END IF;

          WHEN sBSR =>
            state <= sIMMEDIATE;
            
          ---------------------------------------------------
          -- Pop registers from stack. cycle=0 : preparation, cycle=1..n : read
          -- RTI : CC A X PCH PCL     RTS : PCH PCL
          WHEN sREADPOP =>
            IF cycle>0 THEN
              IF dec.op=OP_RTI THEN
                CASE cycle IS
                  WHEN 1 => rcc <= cc_conv(dr_v);
                  WHEN 2 => ra  <= dr_v;
                  WHEN 3 => rx  <= dr_v;
                  WHEN 4 => ea(11 DOWNTO 8) <= dr_v(3 DOWNTO 0);
                  WHEN OTHERS =>
                    rpc   <= ea(11 DOWNTO 8) & dr_v;
                END CASE;
              ELSE
                IF cycle=1 THEN
                  ea(11 DOWNTO 8) <= dr_v(3 DOWNTO 0);
                ELSE
                  rpc <= ea(11 DOWNTO 8) & dr_v;
                END IF;
              END IF;
            END IF;
            IF (cycle=5 AND dec.op =  OP_RTI) OR
               (cycle=2 AND dec.op /= OP_RTI) THEN
              state <= sTURN;
            ELSE
              cycle <= cycle+1;
              rsp <= rsp + 1;
            END IF;

          ---------------------------------------------------
          -- Read vector : PCH then PCL
          WHEN sVECTOR =>
            IF cycle=0 THEN
              ea(11 DOWNTO 8) <= dr_v(3 DOWNTO 0);
              cycle   <= 1;
            ELSE
              rpc   <= ea(11 DOWNTO 8) & dr_v;
              cycle <= 0;
              state <= sTURN;
            END IF;

          ---------------------------------------------------
          -- STOP / WAIT : wait for interrupt (I flag has been cleared)
          WHEN sSTOP_WAIT =>
            IF irq_n='0' OR (tim_n='0' AND op=x"8F") THEN
              state <= sFETCH;
            END IF;

          ---------------------------------------------------
          -- Invalid : 
          WHEN sINVALID =>
            IF cycle=0 THEN
              rpc <= rpc + dec.len - 1;
            END IF;
            IF cycle+2 >= dec.cy THEN
              state <= sFETCH;
            ELSE
              cycle <= cycle+1;
            END IF;
        END CASE;
      END IF;
    END IF;
  END PROCESS Machine;

  --############################################################################

  AutoBus:PROCESS(state,rpc,ea,rsp,rup,rtd,dec,cycle,ra,rx,rcc,vec) IS
    VARIABLE pc_v, sp_v, ret_v : uv12;
  BEGIN
    req_l <= '0';
    wr_l  <= '0';
    ad_l  <= rpc;
    dw_l  <= rtd;

    ret_v  := rpc + dec.len-1;
    
    --   000011x xxxx SP 2K
    --  0000011x xxxx SP 4K
    -- 0000001xx xxxx SP 8K
    sp_v := x"07F";
    sp_v(NB_SP-1 DOWNTO 0) := rsp;

    CASE state IS
      -----------------------------------------------------
      WHEN sFETCH => 
        ad_l  <= rpc;
        req_l <= '1';
        ph_l  <= PH_CODE;

      WHEN sIMMEDIATE | sDIRECT | sEXTENDED | sIX1 | sIX2 =>
        ad_l  <= rpc;
        req_l <= '1';
        ph_l  <= PH_POST;

      -----------------------------------------------------
      WHEN sREADMEM =>
        ad_l  <= ea;
        req_l <= '1';
        ph_l  <= PH_DATA;

      -----------------------------------------------------
      WHEN sWRITEMEM =>
        ad_l  <= ea;
        wr_l  <= '1';
        req_l <= '1';
        ph_l  <= PH_DATA;
        
      -----------------------------------------------------
      WHEN sWRITEPUSH => -- JSR, BSR, IRQ,
        ad_l  <= sp_v;
        req_l <= '1';
        IF cycle>0 THEN
          wr_l  <= '1';
          CASE cycle IS
            WHEN 1 => dw_l <= ret_v(7 DOWNTO 0);
            WHEN 2 => dw_l <= x"F" & ret_v(11 DOWNTO 8);
            WHEN 3 => dw_l <= rx;
            WHEN 4 => dw_l <= ra;
            WHEN OTHERS => dw_l <= cc_conv(rcc);
          END CASE;
          ph_l <= PH_STACK;
        ELSE
          ph_l <= PH_VOID;
        END IF;

      -----------------------------------------------------
      WHEN sREADPOP => -- RTS, RTI
        ad_l  <= sp_v;
        req_l <= '1';
        IF cycle>0 THEN
          ph_l <= PH_STACK;
        ELSE
          ph_l <= PH_VOID;
        END IF;

      -----------------------------------------------------
      WHEN sVECTOR =>
        ad_l  <= (OTHERS => '1');
        ad_l(2 DOWNTO 0) <= vec & to_std_logic(cycle=1);
        req_l <= '1';
        ph_l <= PH_DATA;

      -----------------------------------------------------
      WHEN OTHERS =>
        ad_l  <= rpc;
        ph_l  <= PH_VOID;
        req_l <= '1';
        NULL;

    END CASE;

  END PROCESS Autobus;

  req<=req_l;
  ad <=ad_l;
  dw <=dw_l;
  wr <=wr_l;

--pragma synthesis_off
--##############################################################################
  -- Instruction trace
  Trace:PROCESS (clk) IS
    FILE fil : text OPEN write_mode IS LOGFILE;
    VARIABLE lin : line;
    VARIABLE act   : boolean := false;
    VARIABLE ilen_v : natural;
    VARIABLE ops_v : natural;
    VARIABLE int_v : boolean := false;
    VARIABLE pc_v  : uv12;
    VARIABLE op_v  : uv8;
    VARIABLE b1_v, b2_v  : uv8;
    VARIABLE a_v   : uv8;
    VARIABLE x_v   : uv8;
    VARIABLE sp_v  : uv8;
    VARIABLE cc_v  : uv8;
    VARIABLE dec_v : type_op;
    VARIABLE t_v   : time := 0 ns;
    VARIABLE spf_v : uv12;

    -----------------------------------------------
    PROCEDURE write(cs: INOUT string;
                    s : IN string) IS
      VARIABLE j,k : integer;
    BEGIN
      j:=-1;
      FOR i IN 1 TO cs'length LOOP
        IF cs(i)=nul THEN j:=i; EXIT; END IF;
      END LOOP;
      
      k:=s'length;
      FOR i IN 1 TO s'length LOOP
        IF s(i)=nul THEN k:=i; EXIT; END IF;
      END LOOP;
      
      IF j>0 THEN
        cs(j TO j+k-1):=s(1 TO k);
      END IF;
    END PROCEDURE write;

    FUNCTION strip(s : IN string) RETURN string IS
    BEGIN
      FOR i IN 1 TO s'length LOOP
        IF s(i)=nul THEN RETURN s(1 TO i-1); END IF;
      END LOOP;
      RETURN s;
    END FUNCTION;
    
    PROCEDURE pad(s : INOUT string; l : natural) IS
      VARIABLE j : integer;
    BEGIN
      j:=-1;
      FOR i IN 1 TO s'length LOOP
        IF s(i)=nul THEN j:=i; EXIT; END IF;
      END LOOP;
      IF j>0 THEN
        s(j TO l):=(OTHERS =>' ');
      END IF;
    END PROCEDURE;

    -----------------------------------------------
    FUNCTION operand(d : type_op; pc : uv12; b1, b2 : uv8) RETURN string IS
      VARIABLE tgt : uv12;
    BEGIN
      CASE d.admode IS
        WHEN A_INH =>
          RETURN " ";
        WHEN A_IMM =>
          IF d.op=OP_BCOND OR d.op=OP_BSR THEN
            tgt := pc + d.len + unsigned(resize(signed(b1),12));
            RETURN "$" & to_hstring(tgt);
          ELSE
            RETURN "#$" & to_hstring(b1);
          END IF;
        WHEN A_BRSC =>
          tgt := pc + d.len + unsigned(resize(signed(b2),12));
          RETURN "$" & to_hstring(b1) & ",$" & to_hstring(tgt);
        WHEN A_DIR =>
          RETURN "$" & to_hstring(b1);
        WHEN A_EXT =>
          RETURN "$" & to_hstring(b1(3 DOWNTO 0)) & to_hstring(b2);
        WHEN A_IX =>
          RETURN ",X";
        WHEN A_IX1 =>
          RETURN "$" & to_hstring(b1) & ",X";
        WHEN A_IX2 =>
          RETURN "$" & to_hstring(b1(3 DOWNTO 0)) & to_hstring(b2) & ",X";
      END CASE;
      RETURN " ";
    END FUNCTION operand;

    -----------------------------------------------
    PROCEDURE instruction IS
      VARIABLE l : line;
      VARIABLE cs, ct : string(1 TO 100);
    BEGIN
      cs := (OTHERS => nul);
      write(cs, to_hstring(pc_v) & " : ");
      IF int_v THEN
        write(cs, " ");
      ELSE    
        write(cs,to_hstring(op_v) & ' ');
        IF ilen_v>1 THEN
          write(cs,to_hstring(b1_v) & ' ');
        END IF;
        IF ilen_v>2 THEN
          write(cs,to_hstring(b2_v) & ' ');
        END IF;
      END IF;
      pad(cs,18);      
      write(cs, " {" & integer'image(dec_v.cy) & "}");
      pad(cs,23);
      
      IF int_v OR dec_v.op=OP_INVALID THEN
        write(cs, dec_v.dis);
      ELSE
        write(cs, dec_v.dis & operand(dec_v, pc_v, b1_v, b2_v));
      END IF;
      pad(cs,38);
      write(cs," | A=" & to_hstring(a_v) &
               " X=" & to_hstring(x_v) &
               " SP=" & to_hstring(sp_v) &
               " CC=" & to_hstring(cc_v) &
               "   < " & time'image(t_v));
      write(lin,strip(cs));
      writeline(fil, lin);
      act   := false;
    END PROCEDURE instruction;
    -----------------------------------------------

  BEGIN
    IF rising_edge(clk) THEN
      IF reset_na='0' OR LOGFILE = "" THEN
        act   := false;

      ELSIF ack='1' AND req_l='1' THEN
        CASE ph_l IS
          -------------------------------------------------
          WHEN PH_CODE =>
            spf_v := x"07F";
            spf_v(NB_SP-1 DOWNTO 0) := rsp;

            pc_v  := ad_l;
            op_v  := dr;
            dec_v := opcodes(to_integer(dr));
            a_v   := ra;
            x_v   := rx;
            cc_v  := cc_conv(rcc);
            sp_v  := spf_v(7 DOWNTO 0);
            t_v   := now;
            b1_v  := (OTHERS => '0');
            b2_v  := (OTHERS => '0');
            ops_v  := 0;
            int_v := false;

            IF irq_n='0' AND rcc.i='0' THEN       -- IRQ : opcode is not executed
              int_v      := true;
              dec_v.admode := A_INH;
              dec_v.op   := OP_INT;
              dec_v.len  := 1;
              dec_v.cy   := 11;
              dec_v.dis  := "IRQ     ";
              ilen_v     := 0;
            ELSIF tim_n='0' AND rcc.i='0' THEN    -- Timer IRQ
              int_v      := true;
              dec_v.admode := A_INH;
              dec_v.op   := OP_INT;
              dec_v.len  := 1;
              dec_v.cy   := 11;
              dec_v.dis  := "TIMER   ";
              ilen_v     := 0;
            ELSIF dec_v.op=OP_INVALID THEN      -- Operand bytes are skipped
              ilen_v := 1;
            ELSE
              ilen_v := dec_v.len;
            END IF;

            act := true;
            IF ilen_v=1 THEN
              instruction;
            END IF;

          -------------------------------------------------
          -- Operand byte
          WHEN PH_POST =>
            IF act THEN
              IF ops_v=0 THEN
                b1_v := dr;
              ELSE
                b2_v := dr;
              END IF;
              ops_v := ops_v + 1;
              IF ops_v + 1 >= ilen_v THEN
                instruction;
              END IF;
            END IF;

          -------------------------------------------------
          -- Data / stack / vector access
          WHEN PH_DATA | PH_STACK =>
            IF wr_l='1' THEN
              write(lin, "  WR(" & to_hstring(ad_l) & ")=" & to_hstring(dw_l) &
                    " < " & time'image(now));
            ELSE
              write(lin, "  RD(" & to_hstring(ad_l) & ")=" & to_hstring(dr) &
                    " < " & time'image(now));
            END IF;
            writeline(fil, lin);

          -------------------------------------------------
          WHEN PH_VOID =>
            NULL;
        END CASE;
      END IF;
    END IF;
  END PROCESS Trace;

--pragma synthesis_on

END ARCHITECTURE rtl;