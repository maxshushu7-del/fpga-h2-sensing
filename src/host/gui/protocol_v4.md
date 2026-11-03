# AXAU15 V4 UDP遥测

FPGA源地址为`192.168.1.10:5000`，目的为`192.168.1.255:5001`。PC在同一有线子网监听`0.0.0.0:5001`。每个UDP负载恰好40字节，多字节字段均为大端。

| 字节 | 字段 | 类型与单位 |
|---|---|---|
| 0–3 | magic | ASCII `FPGA` |
| 4 | version | u8，1 |
| 5 | flags | bit0测频有效；bit1温度故障；bit3模型温度；bit4初始化完成；bit5时钟正常；bit6测频使能；bit2/7保留 |
| 6–7 | auto_state / auto_fault | u8 / u8 |
| 8–11 | packet_sequence | u32，网络快照序号 |
| 12–15 | frequency_hz | u32，Hz |
| 16–19 | fft_sequence | u32，新测频结果序号 |
| 20–21 | laser_error | i16，ADC误差码 |
| 22–23 | dac_code | i16，DAC原始码 |
| 24–27 | temperature_mc | i32，m°C |
| 28–29 | temp_duty | u16，PWM计数；0xffff按满量程处理 |
| 30–31 | temp_flags | bit0故障；bit1 PWM状态；bit2模型温度 |
| 32–35 | uptime | u32，每计数10 ms |
| 36–39 | tail | ASCII `TEC2` |

状态码0–13对应IDLE、粗扫初始化、粗扫移动、粗扫等待、粗扫评估、粗扫回程、细扫初始化、细扫移动、细扫等待、细扫评估、定位、驻留、LOCKED、FAILED。状态12及无故障表示控制器报告进入闭环，不单独证明光学锁定品质。

网络快照可能重复携带同一FFT结果；曲线按FFT序号与有效性更新。V4遥测没有PD电压、目标温度、ADC采样块和完整FFT谱线，接收端不会补造这些字段。扩展H2PK/JSON仅在相应发送端提供数据时使用。
