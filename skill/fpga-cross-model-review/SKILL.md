---
name: fpga-cross-model-review
description: Review an RTL change with separate implementation and critique roles, turn disputed claims into checkable counterexamples, and preserve baseline-versus-candidate regression evidence. Use for a scoped FPGA patch or a reproducible suspected defect; does not certify physical loop stability or board timing.
---

# 跨模型审查与反例验收

用于已有RTL的局部修复或补丁审查。模型品牌可以互换；目标是可复查的行为证据，而非让两个模型互相认可。

## 处理方式

1. 固定原版源码与关键依赖，记录哈希、参数、接口及验收条件。使用隔离候选，保留原始失败输入和原工程。对照[任务卡](assets/review_contract.md)只补影响结论的信息。
2. 实现角色给出最小补丁、预期行为和自测；审查角色逐项提出位置、触发条件、预期及可证伪理由。定向复审可以给出缺陷背景；需要盲审时不提供嫌疑位置、修复思路或通过日志。记录实际采用的方式。
3. 先检查质疑本身：输入序列是否满足声称的极值、符号、幅差和阈值，断言是否由契约推出。不要直接运行或采纳自相矛盾的示例，也不以另一模型措辞肯定程度决定结果。
4. 在获准执行与依赖齐备时，用同一个反例对照原版与候选，再运行受影响的既有回归。按实际有效握手与状态更新时刻取样。保留首个失败、完成标记和错误计数；测试器的错误单独处理。
5. 归档每条意见的状态：静态疑点、已复现缺陷、补丁回归通过、或因输入/预期不成立而纠正。新增意见没有运行时保持静态状态。用户只要求审查或停止测试时，交付现有证据与后续建议，不继续扩展测试。

## 产物和边界

产物包括原版哈希、候选差异、审查输入与原始回复、意见裁决、可复现输入、旧新结果、回归及依赖说明。证据见[本轮真实工程实例](references/actual_case.md)。

验收同时检查缺陷反例和既有行为；只有静态审查时不写“已通过仿真”。需要新的ADC、执行器、光学或热模型时，分别评价物理模型和RTL，不由数字通过推断真实装置锁定。补丁功能通过也不能继承旧版综合、布局布线或板级指标。
