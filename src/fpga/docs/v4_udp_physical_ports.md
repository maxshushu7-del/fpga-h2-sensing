# V4 UDP-only physical IO

- 原有 FPGA 数据输入、AD9643 ADC、AD9122 DAC、SPI、LED 保持 V3 约束
- 物理千兆网接口: `phy_reset_n` AF23; `phy_tx_clk` AE16; `phy_tx_ctl` AD16; `phy_txd[0]` Y18, `[1]` AA18, `[2]` AB24, `[3]` AC24; LVCMOS18
- TX 端钟由 V3 DAC MMCM 250MHz 通过 BUFGCE_DIV 2 分频为 125MHz，保留原两时钟域复位与 CDC 处理
- `uart_tx` A13 不再是工程顶层端口，也未添加 UART XDC
- AXAU15 手册 JL2121 绑带显示 RGMII TXCLK 2ns 内部延迟使能，但尚未完成板级时序和实际链路测试
