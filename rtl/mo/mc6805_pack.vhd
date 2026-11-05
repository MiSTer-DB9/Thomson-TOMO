--------------------------------------------------------------------------------
-- 
-- MC6805 CPU
--------------------------------------------------------------------------------

-- Package :
-- - ALU operations
-- - Instruction decode

--------------------------------------------------------------------------------
-- DO 10/2026
--------------------------------------------------------------------------------

LIBRARY ieee;
USE ieee.std_logic_1164.ALL;
USE ieee.numeric_std.ALL;

LIBRARY work;
USE work.base_pack.ALL;

PACKAGE mc6805_pack IS
  
  CONSTANT VEC_RESET : unsigned(2 DOWNTO 1) := "11"; -- xFE
  CONSTANT VEC_SWI   : unsigned(2 DOWNTO 1) := "10"; -- xFC
  CONSTANT VEC_IRQ   : unsigned(2 DOWNTO 1) := "01"; -- xFA
  CONSTANT VEC_TIM   : unsigned(2 DOWNTO 1) := "00"; -- xF8

  TYPE enum_admode IS (
    A_BRSC, -- 1 DIR + Imm value(branch)
    A_INH,  -- 0 
    A_IMM,  -- 1 Imm value
    A_DIR,  -- 1 Direct page 0
    A_EXT,  -- 2 Extended 
    A_IX,   -- 0 Index X
    A_IX1,  -- 1 Index X + Imm
    A_IX2   -- 2 Index X + Extended
  );

  TYPE enum_op IS (
    OP_INVALID,   -- Invalid/Undefined opcode
    OP_ALU,       -- ALU operations   (ADD, SUB, AND, ORA, EOR, ADC, SBC, CMP, BIT, LDA, LDX)
    OP_UNARY,     -- Unary operations (NEG, COM, LSR, ROR, ASR, LSL, ROL, DEC, INC, TST, CLR)
    OP_STORE,     -- (STA, STX)
    OP_BCOND,     -- Conditional branch
    OP_BSR,       -- Branch to Subroutine
    OP_BRSETCLR,  -- Bit Set/Clear Relative Branch (BRSET/BRCLR)
    OP_BSETCLR,   -- Bit Set/Clear (BSET/BCLR)
    OP_CONTROL,
    OP_JMP,       -- Jump
    OP_JSR,       -- Jump to Subroutine
    OP_RTI,       -- Return from Interrupt
    OP_RTS,       -- Return from Subroutine
    OP_INT,       -- Interrupt : SWI or IRQ or Timer
    OP_STOP,      -- Stop
    OP_WAIT       -- Wait
  );

  TYPE type_op IS RECORD
    admode : enum_admode; -- Addressing Mode
    op     : enum_op;  -- Instruction type
    cy     : natural RANGE 0 TO 31; -- TRACE : Cycles
    len    : natural RANGE 0 TO 3;  -- TRACE : Length
    dis    : string(1 TO 8);        -- TRACE : Instruction
  END RECORD;
  TYPE arr_op IS ARRAY (natural RANGE <>) OF type_op;

  -- MODE CYCLES LEN  DISAS
  CONSTANT opcodes:arr_op(0 TO 255):=(
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET0  "), -- 00
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR0  "), -- 01
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET1  "), -- 02
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR1  "), -- 03
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET2  "), -- 04
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR2  "), -- 05
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET3  "), -- 06
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR3  "), -- 07
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET4  "), -- 08
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR4  "), -- 09
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET5  "), -- 0A
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR5  "), -- 0B
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET6  "), -- 0C
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR6  "), -- 0D
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRSET7  "), -- 0E
    (A_BRSC, OP_BRSETCLR, 10, 3, "BRCLR7  "), -- 0F

    (A_DIR,  OP_BSETCLR,  7,  2, "BSET0   "), -- 10
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR0   "), -- 11
    (A_DIR,  OP_BSETCLR,  7,  2, "BSET1   "), -- 12
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR1   "), -- 13
    (A_DIR,  OP_BSETCLR,  7,  2, "BSET2   "), -- 14
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR2   "), -- 15
    (A_DIR,  OP_BSETCLR,  7,  2, "BSET3   "), -- 16
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR3   "), -- 17
    (A_DIR,  OP_BSETCLR,  7,  2, "BSET4   "), -- 18
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR4   "), -- 19
    (A_DIR,  OP_BSETCLR,  7,  2, "BSET5   "), -- 1A
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR5   "), -- 1B
    (A_DIR,  OP_BSETCLR,  7,  2, "BSET6   "), -- 1C
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR6   "), -- 1D
    (A_DIR,  OP_BSETCLR,  7,  2, "BSET7   "), -- 1E
    (A_DIR,  OP_BSETCLR,  7,  2, "BCLR7   "), -- 1F

    (A_IMM,  OP_BCOND,    4,  2, "BRA     "), -- 20
    (A_IMM,  OP_BCOND,    4,  2, "BRN     "), -- 21
    (A_IMM,  OP_BCOND,    4,  2, "BHI     "), -- 22
    (A_IMM,  OP_BCOND,    4,  2, "BLS     "), -- 23
    (A_IMM,  OP_BCOND,    4,  2, "BCC     "), -- 24
    (A_IMM,  OP_BCOND,    4,  2, "BCS     "), -- 25
    (A_IMM,  OP_BCOND,    4,  2, "BNE     "), -- 26
    (A_IMM,  OP_BCOND,    4,  2, "BEQ     "), -- 27
    (A_IMM,  OP_BCOND,    4,  2, "BHCC    "), -- 28
    (A_IMM,  OP_BCOND,    4,  2, "BHCS    "), -- 29
    (A_IMM,  OP_BCOND,    4,  2, "BPL     "), -- 2A
    (A_IMM,  OP_BCOND,    4,  2, "BMI     "), -- 2B
    (A_IMM,  OP_BCOND,    4,  2, "BMC     "), -- 2C
    (A_IMM,  OP_BCOND,    4,  2, "BMS     "), -- 2D
    (A_IMM,  OP_BCOND,    4,  2, "BIL     "), -- 2E
    (A_IMM,  OP_BCOND,    4,  2, "BIH     "), -- 2F

    (A_DIR,  OP_UNARY,    6,  2, "NEG     "), -- 30
    (A_DIR,  OP_INVALID,  6,  2, "Invalid "), -- 31
    (A_DIR,  OP_INVALID,  6,  2, "Invalid "), -- 32
    (A_DIR,  OP_UNARY,    6,  2, "COM     "), -- 33
    (A_DIR,  OP_UNARY,    6,  2, "LSR     "), -- 34
    (A_DIR,  OP_INVALID,  6,  2, "Invalid "), -- 35
    (A_DIR,  OP_UNARY,    6,  2, "ROR     "), -- 36
    (A_DIR,  OP_UNARY,    6,  2, "ASR     "), -- 37
    (A_DIR,  OP_UNARY,    6,  2, "LSL     "), -- 38
    (A_DIR,  OP_UNARY,    6,  2, "ROL     "), -- 39
    (A_DIR,  OP_UNARY,    6,  2, "DEC     "), -- 3A
    (A_DIR,  OP_INVALID,  6,  2, "Invalid "), -- 3B
    (A_DIR,  OP_UNARY,    6,  2, "INC     "), -- 3C
    (A_DIR,  OP_UNARY,    6,  2, "TST     "), -- 3D
    (A_DIR,  OP_INVALID,  6,  2, "Invalid "), -- 3E
    (A_DIR,  OP_UNARY,    6,  2, "CLR     "), -- 3F

    (A_INH,  OP_UNARY,    4,  1, "NEG     "), -- 40 (A) 
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 41
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 42
    (A_INH,  OP_UNARY,    4,  1, "COM     "), -- 43 (A)
    (A_INH,  OP_UNARY,    4,  1, "LSR     "), -- 44 (A)
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 45
    (A_INH,  OP_UNARY,    4,  1, "ROR     "), -- 46 (A)
    (A_INH,  OP_UNARY,    4,  1, "ASR     "), -- 47 (A)
    (A_INH,  OP_UNARY,    4,  1, "LSL     "), -- 48 (A)
    (A_INH,  OP_UNARY,    4,  1, "ROL     "), -- 49 (A)
    (A_INH,  OP_UNARY,    4,  1, "DEC     "), -- 4A (A)
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 4B
    (A_INH,  OP_UNARY,    4,  1, "INC     "), -- 4C (A)
    (A_INH,  OP_UNARY,    4,  1, "TST     "), -- 4D (A)
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 4E
    (A_INH,  OP_UNARY,    4,  1, "CLR     "), -- 4F (A)

    (A_INH,  OP_UNARY,    4,  1, "NEG     "), -- 50 (X)
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 51
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 52
    (A_INH,  OP_UNARY,    4,  1, "COM     "), -- 53 (X)
    (A_INH,  OP_UNARY,    4,  1, "LSR     "), -- 54 (X)
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 55
    (A_INH,  OP_UNARY,    4,  1, "ROR     "), -- 56 (X)
    (A_INH,  OP_UNARY,    4,  1, "ASR     "), -- 57 (X)
    (A_INH,  OP_UNARY,    4,  1, "LSL     "), -- 58 (X)
    (A_INH,  OP_UNARY,    4,  1, "ROL     "), -- 59 (X)
    (A_INH,  OP_UNARY,    4,  1, "DEC     "), -- 5A (X)
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 5B
    (A_INH,  OP_UNARY,    4,  1, "INC     "), -- 5C (X)
    (A_INH,  OP_UNARY,    4,  1, "TST     "), -- 5D (X)
    (A_INH,  OP_INVALID,  4,  1, "Invalid "), -- 5E
    (A_INH,  OP_UNARY,    4,  1, "CLR     "), -- 5F (X)

    (A_IX1,  OP_UNARY,    7,  2, "NEG     "), -- 60
    (A_IX1,  OP_INVALID,  7,  2, "Invalid "), -- 61
    (A_IX1,  OP_INVALID,  7,  2, "Invalid "), -- 62
    (A_IX1,  OP_UNARY,    7,  2, "COM     "), -- 63
    (A_IX1,  OP_UNARY,    7,  2, "LSR     "), -- 64
    (A_IX1,  OP_INVALID,  7,  2, "Invalid "), -- 65
    (A_IX1,  OP_UNARY,    7,  2, "ROR     "), -- 66
    (A_IX1,  OP_UNARY,    7,  2, "ASR     "), -- 67
    (A_IX1,  OP_UNARY,    7,  2, "LSL     "), -- 68
    (A_IX1,  OP_UNARY,    7,  2, "ROL     "), -- 69
    (A_IX1,  OP_UNARY,    7,  2, "DEC     "), -- 6A
    (A_IX1,  OP_INVALID,  7,  2, "Invalid "), -- 6B
    (A_IX1,  OP_UNARY,    7,  2, "INC     "), -- 6C
    (A_IX1,  OP_UNARY,    7,  2, "TST     "), -- 6D
    (A_IX1,  OP_INVALID,  7,  2, "Invalid "), -- 6E
    (A_IX1,  OP_UNARY,    7,  2, "CLR     "), -- 6F

    (A_IX,   OP_UNARY,    6,  1, "NEG     "), -- 70
    (A_IX,   OP_INVALID,  6,  1, "Invalid "), -- 71
    (A_IX,   OP_INVALID,  6,  1, "Invalid "), -- 72
    (A_IX,   OP_UNARY,    6,  1, "COM     "), -- 73
    (A_IX,   OP_UNARY,    6,  1, "LSR     "), -- 74
    (A_IX,   OP_INVALID,  6,  1, "Invalid "), -- 75
    (A_IX,   OP_UNARY,    6,  1, "ROR     "), -- 76
    (A_IX,   OP_UNARY,    6,  1, "ASR     "), -- 77
    (A_IX,   OP_UNARY,    6,  1, "LSL     "), -- 78
    (A_IX,   OP_UNARY,    6,  1, "ROL     "), -- 79
    (A_IX,   OP_UNARY,    6,  1, "DEC     "), -- 7A
    (A_IX,   OP_INVALID,  6,  1, "Invalid "), -- 7B
    (A_IX,   OP_UNARY,    6,  1, "INC     "), -- 7C
    (A_IX,   OP_UNARY,    6,  1, "TST     "), -- 7D
    (A_IX,   OP_INVALID,  6,  1, "Invalid "), -- 7E
    (A_IX,   OP_UNARY  ,  6,  1, "CLR     "), -- 7F

    (A_INH,  OP_RTI,      9,  1, "RTI     "), -- 80
    (A_INH,  OP_RTS,      6,  1, "RTS     "), -- 81
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 82
    (A_INH,  OP_INT,     11,  1, "SWI     "), -- 83
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 84
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 85
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 86
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 87
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 88
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 89
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 8A
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 8B
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 8C
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 8D
    (A_INH,  OP_STOP,     2,  1, "STOP    "), -- 8E
    (A_INH,  OP_WAIT,     2,  1, "WAIT    "), -- 8F

    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 90
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 91
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 92
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 93
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 94
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 95
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 96
    (A_INH,  OP_CONTROL,  2,  1, "TAX     "), -- 97
    (A_INH,  OP_CONTROL,  2,  1, "CLC     "), -- 98
    (A_INH,  OP_CONTROL,  2,  1, "SEC     "), -- 99
    (A_INH,  OP_CONTROL,  2,  1, "CLI     "), -- 9A
    (A_INH,  OP_CONTROL,  2,  1, "SEI     "), -- 9B
    (A_INH,  OP_CONTROL,  2,  1, "RSP     "), -- 9C
    (A_INH,  OP_CONTROL,  2,  1, "NOP     "), -- 9D
    (A_INH,  OP_INVALID,  2,  1, "Invalid "), -- 9E
    (A_INH,  OP_CONTROL,  2,  1, "TXA     "), -- 9F

    (A_IMM,  OP_ALU,      2,  2, "SUB     "), -- A0
    (A_IMM,  OP_ALU,      2,  2, "CMP     "), -- A1
    (A_IMM,  OP_ALU,      2,  2, "SBC     "), -- A2
    (A_IMM,  OP_ALU,      2,  2, "CPX     "), -- A3
    (A_IMM,  OP_ALU,      2,  2, "AND     "), -- A4
    (A_IMM,  OP_ALU,      2,  2, "BIT     "), -- A5
    (A_IMM,  OP_ALU,      2,  2, "LDA     "), -- A6
    (A_IMM,  OP_INVALID,  2,  2, "Invalid "), -- A7
    (A_IMM,  OP_ALU,      2,  2, "EOR     "), -- A8
    (A_IMM,  OP_ALU,      2,  2, "ADC     "), -- A9
    (A_IMM,  OP_ALU,      2,  2, "ORA     "), -- AA
    (A_IMM,  OP_ALU,      2,  2, "ADD     "), -- AB
    (A_IMM,  OP_INVALID,  2,  2, "Invalid "), -- AC
    (A_IMM,  OP_BSR,      8,  2, "BSR     "), -- AD
    (A_IMM,  OP_ALU,      2,  2, "LDX     "), -- AE
    (A_IMM,  OP_INVALID,  2,  2, "Invalid "), -- AF

    (A_DIR,  OP_ALU,      4,  2, "SUB     "), -- B0
    (A_DIR,  OP_ALU,      4,  2, "CMP     "), -- B1
    (A_DIR,  OP_ALU,      4,  2, "SBC     "), -- B2
    (A_DIR,  OP_ALU,      4,  2, "CPX     "), -- B3
    (A_DIR,  OP_ALU,      4,  2, "AND     "), -- B4
    (A_DIR,  OP_ALU,      4,  2, "BIT     "), -- B5
    (A_DIR,  OP_ALU,      4,  2, "LDA     "), -- B6
    (A_DIR,  OP_STORE,    5,  2, "STA     "), -- B7
    (A_DIR,  OP_ALU,      4,  2, "EOR     "), -- B8
    (A_DIR,  OP_ALU,      4,  2, "ADC     "), -- B9
    (A_DIR,  OP_ALU,      4,  2, "ORA     "), -- BA
    (A_DIR,  OP_ALU,      4,  2, "ADD     "), -- BB
    (A_DIR,  OP_JMP,      3,  2, "JMP     "), -- BC
    (A_DIR,  OP_JSR,      7,  2, "JSR     "), -- BD
    (A_DIR,  OP_ALU,      4,  2, "LDX     "), -- BE
    (A_DIR,  OP_STORE,    5,  2, "STX     "), -- BF

    (A_EXT,  OP_ALU,      5,  3, "SUB     "), -- C0
    (A_EXT,  OP_ALU,      5,  3, "CMP     "), -- C1
    (A_EXT,  OP_ALU,      5,  3, "SBC     "), -- C2
    (A_EXT,  OP_ALU,      5,  3, "CPX     "), -- C3
    (A_EXT,  OP_ALU,      5,  3, "AND     "), -- C4
    (A_EXT,  OP_ALU,      5,  3, "BIT     "), -- C5
    (A_EXT,  OP_ALU,      5,  3, "LDA     "), -- C6
    (A_EXT,  OP_STORE,    6,  3, "STA     "), -- C7
    (A_EXT,  OP_ALU,      5,  3, "EOR     "), -- C8
    (A_EXT,  OP_ALU,      5,  3, "ADC     "), -- C9
    (A_EXT,  OP_ALU,      5,  3, "ORA     "), -- CA
    (A_EXT,  OP_ALU,      5,  3, "ADD     "), -- CB
    (A_EXT,  OP_JMP,      4,  3, "JMP     "), -- CC
    (A_EXT,  OP_JSR,      8,  3, "JSR     "), -- CD
    (A_EXT,  OP_ALU,      5,  3, "LDX     "), -- CE
    (A_EXT,  OP_STORE,    6,  3, "STX     "), -- CF

    (A_IX2,  OP_ALU,      6,  3, "SUB     "), -- D0
    (A_IX2,  OP_ALU,      6,  3, "CMP     "), -- D1
    (A_IX2,  OP_ALU,      6,  3, "SBC     "), -- D2
    (A_IX2,  OP_ALU,      6,  3, "CPX     "), -- D3
    (A_IX2,  OP_ALU,      6,  3, "AND     "), -- D4
    (A_IX2,  OP_ALU,      6,  3, "BIT     "), -- D5
    (A_IX2,  OP_ALU,      6,  3, "LDA     "), -- D6
    (A_IX2,  OP_STORE,    7,  3, "STA     "), -- D7
    (A_IX2,  OP_ALU,      6,  3, "EOR     "), -- D8
    (A_IX2,  OP_ALU,      6,  3, "ADC     "), -- D9
    (A_IX2,  OP_ALU,      6,  3, "ORA     "), -- DA
    (A_IX2,  OP_ALU,      6,  3, "ADD     "), -- DB
    (A_IX2,  OP_JMP,      5,  3, "JMP     "), -- DC
    (A_IX2,  OP_JSR,      9,  3, "JSR     "), -- DD
    (A_IX2,  OP_ALU,      6,  3, "LDX     "), -- DE
    (A_IX2,  OP_STORE,    7,  3, "STX     "), -- DF

    (A_IX1,  OP_ALU,      5,  2, "SUB     "), -- E0
    (A_IX1,  OP_ALU,      5,  2, "CMP     "), -- E1
    (A_IX1,  OP_ALU,      5,  2, "SBC     "), -- E2
    (A_IX1,  OP_ALU,      5,  2, "CPX     "), -- E3
    (A_IX1,  OP_ALU,      5,  2, "AND     "), -- E4
    (A_IX1,  OP_ALU,      5,  2, "BIT     "), -- E5
    (A_IX1,  OP_ALU,      5,  2, "LDA     "), -- E6
    (A_IX1,  OP_STORE,    6,  2, "STA     "), -- E7
    (A_IX1,  OP_ALU,      5,  2, "EOR     "), -- E8
    (A_IX1,  OP_ALU,      5,  2, "ADC     "), -- E9
    (A_IX1,  OP_ALU,      5,  2, "ORA     "), -- EA
    (A_IX1,  OP_ALU,      5,  2, "ADD     "), -- EB
    (A_IX1,  OP_JMP,      4,  2, "JMP     "), -- EC
    (A_IX1,  OP_JSR,      8,  2, "JSR     "), -- ED
    (A_IX1,  OP_ALU,      5,  2, "LDX     "), -- EE
    (A_IX1,  OP_STORE,    6,  2, "STX     "), -- EF

    (A_IX,   OP_ALU,      4,  1, "SUB     "), -- F0
    (A_IX,   OP_ALU,      4,  1, "CMP     "), -- F1
    (A_IX,   OP_ALU,      4,  1, "SBC     "), -- F2
    (A_IX,   OP_ALU,      4,  1, "CPX     "), -- F3
    (A_IX,   OP_ALU,      4,  1, "AND     "), -- F4
    (A_IX,   OP_ALU,      4,  1, "BIT     "), -- F5
    (A_IX,   OP_ALU,      4,  1, "LDA     "), -- F6
    (A_IX,   OP_STORE,    5,  1, "STA     "), -- F7
    (A_IX,   OP_ALU,      4,  1, "EOR     "), -- F8
    (A_IX,   OP_ALU,      4,  1, "ADC     "), -- F9
    (A_IX,   OP_ALU,      4,  1, "ORA     "), -- FA
    (A_IX,   OP_ALU,      4,  1, "ADD     "), -- FB
    (A_IX,   OP_JMP,      3,  1, "JMP     "), -- FC
    (A_IX,   OP_JSR,      7,  1, "JSR     "), -- FD
    (A_IX,   OP_ALU,      4,  1, "LDX     "), -- FE
    (A_IX,   OP_STORE,    5,  1, "STX     ") -- FF
    );

  ------------------------------------------------
  TYPE type_ccr IS RECORD
    h : std_logic; -- 5 : Half Carry
    i : std_logic; -- 4 : IRQ mask
    n : std_logic; -- 3 : Negative
    z : std_logic; -- 2 : Zero
    c : std_logic; -- 0 : Carry
  END RECORD;

  ------------------------------------------------
  FUNCTION cc_conv(x:uv8) RETURN type_ccr;
  
  FUNCTION cc_conv(x:type_ccr) RETURN uv8;
  
  ------------------------------------------------
  PROCEDURE bsetclr(
    op   : IN  uv8;
    i_r  : IN  uv8;
    o_r  : OUT uv8);

  PROCEDURE alu(
    op   : IN uv8;
    i_r  : IN uv8;
    i_m  : IN uv8;     -- Mem / Immediate
    i_cc : IN type_ccr;
    o_r  : OUT uv8;
    o_up : OUT std_logic;
    o_cc : OUT type_ccr);

  PROCEDURE unary(
    op   : IN  uv8;
    i_r  : IN  uv8;
    i_cc : IN  type_ccr;
    o_r  : OUT uv8;
    o_up : OUT std_logic;
    o_cc : OUT type_ccr);

  ------------------------------------------------
  FUNCTION bcond(op : uv8;
                 cc : type_ccr;
                 int_n : std_logic) RETURN boolean;

  ------------------------------------------------

END PACKAGE;

--##############################################################################
PACKAGE BODY mc6805_pack IS

  FUNCTION cc_conv(x:type_ccr) RETURN uv8 IS
    VARIABLE t:uv8;
  BEGIN
    t:="111" & x.h & x.i & x.n & x.z & x.c;
    RETURN t;
  END FUNCTION cc_conv;

  FUNCTION cc_conv(x:uv8) RETURN type_ccr IS
  BEGIN
    RETURN (c=>x(0),z=>x(1),n=>x(2),i=>x(3),h=>x(4));
  END FUNCTION cc_conv;

  -----------------------------------------------------------------------------
  PROCEDURE bsetclr(
      op   : IN  uv8;
      i_r  : IN  uv8;
      o_r  : OUT uv8) IS
  BEGIN
    o_r := i_r;
    o_r(to_integer(op(3 DOWNTO 1))) := NOT op(0);
  END PROCEDURE;

  -----------------------------------------------------------------------------
  PROCEDURE alu(
      op   : IN  uv8;
      i_r  : IN  uv8;          -- RA / RX (for STX)
      i_m  : IN  uv8;          -- Mem / Immediate
      i_cc : IN  type_ccr;
      o_r  : OUT uv8;
      o_up : OUT std_logic;
      o_cc : OUT type_ccr) IS
    VARIABLE o_v : uv8;
  BEGIN
    o_v  := i_r;
    o_up := '0';
    o_cc := i_cc;
    
    CASE op(3 DOWNTO 0) IS
      WHEN x"0" => -- SUB  A <= A - M     . .NZC
        o_v    := i_r - i_m;
        o_up   := '1';
        --o_cc.c := (i_r(7) AND i_m(7)) OR (i_m(7) AND NOT o_v(7)) OR (NOT o_v(7) AND i_r(7));
        o_cc.c := (NOT i_r(7) AND i_m(7)) OR (i_m(7) AND o_v(7)) OR (o_v(7) AND NOT i_r(7));

      WHEN x"1" => -- CMP       A - M      ..NZC
        o_v    := i_r - i_m;
        --o_cc.c := (i_r(7) AND i_m(7)) OR (i_m(7) AND NOT o_v(7)) OR (NOT o_v(7) AND i_r(7));
        o_cc.c := (NOT i_r(7) AND i_m(7)) OR (i_m(7) AND o_v(7)) OR (o_v(7) AND NOT i_r(7));
        
      WHEN x"2" => -- SBC  A <= A - M - C  ..NZC
        o_v    := i_r - i_m - ("0" & i_cc.c);
        o_up   := '1';
        --o_cc.c := (i_r(7) AND i_m(7)) OR (i_m(7) AND NOT o_v(7)) OR (NOT o_v(7) AND i_r(7));
        o_cc.c := (NOT i_r(7) AND i_m(7)) OR (i_m(7) AND o_v(7)) OR (o_v(7) AND NOT i_r(7));

      WHEN x"3" => -- CPX       X - M      ..NZC
        o_v    := i_r - i_m;
        --o_cc.c := (i_r(7) AND i_m(7)) OR (i_m(7) AND NOT o_v(7)) OR (NOT o_v(7) AND i_r(7));
        o_cc.c := (NOT i_r(7) AND i_m(7)) OR (i_m(7) AND o_v(7)) OR (o_v(7) AND NOT i_r(7));

      WHEN x"4" => -- AND  A <= A & M      ..NZ.
        o_v    := i_r AND i_m;
        o_up   := '1';

      WHEN x"5" => -- BIT                  ..NZ.
        o_v    := i_r AND i_m;

      WHEN x"6" => -- LDA  A <= M          ..NZ.
        o_v    := i_m;
        o_up   := '1';

      WHEN x"7" => -- STA  M <= A          ..NZ.
        o_v    := i_r;
        
      WHEN x"8" => -- EOR  A <= A ^ M      ..NZ.
        o_v    := i_r XOR i_m;
        o_up   := '1';

      WHEN x"9" => -- ADC  A <= A + M + C  H.NZC
        o_v    := i_r + i_m + ("0" & i_cc.c);
        o_up   := '1';
        o_cc.c := (i_r(7) AND i_m(7)) OR (i_m(7) AND NOT o_v(7)) OR (NOT o_v(7) AND i_r(7));
        --o_cc.h := (i_r(3) AND i_m(3)) OR (i_m(3) AND o_v(3)) OR (o_v(3) AND i_r(3));
        o_cc.h := (i_r(3) AND i_m(3)) OR (i_m(3) AND NOT o_v(3)) OR (NOT o_v(3) AND i_r(3));

      WHEN x"A" => -- ORA  A <= A | M      ..NZ.
        o_v    := i_r OR i_m;
        o_up   := '1';

      WHEN x"B" => -- ADD  A <= A + M      H.NZ.
        o_v    := i_r + i_m;
        o_up   := '1';
        o_cc.c := (i_r(7) AND i_m(7)) OR (i_m(7) AND NOT o_v(7)) OR (NOT o_v(7) AND i_r(7));
        --o_cc.h := (i_r(3) AND i_m(3)) OR (i_m(3) AND o_v(3)) OR (o_v(3) AND i_r(3));
        o_cc.h := (i_r(3) AND i_m(3)) OR (i_m(3) AND NOT o_v(3)) OR (NOT o_v(3) AND i_r(3));

      WHEN x"C" => -- (JMP)
        NULL;

      WHEN x"D" => -- (JSR)
        NULL;

      WHEN x"E" => -- LDX  X <= M          ..NZ.
        o_v    := i_m;
        o_up   := '1';
        
      WHEN x"F" => -- STX  M <= X          ..NZ.
        o_v    := i_r;

      WHEN OTHERS =>
        NULL;
      
    END CASE;
    o_cc.z := to_std_logic(o_v=x"00");
    o_cc.n := o_v(7);
    o_r := o_v;

  END PROCEDURE;

  -----------------------------------------------------------------------------
  PROCEDURE unary(
    op   : IN  uv8;
    i_r  : IN  uv8;
    i_cc : IN  type_ccr;
    o_r  : OUT uv8;
    o_up : OUT std_logic;
    o_cc : OUT type_ccr) IS
    VARIABLE o_v : uv8;
  BEGIN
    o_v  := i_r;
    o_cc := i_cc;
    o_up := '0';

    CASE op(3 DOWNTO 0) IS
      WHEN x"0" => -- NEG   A <= -A    ..NZC
        o_v    := x"00" - i_r;
        o_up   := '1';
        o_cc.c := NOT to_std_logic(o_v = x"00");
      WHEN x"3" => -- COM   A <= !A    ..NZC
        o_v    := NOT i_r;
        o_up   := '1';
        o_cc.c := '1';

      WHEN x"4" => -- LSR              ..NZC
        o_v    := '0' & i_r(7 DOWNTO 1);
        o_up   := '1';
        o_cc.c := i_r(0);

      WHEN x"6" => -- ROR  A|c <= c|A  ..NZC
        o_v    := i_cc.c & i_r(7 DOWNTO 1);
        o_up   := '1';
        o_cc.c := i_r(0);

      WHEN x"7" => -- ASR              ..NZC
        o_v    := i_r(7) & i_r(7 DOWNTO 1);
        o_up   := '1';
        o_cc.c := i_r(0);

      WHEN x"8" => -- LSL = ASL        ..NZC
        o_v    := i_r(6 DOWNTO 0) & '0';
        o_up   := '1';
        o_cc.c := i_r(7);

      WHEN x"9" => -- ROL   c|A <= A|c  ..NZC
        o_v    := i_r(6 DOWNTO 0) & i_cc.c;
        o_up   := '1';
        o_cc.c := i_r(7);

      WHEN x"A" => -- DEC  A <= A - 1   ..NZ.
        o_v    := i_r - 1;
        o_up   := '1';

      WHEN x"C" => -- INC  A <= A + 1   ..NZ.
        o_v    := i_r + 1;
        o_up   := '1';

      WHEN x"D" => -- TST               ..NZ.
        o_v    := i_r;

      WHEN x"F" => -- CLR  A <= "00"    ..NZ.
        o_v    := x"00";
        o_up   := '1';

      WHEN OTHERS => -- Invalid
    END CASE;

    o_cc.z := to_std_logic(o_v=x"00");
    o_cc.n := o_v(7);
    o_r := o_v;

  END PROCEDURE;

  ------------------------------------------------
  FUNCTION bcond(op : uv8;
                 cc : type_ccr;
                 int_n : std_logic) RETURN boolean IS
    VARIABLE br : boolean;
  BEGIN
    CASE op(3 DOWNTO 0) IS
      WHEN x"0" => -- BRA Branch Aways
        br:=true;
      WHEN x"1" => -- BRN Branch Never
        br:=false;
      WHEN x"2" => -- BHI Branch IF Higher
        br:=(cc.c='0' AND cc.z='0');
      WHEN x"3" => -- BLS Branch IF Lower Or Same
        br:=(cc.c='1' OR cc.z='1');
      WHEN x"4" => -- BHS, BCC Branch IF Carry Clear / Higher Or Same
        br:=(cc.c='0');
      WHEN x"5" => -- BLO, BCS Branch IF Lower / Carry Set
        br:=(cc.c='1');
      WHEN x"6" => -- BNE Branch IF Not Equal
        br:=(cc.z='0');
      WHEN x"7" => -- BEQ Branch IF Equal
        br:=(cc.z='1');
      WHEN x"8" => -- BHCC Branch IF Half Carry Clear
        br:=(cc.h='0');
      WHEN x"9" => -- BHCS Branch IF Half Carry Set
        br:=(cc.h='1');
      WHEN x"A" => -- BPL Branch IF Plus
        br:=(cc.n='0');
      WHEN x"B" => -- BMI Branch IF Minus
        br:=(cc.n='1');
      WHEN x"C" => -- BMC Branch IF Interrupt mask bit is clear
        br:=(cc.i='0');
      WHEN x"D" => -- BMS Branch IF Interrupt mask bit is set
        br:=(cc.i='1');
      WHEN x"E" => -- BIL Branch IF interrupt line is Active
        br:=(int_n='0');
      WHEN x"F" => -- BIH Branch IF interrupt line is Inactive
        br:=(int_n='1');
      WHEN OTHERS =>
        br:=false;
    END CASE;
    RETURN br;
  END FUNCTION bcond;
  
END PACKAGE BODY mc6805_pack;


