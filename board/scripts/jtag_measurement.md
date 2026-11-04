# JTAG初始化、测频与结果读取

本说明对应仓库V4顶层 `laser_lock_hw_udp_only_top`，寄存器与探针取自 `src/fpga/rtl/servo/laser_lock_hw_top.v`。

## 下载与初始化

1. 在Vivado Hardware Manager连接板卡，选择 `board/bitstream` 中同一批次的 `.bit` 和 `.ltx` 下载；不要混用其他版本的探针文件。
2. 打开 `u_integrated/g_vio/u_vio`。`probe_out3` 对应两位 `hw_control`：bit0允许AD/DA时钟及SPI初始化，bit1允许DAC样本输出。仅做测频时设为二进制 `01`，保留DAC输出关闭。
3. 观察 `probe_in2` 的硬件状态。低位bit0为初始化完成、bit1为ADC就绪、bit2为发送时钟锁定、bit3为时钟健康。FFT实际使能还要求ADC时钟锁定且复位已解除。异常时先检查时钟、供电和下载文件。

## 开启FFT与读取结果

配置通过VIO请求握手完成：`probe_out1`为8位寄存器地址，`probe_out2`为32位数据，最后将 `probe_out0` 从现值翻转一次，发出请求。每次新请求都要翻转，不能一直写成1。

- 开启FFT：地址十六进制 `70`，数据十六进制 `00000001`，再翻转请求位。
- 停止FFT：同一地址写入 `00000000`，再翻转请求位。
- `probe_in5` 从高到低是 `last_cfg_error / last_cfg_ack / cfg_pending / request_seen`。确认应答且没有错误后再继续配置。
- 读结果时只选择地址，不翻转请求位：`74`读取Hz频率，`78`读取峰值格点与结果标志，`7C`读取结果序号；返回值显示在 `probe_in0`。
- 结果序号持续增加，表示模块产生新结果。连续两次频率相同不能据此判断程序停住；同时检查结果有效位和更新序号。

## ILA与UDP各看什么

归档V4的 `u_integrated/u_core/g_ila/u_ila` 观察锁定反馈：probe0为误差、probe1为DAC数据、probe2为积分状态、probe3为控制状态、probe4为DAC有效、probe5为ADC就绪。按照相应有效或状态信号设置触发，用Run Trigger等待事件；立即触发只读取当时的缓存。

该ILA不是完整FFT频谱输出窗口。V4测频结果通过上面的VIO寄存器和40字节UDP遥测读取；归档UDP不传输4096格完整频谱。若需要频谱曲线，应使用已有RTL验证导出文件，或为新固件另行设计采样导出接口。

PC设置同网段空闲地址，如 `192.168.1.100/24`，接收UDP端口5001。先用 `src/fpga/host/udp_monitor.py` 或匹配GUI检查来源、包序号、FFT序号和有效位，再记录频率。解码方式见 `src/host/gui/protocol_v4.md`。

激光反馈和DAC的启用涉及调谐范围与外部电平，需按实际执行器标定；单独FFT验证不需要开启DAC输出。
