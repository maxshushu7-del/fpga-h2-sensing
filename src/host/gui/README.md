# V4 UDP图形接收器

从本目录运行`python -m pip install -r requirements.txt`，然后`python main.py`。默认监听`0.0.0.0:5001`，PC网卡可设`192.168.1.100/24`，FPGA广播目的`192.168.1.255:5001`。

直接识别40字节大端`FPGA/TEC2`报文；保留H2PK和JSON扩展入口。误差/DAC显示原始code，不推算未知电压。网络包与FFT结果按两个序号分别处理。模型温度、故障与通信超时保留标志。

V4标量遥测不携带完整ADC波形和FFT谱线；这些图窗只有收到独立波形/频谱数据时更新。不会根据一个频率值合成正弦波冒充采集。浓度按提供的标定表作相邻点线性插值；输入超出所设范围或低于最小正标定点时不生成有效浓度。

验证命令：`python -m unittest test_v4_integration test_udp_protocol -v`。报文为本机fixture；解析和UDP回环通过不等于已连接实验板。
