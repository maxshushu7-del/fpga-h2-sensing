---
name: fpga-vivado-diagnosis
description: Diagnose Vivado timing and resource issues with AI using versioned reports, constraint completeness, representative paths, and minimal-change regression. Use after synthesis or implementation to separate RTL, clocking, interface-model, and constraint problems; does not automatically waive CDC warnings or certify board timing.
---

# Vivado 报告驱动的 AI 诊断

适用：实现不满足时序、资源增长、报告看似通过但约束/外部接口仍不完整。输入为自己的设计目标、工具/器件版本、报告、相关约束与最小代码片段；不需要原项目背景。

## 工作方式

1. 阅读 [工作流与提示词](workflow.md)，使用 [报告卡片](assets/report_card.md) 固定本轮基线。先核对报告对应的源码、参数、约束、工具版本和综合/实现阶段，避免把不同版本结果混在一起。
2. 先判断报告覆盖范围：时钟是否定义、路径是否被检查、例外是否合理、板外输入输出模型有无依据。WNS 非负不代表未约束路径或实物接口已经正确。
3. 从真实失败路径或资源分布推导原因：数值组合路径、扇出/布线、时钟关系、输出相位、接口假设或资源结构。报告缺失时输出需要补充的证据，不编造具体原因或指标。
4. 每次提出最小、可回退的修改，说明它改变的是逻辑、延迟、物理实现还是约束模型。没有电路/协议依据，不用 false_path、异步时钟组或 multicycle 将失败隐藏。
5. 改动后重验功能、接口延迟与吞吐，再检查实现、setup/hold、资源、CDC/DRC 和仍未验证的板外条件。流水线修复后必须确认事务对齐。
6. 输出带证据的判断、备选原因、修改/未修改项、实际回归及停止条件。报告“暂定模型下满足时序”与“实板验证通过”必须分开。

## 不做什么

- 不根据资源百分比高低自动判定瓶颈；需要目标、路径/模块分布及权衡依据。
- 不因工具允许某个例外就认为例外符合电路语义。
- 不因握手仿真通过就宣称跨时钟亚稳态风险消失。
- 不把案例里的 MMCM 相位、频率或周期直接用到新板卡。
- 不把工具内部错误归因成 RTL 功能错误；保留复现和失败日志，说明替代流程改变了哪些东西。

## 适配、失效条件与当前效果

需要适配器件、时钟、工具版本、板外延迟、接口和性能目标。只有汇总 WNS 或截图、没有约束/路径时，结论只能停在初步筛查。不同实现阶段的指标不能不加说明地横向比较。

本初稿提供人工/AI 协作流程和模板，不含通用报告解析器，也未在陌生工程上证明诊断成功率。原项目案例见 [经验来源](../cases/experience_sources.md)；迁移验证尚待执行，不承诺自动修好所有工程。

新增的一次[FIR作者试用](../validation/fir_trial.md)应用了报告范围审查，识别出内部时序满足但板外端口未约束；它只是范围检查，不是另一项“失败时序到修复”的完整迁移或独立人员评测。

## 本轮补充材料

需要同题试用其他模型或工作方式时，阅读[模型与方法对照手册](../references/model_comparison_workflow.md)。定点测试中出现限幅、参考或接口期望问题时，参考[本轮经验](../cases/trial_20261102.md)，按任务适用性选择检查，不增加无关流程。
