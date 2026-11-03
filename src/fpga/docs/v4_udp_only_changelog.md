# V4 与 V3 精确差异说明

V3 已在 AXAU15/Vivado 2024.1 路由并通过已约束时序，WNS +0.004ns、WHS +0.011ns，但 `laser_lock_hw_top` 仍然实例化 `contest_dual_uart`，物理顶层也有 `uart_tx`/A13 引脚。

V4 删除了 `laser_lock_hw_top` 中 UART 输出端口与整个 `u_contest_uart` 实例，保留产生 `telemetry_error`/`telemetry_dac` 的源信号并通过 `udp_*` 继续发送。全新物理顶层 `laser_lock_hw_udp_only_top` 不包含 `uart_tx` 输出端口，取消 UART XDC，移除两份 UART TX RTL 和 UART 仿真。并且继续保留 V3 875ps DCI、FFT XCI、ILA/VIO XCI、UDP 的 100/125MHz 握手与 RGMII 发送代码。

原串口的 80 byte FFT 包和状态帧不再生成。新工程仅发送 40 字节 UDP 遥测，不是 4096bin 频谱波形传输。寄存器配置由 JTAG VIO 完成，不提供 UDP 远程控制（TX-only）。

V4 需要重新综合/实现/Bitstream，并生成全新路由后 STA 报告；V3 的 PASS 不能直接移植到 V4。
