# FULLY STANDALONE Vivado 2024.1 project creator: zero dependency on old XPR/DCP.
set ROOT [file normalize [file join [file dirname [info script]] ..]]
set PROJECT_NAME contest_all
set PROJ_DIR [file join $ROOT project]
set XPR [file join $PROJ_DIR ${PROJECT_NAME}.xpr]
if {[regexp {[^ -~]} $ROOT]} {error "Use an ASCII-only extraction path such as E:/FPGA/V4. Current: $ROOT"}
if {![string match "2024.1*" [version -short]]} {
    puts "WARNING: The included XCI files were saved in Vivado 2024.1; currently running [version -short]"
}
# V4 inherits proven V3 875ps DAC phase; recheck STA after recompiling.
set top_source [file join $ROOT rtl servo laser_lock_hw_top.v]
set fh [open $top_source r]; set top_text [read $fh]; close $fh
if {![string match {*DCI_DELAY_PS(875.0)*} $top_text]} {
    error "V4 incorrect DAC phase. Expected legal MMCM 875ps (78.75deg)."
}
if {[file exists $XPR]} {
    puts "FULL_PROJECT_ALREADY_EXISTS: $XPR"
    return
}
file mkdir $PROJ_DIR
create_project $PROJECT_NAME $PROJ_DIR -part xcau15p-ffvb676-2-i
set_property target_language Verilog [current_project]
set_property simulator_language Mixed [current_project]
set_property target_simulator XSim [current_project]

set rtl_count 0
foreach folder {platform servo measurement network temperature} {
    foreach extension {v sv} {
        foreach src [lsort [glob -nocomplain [file join $ROOT rtl $folder *.$extension]]] {
            add_files -fileset sources_1 -norecurse $src
            if {$extension eq "sv"} {set_property FILE_TYPE SystemVerilog [get_files $src]}
            incr rtl_count
        }
    }
}
if {$rtl_count < 30} {error "Too few RTL files found ($rtl_count). Check extraction."}
foreach source [lsort [glob -nocomplain [file join $ROOT coefficients *.mem]]] {
    add_files -fileset sources_1 -norecurse $source
}
foreach extension {v sv} {
    foreach source [lsort [glob -nocomplain [file join $ROOT sim *.$extension]]] {
        add_files -fileset sim_1 -norecurse $source
        if {$extension eq "sv"} {set_property FILE_TYPE SystemVerilog [get_files $source]}
    }
}

foreach filename {axau15_fl4322_pins.xdc axau15_eth_udp_tx.xdc hardware_timing.tcl udp_cdc_timing.tcl} {
    set xdc_file [file join $ROOT constraints $filename]
    if {![file exists $xdc_file]} {error "Missing constraint: $xdc_file"}
    add_files -fileset constrs_1 -norecurse $xdc_file
}
# Keep original V5.5 late CDC/IO constraints without changing or waiving DRC.
set timing_file [get_files [file join $ROOT constraints hardware_timing.tcl]]
set_property FILE_TYPE Tcl $timing_file
set_property USED_IN_SYNTHESIS false $timing_file
set_property USED_IN_IMPLEMENTATION true $timing_file
set_property PROCESSING_ORDER LATE $timing_file

# UDP CDC constraints are implementation-only and must run after hardware_timing.tcl.
set udp_timing_file [get_files [file join $ROOT constraints udp_cdc_timing.tcl]]
set_property FILE_TYPE Tcl $udp_timing_file
set_property USED_IN_SYNTHESIS false $udp_timing_file
set_property USED_IN_IMPLEMENTATION true $udp_timing_file
set_property PROCESSING_ORDER LATE $udp_timing_file

# Import self-contained, version-matched IP configurations (original Vivado 2024.1 XCI).
# Their generated output directory is relative to project/contest_all.srcs/sources_1/ip.
foreach ip {laser_lock_ila laser_lock_hw_vio fft_core} {
    set xci_dir [file join $PROJ_DIR ${PROJECT_NAME}.srcs sources_1 ip $ip]
    file mkdir $xci_dir
    set xci_dest [file join $xci_dir ${ip}.xci]
    file copy -force [file join $ROOT ip_templates $ip ${ip}.xci] $xci_dest
    add_files -fileset sources_1 -norecurse $xci_dest
    if {[llength [get_ips -quiet $ip]] != 1} {error "IP failed to load: $ip"}
}
# Let Vivado generate current OOC synth targets; no imported stale DCPs exist.
foreach ip {laser_lock_ila laser_lock_hw_vio fft_core} {
    puts "GENERATING_IP: $ip"
    generate_target all [get_ips $ip]
}
# V4 exclusive board top. Enforce no physical UART while preserving V3 RGMII.
set_property top laser_lock_hw_udp_only_top [get_filesets sources_1]
set v4_top_file [file join $ROOT rtl servo laser_lock_hw_udp_only_top.v]
set v4_top_fh [open $v4_top_file r]; set v4_top_text [read $v4_top_fh]; close $v4_top_fh
if {[string first "uart_tx" $v4_top_text] != -1 && [regexp {output\s+wire\s+uart_tx} $v4_top_text]} {
    error "V4 top still declares UART; aborting project creation."
}

set_property generic {ENABLE_ILA=1 ENABLE_VIO=1} [get_filesets sources_1]
set_property top tb_udp_ipv4_frame_tx [get_filesets sim_1]
set_property xsim.simulate.runtime all [get_filesets sim_1]
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1
# create_project and close_project persist this project; no parameterless save_project.
puts "ALL_IN_ONE_PROJECT_CREATED: $XPR"
puts "INCLUDES: Servo + 4096-point FFT + V6 FPGA PID + virtual TEC200 + RGMII/UDP transmitter"
puts "HARDWARE TELEMETRY=UDP ONLY (NO UART PORT / NO UART PIN / NO UART TX RTL)"
puts "V4 DAC DCI CLOCK: 875ps = 78.75 degrees / 11.25-degree step = 7 (legal)"
puts "PRESERVED_IP: laser_lock_ila laser_lock_hw_vio fft_core"
close_project
