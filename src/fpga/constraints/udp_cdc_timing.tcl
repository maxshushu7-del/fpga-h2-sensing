# UDP V2: 100MHz work <-> 125MHz Ethernet CDC with handshake.
# CLOCKS are independent (200MHz sys_ref vs 250MHz dac_ref), so a 2ns
# synchronous setup relation is invalid for these particular handshakes.
# Do NOT globally false-path these clock groups: preserve timing on all
# non-CDC endpoints, as in V5.5's hardware_timing.tcl.
# 3-stage toggle synchronizers: only the FIRST stage is asynchronous.
set udp_req_first [get_pins -hier -regexp {.*u_udp/req_sync_reg\[0\]/D$}]
set udp_ack_first [get_pins -hier -regexp {.*u_udp/ack_sync_reg\[0\]/D$}]
if {[llength $udp_req_first] != 1 || [llength $udp_ack_first] != 1} {
    error "UDP CDC: request/ack FIRST synchronization stage missing; no exception applied."
}
set_false_path -to $udp_req_first
set_false_path -to $udp_ack_first
# Bundled-data handshake:
# clk_work holds snapshot until an acknowledgment returns through 3 FFs;
# clk_eth sees req only after 3 FFs, then captures the same unmodified bus.
# Constrain the propagation of this bus to <=12ns (1.5 eth cycles) with
# max 8ns inter-bit skew, rather than pretending it is a synchronous 2ns path.
set udp_src [get_cells -hier -filter {NAME =~ *u_udp/snapshot_reg* && IS_SEQUENTIAL == 1}]
set udp_dst [get_cells -hier -filter {NAME =~ *u_udp/eth_payload_reg* && IS_SEQUENTIAL == 1}]
if {[llength $udp_src] < 8 || [llength $udp_dst] < 8} {
    error "UDP CDC: expected the held snapshot/eth_payload flops; src=[llength $udp_src], dst=[llength $udp_dst]."
}
set_max_delay -datapath_only 12.000 -from $udp_src -to $udp_dst
set_bus_skew 8.000 -from $udp_src -to $udp_dst
puts "UDP CDC V2: two first-stage toggle FFs excluded, 320-bit held payload <=12ns, max bus skew 8ns."
