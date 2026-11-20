# =============================================================================
# vivado/common.tcl -- helpers shared by every batch build script.
# Sourced by vivado/<target>/build_<target>.tcl. Never run this file directly.
#
# Rules every build script follows:
#   * batch mode only, no GUI, no wizards;
#   * every path is built with [file join] from SH_REPO, so the same script
#     runs on Linux and Windows unchanged;
#   * each step is timed into reports/<target>/step_times.txt;
#   * on success OR failure, reports/<target>/SUMMARY.txt is written, so the
#     laptop session always produces something to push back.
#
# Environment overrides:
#   SELFHEAL_BUILD_ROOT  put the (gitignored) build tree somewhere else,
#                        e.g. C:\b on Windows to stay clear of MAX_PATH.
# =============================================================================

set ::SH_REPO [file normalize [file join [file dirname [file normalize [info script]]] ..]]
set ::SH_PART          xc7z020clg400-1
set ::SH_BOARD_PATTERN "tul.com.tw:pynq-z2:part0:*"
set ::SH_BOARD_PART    ""
set ::SH_STEP          init
set ::SH_RESULTS       [list]
set ::SH_ISSUES        [list]

proc sh_env {name default} {
    if {[info exists ::env($name)] && $::env($name) ne ""} { return $::env($name) }
    return $default
}

proc sh_init {tag} {
    set ::SH_TAG    $tag
    set root        [file normalize [sh_env SELFHEAL_BUILD_ROOT [file join $::SH_REPO build]]]
    set ::SH_BUILD  [file join $root $tag]
    set ::SH_BITDIR [file join $::SH_REPO bitstreams $tag]
    set ::SH_RPTDIR [file join $::SH_REPO reports $tag]
    foreach d [list $::SH_BUILD $::SH_BITDIR $::SH_RPTDIR] { file mkdir $d }
    set ::SH_T0 [clock seconds]
    set fh [open [sh_rpt step_times.txt] w]
    puts $fh [format "%-30s %8s %10s" step seconds cumulative]
    close $fh
    sh_result started [clock format $::SH_T0 -format "%Y-%m-%d %H:%M:%S"]
}

proc sh_rpt {name} { return [file join $::SH_RPTDIR $name] }
proc sh_b   {name} { return [file join $::SH_BUILD  $name] }

proc sh_result {key value} { lappend ::SH_RESULTS [list $key $value] }
proc sh_issue  {text} {
    lappend ::SH_ISSUES $text
    puts "CRITICAL WARNING: \[selfheal\] $text"
}

# Run BODY in the caller's scope as a named, timed step.
proc sh_step {name body} {
    set ::SH_STEP $name
    puts "\n================ STEP: $name ================"
    set t [clock seconds]
    uplevel 1 $body
    set now [clock seconds]
    set dt  [expr {$now - $t}]
    set cum [expr {$now - $::SH_T0}]
    set fh [open [sh_rpt step_times.txt] a]
    puts $fh [format "%-30s %8d %10d" $name $dt $cum]
    close $fh
    puts "================ DONE: $name (${dt}s, total ${cum}s) ================"
}

proc sh_write_summary {status {err ""}} {
    if {$status eq "PASS" && [llength $::SH_ISSUES]} { set status BUILT_WITH_ISSUES }
    set fh [open [sh_rpt SUMMARY.txt] w]
    puts $fh "target:     $::SH_TAG"
    puts $fh "status:     $status"
    puts $fh "elapsed_s:  [expr {[clock seconds] - $::SH_T0}]"
    if {$err ne ""} {
        puts $fh "failed_in:  $::SH_STEP"
        puts $fh "error:      $err"
    }
    puts $fh ""
    foreach r $::SH_RESULTS {
        puts $fh [format "%-28s %s" "[lindex $r 0]:" [lindex $r 1]]
    }
    if {[llength $::SH_ISSUES]} {
        puts $fh "\nissues:"
        foreach i $::SH_ISSUES { puts $fh "  - $i" }
    }
    close $fh
    puts "\n#### SUMMARY ($status) written to [sh_rpt SUMMARY.txt]"
}

# Windows MAX_PATH guard. Generated IP paths add ~170 chars under the build
# directory (more once the AXI DMA and interconnect are in), and the failure
# mode is a misleading synthesis error, so refuse to start instead.
proc sh_check_paths {} {
    set n [string length $::SH_BUILD]
    sh_result build_dir "$::SH_BUILD ($n chars)"
    if {$::tcl_platform(platform) eq "windows" && $n > 60} {
        error "Build directory is $n characters long: $::SH_BUILD -- on Windows this \
will exceed the 260-character path limit inside generated IP and fail with an \
unrelated-looking synthesis error. Clone the repo to a short root such as C:\\dfx\\sh, \
or set SELFHEAL_BUILD_ROOT=C:\\b, then re-run."
    }
}

proc sh_preflight {} {
    set v [version -short]
    sh_result vivado_version $v
    if {![string match "2020.2*" $v]} {
        sh_issue "Scripts were written for Vivado 2020.2 but this is $v."
    }
    sh_result host_os "$::tcl_platform(os) $::tcl_platform(osVersion) ($::tcl_platform(platform))"
    sh_check_paths

    if {[llength [get_parts -quiet $::SH_PART]] == 0} {
        error "Part $::SH_PART is not installed. Re-run the Vivado installer and add the Zynq-7000 device family."
    }
    sh_result part $::SH_PART

    # Optional repo-local board files: boards/<anything>/<board files>.
    set local_boards [file join $::SH_REPO boards]
    if {[llength [glob -nocomplain -types d -directory $local_boards *]]} {
        set_param board.repoPaths [list $local_boards]
        sh_result board_repo $local_boards
    }
    set bps [lsort -dictionary [get_board_parts -quiet $::SH_BOARD_PATTERN]]
    if {[llength $bps]} {
        set ::SH_BOARD_PART [lindex $bps end]
        sh_result board_part $::SH_BOARD_PART
    } else {
        set ::SH_BOARD_PART ""
        sh_result board_part "NOT INSTALLED -> part-only PS7 config (works for PYNQ, see docs/BUILD_PLAN.md)"
    }
}

# Latest installed version of a Xilinx catalog IP, e.g. [sh_vlnv axi_gpio].
proc sh_vlnv {name} {
    set defs [lsort -dictionary [get_ipdefs -all "xilinx.com:ip:${name}:*"]]
    if {![llength $defs]} { error "IP xilinx.com:ip:${name} not found in the IP catalog" }
    return [lindex $defs end]
}

proc sh_find_files {dir pattern} {
    set out [glob -nocomplain -types f -directory $dir $pattern]
    foreach sub [glob -nocomplain -types d -directory $dir *] {
        lappend out {*}[sh_find_files $sub $pattern]
    }
    return $out
}

# Standard post-route reports. Timing failure is recorded, not fatal: a
# bitstream with a known violation is still useful evidence.
proc sh_impl_reports {prefix} {
    report_utilization              -file [sh_rpt ${prefix}_utilization.rpt]
    report_utilization -hierarchical -file [sh_rpt ${prefix}_utilization_hier.rpt]
    report_timing_summary -max_paths 10 -report_unconstrained \
                                    -file [sh_rpt ${prefix}_timing_summary.rpt]
    report_drc                      -file [sh_rpt ${prefix}_drc.rpt]
    set wns [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]]
    set whs [get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -hold]]
    sh_result "${prefix}_wns_ns" $wns
    sh_result "${prefix}_whs_ns" $whs
    if {($wns ne "" && $wns < 0) || ($whs ne "" && $whs < 0)} {
        sh_issue "$prefix: timing not met (WNS=$wns ns, WHS=$whs ns)"
    }
}

# write_bitstream wrapper: full bitstream without the side-effect partials.
proc sh_write_full_bit {path} {
    if {[catch {write_bitstream -force -no_partial_bitfile $path} err]} {
        puts "INFO: \[selfheal\] -no_partial_bitfile rejected ($err); retrying without it"
        write_bitstream -force $path
    }
}

proc sh_git_rev {} {
    if {[catch {exec git -C $::SH_REPO rev-parse --short HEAD} rev]} { return unknown }
    return $rev
}

# Copy a file into the committed bitstream folder and log it in the manifest.
proc sh_publish {src dst_name} {
    set dst [file join $::SH_BITDIR $dst_name]
    file copy -force $src $dst
    set fh [open [file join $::SH_BITDIR manifest.txt] a]
    puts $fh [format "%-28s %10d bytes" $dst_name [file size $dst]]
    close $fh
    return $dst
}

proc sh_manifest_header {} {
    set fh [open [file join $::SH_BITDIR manifest.txt] w]
    puts $fh "# target $::SH_TAG  built [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
    puts $fh "# vivado [version -short]  git [sh_git_rev]"
    puts $fh "# Partials are ONLY valid on the full bitstream from this same build."
    close $fh
}
