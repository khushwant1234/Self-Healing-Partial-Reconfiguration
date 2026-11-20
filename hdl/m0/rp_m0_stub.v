// Black-box declaration of the M0 reconfigurable partition.
// Used ONLY for static synthesis. The port list here is the RP contract:
// rm_inv.v and rm_buf.v must match it signal for signal.
`timescale 1ns / 1ps
(* black_box *)
module rp_m0 (
    input  wire        clk,
    input  wire [31:0] din,
    output wire [31:0] dout,
    output wire [7:0]  rm_id
);
endmodule
