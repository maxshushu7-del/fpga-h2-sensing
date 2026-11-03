# 三本AI工程手册怎么用

Skill像菜谱：把材料、顺序、检查办法和最后要交的东西写清楚，让下一位使用者也能按同样方式做。

| 手册 | 通俗用途 | 入口 |
|---|---|---|
| 定点RTL数值与接口验证 | 检查程序算得对不对，数据有没有在该来的时候来 | [SKILL.md](fpga-rtl-verification/SKILL.md) |
| Vivado资源与时序诊断 | 看工具报告，找占地方多或速度不够的原因 | [SKILL.md](fpga-vivado-diagnosis/SKILL.md) |
| 跨模型审查与反例验收 | 请另一位AI挑问题，再检查它举的例子是否真的成立 | [SKILL.md](fpga-cross-model-review/SKILL.md) |

使用时选对应手册，将SKILL.md及其引用模板交给AI，再提供自己的代码或报告。数值契约、时钟和预期先确认；让模型给出可检查的产物，并保留失败、修正与回归。不同模型可交换实现与审查角色，新聊天用于隔离上下文，不是独立的算法创新。

本版主要材料见[真实工程案例](../migration/project_cross_review/README.md)：39文件快照、FFT测频分层验证和锁频终点候选的旧新对照，另有DeepSeek定向静态复审及执行侧裁决。FIR迁移保留1358周期、2199项检查、718个有效结果及三类显式故障检出，支持流程迁移，不冒称陌生团队或跨板卡验证。

原[模型四条件方法](references/model_comparison_workflow.md)和[流程预试](cases/trial_20261102.md)只作前期附录。它们不用于替代本版实际FFT/锁频案例，也不提供模型排名或固定节时结论。
