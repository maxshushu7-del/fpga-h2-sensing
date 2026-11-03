本轮是独立的FPGA小任务。先读取E:/Codex/FPGA/AGENTS.md。
本组工作目录：E:/Codex/FPGA/workspace/report_targeted_revision_20261102/ai_trial/deepseek_ordinary

实现SystemVerilog模块sat_accum_stream，不使用外部IP。端口：clk、rst（高有效同步复位）、输入s_x signed[15:0]整数、输入s_k signed[7:0] Q1.7、输入s_valid、输出s_ready、输出m_y signed[15:0]、输出m_valid、输入m_ready。每次输入握手上升沿计算整数p=s_x*s_k，r=sign(p)*floor((abs(p)+64)/128)，零为零，正负恰好半值都远离零。累加状态a初始0，每次输入握手执行a=clamp16(a+r)，范围-32768..32767，每次累加立即饱和。单级输出寄存器，s_ready=!rst&&(!m_valid||m_ready)。接受输入的上升沿后，新累加值写m_y并置m_valid；允许同拍消费旧结果并接收新输入。背压时m_valid与m_y保持。没有新输入时a和m_y保持；消费且无替补输入时m_valid清零。复位上升沿清a,m_y,m_valid，取消旧的待输出结果。交付RTL、自测、运行入口和实际日志。工具Vivado2024.1在E:/Xilinx/Vivado/2024.1/bin，Python可用C:/Users/dell/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe。所有新文件、临时数据和日志都放本组E盘目录，不能写C盘。工具运行失败保存原始错误，不编写成功日志。

请按上述需求完成实现和自测，运行后给我结果。实现方式由你决定。仅在本组目录中创建文件，不读取另一组产物或acceptance目录。保存首次宣布可验收时的版本与日志，并记录实际发生的自测失败和修正，保存开始/结束UTC时间、可见模型版本。建议15分钟任务上限，权限和工具等待单列。