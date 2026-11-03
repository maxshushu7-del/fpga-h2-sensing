LEGACY EXTENSION NOTES: For V4 FPGA/TEC2 telemetry use README.md and protocol_v4.md first. H2PK/JSON descriptions below are extension paths.

Legacy H2PK/JSON protocol notes from the supplied V6 GUI; use README.md and protocol_v4.md for the released V4 receiver.

FPGA 氢气传感上位机 · V6 外观 · 纯 UDP 实时接收版
=====================================================

用途
----
这是仅使用 Ethernet / UDP 的实时接收程序。没有任何串行端口、转发工具或中间传输层。
两扇窗口保持 V6 的显示结构：
  窗口 1：DA 输出、PD 输出、锁定误差、反馈状态
  窗口 2：ADC 时域、FFT、拍频、频移、H₂ 浓度、温度、频移/浓度响应、标定曲线
  独立“网络设置”：监听 IP、端口、拍频基准、清空记录、导出 CSV
不会自动制造测量曲线，也不会预设浓度阶跃。没收到数据时保持空白或“—”。

1. 运行上位机
--------------
安装 Python 3.9+，在 Windows 解压后双击 run_windows.bat。
默认监听 0.0.0.0:5001（本机全部 IPv4 网卡）。
在“网络设置”可修改监听地址、UDP 端口、基准拍频（默认 1 MHz）。
首次启动如被防火墙询问，按照实验室专用网络规则允许 UDP 5001 入站。
UDP 无需先建立连接；监听成功不代表已收到任何 FPGA 数据。
超过约 3 秒无状态/测频更新，当前读数会失效；超过 4 秒无波形，波形清空。

2. FPGA 如何接入（真正直连）
----------------------------
需要 FPGA 通过板上以太网 PHY/MAC 和 UDP/IP 发送逻辑，主动发包至 PC 的 IPv4 地址：5001。
一个常见直连配置：
  FPGA：192.168.1.10 / 255.255.255.0
  PC：  192.168.1.100 / 255.255.255.0
  FPGA UDP 目标：192.168.1.100:5001
  上位机监听：0.0.0.0:5001
实际地址应与所用网卡的配置一致，源/目标端口可分别设置。

重要：软件是可以真实接收 UDP 的，但必须由 FPGA 端实际实现 Ethernet/IP/UDP 数据发送。
目前上传的 FPGA 工程中没有可直接复用的完整以太网 UDP 发包实现。
只安装这份电脑程序不会自动替 FPGA 增添网络发送能力。

3. 直接 UDP 二进制协议：H2PK v1（推荐给 FPGA RTL）
------------------------------------------------
每个 UDP 数据报恰好包含一个 H2PK v1 负载，统一小端（Little Endian）。

统一头：16 字节
  偏移  大小   字段
    0      4    ASCII "H2PK"
    4      1    version = 1
    5      1    kind: 1=校准遥测、2=ADC采样分包、3=原始码值遥测
    6      2    payload_bytes，无符号16位
    8      4    seq，无符号32位，递增序号
   12      4    timestamp_ms，无符号32位

类型 1（kind=1）：一次同步遥测，头 16B + 负载 32B，总 48B
  Python 格式：<BBHiiiiiiI
  state_code     u8   0..13 状态码；12 代表已锁定
  flags          u8   bit0:locked; bit1:DA有效; bit2:PD有效; bit3:误差有效
                      bit4:温度有效; bit5:PWM有效; bit6:测频字段存在; bit7:测频质量有效
  reserved       u16  置零
  da_uV          i32  DA 电压（微伏）
  pd_uV          i32  PD 电压（微伏）
  error_uV       i32  锁定误差（微伏），允许负数
  temp_mC        i32  当前温度（千分之一摄氏度）
  target_mC      i32  目标温度（千分之一摄氏度）
  heater_permille i32 加热占空比（千分比，0~1000）
  frequency_hz   u32  拍频测量（Hz）
发送真实可用的字段，未实现的字段应清除对应 flags 有效位。
上位机会用当前有效拍频 f 和基准 f0 计算 Δf=f-f0，结合28组标定反算氢气浓度。
只有状态已锁定、测频质量有效且处于标定范围时才给出浓度。

类型 3（kind=3）：只提供原始 FPGA 码值时使用，16B头+16B负载
  Python 格式：<BBHiiI
  state_code(u8), flags(u8), reserved(u16), dac_code(i32), error_code(i32), frequency_hz(u32)
  flags 沿用 bit0/bit1/bit3/bit6/bit7；未标定的码值以 code 显示，不猜测电压。
  PD 和温度缺失时保留“—”。

类型 2（kind=2）：ADC 时域采样分包，每包不超过 512 个 int16
  Python 格式：<IHHIHH 后接 n_samples 个 <h 数据
  capture_id     u32：一次采样帧唯一编号
  chunk_index    u16：从 0 开始
  chunk_count    u16：总分包数
  sample_rate_hz u32：ADC 实际采样率，例如 250000000
  n_samples      u16：本包实际采样数量，最多512
  total_samples  u16：整个帧的采样点数，最多4096
  ADC 数据是有符号 int16，单位为 ADC code，建议已完成原始编码转换与中心化。
  4096 点需要8包，每包最大 1056B UDP 负载，小于普通以太网 MTU。
  包乱序到达可以重组；2 秒内未收齐就抛弃这帧，不假装完整采样。
  收齐后，上位机显示时域波形并以收到的实际 ADC 样本在 PC 计算 Hann FFT。
  注意：PC 计算的频谱不是 FPGA 原始 FFT 完整谱线；频率读数可直接由 FPGA 测频字段提供。

4. 纯 UDP JSON 负载（备选）
---------------------------
若发送端更容易构造 UTF-8 JSON，也可以一个 UDP 数据报发送一条 JSON。
以下仅为字段格式示例，并非实测数值：
{"type":"telemetry","seq":100,"locked":true,"state":"已锁定",
 "da_v":0.612,"pd_v":1.213,"error_mv":1.2,
 "frequency_hz":33000000,"frequency_valid":true,
 "temperature_c":30.01,"temperature_target_c":30.0,"heater_duty_pct":6.2}

可独立发送：
{"type":"temperature","temperature_c":30.01,"temperature_target_c":30.0,"heater_duty_pct":6.2}
{"type":"fft_result","frequency_hz":33000000,"frequency_valid":true}
{"type":"adc_samples","channel":1,"sample_rate_hz":250000000,"samples":[实际ADC码值...]}
{"type":"spectrum","start_hz":0,"bin_hz":61035.15625,"dbfs":[实际谱线值...]}
后两例中的中文占位文字和省略号不是有效 JSON，发送方应提供完整数值数组。
建议 FPGA 直接使用上述 H2PK 小端二进制格式，避免在 RTL 中拼接 JSON 字符串。

5. 如何检查接收程序
------------------
在程序目录下运行：
  python test_udp_protocol.py
测试回环端口（单独打开终端，不会自动执行）：
  python test_udp_sender.py --host 127.0.0.1 --port 5001 --count 20
test_udp_sender.py 只用于协议本机测试，发送人为构造的测试值，不能当作 FPGA 实测数据。
真正现场运行时，不要运行这个测试发送器。

6. 数据一致性与实时性
--------------------
两个窗口公用同一组 UDP 数据，不会根据时间自动生成波形。
每条浓度点只在接收有效拍频时，按实验标定执行一次反算；相同接收时刻记录一对
“频移、浓度”，因此响应图始终严格一一对应。
无有效锁定/无测频/数据超时，浓度结果显示“—”；PD、温度、ADC采样缺失时保持空白。
“监听成功”仅表示本机 UDP 端口已绑定，“正在接收”表示收到通过解析校验的数据。

备注：对接 FPGA 时应共同核对 状态码定义、DAC/PD电压转换、真实 ADC 位格式、
频率计数和有效位、温控定点单位、采样率、对端 IPv4 地址和 UDP 端口。
