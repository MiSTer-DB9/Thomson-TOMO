//============================================================================
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 2 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//
//============================================================================

module emu
(
	//Master input clock
	input         CLK_50M,

	//Async reset from top-level module.
	//Can be used as initial reset.
	input         RESET,

	//Must be passed to hps_io module
	inout  [45:0] HPS_BUS,

	//Base video clock. Usually equals to CLK_SYS.
	output        CLK_VIDEO,

	//Multiple resolutions are supported using different CE_PIXEL rates.
	//Must be based on CLK_VIDEO
	output        CE_PIXEL,

	//Video aspect ratio for HDMI. Most retro systems have ratio 4:3.
	output [12:0] VIDEO_ARX,
	output [12:0] VIDEO_ARY,

	output  [7:0] VGA_R,
	output  [7:0] VGA_G,
	output  [7:0] VGA_B,
	output        VGA_HS,
	output        VGA_VS,
	output        VGA_DE,    // = ~(VBlank | HBlank)
	output        VGA_F1,
	output [1:0]  VGA_SL,
	output        VGA_SCALER, // Force VGA scaler
	output        VGA_DISABLE,

	input  [11:0] HDMI_WIDTH,
	input  [11:0] HDMI_HEIGHT,
	output        HDMI_FREEZE,
	output        HDMI_BLACKOUT,
	output        HDMI_BOB_DEINT,

	/*
	// Use framebuffer from DDRAM (USE_FB=1 in qsf)
	// FB_FORMAT:
	//    [2:0] : 011=8bpp(palette) 100=16bpp 101=24bpp 110=32bpp
	//    [3]   : 0=16bits 565 1=16bits 1555
	//    [4]   : 0=RGB  1=BGR (for 16/24/32 modes)
	//
	// FB_STRIDE either 0 (rounded to 256 bytes) or multiple of 16 bytes.
	output        FB_EN,
	output  [4:0] FB_FORMAT,
	output [11:0] FB_WIDTH,
	output [11:0] FB_HEIGHT,
	output [31:0] FB_BASE,
	output [13:0] FB_STRIDE,
	input         FB_VBL,
	input         FB_LL,
	output        FB_FORCE_BLANK,

	// Palette control for 8bit modes.
	// Ignored for other video modes.
	output        FB_PAL_CLK,
	output  [7:0] FB_PAL_ADDR,
	output [23:0] FB_PAL_DOUT,
	input  [23:0] FB_PAL_DIN,
	output        FB_PAL_WR,
	*/

	output        LED_USER,  // 1 - ON, 0 - OFF.

	// b[1]: 0 - LED status is system status OR'd with b[0]
	//       1 - LED status is controled solely by b[0]
	// hint: supply 2'b00 to let the system control the LED.
	output  [1:0] LED_POWER,
	output  [1:0] LED_DISK,

	// I/O board button press simulation (active high)
	// b[1]: user button
	// b[0]: osd button
	output  [1:0] BUTTONS,

	input         CLK_AUDIO, // 24.576 MHz
	output [15:0] AUDIO_L,
	output [15:0] AUDIO_R,
	output        AUDIO_S,   // 1 - signed audio samples, 0 - unsigned
	output  [1:0] AUDIO_MIX, // 0 - no mix, 1 - 25%, 2 - 50%, 3 - 100% (mono)

	//ADC
	inout   [3:0] ADC_BUS,

	//SD-SPI
	output        SD_SCK,
	output        SD_MOSI,
	input         SD_MISO,
	output        SD_CS,
	input         SD_CD,

	//High latency DDR3 RAM interface
	//Use for non-critical time purposes
	output        DDRAM_CLK,
	input         DDRAM_BUSY,
	output  [7:0] DDRAM_BURSTCNT,
	output [28:0] DDRAM_ADDR,
	input  [63:0] DDRAM_DOUT,
	input         DDRAM_DOUT_READY,
	output        DDRAM_RD,
	output [63:0] DDRAM_DIN,
	output  [7:0] DDRAM_BE,
	output        DDRAM_WE,

	//SDRAM interface with lower latency
	output        SDRAM_CLK,
	output        SDRAM_CKE,
	output [12:0] SDRAM_A,
	output  [1:0] SDRAM_BA,
	inout  [15:0] SDRAM_DQ,
	output        SDRAM_DQML,
	output        SDRAM_DQMH,
	output        SDRAM_nCS,
	output        SDRAM_nCAS,
	output        SDRAM_nRAS,
	output        SDRAM_nWE,

	input         UART_CTS,
	output        UART_RTS,
	input         UART_RXD,
	output        UART_TXD,
	output        UART_DTR,
	input         UART_DSR,

	// Open-drain User port.
	// 0 - D+/RX
	// 1 - D-/TX
	// 2..6 - USR2..USR6
	// Set USER_OUT to 1 to read from USER_IN.
	input   [6:0] USER_IN,
	output  [6:0] USER_OUT,

	input         OSD_STATUS
);

///////// Default values for ports not used in this core /////////

assign ADC_BUS  = 'Z;
assign USER_OUT = '1;
assign {UART_RTS, UART_TXD, UART_DTR} = 0;
assign {SD_SCK, SD_MOSI, SD_CS} = 'Z;

assign VGA_SL = 0;
assign VGA_F1 = 0;
assign VGA_SCALER = 0;
assign VGA_DISABLE = 0;
assign HDMI_FREEZE = 0;
assign HDMI_BLACKOUT = 0;

assign AUDIO_S = 1;
assign AUDIO_MIX = 0;

assign LED_DISK = 0;
assign LED_POWER = 0;
assign BUTTONS = 0;

//////////////////////////////////////////////////////////////////

wire [1:0] ar = status[9:8];

assign VIDEO_ARX = (!ar) ? 13'd4 : (ar - 1'd1);
assign VIDEO_ARY = (!ar) ? 13'd3 : 13'd0;

wire        ioctl_download;
wire [7:0]  ioctl_index;
wire        ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0]  ioctl_dout;
wire        ioctl_wait;
wire [31:0] joystick_0,joystick_1;
wire [15:0] joystick_analog_0,joystick_analog_1;

`include "build_id.v" 
localparam CONF_STR = {
	"TOMO;;",
	"-;",
	"FC0,ROM,Load ROM;",
	"F1,BINROM,Load cartridge;",
	"F2,WAV,Load tape;",
	"F3,FD,Load floppy;",
	"OM,Floppy,On,Off;",
	"O13,Model,Auto,MO5,MO6,TO7,TO770,TO8,TO9,TO9+;",
	"O89,Aspect ratio,Original,Full Screen,[ARC1],[ARC2];",
	"OH,Mouse,LightPen,Mouse;",
	"OK,CPU,VHDL,Verilog;",
	"OAB,Speed,1MHz (normal),2MHz,4MHz;",
	"OCD,Cursor,Off,White,Black,Red;",
	"OL,Bar (tape+disk),On,Off;",
	"OE,Border,On,Off;",
	"TG,Rewind Tape;",
	"-;",
	"R0,Reset;",
	"V,v",`BUILD_DATE 
};

//	"O45,Keyboard,Auto,FR,IT,DE;",
//	"O67,Keyboard,DCMOTO,QWERTY,AZERTY;",


// 0         1         2         3 
// 01234567890123456789012345678901
// 0123456789ABCDEFGHIJKLMNOPQRSTUV
//  XXX....XXXXXXXXXX  XXX
    

wire forced_scandoubler;
wire  [1:0] buttons;
wire [31:0] status;
wire        status_set;
wire [10:0] ps2_key;
wire [24:0] ps2_mouse;

wire [2:0] modsel;
wire [1:0] kbdsel, kbdmode; 
wire [1:0] cursor;
wire [1:0] speed;
wire nobord;
wire azerty, dcmoto;
wire cputype;
wire mouse;

assign modsel  = status[3:1];
assign kbdsel  = status[5:4];
assign kbdmode = status[7:6];
assign cursor  = status[13:12];
assign nobord  = status[14];

assign cputype = status[20];
assign bar     = !status[21];
assign flopex  = !status[22];
assign speed   = status[11:10] & {!cputype,!cputype};
assign mouse   = status[17];

wire pll_locked;

assign status_set = cputype & (status[11] | status[10]); // Force 1MHz if Verilog CPU

hps_io #(.CONF_STR(CONF_STR)) hps_io
(
	.clk_sys(clk_sys),
	.HPS_BUS(HPS_BUS),
	.EXT_BUS(),
	.gamma_bus(),

	.forced_scandoubler(forced_scandoubler),

	.buttons(buttons),
	.status(status),
	.status_in({status[31:12],2'h00,status[9:0]}),
	.status_set(status_set),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait),
	
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	.joystick_r_analog_0(joystick_analog_0),
	.joystick_r_analog_1(joystick_analog_1),

	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse)
	
);


///////////////////////   CLOCKS   ///////////////////////////////

wire clk_sys;
pll pll
(
	.refclk(CLK_50M),
	.rst(0),
	.locked(pll_locked),
	.outclk_0(clk_sys)
);

wire reset = RESET | buttons[1];
wire menureset = status[0];

//////////////////////////////////////////////////////////////////

tomo_core tomo_core
(
	.sysclk(clk_sys),
	.pll_locked(pll_locked),
	.reset(reset),
	.menureset(menureset),

	.cputype(cputype),
	.modsel(modsel),
	.kbdsel(kbdsel),
	.kbdmode(kbdmode),
	.flopex(flopex),
	.mouse(mouse),

	.nobord(nobord),
	.cursor(cursor),
	.bar(bar),
	
	.rewind(status[16]),
	.speed(speed),
	.capslock(LED_USER),
 
	.clk_video(CLK_VIDEO),
	.ce_pixel(CE_PIXEL),
	.vga_r(VGA_R),
	.vga_g(VGA_G),
	.vga_b(VGA_B),
	.vga_hs(VGA_HS),
	.vga_vs(VGA_VS),
	.vga_de(VGA_DE),
	
	.audio_l(AUDIO_L),
	.audio_r(AUDIO_R),
	
	.ps2_key(ps2_key),
	.ps2_mouse(ps2_mouse),
	.joystick_0(joystick_0),
	.joystick_1(joystick_1),
	//.joystick_analog_0(joystick_analog_0),
	//.joystick_analog_1(joystick_analog_1),
	
	.ddram_clk(DDRAM_CLK),
	.ddram_waitrequest(DDRAM_BUSY),
	.ddram_burstcount(DDRAM_BURSTCNT),
	.ddram_address(DDRAM_ADDR),
	.ddram_readdata(DDRAM_DOUT),
	.ddram_readdatavalid(DDRAM_DOUT_READY),
	.ddram_read(DDRAM_RD),
	.ddram_writedata(DDRAM_DIN),
	.ddram_byteenable(DDRAM_BE),
	.ddram_write(DDRAM_WE),

    .sdram_dq(SDRAM_DQ),
    .sdram_a(SDRAM_A),
    .sdram_dqml(SDRAM_DQML),
    .sdram_dqmh(SDRAM_DQMH),
    .sdram_ba(SDRAM_BA),
    .sdram_ncs(SDRAM_nCS),
    .sdram_nwe(SDRAM_nWE),
    .sdram_nras(SDRAM_nRAS),
    .sdram_ncas(SDRAM_nCAS),
    .sdram_cke(SDRAM_CKE),
    .sdram_clk(SDRAM_CLK),

	.ioctl_download(ioctl_download),
	.ioctl_index(ioctl_index),
	.ioctl_wr(ioctl_wr),
	.ioctl_addr(ioctl_addr),
	.ioctl_dout(ioctl_dout),
	.ioctl_wait(ioctl_wait)

);
  
endmodule
