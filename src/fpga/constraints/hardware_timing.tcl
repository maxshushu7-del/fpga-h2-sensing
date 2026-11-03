# Implementation-only, LATE Tcl constraint file. External numbers are a
# PROVISIONAL engineering envelope, not measured board/signoff evidence.
# ADC 0x16=00/0x17=85 nominal lead1.0..1.6ns; board skew +/-0.10ns,
# margin0.05ns. DAC 0x16=00 setup=-.05ns, hold=.65ns, same skew/margin.
set work_pin [get_pins -hier -filter {NAME =~ *u_core/u_clock/u_mmcm/CLKOUT0}]
set work_clk [get_clocks -of_objects $work_pin]
set dci_source [get_pins -hier -filter {NAME =~ *u_tx/u_clock_mmcm/CLKOUT1}]
create_generated_clock -name dac_dci_forwarded -source $dci_source -divide_by 1 [get_ports dac_dci_p]
create_generated_clock -name spi_forwarded -source $work_pin -divide_by 100 [get_ports spi_clk]
set adc_ports [get_ports {adc_data_p[*] adc_data_n[*]}]
set dac_ports [get_ports {dac_data_p[*] dac_data_n[*] dac_frame_p dac_frame_n}]
# Reference ADC transition to the PREVIOUS opposite DCO edge (2ns UI).
set_input_delay -clock adc_dco -min 0.250 $adc_ports
set_input_delay -clock adc_dco -max 1.150 $adc_ports
set_input_delay -clock adc_dco -clock_fall -add_delay -min 0.250 $adc_ports
set_input_delay -clock adc_dco -clock_fall -add_delay -max 1.150 $adc_ports
# Default DDR STA compares opposite edges. Add the 2ns UI to both external
# requirements to model capture of the newly launched word at the next DCI
# edge delayed by the configured MMCM phase, without granting an extra half-cycle to setup.
set_output_delay -clock dac_dci_forwarded -max 2.100 $dac_ports
set_output_delay -clock dac_dci_forwarded -min 1.200 $dac_ports
set_output_delay -clock dac_dci_forwarded -clock_fall -add_delay -max 2.100 $dac_ports
set_output_delay -clock dac_dci_forwarded -clock_fall -add_delay -min 1.200 $dac_ports
set_output_delay -clock spi_forwarded -max 5.000 [get_ports {spi_sdio clk_cs_n adc_cs_n dac_cs_n}]
set_output_delay -clock spi_forwarded -min -5.000 [get_ports {spi_sdio clk_cs_n adc_cs_n dac_cs_n}]
# Mode0 sequencer changes SDIO at SCLK falling edges; CS setup/hold are also
# >=50 work clocks. Unit wire-edge test proves this enable schedule.
# Setup shifts launch back49 work edges; hold requires at least the next
# work edge (actual next permitted transition is 50 clocks after capture).
set_multicycle_path 50 -setup -start -from $work_clk -to [get_clocks spi_forwarded]
set_multicycle_path 50 -hold -start -from $work_clk -to [get_clocks spi_forwarded]
set_output_delay -clock $work_clk -max 2.000 [get_ports {led_ready led_servo}]
set_output_delay -clock $work_clk -min 0.000 [get_ports {led_ready led_servo}]
# Preserve the timing of downstream synchronization stages and datapaths.
# Never use asynchronous clock_groups: they would hide bounded mailbox paths.
set sync_inputs [get_pins -hier -regexp {.*(u_rx/(req_sync1|ack_sync1|config_sync1|source_ready_sync1|overflow_sync1)_reg/D|u_tx/(request_sync|epoch_sync|acknowledge_sync|enable_sync|configured_sync)_reg\[0\]/D|u_health/(adc_sync|tx_sync)_reg\[0\]/D|(tx_lock_sync|tx_active_sync)_reg\[0\]/D)$}]
if {[llength $sync_inputs]==0} { error "Hardware CDC synchronizers were not found" }
set_false_path -to $sync_inputs
set rx_from [get_cells -hier -filter {NAME =~ *u_rx/mailbox_data_reg* && IS_SEQUENTIAL == 1}]
set rx_to [get_cells -hier -filter {NAME =~ *u_rx/adc_data_out_reg* && IS_SEQUENTIAL == 1}]
set_max_delay -datapath_only 20.000 -from $rx_from -to $rx_to
set_bus_skew 10.000 -from $rx_from -to $rx_to
set tx_from [get_cells -hier -filter {(NAME =~ *u_tx/mailbox_code_reg* || NAME =~ *u_tx/mailbox_epoch_reg*) && IS_SEQUENTIAL == 1}]
set tx_to [get_cells -hier -filter {NAME =~ *u_tx/held_code_reg* && IS_SEQUENTIAL == 1}]
set_max_delay -datapath_only 4.000 -from $tx_from -to $tx_to
# V5.3: No set_bus_skew on this particular TX mailbox path.
# Vivado TIMING-39 reports this path has too many LUT levels for bus-skew
# validation.  Retain the 4ns bounded per-bit max delay above; the TX request
# crosses a 3-stage toggle synchronizer and a further 2-cycle capture_wait,
# while mailbox_code/epoch are held through the return acknowledgment.
# The 2ns set_bus_skew here was invalid and could not be treated as sign-off.
set gray_from [get_cells -hier -filter {NAME =~ *u_rx/dropped_gray_source_reg* && IS_SEQUENTIAL == 1}]
set gray_to [get_cells -hier -filter {NAME =~ *u_rx/drop_gray_sync1_reg* && IS_SEQUENTIAL == 1}]
set_max_delay -datapath_only 4.000 -from $gray_from -to $gray_to
set_bus_skew 4.000 -from $gray_from -to $gray_to
# ============================================================================
# V5.2: IQ snapshot cross-clock handshake constraints (no FFT/servo RTL edits).
# From timing report 2026-10-26: tune_latched_reg[5] (100 MHz work) ->
# tune_adc_reg[5] (250 MHz ADC DCO), WNS=-0.497ns.  This is a HELD DATA BUS:
# source data/toggle are latched together; request_toggle synchronizes via 2 FFs;
# ADC copies the held bus when the delayed toggle arrives.  The bundled data
# is not a free-running synchronous path.  Constrain physical latency/skew,
# never blanket-false-path work vs ADC clocks.
# ============================================================================
set snap_req_first [get_pins -hier -regexp {.*u_measurement/u_snapshot/(request_sync|abort_sync|completed_sync)_reg\[0\]/D$}]
if {[llength $snap_req_first] != 3} {
    error "V5.2 CDC: expected 3 first-stage iq_snapshot toggle sync pins; found [llength $snap_req_first]. Check the synthesized netlist before continuing."
}
# Only first metastability receiver flip-flop D pins may ignore STA.
# Their SECOND-stage sync paths remain timed by Vivado.
set_false_path -to $snap_req_first

set snap_tune_src [get_cells -hier -filter {NAME =~ *u_measurement/u_snapshot/tune_latched_reg* && IS_SEQUENTIAL == 1}]
set snap_tune_dst [get_cells -hier -filter {NAME =~ *u_measurement/u_snapshot/tune_adc_reg* && IS_SEQUENTIAL == 1}]
if {[llength $snap_tune_src] < 2 || [llength $snap_tune_dst] < 2} {
    error "V5.2 CDC: IQ snapshot tuning word registers not found. No constraints applied."
}
# 4 ns <= one ADC clock cycle; request control traverses two synchronizer FFs.
set_max_delay -datapath_only 4.000 -from $snap_tune_src -to $snap_tune_dst
set_bus_skew 2.000 -from $snap_tune_src -to $snap_tune_dst

# The one-bit fine/low-path selector is transferred with the tuning word.
set snap_mode_src [get_cells -hier -filter {NAME =~ *u_measurement/u_snapshot/fine_latched_reg* && IS_SEQUENTIAL == 1}]
set snap_mode_dst [get_cells -hier -filter {NAME =~ *u_measurement/u_snapshot/fine_adc_reg* && IS_SEQUENTIAL == 1}]
if {[llength $snap_mode_src] != 1 || [llength $snap_mode_dst] != 1} {
    error "V5.2 CDC: IQ snapshot fine mode data flops not found."
}
set_max_delay -datapath_only 4.000 -from $snap_mode_src -to $snap_mode_dst

# Result metadata is held in the ADC domain BEFORE completed_toggle changes.
# completed_sync[] crosses into work domain, then the work domain samples the
# held accumulators/counters.  Limit payload propagation to 12 ns (< two work
# cycles) and skew of each independent multibit result bus to 4 ns.
foreach {src_name dst_name} {
    sum_i          mean_i
    sum_q          mean_q
    adc_clip_count clipped_samples
    bad_adc        capture_bad
} {
    set snapshot_src [get_cells -hier -filter "NAME =~ *u_measurement/u_snapshot/${src_name}_reg* && IS_SEQUENTIAL == 1"]
    set snapshot_dst [get_cells -hier -filter "NAME =~ *u_measurement/u_snapshot/${dst_name}_reg* && IS_SEQUENTIAL == 1"]
    if {[llength $snapshot_src] == 0 || [llength $snapshot_dst] == 0} {
        error "V5.2 CDC: missing result-payload flops: $src_name -> $dst_name."
    }
    set_max_delay -datapath_only 12.000 -from $snapshot_src -to $snapshot_dst
    if {[llength $snapshot_src] > 1 && [llength $snapshot_dst] > 1} {
        set_bus_skew 4.000 -from $snapshot_src -to $snapshot_dst
    }
}
puts "V5.2 IQ SNAPSHOT CDC: request first-stage false paths; tuning/mode bounded to 4ns; result payload bounded to 12ns, bus skew constrained."
# ============================================================================

# MMCM LOCKED is an asynchronous reset condition, not a sampled data clock.
set lock_sources [get_pins -hier -filter {REF_PIN_NAME == LOCKED}]
set reset_targets [get_pins -hier -filter {REF_PIN_NAME == CLR || REF_PIN_NAME == PRE || REF_PIN_NAME == RST}]
set_false_path -through $lock_sources -to $reset_targets
puts "HARDWARE EXTERNAL TIMING: PROVISIONAL (nominal DCO delay and unmeasured +/-100ps board-skew envelope)."


