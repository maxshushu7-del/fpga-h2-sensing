# SWEEP 终点修复候选

隔离候选，DeepSeek定向静态复审已归档；其意见与执行侧裁决分别见../deepseek_review/patch_review_response.md和review_disposition.md。原工程和 inputs 未修改。只修复 `auto_lock_fsm` 在 SWEEP 最后一个平均采样点尚未提交寄存器时，使用旧 min/max/min_code 进行资格与半高值计算的问题；FIND、PI 和锁定逻辑保持原代码。

交付：

- `rtl/auto_lock_fsm.v`：单文件候选。
- `auto_lock_fsm.patch`：相对于工程 `rtl/laser/auto_lock_fsm.v` 的统一差异，净增加8行（10增、2删）；已通过 git apply --numstat 解析。
- `source_hashes.json`：原快照、候选、补丁 SHA-256。候选为 `1f38ffe3037864db72059dec983717f2b6487babb30b4cef2344cb5a7f516bf8`，原快照仍与 source_manifest 相符。
- `commands.ps1`：四组 Vivado 2024.1 重放，显式使用 E: 目录；每组保留 compile.log、elaborate.log、run.log。
- `logs/run_summary.log`：真实命令、实际所编译的源哈希、UTC起止与四组运行结果。
- `tests/`：端点/最后新最大值边界测试，以及从既有 AUTO_FSM 测试改编的生产参数回归。

修复将本点 average 纳入 sweep_min_next/sweep_max_next/sweep_min_code_next，再用这些完整扫描值计算 contrast 与 half_level。17位中间加减保留符号与范围。

| 测试 | 旧版对照 | 候选结果 |
|---|---|---|
| 单调下降 `ADC=3000-(DAC+1024)` | min_code=1024 却 LOCKING、servo_enable=1 | RETRY_WAIT、reason=1、servo_enable=0 |
| 单调上升 `ADC=952+(DAC+1024)` | RETRY_WAIT、reason=1、servo_enable=0 | 保持相同拒绝结果 |
| 内部最小990、此前最大1000、终点新最大1090 | 使用旧contrast=10拒绝 | 使用完整contrast=100接受到FIND_WAIT，half_level=1040 |
| 原 AUTO_FSM 捕获、失锁、重获、平光拒绝 | 4项通过 | 4项通过，setpoint1650/selected0/min_code2/contrast630与旧版一致 |

端点单测保留生产 SPAN=1024、STEP=2、MIN_CONTRAST=24，仅缩短 SETTLE_CLOCKS=0、AVG_LOG2=0。生产跨度回归保留全部生产参数默认值（包括 AVG_LOG2=2、STABLE_SAMPLES=64、LOST_SAMPLES=256），仅缩短 SETTLE_CLOCKS=2、RETRY_CLOCKS=10，扩大测试等待上限。

四组数字单元仿真全部完成：UTC 2026-11-02T13:33:34.8725941Z 至 2026-11-02T13:33:57.7420987Z。这些结果验证扫描状态与数字序列，不代表真实光学闭环或硬件时序验证；未运行综合/实现。

重放：

```powershell
& 'E:\Codex\FPGA\workspace\report_targeted_revision_20261102\project_cross_review\candidate\commands.ps1'
```

只读审查报告另见 `gpt_review/review.md`、`gpt_review/review.json`；其发现 GPT-001 是本候选的唯一修复目标。
