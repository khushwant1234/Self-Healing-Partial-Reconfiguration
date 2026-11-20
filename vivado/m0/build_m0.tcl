# =============================================================================
# Milestone 0 -- DFX toolchain smoke test (one RP, two RMs: inv, buf).
#
#   vivado -mode batch -notrace -source vivado/m0/build_m0.tcl
#   (normally via:  scripts/run.sh m0   or   scripts\run.bat m0)
#
# Flow (non-project DFX, as in UG909/UG947):
#   1. static: block design (PS7 + 2x AXI GPIO) + m0_top, RP as black box
#   2. each RM synthesised out-of-context
#   3. parent config  (static + inv): place & route, carve out RP, lock static
#   4. child config   (locked static + buf): place & route RM only
#   5. bitstreams: one full (static+inv), one partial per RM
#   6. pr_verify: confirm both configs share identical static
#
# Outputs (committed):  bitstreams/m0/{m0_static.bit, m0_static.hwh,
#                       rm_inv_partial.bit, rm_buf_partial.bit, manifest.txt}
#                       reports/m0/{SUMMARY.txt, step_times.txt, *.rpt}
# =============================================================================
source [file join [file dirname [file normalize [info script]]] .. common.tcl]

sh_init m0
set ::M0_HDL [file join $::SH_REPO hdl m0]
set ::M0_XDC [file join $::SH_REPO constraints m0]
set ::M0_RMS {inv buf}   ;# first entry is implemented in the parent config

# -----------------------------------------------------------------------------
proc m0_static_synth {} {
    set pdir [sh_b bdp]
    create_project -force bdp $pdir -part $::SH_PART
    if {$::SH_BOARD_PART ne ""} {
        set_property board_part $::SH_BOARD_PART [current_project]
    }
    set_property target_language Verilog [current_project]

    create_bd_design m0_bd

    # --- PS7 -----------------------------------------------------------------
    set ps [create_bd_cell -type ip -vlnv [sh_vlnv processing_system7] ps7]
    set preset [expr {$::SH_BOARD_PART ne "" ? 1 : 0}]
    apply_bd_automation -rule xilinx.com:bd_rule:processing_system7 \
        -config [list make_external "FIXED_IO, DDR" apply_board_preset $preset \
                      Master Disable Slave Disable] $ps
    set_property -dict [list \
        CONFIG.PCW_USE_M_AXI_GP0            1   \
        CONFIG.PCW_EN_CLK0_PORT             1   \
        CONFIG.PCW_EN_RST0_PORT             1   \
        CONFIG.PCW_FPGA0_PERIPHERAL_FREQMHZ 100 ] $ps

    # --- GPIOs ---------------------------------------------------------------
    set gd [create_bd_cell -type ip -vlnv [sh_vlnv axi_gpio] gpio_data]
    set_property -dict [list CONFIG.C_GPIO_WIDTH 32 CONFIG.C_ALL_OUTPUTS 1 \
        CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH 32 CONFIG.C_ALL_INPUTS_2 1] $gd
    set gc [create_bd_cell -type ip -vlnv [sh_vlnv axi_gpio] gpio_ctrl]
    set_property -dict [list CONFIG.C_GPIO_WIDTH 1 CONFIG.C_ALL_OUTPUTS 1 \
        CONFIG.C_IS_DUAL 1 CONFIG.C_GPIO2_WIDTH 8 CONFIG.C_ALL_INPUTS_2 1] $gc

    foreach g {gpio_data gpio_ctrl} {
        apply_bd_automation -rule xilinx.com:bd_rule:axi4 -config [list \
            Clk_master {Auto} Clk_slave {Auto} Clk_xbar {Auto} \
            Master {/ps7/M_AXI_GP0} Slave "/$g/S_AXI" \
            intc_ip {Auto} master_apm {0}] [get_bd_intf_pins $g/S_AXI]
    }

    # --- ports out to the static RTL ----------------------------------------
    create_bd_port -dir O -from 31 -to 0 data_to_rp
    connect_bd_net [get_bd_pins gpio_data/gpio_io_o]  [get_bd_ports data_to_rp]
    create_bd_port -dir I -from 31 -to 0 data_from_rp
    connect_bd_net [get_bd_ports data_from_rp]        [get_bd_pins gpio_data/gpio2_io_i]
    create_bd_port -dir O -from 0 -to 0 decouple
    connect_bd_net [get_bd_pins gpio_ctrl/gpio_io_o]  [get_bd_ports decouple]
    create_bd_port -dir I -from 7 -to 0 rm_id
    connect_bd_net [get_bd_ports rm_id]               [get_bd_pins gpio_ctrl/gpio2_io_i]
    create_bd_port -dir O -type clk fclk
    connect_bd_net [get_bd_pins ps7/FCLK_CLK0]        [get_bd_ports fclk]

    assign_bd_address
    validate_bd_design
    save_bd_design

    set bd [get_files m0_bd.bd]
    set_property synth_checkpoint_mode None $bd   ;# global synth, no OOC IP runs
    generate_target all $bd
    add_files -norecurse [make_wrapper -files $bd -top]

    add_files -norecurse [list [file join $::M0_HDL m0_top.v] \
                               [file join $::M0_HDL rp_m0_stub.v]]
    add_files -fileset constrs_1 -norecurse [file join $::M0_XDC m0_pins.xdc]
    set_property top m0_top [current_fileset]
    update_compile_order -fileset sources_1

    synth_design -top m0_top -part $::SH_PART
    write_checkpoint -force [sh_b static_synth.dcp]
    report_utilization -file [sh_rpt static_synth_utilization.rpt]

    # PYNQ needs the .hwh next to the full .bit, with the same basename.
    set hwh [sh_find_files $pdir m0_bd.hwh]
    if {![llength $hwh]} { error "m0_bd.hwh was not generated -- PYNQ cannot load the overlay without it" }
    set ::M0_HWH [lindex $hwh 0]
    sh_result hwh_source $::M0_HWH
    close_project
}

proc m0_rm_synth {rm} {
    catch {close_project}
    create_project -in_memory -part $::SH_PART
    read_verilog [file join $::M0_HDL rm_${rm}.v]
    synth_design -mode out_of_context -top rp_m0 -part $::SH_PART
    write_checkpoint -force [sh_b rm_${rm}_synth.dcp]
    report_utilization -file [sh_rpt rm_${rm}_synth_utilization.rpt]
    close_project
}

proc m0_impl_parent {rm} {
    catch {close_project}
    open_checkpoint [sh_b static_synth.dcp]
    set rp [get_cells u_rp]
    if {![llength $rp]} { error "cell u_rp not found in the static netlist" }
    read_checkpoint -cell $rp [sh_b rm_${rm}_synth.dcp]
    set_property HD.RECONFIGURABLE true $rp
    read_xdc [file join $::M0_XDC m0_pblock.xdc]

    opt_design
    place_design
    route_design

    sh_impl_reports cfg_${rm}
    report_utilization -pblocks [get_pblocks pblock_rp] \
        -file [sh_rpt cfg_${rm}_pblock_utilization.rpt]
    write_checkpoint -force [sh_b cfg_${rm}_routed.dcp]

    # carve out the RM and lock the static routing for every child config
    update_design -cell $rp -black_box
    lock_design -level routing
    write_checkpoint -force [sh_b static_routed.dcp]
    close_project
}

proc m0_impl_child {rm} {
    catch {close_project}
    open_checkpoint [sh_b static_routed.dcp]
    read_checkpoint -cell [get_cells u_rp] [sh_b rm_${rm}_synth.dcp]
    opt_design
    place_design
    route_design
    sh_impl_reports cfg_${rm}
    write_checkpoint -force [sh_b cfg_${rm}_routed.dcp]
    close_project
}

proc m0_bitstreams {parent rms} {
    catch {close_project}
    sh_manifest_header

    open_checkpoint [sh_b cfg_${parent}_routed.dcp]
    sh_write_full_bit [sh_b m0_static.bit]
    close_project
    sh_publish [sh_b m0_static.bit] m0_static.bit
    sh_publish $::M0_HWH            m0_static.hwh

    foreach rm $rms {
        open_checkpoint [sh_b cfg_${rm}_routed.dcp]
        write_bitstream -force -cell u_rp [sh_b rm_${rm}_partial.bit]
        close_project
        sh_publish [sh_b rm_${rm}_partial.bit] rm_${rm}_partial.bit
        sh_result "rm_${rm}_partial_bytes" [file size [sh_b rm_${rm}_partial.bit]]
    }
    sh_result full_bit_bytes [file size [sh_b m0_static.bit]]
}

# Non-fatal: bitstreams are already written; a failure here is recorded
# loudly in SUMMARY.txt and the partials must not be trusted.
proc m0_pr_verify {parent children} {
    catch {close_project}
    set add [list]
    foreach c $children { lappend add [sh_b cfg_${c}_routed.dcp] }
    set rpt [sh_rpt pr_verify.rpt]
    if {[catch {pr_verify -initial [sh_b cfg_${parent}_routed.dcp] \
                          -additional $add -file $rpt} err]} {
        sh_result pr_verify "ERROR: $err"
        sh_issue "pr_verify errored -- do NOT load these partials until resolved"
        return
    }
    set txt ""
    if {[file exists $rpt]} { set fh [open $rpt r]; set txt [read $fh]; close $fh }
    if {[regexp -nocase {incompatible} $txt]} {
        sh_result pr_verify FAIL
        sh_issue "pr_verify reports INCOMPATIBLE configurations -- do NOT load these partials"
    } elseif {[regexp -nocase {compatible} $txt]} {
        sh_result pr_verify PASS
    } else {
        sh_result pr_verify "UNKNOWN (see reports/m0/pr_verify.rpt and vivado.log)"
        sh_issue "pr_verify result could not be parsed"
    }
}

# -----------------------------------------------------------------------------
proc m0_main {} {
    set parent   [lindex $::M0_RMS 0]
    set children [lrange $::M0_RMS 1 end]

    sh_step preflight     { sh_preflight }
    sh_step static_synth  { m0_static_synth }
    foreach rm $::M0_RMS  { sh_step rm_${rm}_synth [list m0_rm_synth $rm] }
    sh_step impl_parent_$parent [list m0_impl_parent $parent]
    foreach rm $children  { sh_step impl_child_$rm [list m0_impl_child $rm] }
    sh_step bitstreams    [list m0_bitstreams $parent $::M0_RMS]
    sh_step pr_verify     [list m0_pr_verify $parent $children]
}

if {[catch {m0_main} err]} {
    puts "ERROR: \[selfheal\] build failed in step '$::SH_STEP': $err"
    sh_write_summary FAIL $err
    exit 1
}
sh_write_summary PASS
exit 0
