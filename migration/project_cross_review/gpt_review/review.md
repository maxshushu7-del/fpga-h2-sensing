# 实际比赛工程 RTL 审查

本轮确认 **1 项 P2 功能缺陷**：自动扫描最后一个点成为端点最小值时，状态机仍使用上一点的最小值位置进行凹谷资格判断，可能把没有内部凹谷的单调响应带入伺服状态。没有修改生产 RTL、输入快照或原工程，没有连接板卡。

来源为 `sensor_integrated_20261018` 的实际代码快照；输入清单全部 39 项 SHA-256 与 manifest 相符，见 `input_hash_check.json`。审查只使用本轮 inputs，不读取其他评审或 validation。UTC 起点为 2026-11-02T13:12:19.5872231Z；UTC 结束为 2026-11-02T13:25:53.9914253Z。

## GPT-001 · P2 · 扫描终点的新最小值没有参加端点拒绝判断

- 文件：[auto_lock_fsm.v:109](E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/inputs/rtl/laser/auto_lock_fsm.v:109)，相关逻辑为 103–113 行。
- 实际触发：正向扫描的最后一点 `scan_code==SPAN` 出现新的最小值，而上一点的 `min_code` 仍在内部。103–106 行通过非阻塞赋值写入本点极值；109 行检查的 `min_code`、`contrast` 仍属于此前的扫描点。113 行计算半高时也尚未包含最后一点。
- 预期：既然完整扫描的最小值在 `+SPAN`，应按现有端点拒绝分支进入 `RETRY_WAIT(7)`、`last_reason=1`，保持 `servo_enable=0`。
- 实际：完整扫描最终 `min_code=1024`，却进入 `LOCKING(6)`、`last_reason=0`、`servo_enable=1`。这证明了错误的扫描接受与伺服使能；本测试没有证明真实光学锁定，`servo_valid` 始终为 0。

复现使用未修改的实际 `auto_lock_fsm.v`，保留生产 `SPAN=1024`、`STEP=2`。仅将 `SETTLE_CLOCKS=0`、`AVG_LOG2=0` 缩短单元测试时间，`NO_SAMPLE_CLOCKS=1000000` 防止本测试超时。时钟周期 10ns，复位保持五个下降沿后 `rst=0, arm=1`；`dac_at_goal=1, adc_valid=arm`；每个下降沿输入 `adc_sample=3000-(dac_code+1024)`。ADC 随 DAC 单调递减，范围 952–3000，且没有削顶；不使用 force 或内部状态写入。

实际日志：

```text
FINAL_SWEEP t=20555000 sample=952 old_scan_min=954 old_min_code=1022 old_contrast=2046
RESULT state=6 reason=0 min_code=1024 scan_min=952 scan_max=3000 selected_code=-2 setpoint=1978 servo_enable=1
REPRODUCED: monotonic decreasing response with positive-edge minimum was accepted into LOCKING; expected RETRY_WAIT reason=1.
```

证据：[复现 TB](E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/gpt_review/laser/tb_auto_lock_endpoint.v)、[真实仿真日志](E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/gpt_review/laser/endpoint_run.log)。

最小修正建议：先由本点 `average/scan_code` 计算完整扫描的下一版 `min/max/min_code`，再统一进行 contrast、端点及 half_level 判断；或增加一个扫描结束状态，等本点寄存器更新后再判断。保留该单调响应作为拒绝回归。此次只提出建议，没有改 RTL。

## 已实际运行的验证

| 检查 | 实际结果 | 证据 |
|---|---|---|
| 既有 spectral_estimator TB | 18/18 通过；16bin、29bit，含负频、DC、畸形帧、重复帧、插值与大数值 | fft/estimator_existing.log |
| 新增生产尺寸谱估计单测 | 4096bin、29bit、1MHz，5/5 通过；零点正负 1/4bin、wrapped 负频、提前 TLAST 无效、随后新完整帧恢复 | fft/estimator_production.log |
| FFT 封装握手单测 | 4096 次样本接受、1171 次停顿；正确 TLAST、早 TLAST 错误检测、复位清除并重配置通过 | fft/wrapper_boundary.log |
| 既有结果 UART 引脚解码 TB | 5 个完整 64byte 包通过，覆盖模式、正负偏移、待发覆盖、丢包计数 | fft/uart_existing.log、fft/uart_pin_bytes.hex |
| 既有自动锁定 FSM TB | 扫描捕获、失锁重扫、平坦输入拒绝通过 | laser/existing_fsm_run.log |
| 既有自动锁定 UART TB | 状态输出解码通过 | laser/uart_run.log |
| 新增 PI2D 单测 | 比例正负及限幅、积分界限/恢复、抗饱和、零执行器比例、K2 二阶差分通过；十个处理阶段逐一 clear 均撤销在途输出 | laser/pi_run.log |
| 扫描末点新最小值 | 确认 GPT-001，不属于通过项 | laser/endpoint_run.log |

命令与编译/展开/仿真日志见 [commands.md](E:/Codex/FPGA/workspace/report_targeted_revision_20261102/project_cross_review/gpt_review/commands.md) 及 laser 的重放脚本。PI 单测初版检查器在 clear 边沿同一时间槽检查组合 ready，产生一次 delta-cycle 采样错误；修正测试检查器后重新通过，初始日志保留为 `laser/pi_run_initial_checker_delta_issue.log`，不将其列为 RTL 缺陷。

## 静态审查范围与限制

静态检查了 measurement_improved 的粗/低/细模式选择、同次 NCO 中心与有符号 fine 偏移的组合、发布模式锁存、跟踪后检查、序号与超时恢复；spectral_estimator 的帧次序/last、功率、负频与插值；fft_stream_improved 的输入握手及粘滞错误。上述检查未再确认其他功能缺陷。

锁频检查覆盖 auto_lock_fsm、pi2d_controller、servo_scheduler、laser_lock_top 及相关接口调用。ARM 撤销在实际自动锁定调用关系中伴随 servo_clear；未把单独推演的 busy 粘滞情形列为真实集成缺陷。servo_scheduler 与 laser_lock_top 的完整链路主要为静态审查，未声称已完成全部集成时序验证。

输入快照不包含生成的 fft_core IP 与系数文件，而测频 RTL 的 readmemh 路径指向原工程。为遵守只读 inputs 的范围，本轮没有运行依赖这些文件的完整测频链路 TB，也没有读取或写入那些原工程路径。4096bin 谱估计测试直接输入合成频谱，FFT 封装测试使用明确标注的非 DSP 握手替身；二者都不是 4096 点 FFT 变换、完整 DDC 测频链或真实光学锁定验证。执行器标定及外部电压转换未作判断。

