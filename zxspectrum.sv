//============================================================================
// Sinclair ZX Spectrum host board
// 
//  Port to MIST board. (C) 2015 Sorgelig
//
//  Copyright (C) 2014  Goran Devic
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
//============================================================================
module zxspectrum
(
   input  wire [1:0]  CLOCK_27,            // Input clock 27 MHz

   output wire [5:0]  VGA_R,
   output wire [5:0]  VGA_G,
   output wire [5:0]  VGA_B,
   output wire        VGA_HS,
   output wire        VGA_VS,
	 
	output wire        LED,

	output wire        AUDIO_L,
   output wire        AUDIO_R,

   input  wire        SPI_SCK,
   output wire        SPI_DO,
   input  wire        SPI_DI,
   input  wire        SPI_SS2,
   input  wire        SPI_SS3,
	input  wire        SPI_SS4,
   input  wire        CONF_DATA0,

	output wire [12:0] SDRAM_A,
	inout  wire [15:0] SDRAM_DQ,
	output wire        SDRAM_DQML,
	output wire        SDRAM_DQMH,
	output wire        SDRAM_nWE,
	output wire        SDRAM_nCAS,
	output wire        SDRAM_nRAS,
	output wire        SDRAM_nCS,
	output wire [1:0]  SDRAM_BA,
	output wire        SDRAM_CLK,
	output wire        SDRAM_CKE
);
`default_nettype none


`define DIVMMC_ROM
//`define ENABLE_WAIT

////////////////////////////////////////////////////////////////////////

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Internal buses and address map selection logic
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
always_comb
begin
    case ({nMREQ,nIORQ,nRD,nWR})
        // -------------------------------- Memory read --------------------------------
        4'b0101: D =          (A[15:14] > 2'b00) ? sram_data : 
                    `ifdef DIVMMC_ROM divmmc_rom ? divmmc_rom_data : `endif
                                         ext_ram ? sram_data :
                                                   vram_data_cpu;

        // ---------------------------------- IO read ----------------------------------
        4'b1001: D =                      (!nM1) ? 8'hFF :
                                divmmc_active_io ? divmmc_data :
		                           (A[7:0]==8'h1F) ? {2'b00, joystick_0[5:0] | joystick_1[5:0]} :
                                                   ula_data;

        default: D = 8'bzzzzzzzz;
    endcase
end

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate Memory
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

// VRAM 16K blocks:
// 00 - ROM0
// 01 - ROM1
// 10 - Screen 0,1 (8k*2)
wire [7:0] vram_data_cpu;
wire vram_we = ((A[15:13] == 3'b010) || ((A[15:13] == 3'b110) && page_ram_sel[2] && page_ram_sel[0])) && !nMREQ && nRD && !nWR;
wire [15:0] vram_addr_cpu =  (A[15:14] == 2'b00) ? {1'b0, page_rom_sel, A[13:0]} :
							        (A[15:14] == 2'b01) ? {3'b100, A[12:0]} :
		                           page_ram_sel[1] ? {3'b101, A[12:0]} :
										                     {3'b100, A[12:0]};

// "A" side is the CPU side, "B" side is the VGA image generator
vram vram(
    .clock      (clk_pix),       // RAM connects to 112MHz

    .address_a  (vram_addr_cpu), // Address in to the RAM from the CPU side
    .data_a     (D),             // Data in to the RAM from the CPU side
    .q_a        (vram_data_cpu), // Data out from the RAM into the data bus selector
    .wren_a     (vram_we),

    .address_b  ({2'b10, page_shadow_scr, vram_address}),
    .data_b     (0),
    .q_b        (vram_data),
    .wren_b     (0)
);

wire [7:0] sram_data;
wire sram_we = (ext_ram_write || (A[15:14] > 2'b00)) && !nMREQ && nRD && !nWR;
wire sram_rd = !nMREQ && !nRD && nWR;
wire [24:0] sram_addr = (A[15:14] == 2'b00) ? divmmc_addr :
                        (A[15:14] == 2'b01) ? {11'd5, A[13:0]} :
								(A[15:14] == 2'b10) ? {11'd2, A[13:0]} :
								                      {8'd0, page_ram_sel, A[13:0]};

wire ioctl_req = (!nRESET || !nBUSACK) && !nBUSRQ;
wire pWAIT;

sram sram( .*,
    .init(!locked),
	 .clk_sdram(clk_ram),
	 .dout(sram_data),
	 .din (ioctl_req ? ioctl_data      : 
			  (!nRFSH) ? 8'b0            :
			             D               ),

	 .addr(ioctl_req ? ioctl_addr      : 
			  (!nRFSH) ? tape_addr_save  :
	                   sram_addr       ),

	 .we  (ioctl_req ? ioctl_wr        : 
			  (!nRFSH) ? 1'b0            :
                      sram_we         ),
							 
	 .rd  (ioctl_req ? 1'b0            :
			  (!nRFSH) ? tape_io         :
                      sram_rd         ),
	 .cpu_wait(pWAIT)
);

reg       page_shadow_scr  = 1'b0;
reg       page_reg_disable = 1'b0;
reg [2:0] page_ram_sel     = 3'b000;
reg       page_rom_sel     = 1'b0;

wire page_write = io_we && A[0] && !(A[15] || A[1]);

always @ (posedge clk_cpu or negedge nRESET) begin
	if (!nRESET) begin
		page_reg_disable <= 1'b0;
		page_rom_sel     <= 1'b0;
		page_shadow_scr  <= 1'b0;
		page_ram_sel     <= 3'b000;
	end else begin
		if (page_write && !page_reg_disable) begin
			page_reg_disable <= D[5];
			page_rom_sel     <= D[4];
			page_shadow_scr  <= D[3];
			page_ram_sel     <= D[2:0];
		end
	end
end

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate ULA
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire        locked;
wire        clk_cpu;       // CPU clock of 3.5 MHz
wire        clk_pix;			// pixel clock according to choosen standard
wire        clk_ram;			// 112MHz clock for RAM 
wire        clk_sys;       // 28MHz for system synchronization 
wire        clk_ula;       // 14MHz
wire [12:0] vram_address;
wire [7:0]  vram_data;
wire        vs_nintr;      // Generates a vertical retrace interrupt
wire [7:0]  ula_data;
wire        F11;
wire        F1;
reg         AUDIO_IN;
wire [5:0]  VGA_Rx;
wire [5:0]  VGA_Gx;
wire [5:0]  VGA_Bx;
wire        VGA_HS_OSD;
wire        VGA_VS_OSD;

ula ula_( .*, .turbo(status[2]), .nCONT(status[3]));

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate A-Z80 CPU
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire [15:0] A;  // Global address bus
wire [7:0]  D;  // CPU data bus

wire nM1;
wire nMREQ;
wire nIORQ;
wire nRD;
wire nWR;
wire nRFSH;
wire nHALT;
wire nBUSACK;

wire nWAIT	= `ifdef ENABLE_WAIT !pWAIT; `else 1'b1; `endif
wire nINT   = vs_nintr;
wire nNMI   = esxNMI;
wire nBUSRQ = !ioctl_download;
wire nRESET = locked && !buttons[1] && !status[0] && !status[4] && esxRESET;

wire io_we = !nIORQ && nRD && !nWR && nM1;
wire io_rd = !nIORQ && !nRD && nWR && nM1;

z80_top_direct_n cpu( .*, .CLK(clk_cpu));

//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
// Instantiate MIST ARM I/O
//~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
wire        PS2_CLK;
wire        PS2_DAT;

wire [7:0]  joystick_0;
wire [7:0]  joystick_1;
wire [1:0]  buttons;
wire [1:0]  switches;
wire		   scandoubler_disable;
wire [7:0]  status;

wire [31:0] sd_lba;
wire        sd_rd;
wire        sd_wr;
wire        sd_ack;
wire        sd_conf;
wire        sd_sdhc;
wire [7:0]  sd_dout;
wire        sd_dout_strobe;
wire [7:0]  sd_din;
wire        sd_din_strobe;

reg [10:0]  clk14k_div;
reg         clk_ps2;

always @(posedge clk_sys)
begin
	clk14k_div <= clk14k_div + 11'b1;
	clk_ps2 <= clk14k_div[10];
end

user_io #(.STRLEN(94)) user_io (
	.*,
	.conf_str("SPECTRUM;CSW;T1,ESXDOS Menu (F11);O2,CPU Speed,3.5MHz,4MHz;O3,Contended memory,On,Off;T4,Reset"),

	// ps2 keyboard emulation
	.ps2_clk(clk_ps2),				// 12-16khz provided by core
	.ps2_kbd_clk(PS2_CLK),
	.ps2_kbd_data(PS2_DAT),
	
	// unused
	.joystick_analog_0(),
	.joystick_analog_1(),
	.ps2_mouse_clk(),
	.ps2_mouse_data(),
	.serial_data(),
	.serial_strobe()
);

osd osd( .*);

//////////////////////////////////////////////////////////////////////////////////

reg  [1:0] esxdos_downloaded = 1'b00;
wire ext_ram = divmmc_active && esxdos_downloaded[1];

// write to upper 8k unless
wire ext_ram_write = ext_ram && (A[15:13] == 3'b001);

// DIVMMC mapping
wire [24:0] divmmc_addr = {6'b000011, divmmc_mapaddr};

wire esxRESET = !(esxRQ && (esxdos_downloaded == 2'b01)) && (initRESET == 0);
wire esxNMI   = !(esxRQ && esxdos_downloaded[1]);

reg esxRQb = 0;
wire esxRQ = esxRQb || status[1];

reg sRST1 = 0, sRST2 = 0;
always @(posedge clk_ps2) begin
	sRST1 <= F11 || joystick_0[7] || joystick_1[7];
	sRST2 <= sRST1;

	if(sRST2 && !sRST1) esxRQb <= 1;
	else esxRQb <= 0;
end

// wait for ESXDOS ROM loading 
integer initRESET = 32000000;
always @(posedge clk_sys) begin 
	if(initRESET!=0) begin 

`ifdef DIVMMC_ROM
		if(initRESET == 1) begin 
			esxdos_downloaded[0] <= 1'b1;
			force_erase <=1'b1;
		end
`endif

		initRESET <= initRESET - 1;
	end
end

always @(negedge esxRQ) begin
	esxdos_downloaded <= {esxdos_downloaded[0], esxdos_downloaded[0]};
end

assign LED = !(!divmmc_sd_activity || ioctl_download);

wire        divmmc_sd_activity;
wire        divmmc_active;
wire        divmmc_active_io;
wire [18:0] divmmc_mapaddr;
wire  [7:0] divmmc_data;

divmmc divmmc(
	.*,
	.clk(clk_sys),

	.enabled(esxdos_downloaded[1]),
	.din(D),
	.dout(divmmc_data),

	.active(divmmc_active),
	.active_io(divmmc_active_io),
	.mapped_addr(divmmc_mapaddr),

	.sd_activity(divmmc_sd_activity)
);

`ifdef DIVMMC_ROM

wire divmmc_rom = (A[15:13]==3'b000) && ext_ram;
wire [7:0] divmmc_rom_data;

divmmc_rom esxrom(
    .clock   (clk_sys),
    .address (A[12:0]),
    .q       (divmmc_rom_data)
);

`else

always @ (posedge ioctl_download) begin
	if(ioctl_index == 5'b00000) esxdos_downloaded[0] <= 1'b1;
end

`endif

////////////////////////////////////////////////////////////////////////////////////

wire ioctl_wr;
wire [24:0] ioctl_addr;
wire [7:0]  ioctl_data;
reg  force_erase = 1'b0;

data_io data_io(
	.sck(SPI_SCK),
	.ss(SPI_SS2),
	.sdi(SPI_DI),

	.force_erase(force_erase),
	.downloading(ioctl_download),
	.size(ioctl_size),
	.index(ioctl_index),

	.clk(clk_sys),
	.wr(ioctl_wr),
	.a(ioctl_addr),
	.d(ioctl_data)
);

wire [24:0] ioctl_size;
wire        ioctl_download;
wire [4:0]  ioctl_index;

// tape download comes from OSD entry 1
wire tape_download = (ioctl_index == 5'b00001) && ioctl_download;
wire tape_rd;

reg [2:0] tape_ack_delay = 3'd0;
reg tape_io = 1'b0;

wire [24:0] tape_addr;
wire  [7:0] tape_data;

reg tRFSH;
reg [24:0] tape_addr_save = 25'd0;

always @(posedge clk_sys) begin
	tRFSH <= nRFSH;
	if(tape_rd) begin
		if(!nRFSH && tRFSH) begin
			if(tape_addr_save != tape_addr) begin
				tape_addr_save <= tape_addr;
				tape_io <= 1'b1;
				tape_ack_delay <= 3'd7;
			end
		end

		if(tape_ack_delay != 3'd0) begin
			tape_ack_delay <= tape_ack_delay - 3'd1;
			if(tape_ack_delay == 3'b1) begin
				tape_data <= sram_data;
				tape_io <= 1'b0;
			end
		end
	end
		
	if(nRFSH) begin
		tape_ack_delay <= 3'd0;
		tape_io <= 1'b0;
	end
end

tape tape (
	.clk(clk_sys),
	.reset(!nRESET),
	.iocycle(tape_io),

	.audio_out(AUDIO_IN),
	.pause(F1),

	.downloading(tape_download),
	.size(ioctl_size),

	.rd(tape_rd),
	.a(tape_addr),
	.d(tape_data)
);

endmodule
