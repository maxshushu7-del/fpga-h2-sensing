set ROOT [file normalize [file join [file dirname [info script]] ..]]
set P [file join $ROOT results udp_tx_sim]
file mkdir [file dirname $P]
create_project -force udp_tx_sim $P -part xcau15p-ffvb676-2-i
add_files -fileset sim_1 -norecurse [file join $ROOT rtl network udp_ipv4_frame_tx.v]
add_files -fileset sim_1 -norecurse [file join $ROOT sim tb_udp_ipv4_frame_tx.sv]
set_property FILE_TYPE SystemVerilog [get_files [file join $ROOT sim tb_udp_ipv4_frame_tx.sv]]
set_property top tb_udp_ipv4_frame_tx [get_filesets sim_1]
update_compile_order -fileset sim_1
launch_simulation -simset sim_1 -mode behavioral
run 2 us
close_sim
close_project
puts "UDP_SIM_DONE: read transcript for UDP_FRAME_TEST_PASS"
