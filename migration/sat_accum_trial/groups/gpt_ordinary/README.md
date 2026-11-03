# sat_accum_stream 独立实现与自测

状态：已通过 Vivado 2024.1 XSim 行为仿真，可提交独立验收。

## 文件

- `sat_accum_stream.sv`：可综合 SystemVerilog RTL，无外部 IP。
- `tb_sat_accum_stream.sv`：独立整数除法参考模型，每拍检查 ready、valid、y；检查上升沿前寄存输出保持。
- `run_test.py`：编译、展开、仿真入口；使用本机 Vivado 2024.1，生成内容全部留在本目录。
- `compile.log`、`elaborate.log`、`simulate.log`：最终原始日志。
- `test_summary.json`：实际执行时间、命令、返回码、RTL 和测试文件 SHA-256。
- `attempt1_*`：首次运行的编译成功和工具链展开失败证据。
- `attempt2_*`：首次仿真通过时的自测版本与日志。
- `diagnostic_elaborate.log`：展开失败的详细诊断原始日志。
- `first_ready/`：首次宣布可验收时冻结的 RTL、自测、入口、最终日志和校验清单。
- `task_metadata.json`：开始/结束 UTC、模型标识可见性和实际失败修正记录。

## 实现

乘积使用 24 位有符号数，取绝对值前扩为 25 位。绝对值加 64 后右移 7 位，再恢复符号，故正负半值均远离零。舍入值保留 +32768，使用 18 位有符号加法后钳位到 16 位，不提前饱和舍入值。

每次输入握手同时更新累加状态和单级输出寄存器。`s_ready = !rst && (!m_valid || m_ready)`，支持同拍输出消费和输入替补。同步复位优先；背压以及没有输入握手时保持累加状态和 y。

## 实际验证

最终结果：PASS，757132 拍，388813 次输入握手。编译、展开、仿真返回码全部为 0。

- 所有 65536 个输入 x，分别使用 k=-128、127、-1、1，逐样本复位以直接观察舍入结果。
- 全部 256 个系数与 x=-129..129 的组合。
- 极值组合、正负半值、舍入值 +32768 的非提前饱和检查、正负累加饱和及反向离开饱和。
- 空输出接收、持续背压、消费并替补、无替补清 valid、无输入时 y 保持、待输出被同步复位取消、复位前半周期保持。
- 固定种子 0x61eac4b9 的 100000 拍随机输入/valid/ready/reset。
- 19467 拍背压，45006 次同拍消费替补，2503/2518 个正/负半值，5780/5817 次正/负溢出钳位。

没有执行综合、布线、时序分析或板级验证；没有读取其他候选组和 acceptance 目录。

## 实际失败与修正

1. 目标目录最初不存在；目录创建在受限权限下被拒绝。仅对本组 E 盘目录取得写授权，并通过授权执行创建后继续。
2. 首轮 xvlog 编译成功，xelab 在调用内置 MinGW gcc 时失败，报 XSIM 43-3409/43-3915。详细日志显示 `The system cannot execute the specified program.`，单独受限调用 gcc 报“无效的系统 DLL 重定位”。同一 gcc 在授权的正常执行中 `--version` 成功，因此使用授权正常执行运行同一 RTL 和自测，编译/展开/仿真通过。
3. 未出现 RTL 数值或握手断言失败，RTL 从首版到验收版未修改。首次仿真通过后，增加同步复位半周期保持断言与 a=-1 加 r=32768 的定向用例，重新运行通过；这是验证覆盖补充，不记为 RTL 修复。

运行入口：

```powershell
& 'C:/Users/dell/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/python.exe' 'E:/Codex/FPGA/workspace/report_targeted_revision_20261102/ai_trial/gpt_ordinary/run_test.py'
```

本机内置 gcc 在受限运行环境中不能启动；复现应使用已授权的正常工具执行。实际模型 ID 未从环境暴露，组名 gpt_ordinary 不是可核验模型标签。
