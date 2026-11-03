# V4 standalone project + routed STA (true phase adjustment, no relaxed constraints).
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set XPR [file join $ROOT project contest_all.xpr]
if {![file exists $XPR]} {
    puts "PHASE_1: Creating full, independent project from bundled sources and XCI"
    source [file join $ROOT scripts create_project.tcl]
}
if {![file exists $XPR]} {error "Project creation did not produce $XPR"}
open_project $XPR
set_property top laser_lock_hw_udp_only_top [get_filesets sources_1]
update_compile_order -fileset sources_1
# Never attach an incremental checkpoint. Old Vivado synth DCPs are intentionally absent.
if {[get_property STATUS [get_runs synth_1]] ne "Not started"} {
    puts "Resetting old synthesis/implementation runs for a full rebuild"
    reset_run synth_1
}
puts "PHASE_2: Starting full synthesis"
launch_runs synth_1 -jobs 2
wait_on_run synth_1
set synth_status [get_property STATUS [get_runs synth_1]]
puts "SYNTH_STATUS=$synth_status"
if {$synth_status ne "synth_design Complete!"} {
    error "Synthesis failed. See project/contest_all.runs/synth_1/runme.log"
}
# Enforce UDP-only PHYSICAL ports and confirm RTL hierarchy contains UDP/PHY.
open_run synth_1
set portnames [get_ports -quiet *]
set bad_uart [lsearch -all -inline -regexp -nocase $portnames {uart|serial}]
if {[llength $bad_uart] > 0} {error "UDP-only FAIL: UART top ports present: $bad_uart"}
foreach outpin {phy_reset_n phy_tx_clk phy_tx_ctl phy_txd[0] phy_txd[1] phy_txd[2] phy_txd[3]} {
    if {[lsearch -exact $portnames $outpin] == -1} {error "UDP-only FAIL: missing RGMII pin $outpin"}
}
puts "UDP_ONLY_PORT_CHECK=PASS: 7 physical RGMII signals present; no UART port"
close_design
puts "PHASE_3: Place, route and generate bitstream"
launch_runs impl_1 -to_step write_bitstream -jobs 2
wait_on_run impl_1
set impl_status [get_property STATUS [get_runs impl_1]]
puts "IMPL_STATUS=$impl_status"
set bitfiles [glob -nocomplain [file join $ROOT project contest_all.runs impl_1 *.bit]]
if {[llength $bitfiles] < 1} {
    error "No bitstream. Check project/contest_all.runs/impl_1/runme.log and DRC/errors"
}
puts "BITSTREAM_FILE=[lindex $bitfiles 0]"
file mkdir [file join $ROOT results]
open_run impl_1
report_timing_summary -delay_type min_max -file [file join $ROOT results final_timing_summary.txt]
report_utilization -file [file join $ROOT results final_utilization.txt]
# Never confuse a .bit file with passing setup/hold. This is a routed report,
# and unmeasured RGMII PHY/board I/O constraints still require signoff.
set sta_report [file join $ROOT results final_timing_summary.txt]
set sta_handle [open $sta_report r]
set sta_text [read $sta_handle]
close $sta_handle
set status_file [file join $ROOT results V4_TIMING_STATUS.txt]
set status_handle [open $status_file w]
if {[regexp -line {^\s*([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+(\d+)\s+\d+\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)\s+(\d+)\s+\d+\s+([-+]?\d+\.\d+)\s+([-+]?\d+\.\d+)} $sta_text -> wns tns nsetup whs ths nhold wpws tpws]} {
    set pass [expr {double($wns)>=0.0 && double($tns)>=0.0 && int($nsetup)==0 && double($whs)>=0.0 && double($ths)>=0.0 && int($nhold)==0 && double($wpws)>=0.0 && double($tpws)>=0.0}]
    set verdict [expr {$pass ? "PASS" : "FAIL"}]
    puts "V4_ROUTE_STA=$verdict WNS=$wns TNS=$tns SETUP_ENDPOINTS=$nsetup WHS=$whs THS=$ths HOLD_ENDPOINTS=$nhold"
    puts $status_handle "CONSTRAINED_SETUP_HOLD_STA=$verdict"
    puts $status_handle "WNS=$wns TNS=$tns FAIL_SETUP=$nsetup WHS=$whs THS=$ths FAIL_HOLD=$nhold WPWS=$wpws TPWS=$tpws"
} else {
    puts "V4_ROUTE_STA=UNPARSED: read $sta_report manually"
    puts $status_handle "CONSTRAINED_SETUP_HOLD_STA=UNPARSED"
}
puts $status_handle "PHYSICAL_IO_SIGNOFF=NOT_DONE; RGMII PHY/PCB skew and output delays unverified."
puts $status_handle "NOTE=No endpoint false paths or DAC output-delay constraints weakened to pass STA."
close $status_handle
puts "V4_STATUS_FILE=$status_file"

puts "TIMING_REPORT=[file join $ROOT results final_timing_summary.txt]"
puts "NOTE: Consult results/V4_TIMING_STATUS.txt; UDP-only physical pins; BIT success != STA and PHY link success."
puts "NOTE: TEC200 uses a VIRTUAL temperature plant. External heater power is NEVER driven."
close_project
puts "ALL_IN_ONE_BUILD_FINISHED"
