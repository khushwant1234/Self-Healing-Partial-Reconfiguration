// M0 reconfigurable module "buf": registered pass-through.  RM_ID = 0xB2
`timescale 1ns / 1ps
`default_nettype none
module rp_m0 (
    input  wire        clk,
    input  wire [31:0] din,
    output wire [31:0] dout,
    output wire [7:0]  rm_id
);
    reg [31:0] q = 32'h0000_0000;
    always @(posedge clk) q <= din;
    assign dout  = q;
    assign rm_id = 8'hB2;
endmodule
`default_nettype wire
