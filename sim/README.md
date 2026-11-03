# 仿真与验证入口

| 对象 | 入口 | 结果 |
|---|---|---|
| V4 UDP报文与以太网帧 | `../src/fpga/sim`、`../src/fpga/tests`、`../src/fpga/scripts/udp_sim.tcl` | 原工程测试入口 |
| UDP图形接收器 | `../src/host/gui/test_v4_integration.py`、`test_udp_protocol.py` | [12项运行日志](results/host_udp_tests.txt) |
| 实际FFT、PI²D、扫描状态机 | [跨模型案例](../migration/project_cross_review/README.md) | 历史源码快照、提示词、原始结果、反例及候选回归 |
| FIR技能迁移 | [fir_trial](../migration/fir_trial) | 参考与RTL比对、故障注入及边界 |
| 粗细频谱CSV | [原始频谱及来源](../data/reference) | 同次RTL输出8192行；不是新增ILA采集 |

数字模型、模块单测、全链及板级数据分别说明范围。记录工具、输入、单位、参数、命令、实际结果与退出状态，历史日志不改写为新运行结果。
