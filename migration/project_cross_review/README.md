# 实际FFT/锁频的跨模型审查案例

本目录是2026-11-02已完成过程的轻量归档。输入是真实sensor_integrated_20261018工程及既有测试；没有人为埋入缺陷。保留源文件、日志、脚本与最终意见，不附Vivado编译缓存、可执行文件或工具库。

## 先读哪些材料

1. inputs/source_manifest.json：39份原始快照的来源与SHA-256；目录中的源码逐字保留。
2. gpt_review/review.md：GPT自然发现的扫描终点旧极值问题与已运行检查。
3. candidate/README.md、auto_lock_fsm.patch及logs/run_summary.log：隔离补丁和旧新对照，生产工程未被覆盖。
4. deepseek_review/followup_patch_review.md、patch_review_response.md及review_disposition.md：另一模型的定向静态复审、原话和执行侧裁决。它没有独立运行仿真，部分示例自身不成立，未直接采纳。
5. validation/report.md：独立执行的估计器回归与5MHz粗细FFT全链。PI2D自测在gpt_review/laser，来源分别保留。

## 已有结果与层级

- 估计器直接输入频谱：既有16点18例、新增生产4096点19例通过；不把它们称为FFT变换全链。
- 实际AMD FFT模型全链：5MHz→4096粗FFT→DDC/CIC250倍→4096细FFT→valid=1、5000000Hz，spectrum.csv共8192行。只在无事务期间暂停FFT行为模型时钟，ADC/处理/CIC持续运行；未在本轮作全时钟策略的等价复跑。
- PI2D：14项数值场景，以及10个处理阶段逐一clear取消在途输出。
- 锁频候选：终点最小和新最大值边界，以及生产扫描跨度的捕获、失锁、重获、平光四项回归。

以上属于软件RTL与模型验证。候选没有重新综合、布局布线或上板；不表示真实激光闭环已通过，也不能替换原版时序基线。

## 如何重放

已有日志不需要再次运行即可核查。用户要求停止新增测试后，本次打包仅做文件、哈希、语法与压缩完整性检查，没有再次运行RTL。

可移植单元入口为candidate/replay_candidate.ps1与validation/replay_units.py：均从相邻inputs读取源码，要求显式指定一个新的输出目录以保留历史日志，Vivado工具目录可以传入。它们由已有运行命令作路径适配，已作静态语法检查；本次没有重新运行适配版，已有通过结果对应历史原版入口。

```powershell
# 示例：修改工具路径，输出到新的E盘目录后手动执行。
./candidate/replay_candidate.ps1 -VivadoBin 'E:/Xilinx/Vivado/2024.1/bin' -OutputRoot 'E:/Codex/FPGA/workspace/skill_replay_fsm_01'
python ./validation/replay_units.py --vivado-bin 'E:/Xilinx/Vivado/2024.1/bin' --out 'E:/Codex/FPGA/workspace/skill_replay_units_01'
```

历史candidate/commands.ps1、validation/run_validation.py、run_fullchain.py以及gpt_review中的脚本保留当时E盘绝对路径，只能在匹配路径和依赖的环境重放；不能直接将它们当成异机一键运行入口。

全链另需Vivado2024.1对应的xfft_v9_1_12等库，详见fullchain_5mhz_quoted_args/dependencies_manifest.json、commands.jsonl和附带fft_core.vhd。系数另存dependencies/coefficients；原版RTL的readmemh仍指向原工程E盘绝对位置。迁移全链时应在隔离副本中改系数路径、启动脚本的工程根与输出根，记录新的源码哈希，然后重新验收；不要覆盖原始快照并继续使用旧哈希。工具库按安装环境提供，压缩包不含Vivado或商业IP库。

## 记录说明

原始失败入口与测试器采样错误保留在日志中；启动引用问题不计为RTL缺陷。DeepSeek复审不是GPT/DeepSeek盲评，也不是模型能力排名。裁决仅核对已存在证据和静态输入矛盾，没有把建议当作新增测试通过。
