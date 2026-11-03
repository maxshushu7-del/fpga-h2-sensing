# 大模型协作与可迁移经验

## 真实FFT与锁频案例

固定39文件源码快照 → GPT审查FFT/锁频 → 构造失败输入 → 候选最小修复 → DeepSeek定向复审 → 人工核对接口和预期 → 运行回归。

- [案例与重放入口](../../migration/project_cross_review/README.md)
- [原始任务](../../migration/project_cross_review/gpt_review/task.md)
- [GPT审查及运行证据](../../migration/project_cross_review/gpt_review/review.md)
- [DeepSeek复审请求](../../migration/project_cross_review/deepseek_review/followup_patch_review.md)
- [DeepSeek原回复](../../migration/project_cross_review/deepseek_review/patch_review_response.md)
- [逐条裁决](../../migration/project_cross_review/deepseek_review/review_disposition.md)
- [验证结果](../../migration/project_cross_review/validation/report.md)
- [FIR迁移](../../migration/fir_trial)

另见[UDP接收适配案例](udp_adapter_case.md)与本次执行日志。

## 人与AI的分工

人确定光学原理、硬件接线、电平、验收目标和实验条件；AI整理接口、编写候选与测试、读工具报告和准备复现材料。模型给出的反例也要验算；两个回答一致不能代替程序通过。

上下文隔离是让审查者先看同一份代码和接口，减少被原解释带偏。快照是冻结审查输入，确保后续改动与回归针对同一份文件。旧新只保留与具体缺陷有关的对照，不做模型能力排名。

## Skill提炼

三项可复用Skill见[入口](../../skill/README.md)：定点RTL验证、Vivado诊断、跨模型反例审查。每项记录输入、步骤、脚本、输出、验收、失败条件与经验来源；FIR用于检查换任务后的流程适用性。完整材料随独立Skill压缩包提供，报告内保留过程和结论。
