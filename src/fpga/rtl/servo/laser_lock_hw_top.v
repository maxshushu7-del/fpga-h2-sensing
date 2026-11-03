`timescale 1ns/1ps
// AXAU15 + FL4322 physical wrapper. Existing digital control is unmodified.
// All configuration/debug buses stay internal; VIO supplies register requests.
module laser_lock_hw_top #(parameter ENABLE_ILA=1,parameter ENABLE_VIO=1, parameter integer TEMP_TIMEOUT_CYCLES=20000000) (
    input wire sys_clk_p,input wire sys_clk_n,input wire key_reset_n,
    input wire adc_dco_p,input wire adc_dco_n,
    input wire [13:0] adc_data_p,input wire [13:0] adc_data_n,
    input wire fpga_clk_p,input wire fpga_clk_n,
    output wire [15:0] dac_data_p,output wire [15:0] dac_data_n,
    output wire dac_dci_p,output wire dac_dci_n,output wire dac_frame_p,output wire dac_frame_n,
    output wire spi_clk,output wire spi_sdio,output wire clk_cs_n,output wire adc_cs_n,output wire dac_cs_n,
    output wire led_ready,output wire led_servo,
    input wire signed [31:0] temp_temperature_mc,
    input wire temp_sample_valid,input wire temp_sensor_fault,
    output wire temp_heater_pwm,output wire temp_fault,
    // READ-ONLY UDP telemetry exports. Clock domains explicitly documented.
    output wire udp_clk_work, output wire udp_clk_250, output wire udp_tx_clock_locked,
    output wire udp_reset,
    output wire [31:0] udp_frequency_hz, output wire [31:0] udp_fft_sequence,
    output wire signed [15:0] udp_laser_error, output wire signed [15:0] udp_dac_code,
    output wire [15:0] udp_temp_duty, output wire udp_temp_fault,
    output wire udp_temp_pwm, output wire udp_fft_valid,
    output wire [7:0] udp_auto_state, output wire [7:0] udp_auto_fault,
    output wire [7:0] udp_hw_status, output wire udp_fft_enable
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
    wire [31:0] cfg_rdata,core_cfg_rdata;
    // Independent FFT function enable, register 0x70 (default OFF).
    reg fft_enable=1'b0;
    // FUNCTION THREE: independent temperature PID, digital input/output only.
    // No extra AD9643 channel or AD9122/DAC owner is introduced.
    // External sensor ADC must deliver temperature_mc and sample_valid
    // synchronized to clk_work; GPIO pin assignment is NOT provided.
    wire temp_addr_selected=(request_addr==8'h5c || request_addr==8'h68 ||
        request_addr==8'h6c || request_addr==8'h94 || request_addr==8'h98 ||
        request_addr==8'h9c || request_addr==8'hf8 || request_addr==8'hfc);
    wire temp_cfg_pending=cfg_pending && (cfg_addr_latched==8'h5c ||
        cfg_addr_latched==8'h68 || cfg_addr_latched==8'h6c ||
        cfg_addr_latched==8'h94 || cfg_addr_latched==8'h98 ||
        cfg_addr_latched==8'h9c || cfg_addr_latched==8'hf8 || cfg_addr_latched==8'hfc);
    wire [31:0] temp_read_data;
    wire temp_cfg_error;
    wire [15:0] temp_duty;
    temperature_peripheral #(.TIMEOUT_CYCLES(TEMP_TIMEOUT_CYCLES)) u_temperature(
        .clk(clk_work),.rst(hw_rst),.cfg_we(temp_cfg_pending),
        .cfg_addr(cfg_pending ? cfg_addr_latched:request_addr),.cfg_wdata(cfg_data_latched),
        .cfg_rdata(temp_read_data),.cfg_error(temp_cfg_error),
        .temperature_mc(temp_temperature_mc),.sample_valid(temp_sample_valid),
        .sensor_fault(temp_sensor_fault),.heater_pwm(temp_heater_pwm),
        .fault(temp_fault),.duty(temp_duty));
    wire fft_cfg_pending=cfg_pending && cfg_addr_latched==8'h70;
    wire [31:0] fft_frequency_hz,fft_sequence_number;
    wire fft_result_strobe,fft_measurement_valid;
    wire [11:0] fft_peak_bin;
    wire [7:0] fft_flags;
    wire sequence_done;
    wire [7:0] writes_sent;
    wire adc_clk,tx_clk,rx_ready,rx_clock_locked,overflow_sticky,tx_locked,tx_active,control_ready,clocks_ok;
    wire cfg_ready,cfg_ack,cfg_error;
    wire [7:0] status;
    wire signed [31:0] debug_error,debug_output;
    wire signed [47:0] debug_integral;
    wire request_toggle;
    wire [7:0] request_addr;
    wire [31:0] request_data;
    wire [1:0] hw_control; // bit0 init; bit1 permit DAC samples. Both default zero.
    reg request_seen=0,cfg_pending=0,last_cfg_ack=0,last_cfg_error=0;
    reg [7:0] cfg_addr_latched=0;
    reg [31:0] cfg_data_latched=0;

    // Reserved JTAG/VIO register space 0x80..0x9F.  This is separate from
    // the original core servo register map (unchanged).
    reg scan_enable=0;
    reg [15:0] scan_half_span=16'd2048;   // DAC codes, NOT 100 mV calibrated
    reg [15:0] scan_step_size=16'd8;      // at most 16 codes / update
    reg [31:0] scan_interval=32'd20000;  // 0.2 ms @ 100 MHz
    reg signed [15:0] scan_center=16'sd0;
    wire scan_cfg_pending=cfg_pending && (cfg_addr_latched[7:5]==3'b100);
    wire auto_cfg_pending=cfg_pending && (cfg_addr_latched>=8'ha0);
    wire core_cfg_pending=cfg_pending && !temp_cfg_pending && !scan_cfg_pending && !auto_cfg_pending && !fft_cfg_pending &&
                          !(auto_requested && cfg_addr_latched==8'h14);
    wire scan_selected=scan_enable && !status[1] && !auto_requested && !auto_was_used; // never mix with servo
    wire scan_running=scan_selected && hw_control[1] && sequence_done &&
                      clocks_ok && rx_ready && !hw_rst;
    wire signed [15:0] scan_code;
    wire scan_valid;
    laser_triangle_scan u_scan(.clk(clk_work),.rst(hw_rst),.enable(scan_running),
        .half_span(scan_half_span),.step_size(scan_step_size),
        .interval_clocks(scan_interval),.center(scan_center),
        .code_out(scan_code),.code_valid(scan_valid));
    // The full-scale voltage must be measured with the actual board, load,
    // bias and laser connector DISCONNECTED. These are DAC codes, NOT volts.
    // No autonomous output is possible until bounded codes are calibrated and
    // 0xAC is explicitly written with the unlock value after the bounds.
    reg auto_requested=0,auto_calibrated=0;
    reg auto_stop_pending=0,auto_was_used=0;
    reg [31:0] auto_stop_wait=0;
    reg signed [15:0] safe_lo=0,safe_hi=0;
    reg signed [15:0] coarse_lo=0,coarse_hi=0;
    reg [15:0] coarse_step=16'd32,fine_half=16'd256,fine_step=16'd4;
    reg [31:0] auto_dwell=32'd20000,guard_interval=32'd1000;
    reg [15:0] min_depth=16'd150,min_slope=16'd3;
    reg [15:0] lock_error_limit=16'd700,guard_step=16'd8;
    wire valid_safe_range=(safe_lo<0 && safe_hi>0 && safe_hi>safe_lo &&
                           safe_lo>=-16'sd16384 && safe_hi<=16'sd16384);
    wire valid_search_range=(coarse_lo>=safe_lo && coarse_hi<=safe_hi &&
                             coarse_hi>coarse_lo &&
                             ($signed(coarse_hi)-$signed(coarse_lo))>=64);
    wire auto_active=auto_requested && auto_calibrated && valid_safe_range &&
            valid_search_range && hw_control[1] && sequence_done &&
            clocks_ok && rx_ready && !hw_rst;
    wire signed [15:0] auto_command,applied_code,auto_lock_base,auto_setpoint;
    wire auto_pid_enable,auto_pid_clear,applied_valid;
    wire [4:0] auto_state;
    wire [7:0] auto_fault;
    wire signed [15:0] detected_code,detected_adc;
    wire [15:0] detected_depth,detected_slope;
    wire [31:0] auto_points;
    laser_auto_search u_auto(.clk(clk_work),.rst(hw_rst),.enable(auto_active),
        .applied_code(applied_code),.adc_sample(adc_sample),.adc_valid(adc_valid),
        .coarse_lo(coarse_lo),.coarse_hi(coarse_hi),
        .coarse_step(coarse_step),.fine_half(fine_half),.fine_step(fine_step),
        .dwell_clocks(auto_dwell),.min_depth(min_depth),.min_slope(min_slope),
        .lock_error_limit(lock_error_limit),.requested_code(auto_command),
        .pid_enable(auto_pid_enable),.pid_clear(auto_pid_clear),
        .lock_code(auto_lock_base),.lock_setpoint(auto_setpoint),
        .state(auto_state),.fault(auto_fault),
        .coarse_min_code(detected_code),.coarse_min_adc(detected_adc),
        .coarse_depth(detected_depth),.best_slope(detected_slope),
        .points_tested(auto_points));
    // The PI2D output is a signed correction around the acquired lock_code.
    // Clamp at 32 bits BEFORE conversion to 16-bit DAC code.
    wire signed [31:0] auto_raw_target=$signed(auto_lock_base)+$signed(dac_command);
    wire signed [31:0] auto_bounded_target=
          (auto_raw_target>$signed(safe_hi))?$signed(safe_hi):
          (auto_raw_target<$signed(safe_lo))?$signed(safe_lo):auto_raw_target;
    wire signed [15:0] guarded_target=auto_stop_pending ? 16'sd0 : auto_pid_enable ?
                                   auto_bounded_target[15:0] : auto_command;
    laser_code_guard u_guard(.clk(clk_work),.rst(hw_rst),.enable(auto_active),
        .target_code(guarded_target),.min_code(safe_lo),.max_code(safe_hi),
        .max_step(guard_step),.interval_clocks(guard_interval),
        .applied_code(applied_code),.applied_valid(applied_valid));
    reg [31:0] auto_read_data;
    always @* begin
        case(request_addr)
            8'ha0:auto_read_data={31'd0,auto_requested};
            8'ha4:auto_read_data={{16{safe_lo[15]}},safe_lo};
            8'ha8:auto_read_data={{16{safe_hi[15]}},safe_hi};
            8'hac:auto_read_data={31'd0,auto_calibrated};
            8'hb0:auto_read_data={{16{coarse_lo[15]}},coarse_lo};
            8'hb4:auto_read_data={{16{coarse_hi[15]}},coarse_hi};
            8'hb8:auto_read_data={16'd0,coarse_step};
            8'hbc:auto_read_data={16'd0,fine_half};
            8'hc0:auto_read_data={16'd0,fine_step};
            8'hc4:auto_read_data=auto_dwell;
            8'hc8:auto_read_data={16'd0,min_depth};
            8'hcc:auto_read_data={16'd0,min_slope};
            8'hd0:auto_read_data={16'd0,guard_step};
            8'hd4:auto_read_data=guard_interval;
            8'hd8:auto_read_data={17'd0,auto_calibrated,auto_pid_enable,auto_fault,auto_state};
            8'hdc:auto_read_data={{16{detected_code[15]}},detected_code};
            8'he0:auto_read_data={{16{auto_lock_base[15]}},auto_lock_base};
            8'he4:auto_read_data={{16{auto_setpoint[15]}},auto_setpoint};
            8'he8:auto_read_data={detected_depth,detected_slope};
            8'hec:auto_read_data=auto_points;
            8'hf0:auto_read_data={16'd0,lock_error_limit};
            8'hf4:auto_read_data={{16{applied_code[15]}},applied_code};
            default:auto_read_data=0;
        endcase
    end
    reg [31:0] scan_read_data;
    always @* begin
        case(request_addr)
            8'h80:scan_read_data={31'd0,scan_enable};
            8'h84:scan_read_data={16'd0,scan_half_span};
            8'h88:scan_read_data={16'd0,scan_step_size};
            8'h8c:scan_read_data=scan_interval;
            8'h90:scan_read_data={{16{scan_center[15]}},scan_center};
            default:scan_read_data=32'd0;
        endcase
    end
    assign cfg_rdata=temp_addr_selected ? temp_read_data : (request_addr==8'h70) ? {31'd0,fft_enable} :
                     (request_addr==8'h74) ? fft_frequency_hz :
                     (request_addr==8'h78) ? {12'd0,fft_peak_bin,fft_flags} :
                     (request_addr==8'h7c) ? fft_sequence_number :
                     (request_addr[7:5]==3'b100) ? scan_read_data :
                     (request_addr>=8'ha0) ? auto_read_data : core_cfg_rdata;
    always @(posedge clk_work)begin
        if(hw_rst)begin
            request_seen<=request_toggle;cfg_pending<=0;cfg_addr_latched<=0;
            cfg_data_latched<=0;last_cfg_ack<=0;last_cfg_error<=0;
            fft_enable<=1'b0;
            scan_enable<=0;scan_half_span<=16'd2048;scan_step_size<=16'd8;
            scan_interval<=32'd20000;scan_center<=0;
            auto_requested<=0;auto_stop_pending<=0;auto_was_used<=0;auto_stop_wait<=0;
            auto_calibrated<=0;safe_lo<=0;safe_hi<=0;
            coarse_lo<=0;coarse_hi<=0;
            coarse_step<=16'd32;fine_half<=16'd256;fine_step<=16'd4;
            auto_dwell<=32'd20000;guard_interval<=32'd1000;
            min_depth<=16'd150;min_slope<=16'd3;
            lock_error_limit<=16'd700;guard_step<=16'd8;
        end
        else begin
            if(auto_requested)auto_was_used<=1;
            if(auto_stop_pending)begin
                if(!auto_active)begin
                    auto_requested<=0;auto_stop_pending<=0;auto_stop_wait<=0;
                end else if(applied_code==16'sd0)begin
                    if(auto_stop_wait>=32'd100000)begin
                        auto_requested<=0;auto_stop_pending<=0;auto_stop_wait<=0;
                    end else auto_stop_wait<=auto_stop_wait+1'b1;
                end else auto_stop_wait<=0;
            end
            if(cfg_ack)begin last_cfg_ack<=1;last_cfg_error<=cfg_error;end
            if(cfg_pending)begin
                if(temp_cfg_pending) begin
                    cfg_pending<=0;last_cfg_ack<=1;last_cfg_error<=temp_cfg_error;
                end else if(fft_cfg_pending) begin
                    cfg_pending<=0;
                    last_cfg_ack<=1;
                    if(cfg_data_latched[31:1]!=0) last_cfg_error<=1;
                    else begin fft_enable<=cfg_data_latched[0];last_cfg_error<=0; end
                end else if(scan_cfg_pending)begin
                    cfg_pending<=0;
                    last_cfg_ack<=1;
                    last_cfg_error<=auto_requested;
                    if(!auto_requested) case(cfg_addr_latched)
                        8'h80: begin
                            if(cfg_data_latched[31:1]!=0)last_cfg_error<=1;
                            else scan_enable<=cfg_data_latched[0];
                        end
                        8'h84: scan_half_span <= (cfg_data_latched>16384) ? 16'd16384 : cfg_data_latched[15:0];
                        8'h88: scan_step_size <= (cfg_data_latched==0) ? 16'd1 :
                                                 (cfg_data_latched>16) ? 16'd16 : cfg_data_latched[15:0];
                        8'h8c: scan_interval <= (cfg_data_latched<1000) ? 32'd1000 : cfg_data_latched;
                        8'h90: scan_center <= ($signed(cfg_data_latched)>16384) ? 16'sd16384 :
                                                  ($signed(cfg_data_latched)<-16384) ? -16'sd16384 : cfg_data_latched[15:0];
                        default: last_cfg_error<=1;
                    endcase
                end else if(auto_cfg_pending) begin
                    cfg_pending<=0;last_cfg_ack<=1;last_cfg_error<=0;
                    if(auto_requested && cfg_addr_latched!=8'ha0)begin
                        // Do not mutate acquisition/safety settings during auto.
                        last_cfg_error<=1;
                    end else case(cfg_addr_latched)
                        8'ha0:begin
                            if(cfg_data_latched==0) begin
                                if(auto_requested) auto_stop_pending<=1;
                                else auto_stop_pending<=0;
                            end
                            else if(cfg_data_latched==1 && !auto_stop_pending &&
                                    auto_calibrated &&
                                    valid_safe_range && valid_search_range &&
                                    !scan_enable && !status[1])auto_requested<=1;
                            else last_cfg_error<=1;
                        end
                        8'ha4:begin
                            if($signed(cfg_data_latched)>=-16384 &&
                               $signed(cfg_data_latched)<0) begin
                                safe_lo<=cfg_data_latched[15:0];auto_calibrated<=0;
                            end else last_cfg_error<=1;
                        end
                        8'ha8:begin
                            if($signed(cfg_data_latched)>0 &&
                               $signed(cfg_data_latched)<=16384)begin
                                safe_hi<=cfg_data_latched[15:0];auto_calibrated<=0;
                            end else last_cfg_error<=1;
                        end
                        8'hac:begin
                            if(cfg_data_latched==32'hC0DE1A5E && valid_safe_range)
                                auto_calibrated<=1;
                            else begin auto_calibrated<=0;last_cfg_error<=1;end
                        end
                        8'hb0:coarse_lo<=cfg_data_latched[15:0];
                        8'hb4:coarse_hi<=cfg_data_latched[15:0];
                        8'hb8:coarse_step<=(cfg_data_latched<1)?16'd1:
                                       (cfg_data_latched>1024)?16'd1024:cfg_data_latched[15:0];
                        8'hbc:fine_half<=(cfg_data_latched<16)?16'd16:
                                      (cfg_data_latched>4096)?16'd4096:cfg_data_latched[15:0];
                        8'hc0:fine_step<=(cfg_data_latched<1)?16'd1:
                                      (cfg_data_latched>128)?16'd128:cfg_data_latched[15:0];
                        8'hc4:auto_dwell<=(cfg_data_latched<1000)?32'd1000:
                                        (cfg_data_latched>10000000)?32'd10000000:cfg_data_latched;
                        8'hc8:min_depth<=cfg_data_latched[15:0];
                        8'hcc:min_slope<=cfg_data_latched[15:0];
                        8'hd0:guard_step<=(cfg_data_latched<1)?16'd1:
                                       (cfg_data_latched>16)?16'd16:cfg_data_latched[15:0];
                        8'hd4:guard_interval<=(cfg_data_latched<1000)?32'd1000:
                                             (cfg_data_latched>1000000)?32'd1000000:cfg_data_latched;
                        8'hf0:lock_error_limit<=cfg_data_latched[15:0];
                        default:last_cfg_error<=1;
                    endcase
                end else if(auto_requested && cfg_addr_latched==8'h14)begin
                    cfg_pending<=0;last_cfg_ack<=1;last_cfg_error<=1;
                end else if(cfg_ready) cfg_pending<=0;
            end
            else if(request_toggle!=request_seen)begin
                request_seen<=request_toggle;cfg_pending<=1;last_cfg_ack<=0;last_cfg_error<=0;
                cfg_addr_latched<=request_addr;cfg_data_latched<=request_data;
            end
        end
    end
    laser_lock_top #(.ENABLE_ILA(ENABLE_ILA),.ENABLE_AUTO(1)) u_core(
        .clk_200m_p(sys_clk_p),.clk_200m_n(sys_clk_n),.rst_n(key_reset_n),
        .adc_data_in(adc_sample),.adc_valid(adc_valid),.adc_ready(adc_ready),
        .auto_servo_enable(auto_pid_enable && auto_active && !auto_stop_pending),
        .auto_servo_clear(auto_pid_clear),.auto_setpoint(auto_setpoint),
        .dac_data_out(dac_command),.dac_valid(dac_valid),
        .cfg_we(core_cfg_pending),.cfg_addr(cfg_pending ? cfg_addr_latched:request_addr),.cfg_wdata(cfg_data_latched),
        .cfg_rdata(core_cfg_rdata),.cfg_ready(cfg_ready),.cfg_ack(cfg_ack),.cfg_error(cfg_error),
        .clk_work_out(clk_work),.clock_locked(core_locked),.status(status),
        .ila_error(debug_error),.ila_control_output(debug_output),.ila_integral(debug_integral));
    // Only the physical wrapper selects global routing to the controller CMT.
    // The generic servo top and all its control modules keep their defaults.
    defparam u_core.u_clock.CLOCK_INPUT_BUFG=1;
    hw_fl4322_init u_init(.clk(clk_work),.rst(hw_rst),.init_enable(hw_control[0]),
        .spi_clk(spi_clk),.spi_sdio(spi_sdio),.clk_cs_n(clk_cs_n),.adc_cs_n(adc_cs_n),.dac_cs_n(dac_cs_n),
        .sequence_done(sequence_done),.writes_sent(writes_sent));
    wire [13:0] raw_a,raw_b;
    wire [31:0] dropped_count;
    hw_ad9643_rx #(.DECIMATION(256)) u_rx(.rst_n(hw_reset_n),.clk_work(clk_work),
        .config_done(sequence_done),.adc_dco_p(adc_dco_p),.adc_dco_n(adc_dco_n),
        .adc_data_p(adc_data_p),.adc_data_n(adc_data_n),
        .adc_ready(adc_ready || auto_requested),
        .adc_data_out(adc_sample),.adc_valid(adc_valid),.adc_clk_out(adc_clk),
        .raw_data_a(raw_a),.raw_data_b(raw_b),.rx_ready(rx_ready),.rx_clock_locked(rx_clock_locked),
        .overflow_sticky(overflow_sticky),.dropped_count(dropped_count));
    // ========= FUNCTION TWO: independent beat-frequency capture on ADC B =========
    // One physical AD9643 receiver; rising DDR slot A feeds the original
    // servo mailbox, falling DDR slot B feeds the FFT in adc_clk domain.
    // No second SPI initializer, no duplicate DCO input and no new DAC owner.
    wire fft_adc_rst_n,fft_proc_rst_n;
    reset_sync u_fft_adc_reset(.clk(adc_clk),
        .async_ok(hw_reset_n && rx_clock_locked),.rst_n(fft_adc_rst_n));
    reset_sync u_fft_proc_reset(.clk(clk_work),
        .async_ok(hw_reset_n && rx_clock_locked),.rst_n(fft_proc_rst_n));
    wire fft_active=fft_enable && sequence_done && rx_ready &&
                    rx_clock_locked && !hw_rst;
    wire fft_capture_active,fft_valid,fft_last,fft_fine_mode,fft_low_mode;
    wire fft_result_fine,fft_result_low,fft_tracking,fft_protocol_error;
    wire [11:0] fft_capture_address,fft_bin,fft_coarse_bin;
    wire signed [28:0] fft_re,fft_im;
    wire signed [17:0] fft_bin_offset;
    wire signed [31:0] fft_fine_offset_hz;
    wire [58:0] fft_peak_power,fft_noise_power;
    wire [31:0] fft_reacquires,fft_clipped;
    measurement_improved #(.ALGORITHM_VERSION(3),.ADC_CHANNEL(1),
        .FFT_LOG2(12),.WINDOW_ENABLE(1),.DECIMATION(250),
        .ADC_SAMPLE_RATE_HZ(250000000),.TRACKING_ENABLE(1),
        .TRACK_RECHECK_FRAMES(4),.FRAME_GAP_CYCLES(200000),
        .SIM_IDLE_FFT_PAUSE(0)) u_measurement (
        .adc_clk(adc_clk),.adc_rst_n(fft_adc_rst_n),
        .channel_a($signed(raw_a)),.channel_b($signed(raw_b)),
        .proc_clk(clk_work),.proc_rst_n(fft_proc_rst_n),.enabled(fft_active),
        .capture_active(fft_capture_active),.capture_address(fft_capture_address),
        .fft_re(fft_re),.fft_im(fft_im),.fft_bin(fft_bin),
        .fft_valid(fft_valid),.fft_last(fft_last),
        .result_strobe(fft_result_strobe),.measurement_valid(fft_measurement_valid),
        .fine_mode(fft_fine_mode),.low_mode(fft_low_mode),
        .result_fine_mode(fft_result_fine),.result_low_mode(fft_result_low),
        .tracking_active(fft_tracking),.reacquire_count(fft_reacquires),
        .frequency_hz(fft_frequency_hz),.sequence_number(fft_sequence_number),
        .peak_bin(fft_peak_bin),.coarse_bin(fft_coarse_bin),
        .bin_offset_q16(fft_bin_offset),.fine_offset_hz(fft_fine_offset_hz),
        .peak_power(fft_peak_power),.noise_power(fft_noise_power),
        .result_flags(fft_flags),.clipped_samples(fft_clipped),
        .protocol_error(fft_protocol_error));
    // ========= END FUNCTION TWO =========
    // SCAN is explicitly enabled via VIO register 0x80 and is selected only
    // when servo_enable=0. Otherwise preserve the original lock datapath.
    // Hardware permission still defaults off and gates both modes.
    wire signed [15:0] dac_selected_code=auto_requested ? applied_code :
                                               scan_selected ? scan_code : dac_command;
    wire dac_selected_valid=auto_requested ? applied_valid :
                                                 scan_selected ? scan_valid : dac_valid;
    // While editing scan registers, do not forcibly zero the DAC output.
    // Preserve original gating for any servo-register write.
    hw_ad9122_tx #(.INPUT_CLK_PERIOD_NS(4.0),.MMCM_MULT_F(4.0),.OUTPUT_DIVIDE(4),.DCI_DELAY_PS(875.0)) u_tx(.clk_work(clk_work),.rst_n(hw_reset_n),.fpga_clk_p(fpga_clk_p),.fpga_clk_n(fpga_clk_n),
        .control_in(dac_selected_code),.control_valid(dac_selected_valid),
        .tx_enable(hw_control[1] && clocks_ok && rx_ready && !hw_rst &&
                   (auto_requested ? auto_active :
                    (!auto_was_used &&
                     (scan_selected || (status[1] && !cfg_pending))))),
        .config_done(sequence_done),.control_ready(control_ready),.tx_clk_out(tx_clk),
        .ethernet_raw_clock_250(udp_clk_250),
        .tx_clock_locked(tx_locked),.tx_active(tx_active),
        .dac_data_p(dac_data_p),.dac_data_n(dac_data_n),.dac_dci_p(dac_dci_p),.dac_dci_n(dac_dci_n),
        .dac_frame_p(dac_frame_p),.dac_frame_n(dac_frame_n));
    wire [9:0] adc_beats,tx_beats;
    hw_clock_health u_health(.rst_n(hw_reset_n),.clk_work(clk_work),.adc_clk(adc_clk),.tx_clk(tx_clk),
        .enable(sequence_done),.clocks_ok(clocks_ok),.adc_beats(adc_beats),.tx_beats(tx_beats));
    (* ASYNC_REG="TRUE" *) reg [1:0] tx_lock_sync,tx_active_sync;
    // Status synchronizers release with the already qualified work-domain reset.
    always @(posedge clk_work)begin
        if(hw_rst)begin tx_lock_sync<=0;tx_active_sync<=0;end
        else begin tx_lock_sync<={tx_lock_sync[0],tx_locked};tx_active_sync<={tx_active_sync[0],tx_active};end
    end
    assign led_ready=sequence_done && rx_ready && tx_lock_sync[1] && clocks_ok;
    assign led_servo=status[1] && tx_active_sync[1];
    wire [7:0] hw_status={overflow_sticky,control_ready,hw_rst,tx_active_sync[1],clocks_ok,
        tx_lock_sync[1],rx_ready,sequence_done};
    // V4 UDP-ONLY: removed the old UART telemetry transmitter entirely.
    // The exported status signals below feed only the 100Hz UDP bridge.
    // Telemetry is read-only and cannot directly enable servo/DAC/PID.
    // debug_error is a signed 16-bit normalized PI2D error (not Hz).
    wire signed [15:0] telemetry_error=auto_pid_enable && auto_active &&
        !auto_stop_pending ? debug_error[15:0] : 16'sd0;
    wire signed [15:0] telemetry_dac=(hw_control[1] && tx_active_sync[1]) ?
        dac_selected_code : 16'sd0;

    // Telemetry remains passive: it cannot write servo, DAC or PID registers.
    assign udp_clk_work=clk_work;
    assign udp_tx_clock_locked=tx_locked;
    assign udp_reset=hw_rst;
    assign udp_frequency_hz=fft_frequency_hz;
    assign udp_fft_sequence=fft_sequence_number;
    assign udp_laser_error=telemetry_error;
    assign udp_dac_code=telemetry_dac;
    assign udp_temp_duty=temp_duty;
    assign udp_temp_fault=temp_fault;
    assign udp_temp_pwm=temp_heater_pwm;
    assign udp_fft_valid=fft_measurement_valid;
    assign udp_auto_state=auto_requested ? {3'd0,auto_state}:8'd0;
    assign udp_auto_fault=auto_requested ? auto_fault:8'd0;
    assign udp_hw_status=hw_status;
    assign udp_fft_enable=fft_active;

    generate if(ENABLE_VIO!=0)begin:g_vio
        laser_lock_hw_vio u_vio(.clk(clk_work),
            .probe_in0(cfg_rdata),.probe_in1(status),.probe_in2(hw_status),
            .probe_in3(adc_sample),.probe_in4(dac_command),
            .probe_in5({last_cfg_error,last_cfg_ack,cfg_pending,request_seen}),.probe_in6(dropped_count),
            .probe_out0(request_toggle),.probe_out1(request_addr),.probe_out2(request_data),.probe_out3(hw_control));
    end else begin:g_no_vio
        assign request_toggle=0;assign request_addr=0;assign request_data=0;assign hw_control=0;
    end endgenerate
endmodule




