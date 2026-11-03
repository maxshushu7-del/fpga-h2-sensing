`timescale 1ns/1ps
// Shared AXAU15/FL4322 front end: laser servo + beat measurement + TEC core.
// All physical actuator permissions reset OFF. TEC ports below are calibrated
// digital interfaces only: no temperature sensor/TEC power adapter is inferred.
module top_sensor_integrated #(
    parameter ENABLE_ILA=1, ENABLE_VIO=1,
    parameter integer BEAT_CHANNEL=1, SERVO_CHANNEL=0, CHANNEL_SWAP=0,
    parameter integer SIM_IDLE_FFT_PAUSE=0, FRAME_GAP_CYCLES=200000,
    parameter integer INIT_HALF_PERIOD=50, INIT_STARTUP_CYCLES=1000000, INIT_PLL_SETTLE_CYCLES=2000000,
    parameter integer AUTO_SPAN=1024, AUTO_SETTLE_CLOCKS=200000, DAC_SLEW_PERIOD=1000,
    parameter integer TEC_SAMPLE_PERIOD_CYCLES=1000000,
    parameter real DAC_DCI_DELAY_PS=875.0
) (
    input wire sys_clk_p,input wire sys_clk_n,input wire key_reset_n,
    input wire adc_dco_p,input wire adc_dco_n,
    input wire [13:0] adc_data_p,input wire [13:0] adc_data_n,
    input wire fpga_clk_p,input wire fpga_clk_n,
    output wire [15:0] dac_data_p,output wire [15:0] dac_data_n,
    output wire dac_dci_p,output wire dac_dci_n,output wire dac_frame_p,output wire dac_frame_n,
    output wire spi_clk,output wire spi_sdio,output wire clk_cs_n,output wire adc_cs_n,output wire dac_cs_n,
    output wire led_ready,output wire led_servo,output wire uart_tx
);
    wire clk_work,core_locked;
    wire hw_reset_n=key_reset_n && core_locked;
    (* ASYNC_REG="TRUE" *) reg [2:0] hw_reset_pipe;
    always @(posedge clk_work or negedge hw_reset_n)begin
        if(!hw_reset_n)hw_reset_pipe<=3'b111;
        else hw_reset_pipe<={hw_reset_pipe[1:0],1'b0};
    end
    wire hw_rst=hw_reset_pipe[2];
    wire signed [13:0] adc_sample;
    wire adc_valid,adc_ready;
    wire signed [15:0] dac_command;
    wire dac_valid;
    wire [31:0] cfg_rdata, core_cfg_rdata;
    wire cfg_ready,cfg_ack,cfg_error;
    wire [7:0] status;
    wire signed [31:0] debug_error,debug_output;
    wire signed [47:0] debug_integral;
    wire request_toggle;
    wire [7:0] request_addr;
    wire [31:0] request_data;
    // bit0 init, bit1 laser ARM, bit2 measurement enable, bit3 TEC enable,
    // bit4 TEC fault clear, bit5 temperature sample toggle, bit6 sensor fault.
    // VIO temperature inputs are a debug injection port, NOT a sensor reading.
    wire [7:0] hw_control;
    wire signed [31:0] temperature_mc,setpoint_mc;
    reg request_seen=0,cfg_pending=0,last_cfg_ack=0,last_cfg_error=0;
    reg [7:0] cfg_addr_latched=0;
    reg [31:0] cfg_data_latched=0;
    always @(posedge clk_work)begin
        if(hw_rst)begin request_seen<=request_toggle;cfg_pending<=0;cfg_addr_latched<=0;cfg_data_latched<=0;last_cfg_ack<=0;last_cfg_error<=0;end
        else begin
            if(cfg_ack)begin last_cfg_ack<=1;last_cfg_error<=cfg_error;end
            if(cfg_pending)begin if(cfg_ready)cfg_pending<=0;end
            else if(request_toggle!=request_seen)begin
                request_seen<=request_toggle;cfg_pending<=1;last_cfg_ack<=0;last_cfg_error<=0;
                cfg_addr_latched<=request_addr;cfg_data_latched<=request_data;
            end
        end
    end
    wire sequence_done;
    wire [7:0] writes_sent;
    wire adc_clk,tx_clk,rx_ready,rx_clock_locked,overflow_sticky,tx_locked,tx_active,control_ready,clocks_ok;
    wire [13:0] raw_a,raw_b;
    wire [31:0] dropped_count;
    (* ASYNC_REG="TRUE" *) reg [1:0] tx_lock_sync,tx_active_sync;
    // The autonomous state machine is held inactive until the physical-output
    // permission is explicitly granted. VIO 'hw_control=3' once; no live
    // manual peak search or parameter writes are needed.
    wire [3:0] auto_state,auto_reason;
    wire auto_locked,auto_ever_locked,auto_reverse,auto_pi_enable,auto_clear;
    wire auto_adc_enable,auto_dac_valid;
    wire dac_slew_valid,dac_at_goal;
    wire signed [15:0] dac_slew_code;
    wire [7:0] auto_attempts;
    wire signed [15:0] auto_dac_code,auto_setpoint;
    wire signed [15:0] scan_min,scan_max,scan_min_code,scan_best_code;
    wire [31:0] reacquire_count,samples_seen;
    wire arm_auto=hw_control[0] && hw_control[1] && sequence_done &&
                  rx_ready && tx_lock_sync[1] && clocks_ok && !hw_rst && !cfg_pending;
    auto_lock_fsm #(.SPAN(AUTO_SPAN),.SETTLE_CLOCKS(AUTO_SETTLE_CLOCKS)) u_autolock(.clk(clk_work),.rst(hw_rst),.arm(arm_auto),
        .adc_valid(adc_valid),.adc_sample(adc_sample),.dac_at_goal(dac_at_goal),
        .servo_valid(dac_valid),.servo_delta(dac_command),
        .servo_error(debug_error[15:0]),.servo_clipped(status[3]),
        .dac_code(auto_dac_code),.dac_valid(auto_dac_valid),
        .adc_scan_enable(auto_adc_enable),.servo_enable(auto_pi_enable),
        .servo_setpoint(auto_setpoint),.reverse_error(auto_reverse),.servo_clear(auto_clear),
        .state(auto_state),.locked(auto_locked),.ever_locked(auto_ever_locked),
        .last_reason(auto_reason),.attempts(auto_attempts),
        .scan_min(scan_min),.scan_max(scan_max),.min_code(scan_min_code),
        .selected_code(scan_best_code),.reacquire_count(reacquire_count),
        .samples_seen(samples_seen));
    laser_dac_slew #(.SLEW_PERIOD(DAC_SLEW_PERIOD)) u_slew(
        .clk(clk_work),.rst(hw_rst),.enable(arm_auto),.goal_code(auto_dac_code),
        .output_code(dac_slew_code),.output_valid(dac_slew_valid),
        .goal_reached(dac_at_goal));
    laser_lock_top #(.ENABLE_ILA(0),.AUTONOMOUS(1)) u_core(
        .clk_200m_p(sys_clk_p),.clk_200m_n(sys_clk_n),.rst_n(key_reset_n),
        .adc_data_in(adc_sample),.adc_valid(adc_valid),.adc_ready(adc_ready),
        .auto_servo_enable(auto_pi_enable),.auto_setpoint(auto_setpoint),
        .auto_error_invert(auto_reverse),.auto_clear(auto_clear),
        .dac_data_out(dac_command),.dac_valid(dac_valid),
        .cfg_we(cfg_pending),.cfg_addr(cfg_pending ? cfg_addr_latched:request_addr),.cfg_wdata(cfg_data_latched),
        .cfg_rdata(core_cfg_rdata),.cfg_ready(cfg_ready),.cfg_ack(cfg_ack),.cfg_error(cfg_error),
        .clk_work_out(clk_work),.clock_locked(core_locked),.status(status),
        .ila_error(debug_error),.ila_control_output(debug_output),.ila_integral(debug_integral));
    // Only the physical wrapper selects global routing to the controller CMT.
    // The generic servo top and all its control modules keep their defaults.
    defparam u_core.u_clock.CLOCK_INPUT_BUFG=1;
    hw_fl4322_init #(.HALF_PERIOD(INIT_HALF_PERIOD),.STARTUP_CYCLES(INIT_STARTUP_CYCLES),
        .PLL_SETTLE_CYCLES(INIT_PLL_SETTLE_CYCLES)) u_init(.clk(clk_work),.rst(hw_rst),.init_enable(hw_control[0]),
        .spi_clk(spi_clk),.spi_sdio(spi_sdio),.clk_cs_n(clk_cs_n),.adc_cs_n(adc_cs_n),.dac_cs_n(dac_cs_n),
        .sequence_done(sequence_done),.writes_sent(writes_sent));
    hw_ad9643_rx #(.DECIMATION(256),.CHANNEL_SELECT(SERVO_CHANNEL),.CHANNEL_SWAP(CHANNEL_SWAP)) u_rx(.rst_n(hw_reset_n),.clk_work(clk_work),
        .config_done(sequence_done),.adc_dco_p(adc_dco_p),.adc_dco_n(adc_dco_n),
        .adc_data_p(adc_data_p),.adc_data_n(adc_data_n),.adc_ready(adc_ready || auto_adc_enable || !arm_auto),
        .adc_data_out(adc_sample),.adc_valid(adc_valid),.adc_clk_out(adc_clk),
        .raw_data_a(raw_a),.raw_data_b(raw_b),.rx_ready(rx_ready),.rx_clock_locked(rx_clock_locked),
        .overflow_sticky(overflow_sticky),.dropped_count(dropped_count));
    // If the core is disabled/configured, its DAC register clears to zero without
    // dac_valid. Gate the physical adapter with core enable so no old code persists.
    hw_ad9122_tx #(.INPUT_CLK_PERIOD_NS(4.0),.MMCM_MULT_F(4.0),.OUTPUT_DIVIDE(4),.DCI_DELAY_PS(DAC_DCI_DELAY_PS)) u_tx(.clk_work(clk_work),.rst_n(hw_reset_n),.fpga_clk_p(fpga_clk_p),.fpga_clk_n(fpga_clk_n),
        .control_in(dac_slew_code),.control_valid(dac_slew_valid),
        .tx_enable(arm_auto),
        .config_done(sequence_done),.control_ready(control_ready),.tx_clk_out(tx_clk),
        .tx_clock_locked(tx_locked),.tx_active(tx_active),
        .dac_data_p(dac_data_p),.dac_data_n(dac_data_n),.dac_dci_p(dac_dci_p),.dac_dci_n(dac_dci_n),
        .dac_frame_p(dac_frame_p),.dac_frame_n(dac_frame_n));
    wire [9:0] adc_beats,tx_beats;
    hw_clock_health u_health(.rst_n(hw_reset_n),.clk_work(clk_work),.adc_clk(adc_clk),.tx_clk(tx_clk),
        .enable(sequence_done),.clocks_ok(clocks_ok),.adc_beats(adc_beats),.tx_beats(tx_beats));
    // Status synchronizers release with the already qualified work-domain reset.
    always @(posedge clk_work)begin
        if(hw_rst)begin tx_lock_sync<=0;tx_active_sync<=0;end
        else begin tx_lock_sync<={tx_lock_sync[0],tx_locked};tx_active_sync<={tx_active_sync[0],tx_active};end
    end
    assign led_ready=sequence_done && rx_ready && tx_lock_sync[1] && clocks_ok;
    assign led_servo=auto_locked && tx_active_sync[1];
    wire [7:0] hw_status={overflow_sticky,control_ready,hw_rst,tx_active_sync[1],clocks_ok,
        tx_lock_sync[1],rx_ready,sequence_done};
    // Read-only automatic operation diagnostics through existing VIO address
    // input; leave request_toggle untouched for reads.
    wire [31:0] auto_status={auto_state,auto_locked,auto_ever_locked,
            auto_reason,2'b00,auto_attempts,reacquire_count[11:0]};
    assign cfg_rdata = (request_addr==8'h80) ? auto_status :
        (request_addr==8'h84) ? {{16{scan_best_code[15]}},scan_best_code} :
        (request_addr==8'h88) ? {{16{scan_min[15]}},scan_min} :
        (request_addr==8'h8c) ? {{16{scan_max[15]}},scan_max} :
        (request_addr==8'h90) ? {{16{auto_setpoint[15]}},auto_setpoint} :
        (request_addr==8'h94) ? {{16{dac_slew_code[15]}},dac_slew_code} :
        (request_addr==8'h98) ? {{16{scan_min_code[15]}},scan_min_code} :
        (request_addr==8'h9c) ? reacquire_count :
        (request_addr==8'ha0) ? samples_seen : core_cfg_rdata;
    // Reset both sides of the frozen FFT snapshot after ADC capture-clock loss.
    wire measure_adc_rst_n,measure_proc_rst_n;
    reset_sync u_measure_adc_reset(.clk(adc_clk),.async_ok(hw_reset_n && rx_clock_locked),.rst_n(measure_adc_rst_n));
    reset_sync u_measure_proc_reset(.clk(clk_work),.async_ok(hw_reset_n && rx_clock_locked),.rst_n(measure_proc_rst_n));
    wire measure_enable=hw_control[2] && sequence_done && rx_ready;
    wire capture_active,fft_valid,fft_last,result_strobe,measurement_valid,fine_mode,low_mode,protocol_error;
    wire result_fine_mode,result_low_mode,tracking_active;
    wire [31:0] frequency_hz,sequence_number,clipped_samples,dropped_results,fft_reacquire_count;
    wire [11:0] capture_address,fft_bin,peak_bin,coarse_bin;
    wire signed [28:0] fft_re,fft_im;
    wire signed [17:0] bin_offset_q16;
    wire signed [31:0] fine_offset_hz;
    wire [58:0] peak_power,noise_power;
    wire [7:0] result_flags;
    measurement_improved #(.ALGORITHM_VERSION(3),.ADC_CHANNEL(BEAT_CHANNEL),.FFT_LOG2(12),
        .WINDOW_ENABLE(1),.ADC_SAMPLE_RATE_HZ(250000000),.TRACKING_ENABLE(1),
        .TRACK_RECHECK_FRAMES(4),.FRAME_GAP_CYCLES(FRAME_GAP_CYCLES),
        .SIM_IDLE_FFT_PAUSE(SIM_IDLE_FFT_PAUSE)) u_measurement(
        .adc_clk(adc_clk),.adc_rst_n(measure_adc_rst_n),.channel_a($signed(raw_a)),.channel_b($signed(raw_b)),
        .proc_clk(clk_work),.proc_rst_n(measure_proc_rst_n),.enabled(measure_enable),
        .capture_active(capture_active),.capture_address(capture_address),
        .fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),.fft_valid(fft_valid),.fft_last(fft_last),
        .result_strobe(result_strobe),.measurement_valid(measurement_valid),.fine_mode(fine_mode),.low_mode(low_mode),
        .result_fine_mode(result_fine_mode),.result_low_mode(result_low_mode),.tracking_active(tracking_active),
        .reacquire_count(fft_reacquire_count),.frequency_hz(frequency_hz),.sequence_number(sequence_number),
        .peak_bin(peak_bin),.coarse_bin(coarse_bin),.bin_offset_q16(bin_offset_q16),.fine_offset_hz(fine_offset_hz),
        .peak_power(peak_power),.noise_power(noise_power),.result_flags(result_flags),
        .clipped_samples(clipped_samples),.protocol_error(protocol_error));
    // One physical transmitter: preserve Protocol3 and existing host software.
    // Servo/TEC status stays on ILA/VIO until a versioned telemetry protocol exists.
    result_uart_v2 #(.ALGORITHM_VERSION(3),.ADC_CHANNEL(BEAT_CHANNEL),.FFT_LOG2(12),
        .OUT_WIDTH(29),.WINDOW_ENABLE(1),.ADC_SAMPLE_RATE_HZ(250000000)) u_uart(
        .clk(clk_work),.rst_n(!hw_rst),.result_strobe(result_strobe),.measurement_valid(measurement_valid),
        .fine_mode(result_fine_mode),.low_mode(result_low_mode),.frequency_hz(frequency_hz),.sequence_number(sequence_number),
        .peak_bin(peak_bin),.coarse_bin(coarse_bin),.bin_offset_q16(bin_offset_q16),.fine_offset_hz(fine_offset_hz),
        .peak_power(peak_power),.noise_power(noise_power),.clipped_samples(clipped_samples),
        .result_flags(result_flags),.uart_tx(uart_tx),.dropped_results(dropped_results));

    reg temperature_toggle_seen;
    always @(posedge clk_work) begin
        if(hw_rst) temperature_toggle_seen<=hw_control[5];
        else temperature_toggle_seen<=hw_control[5];
    end
    wire temperature_sample_valid=!hw_rst && (temperature_toggle_seen!=hw_control[5]);
    wire signed [15:0] tec_command;
    wire tec_output_enable,tec_command_strobe,tec_fault,tec_saturated,tec_slew_limited;
    wire [7:0] tec_fault_flags;
    wire signed [31:0] tec_error_mc;
    wire signed [63:0] tec_i1_q16,tec_i2_q16;
    tec_pid_controller #(.SAMPLE_PERIOD_CYCLES(TEC_SAMPLE_PERIOD_CYCLES),
        .SAMPLE_TOLERANCE_CYCLES(TEC_SAMPLE_PERIOD_CYCLES/10),
        .SENSOR_TIMEOUT_CYCLES(TEC_SAMPLE_PERIOD_CYCLES*3)) u_tec(
        .clk(clk_work),.rst_n(!hw_rst),.enable(hw_control[3]),.fault_clear(hw_control[4]),
        .sample_valid(temperature_sample_valid),.sensor_fault(hw_control[6]),
        .temperature_mc(temperature_mc),.setpoint_mc(setpoint_mc),.command(tec_command),
        .output_enable(tec_output_enable),.command_strobe(tec_command_strobe),
        .fault_latched(tec_fault),.fault_flags(tec_fault_flags),.saturated(tec_saturated),
        .slew_limited(tec_slew_limited),.error_mc(tec_error_mc),
        .integral_q16(tec_i1_q16),.integral2_q16(tec_i2_q16));
    // Snapshot optical/temperature state with the result, not the next frame.
    reg locked_at_result,tec_enabled_at_result,tec_fault_at_result;
    always @(posedge clk_work) begin
        if(hw_rst || !measure_proc_rst_n) begin locked_at_result<=0;tec_enabled_at_result<=0;tec_fault_at_result<=0;end
        else if(result_strobe) begin
            locked_at_result<=auto_locked;tec_enabled_at_result<=tec_output_enable;tec_fault_at_result<=tec_fault;
        end
    end
    wire [15:0] system_status={result_flags,locked_at_result,tec_enabled_at_result,tec_fault_at_result,
        measure_enable,measurement_valid,protocol_error,tracking_active,auto_locked};
    generate if(ENABLE_ILA!=0)begin:g_debug
        ila_adc u_ila_adc(.clk(adc_clk),.probe0(raw_a),.probe1(raw_b),.probe2(capture_active),.probe3(capture_address));
        ila_fft u_ila_fft(.clk(clk_work),.probe0(fft_re),.probe1(fft_im),.probe2(fft_bin),.probe3(fft_valid),.probe4(fine_mode),.probe5(low_mode));
        ila_result u_ila_result(.clk(clk_work),.probe0(frequency_hz),.probe1(peak_bin),.probe2(bin_offset_q16),
            .probe3(peak_power),.probe4(noise_power),.probe5({measure_enable,result_fine_mode,measurement_valid,result_strobe,result_flags}),
            .probe6(fine_offset_hz),.probe7(sequence_number),.probe8(result_low_mode),.probe9(tracking_active),.probe10(fft_reacquire_count));
        ila_control u_ila_control(.clk(clk_work),.probe0(debug_error),.probe1(dac_slew_code),.probe2(debug_integral),
            .probe3({auto_state,auto_reason,status}),.probe4(temperature_mc),.probe5(setpoint_mc),.probe6(tec_command),
            .probe7({tec_command_strobe,tec_output_enable,tec_saturated,tec_slew_limited,tec_fault_flags}),
            .probe8(system_status),.probe9(sequence_number));
    end endgenerate
    generate if(ENABLE_VIO!=0)begin:g_vio
        system_control_vio u_vio(.clk(clk_work),
            .probe_in0(cfg_rdata),.probe_in1(status),.probe_in2(hw_status),
            .probe_in3(adc_sample),.probe_in4(dac_slew_code),
            .probe_in5({last_cfg_error,last_cfg_ack,cfg_pending,request_seen}),.probe_in6(auto_status),
            .probe_in7(frequency_hz),.probe_in8(sequence_number),.probe_in9(tec_command),
            .probe_in10({tec_output_enable,tec_fault,tec_saturated,tec_slew_limited,tec_fault_flags}),.probe_in11(system_status),
            .probe_out0(request_toggle),.probe_out1(request_addr),.probe_out2(request_data),.probe_out3(hw_control),
            .probe_out4(temperature_mc),.probe_out5(setpoint_mc));
    end else begin:g_no_vio
        assign request_toggle=0;assign request_addr=0;assign request_data=0;assign hw_control=0;
        assign temperature_mc=0;assign setpoint_mc=25000;
    end endgenerate
endmodule




