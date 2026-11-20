// ============================================================================
// Milestone 0 -- DFX toolchain smoke test, static top level.
//
//   PS7 --AXI-Lite--> gpio_data.ch1 (32b out) --> u_rp.din
//                     gpio_data.ch2 (32b in)  <-- isolation <-- u_rp.dout
//                     gpio_ctrl.ch1 (1b out)  --> decouple
//                     gpio_ctrl.ch2 (8b in)   <-- isolation <-- u_rp.rm_id
//   LEDs[3:0] show the (isolated) low nibble of u_rp.dout.
//
// u_rp is the single reconfigurable partition. Its module (rp_m0) is a black
// box here; the RMs live in rm_inv.v / rm_buf.v and are synthesised
// out-of-context. Every RM must match this exact port list.
//
// Isolation: while decouple=1 the static side sees all-zero data and RM ID,
// whatever the region is doing mid-reconfiguration. This is the hand-written
// equivalent of a DFX Decoupler, sized for a smoke test.
// ============================================================================
`timescale 1ns / 1ps
`default_nettype none

module m0_top (
    inout  wire [14:0] DDR_addr,
    inout  wire [2:0]  DDR_ba,
    inout  wire        DDR_cas_n,
    inout  wire        DDR_ck_n,
    inout  wire        DDR_ck_p,
    inout  wire        DDR_cke,
    inout  wire        DDR_cs_n,
    inout  wire [3:0]  DDR_dm,
    inout  wire [31:0] DDR_dq,
    inout  wire [3:0]  DDR_dqs_n,
    inout  wire [3:0]  DDR_dqs_p,
    inout  wire        DDR_odt,
    inout  wire        DDR_ras_n,
    inout  wire        DDR_reset_n,
    inout  wire        DDR_we_n,
    inout  wire        FIXED_IO_ddr_vrn,
    inout  wire        FIXED_IO_ddr_vrp,
    inout  wire [53:0] FIXED_IO_mio,
    inout  wire        FIXED_IO_ps_clk,
    inout  wire        FIXED_IO_ps_porb,
    inout  wire        FIXED_IO_ps_srstb,
    output reg  [3:0]  led
);

    wire        clk;
    wire [31:0] data_to_rp;
    wire [31:0] data_from_rp;
    wire [0:0]  decouple;
    wire [7:0]  rm_id_to_ps;

    wire [31:0] rp_dout;
    wire [7:0]  rp_rm_id;

    m0_bd_wrapper u_bd (
        .DDR_addr          (DDR_addr),
        .DDR_ba            (DDR_ba),
        .DDR_cas_n         (DDR_cas_n),
        .DDR_ck_n          (DDR_ck_n),
        .DDR_ck_p          (DDR_ck_p),
        .DDR_cke           (DDR_cke),
        .DDR_cs_n          (DDR_cs_n),
        .DDR_dm            (DDR_dm),
        .DDR_dq            (DDR_dq),
        .DDR_dqs_n         (DDR_dqs_n),
        .DDR_dqs_p         (DDR_dqs_p),
        .DDR_odt           (DDR_odt),
        .DDR_ras_n         (DDR_ras_n),
        .DDR_reset_n       (DDR_reset_n),
        .DDR_we_n          (DDR_we_n),
        .FIXED_IO_ddr_vrn  (FIXED_IO_ddr_vrn),
        .FIXED_IO_ddr_vrp  (FIXED_IO_ddr_vrp),
        .FIXED_IO_mio      (FIXED_IO_mio),
        .FIXED_IO_ps_clk   (FIXED_IO_ps_clk),
        .FIXED_IO_ps_porb  (FIXED_IO_ps_porb),
        .FIXED_IO_ps_srstb (FIXED_IO_ps_srstb),
        .fclk              (clk),
        .data_to_rp        (data_to_rp),
        .data_from_rp      (data_from_rp),
        .decouple          (decouple),
        .rm_id             (rm_id_to_ps)
    );

    // ---- the reconfigurable partition ------------------------------------
    rp_m0 u_rp (
        .clk   (clk),
        .din   (data_to_rp),
        .dout  (rp_dout),
        .rm_id (rp_rm_id)
    );

    // ---- isolation (static side of the RP boundary) ----------------------
    assign data_from_rp = decouple[0] ? 32'h0000_0000 : rp_dout;
    assign rm_id_to_ps  = decouple[0] ? 8'h00         : rp_rm_id;

    always @(posedge clk)
        led <= data_from_rp[3:0];

endmodule

`default_nettype wire
