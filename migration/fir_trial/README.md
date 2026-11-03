# 定点 FIR：技能包第一次新任务试用

本任务用于检验可复用工程流程，不是氢气项目的新功能。它独立包含规格、参考、RTL、testbench、故障变体生成、运行入口与证据。

先读 [验证报告](report.md)，详细规则见 [数值与接口契约](contract.md)。[工作流应用记录](workflow_record.md)解释本轮如何使用技能、遇到了什么问题及仍不能证明什么。

## 复现

需要 Windows PowerShell、Python 3.10+ 标准库和可用 Vivado Simulator。本机实际使用 Vivado 2024.1；其它版本与带空格路径未验证。

从本目录运行，将参数换成自己的工具位置：

```powershell
./run.ps1 -VivadoBin 'path/to/Vivado/bin' -Python 'python'
```

加 `-Implementation` 执行额外 OOC 综合/布局布线。示例器件固定在 implement.tcl 中，为 xcau15p-ffvb676-2-i；这是模块内部路径检查，不提供板外I/O模型或bit文件，不是跨板卡测试。

每次运行生成新的 verification/run_时间戳 目录，不覆盖旧记录。内部流程为参考自检→固定种子向量→正常实现→3个显式故障变体→恢复正常实现。所有实际数据均由真实RTL仿真产生，不用Python输出代替DUT。

summary.json汇总的是仿真分支；额外实现应另查 implementation/implementation_complete.txt 和实际报告，不能因仿真PASS就宣称实现或实板通过。

## 原样复用和任务适配

- tools/compare_vectors.py 是技能包比对工具的原样副本。
- 复用技能里的契约、参考/反例、逐周期检查、最小修改和重跑规则。
- FIR算法、数值格式、固定延迟、复位语义、参考、向量和testbench是本任务适配层，不声称通用脚本可以自动生成这些内容。
- 原工程未被修改，未连接硬件。作者也是执行者，因此不是陌生队伍试用或独立AI评测；没有有/无技能对照。
