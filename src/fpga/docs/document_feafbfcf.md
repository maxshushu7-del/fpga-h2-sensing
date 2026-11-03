> 历史 V3 时序设计说明：V4 保留 875ps 相位和数值约束，但 V4 需重新编译并生成自己的最终 STA 报告。

# V3（V2 CDC 保留，针对最后一个 DAC STA 问题）

## 先前真实报告
2026-11-01 V2（Vivado2024.1，xcau15p-ffvb676-2-i）：WNS = -0.019 ns，TNS = -0.082 ns，12 个 DAC 时序端点违例。其余所有已约束时序组满足。DAC 专属 Hold 最差 +0.212 ns（**不是**全局 WHS +0.011 ns）。

## 本版唯一用于时序收敛的硬件改动
`rtl/servo/laser_lock_hw_top.v` 中 `hw_ad9122_tx` 的 `DCI_DELAY_PS` 从 **750.0 ps 改为 875.0 ps**。数据源代码、FFT、PID、UDP CDC、网络物理层、board XDC、DAC 输出 delay 2.100 ns/1.200 ns 都没改变。2.100ns 属于当前工程的暂定外部时序预算，并非从真实原理图签核得到的精确数值。没有 `set_false_path` DAC，没有降级 DRC，没有改变时钟周期。

给定 DAC 时钟周期 4000ps，`CLKOUT1_PHASE = 875/4000*360 = 78.75°`。`CLKOUT1_DIVIDE=4`，固定相位步距 `45°/4=11.25°`，所以 78.75°=7×11.25°，是可实现的 MMCM 配置。历史的 800ps=72° 不是整数步进，曾触发 DRC AVAL-168。

按 V2 **同一物理布局**线性估算：Setup 约 -0.019+0.125=+0.106ns；DAC 专属 Hold 约 +0.212-0.125=+0.087ns。**仅预测，物理重新布局后可能不同，绝不能写成 Vivado 已实测通过。** 全局 Hold 最差由 FFT 内部路径决定，不能简单减去 125ps。

## 必须验证
- `00_create_and_build.cmd` 自动全新创建 Vivado 2024.1 工程、合成、实现、Bitstream、生成 `results/final_timing_summary.txt`、`results/V3_TIMING_STATUS.txt`。
- 以实际 `WNS>=0, TNS=0, WHS>=0, THS=0, WPWS>=0, TPWS=0` 为准；任何负值都说明 **STA 未通过**。若不通过，上传这两个 TXT、若需要再给 30 条 worst paths。不要再随意改相位（1000ps可能越过 Hold 余量）。
- 即便出现 STA PASS，`check_timing no_output_delay` 仍提示若干网口输出没有按照 JL2121 PHY 最坏值加板上走线偏斜约束。硬件实际 RGMII 时序未签核，不能称为所有物理接口时序“完美”。
- TEC200 仍为虚拟温度模型，无真实加热输出。UDP TX 为未经过实物收包验证的演示代码。

## V3 是完整独立 ZIP
只解压到新目录（例 `C:\FPGA\ContestAllV3`），双击批处理。无需旧 XPR，无需叠加任何补丁。旧 V2 原样备份保存。
