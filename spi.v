// spi.v inspired by zxuno project

module spi (
   input clk,              // 7MHz
   input tx_strobe,        // Byte ready to be transmitted
   input rx_strobe,        // request to read one byte
   input [7:0] din,        // del bus de datos de salida de la CPU
   output reg [7:0] dout,  // al bus de datos de entrada de la CPU
   
   output spi_clk,         // spi itself
   input  spi_di,          //
   output spi_do,          //
	output reg transmit
);

reg [4:0] counter = 5'd16; // tx/rx counter is idle
reg [7:0] io_byte;
   
assign spi_clk = counter[0];
assign spi_do = io_byte[7];       // data is shifted up during transfer
wire io_strobe = tx_strobe || rx_strobe;
reg old_strobe;

always @(posedge clk) begin
	// spi engine idle and is supposed to be started?
	old_strobe <= io_strobe;
	if (io_strobe && !old_strobe && (counter == 16)) begin
		// kickstart engine
      counter <= 5'd0;
		dout <= io_byte;
		io_byte <= tx_strobe?din:8'hff;
		transmit <= 1'b1;
   end else if(counter != 16) begin
		if(spi_clk) io_byte <= { io_byte[6:0], spi_di };
      counter <= counter + 5'd1;
		transmit <= 1'b1;
   end else transmit <= 1'b0;
end

endmodule
