# Internal-path OOC implementation only. No real board I/O timing model or bitfile.
set trial_root [lindex $argv 0]
set report_root [lindex $argv 1]
create_project -in_memory -part xcau15p-ffvb676-2-i
read_verilog -sv [file join $trial_root rtl fir4.sv]
synth_design -top fir4 -mode out_of_context -part xcau15p-ffvb676-2-i
create_clock -name trial_clk -period 10.000 [get_ports clk]
opt_design
place_design
route_design
report_utilization -file [file join $report_root utilization.rpt]
report_timing_summary -delay_type min_max -report_unconstrained -file [file join $report_root timing_summary.rpt]
check_timing -verbose -file [file join $report_root check_timing.rpt]
report_drc -file [file join $report_root drc.rpt]
write_checkpoint [file join $report_root fir_ooc.dcp]
set status_fd [open [file join $report_root implementation_complete.txt] w]
puts $status_fd "STATUS=OOC_IMPLEMENTATION_COMPLETE"
puts $status_fd "SCOPE=INTERNAL_REGISTER_PATHS_ONLY_EXTERNAL_PORT_TIMING_UNCONSTRAINED"
puts $status_fd "BOARD_VALIDATED=0"
close $status_fd
close_project
