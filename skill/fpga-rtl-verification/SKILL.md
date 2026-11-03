---
name: fpga-rtl-verification
description: Verify fixed-point RTL developed with AI by defining numeric and transaction contracts, comparing an independently reasoned reference, and testing numeric and protocol boundaries. Use for arithmetic, filters, estimators, and discrete controllers; does not certify physical closed-loop stability or replace CDC analysis.
---

# 定点 RTL 的 AI 协作验证

适用：算法转 RTL、定点运算错误排查、流水线修改后回归。输入为算法/需求、RTL 与目标环境；已存在的实现属于待检查对象，不是默认正确的规范。

## 使用流程

1. 先读 [工作流与提示词](workflow.md)，按 [数值与接口契约](assets/interface_contract.md) 收集本任务约束。只补影响正确性的缺项，不要求无关信息。若只是解释问题，不擅自修改代码。
2. 将单位、编码、位宽、小数位、截断位置、舍入、饱和/回绕、运算次序与状态更新时刻显式写出。协议上的“有效/接受/发布”也属于正确性。
3. 参考模型应依据算法和契约推导，配少量手算例与独立不变量；不要机械翻译 DUT 后把相同错误复制到参考中。先建立高精度算法参考，再按需要增加位准确模型。
4. 用数值边界和协议场景生成测试；固定随机种子，给出能复现的首个失败输入。闭环模块除输出误差外，还检查状态、限幅与故障撤销。
5. 按契约导出接受事务的输出。可使用 [比对脚本](scripts/compare_vectors.py) 对唯一 sample_id、顺序及选定十进制数值列做检查。它不能代替逐周期协议断言、CDC 检查或完整 DUT 仿真。
6. 根据失败分类做最小修改，再运行原用例与新增反例；用户未要求修复时，只报告诊断。通过数值测试后，另检查综合/实现是否改变延迟、吞吐与资源。

## 输入和输出

- 最小输入：算法或期望行为、接口、编码/缩放、复位与有效规则。缺失时标为未定，不猜测案例参数。
- 输出：已确认契约、参考依据、测试矩阵、复现命令、首个差异、修复/未修复状态、回归结果和未覆盖边界。
- 判断“有效输出”必须看本模块自己的 valid/ready/enable 契约；不强制所有模块采用 AXI。

## 适配与失效条件

- 新题目要替换算法、状态方程、位宽、时序及容差，不能直接套示例常数。
- 未说明定点缩放或参考自身未经检查时，不能给出“数值正确”的结论。
- 跨时钟、多速率、浮点特殊值及真实传感/执行器另需专门验证；数值一致不证明这些部分安全。
- 对估计器，允许误差需由需求/参考精度给定，不能按 DUT 的现有误差反向放宽。
- 物理模型简化时，明确模型与真实对象的差异。仿真稳定不等于真实闭环稳定。

## 已验证效果的当前边界

CSV工具已有14项合成自动测试。[FIR迁移试用](../validation/fir_trial.md)正常RTL精确比对通过，3个显式故障变体被拒绝，恢复后回归通过。本轮进一步使用实际联合工程的谱估计器、粗细FFT测频链、PI2D与自动锁频源码；具体层级和已有原始日志见[真实工程案例](../../migration/project_cross_review/README.md)。自然发现的锁频终点缺陷与FIR显式故障分开计数。DeepSeek只做定向静态补丁复审，不提供独立硬件验证或Skill普遍增益结论。

## 本轮补充材料

需要同题试用其他模型或工作方式时，阅读[模型与方法对照手册](../references/model_comparison_workflow.md)。定点测试中出现限幅、参考或接口期望问题时，参考[本轮经验](../cases/trial_20261102.md)，按任务适用性选择检查，不增加无关流程。

需要跨模型复审局部补丁时，使用[跨模型审查与反例验收](../fpga-cross-model-review/SKILL.md)，并检查其反例自身是否成立。
