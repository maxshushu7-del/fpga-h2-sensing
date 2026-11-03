`timescale 1ns/1ps
// TEC200 PID replacement -- LOGICAL SIGNAL BOUNDARY, NOT a physical TEC200 pinout.
// Inputs temperature_mc_in/sample_valid_in/sensor_fault_in MUST already be
// synchronous to laser_lock_hw_top.clk_work (100 MHz) and coherent as a bus.
// DO NOT connect 32 data bits directly to analog measurement lines.
// The downstream driver must explicitly accept active-high PWM; otherwise
// replace the output conversion stage after checking the actual circuit.
// External hardware over-temperature/current limit and output disconnection
// are mandatory and NOT replaced by this FPGA logic.
module tec200_pid_io_guard(
    input  wire signed [31:0] temperature_mc_in,
    input  wire               sample_valid_in,
    input  wire               sensor_fault_in,
    input  wire               temperature_link_ready,
    input  wire               power_stage_ready,
    input  wire               external_interlock_ok,
    input  wire               pid_pwm_in,
    input  wire               pid_fault_in,
    output wire signed [31:0] temperature_mc_to_pid,
    output wire               sample_valid_to_pid,
    output wire               sensor_fault_to_pid,
    output wire               power_stage_pwm_out,
    output wire               boundary_fault
);
    wire interface_safe = temperature_link_ready && power_stage_ready &&
                          external_interlock_ok;
    assign temperature_mc_to_pid = temperature_mc_in;
    assign sample_valid_to_pid   = interface_safe && sample_valid_in &&
                                   !sensor_fault_in;
    // Fail-closed: a missing sensor path / driver / interlock sets the V6
    // sensor_fault input; the V6 PID latches fault on the working clock.
    assign sensor_fault_to_pid  = !interface_safe || sensor_fault_in;
    // Additional combinational cut-off, independent of PID clock-edge latency.
    assign power_stage_pwm_out = interface_safe && !sensor_fault_in &&
                                 !pid_fault_in && pid_pwm_in;
    assign boundary_fault      = sensor_fault_to_pid || pid_fault_in;
endmodule
