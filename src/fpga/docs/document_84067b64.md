# UDP CDC V2：设计与 STA 检查点

## 源文件改动

- `rtl/network/rgmii_udp_tx.v`：BUFGCE_DIV.CLR 固定为 0，保持派生时钟稳定；`reset_sync` 使 125MHz 域复位同步释放；PHY 就绪仍等待 200000 个 125MHz 周期；独立 `reset125` 输出。
- `rtl/servo/laser_lock_hw_udp_only_top.v`（V4 继承同样复位方案）：将工作域 hw_rst 与 Ethernet reset125 分离；以太网用本时钟域的 phy_ready_eth 控制发送复位，外部 phy_reset_n 的异步组合仅用作 PHY 硬复位。
- `rtl/network/udp_telemetry_bridge.v`：新增 rst_work/rst_eth；req_sync/ack_sync 设置 `ASYNC_REG` 和 `SHREG_EXTRACT=NO`。
- `constraints/udp_cdc_timing.tcl`：精确排除 request/ack 第一拍的 STA，其他拍照常分析；snapshot 到 eth_payload 按相对多周期数据握手限定最大线延迟和数据总线 skew。

## 协议不变

- 每秒 100 次只读 UDP 遥测，包长、IP、端口、广播 MAC 均不变。
- 32bit 温度等来自 FPGA 虚拟 TEC200 测量模型。

## 时序判断

旧报告 2026-11-01：WNS -2.300ns，TNS -931.077ns；其中 760 个工作->以太网和 171 个反向端点是主要问题，另外仍有 9 个 DAC DDR Setup 端点 WNS -0.018ns。
本修订针对这些现象，但未在 Vivado 2024.1 实际运行；不能先宣称收敛。若 remaining negative，请提供 Vivado `report_timing_summary` 和最差路径。

不为获得绿色 WNS 而消除真实的 DAC/RGMII 物理 I/O 检查，不降级 DRC，也不使用工作域/以太网全局异步时钟组豁免。
