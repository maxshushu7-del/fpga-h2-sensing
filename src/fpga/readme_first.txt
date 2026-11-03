AXAU15 四功能独立工程 V4 — 上位机 UDP-ONLY 版本（2026-11-03）
=============================================================
【这版修改原因】
V3 曾在同一个硬件顶层同时输出 UART (uart_tx/A13) 和 UDP (PHY RGMII)。
这会使用户以为上位机数据仍是 UART。V4 已真正删去原 UART TX 实例、
取消 uart_tx 物理端口和 A13 UART XDC，所有集成状态遥测只经 RGMII -> UDP 输出。
不是仅改模块名！

【准备和操作】
1. 完整备份已经 Bitstream + 已约束 STA PASS 的 V3 原工程，千万不要覆盖。
2. 将此 ZIP 全部解压到一个新、短英文路径：C:\FPGA\V4
   确认 00_create_and_build.cmd 就在 C:\FPGA\V4 目录下。
3. 双击 00_create_and_build.cmd: 自动创建 project/contest_all.xpr，
   自动生成 Vivado 2024.1 FFT / ILA / VIO IP，执行 Synthesis/Implementation/Bitstream。
4. 完成后打开 results/V4_TIMING_STATUS.txt 和 final_timing_summary.txt。
   注意 V3 实测 WNS=+0.004ns 裕量小，代码删 UART 后布局改变，V4 必须重新测 STA，
   不能直接继承 V3 的 PASS 结论。
5. 上位机运行 03_start_pc_udp_receiver.cmd，或 python host/udp_monitor.py。

【UDP 发送线路 — 没有 UART】
ADC B -> FFT 4096 -> 最新频率 Hz ------\
伺服 PI2D / 扫描状态、DAC 码 ----------+--> 100MHz status snapshot
FPGA PID、虚拟温度(毫摄氏度) -----------/         |
                                      100->125MHz 握手跨时钟
                                               |
                            Ethernet II -> IPv4 -> UDP -> Ethernet CRC32
                                               |
                 125MHz RGMII DDR -> JL2121 PHY -> RJ45 网线 -> Windows UDP 5001

【网络参数】
PHY：AXAU15 JL2121-N040I，默认上电绑带启用 TXCLK 2ns 内部延时；要求 1Gbps 链路。
发送端源 MAC: 02:15:66:00:00:01
发送端 IP: 192.168.1.10，发送端 UDP Port: 5000
目的 IP: 192.168.1.255（广播），目的 UDP Port: 5001
默认报文频率: 100 个/秒，每包 40 字节有效负载。
PC 可将有线网卡配置为 192.168.1.100/24 (子网掩码 255.255.255.0)，
打开 Windows 防火墙对 UDP/5001 的入站许可，并确保 PHY 和网卡协商 1Gbps。
这是 TX-only、单向 UDP。无 ARP/MDIO 控制、DHCP、接收 FPGA 配置指令。

【UDP 40 字节数据：网络序，大端】
 0..3  ASCII FPGA; 4 协议版本; 5 flags; 6 auto_state; 7 auto_fault;
 8..11 packet_seq; 12..15 FFT peak frequency Hz;
16..19 FFT result sequence; 20..21 servo error(int16);
22..23 DAC code(int16); 24..27 温度(milli-degree Celsius,int32);
28..29 PID duty(uint16); 30..31 temperature flags;
32..35 uptime(10ms ticks); 36..39 ASCII TEC2。
此版本传送的是 FFT 估计峰值和状态，不是整幅 4096bin 原始频谱。

【四功能仍保留】
1. 激光自动扫描 + PI2D 反馈 + ADC A / DAC
2. ADC B + DDC + 4096 点 FFT + 频率峰值
3. FPGA PID + PWM，仍用内部虚拟 TEC200 温度模型（不连接实物）
4. FPGA 千兆 UDP 发送，只走 RGMII 网口；取消原 A13 UART 输出

【重要状态边界】
- V3 实测：Bitstream 和所有“已约束路径”的 Setup/Hold/Pulse Width 通过。
- V4 未在本环境实际运行 Vivado 2024.1；需要你本机验证，不保证一次成功。
- FPGA 原有 DAC 模拟输出需要独立上板安全验证，勿直接连接激光器。
- TEC200 实物接口未知，温度是虚拟模型，不能声称真实 TEC200 控温成功。
- RGMII TX 物理接口的真实板级偏斜、输出延迟仍未完成正式时序签核。
- UDP 实际能否在 PC 端收到包，需要连接网线后测试，不能用生成 .bit 代替。
- 无 RX/MDIO；网口协商不是这个 FPGA RTL 代码主动完成。

【诊断】
V4 顶层：laser_lock_hw_udp_only_top
物理输出有 phy_reset_n、phy_tx_clk、phy_tx_ctl、phy_txd[3:0]
物理输出没有 uart_tx；项目不读取 uart_tx_pin.xdc，也不实例化 UART 模块。
独立 IP .xci：fft_core、laser_lock_hw_vio、laser_lock_ila。
UDP 结构检查：python scripts/check_local.py
UDP 独立协议仿真：04_test_udp_sim.cmd
