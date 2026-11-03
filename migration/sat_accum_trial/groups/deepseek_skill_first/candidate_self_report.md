# sat_accum_stream 交付报告（Skill 流程试用）

工作目录：E:\Codex\FPGA\workspace\report_targeted_revision_20261102\ai_trial\deepseek_skill
会话 UTC 起：2026-11-02T11:40:39Z（本地 19:40:39 +08:00）
最后一次回归 UTC 止：2026-11-02T11:58:30Z
可见模型：DeepSeek Harness agent（deepseek-flash 档位），单一模型 + 一个独立审查子代理（见 §8）
工具：Vivado Simulator 2024.1（SW Build 5076996，2024-05-22），Python 3.11

## 0. 结论

- 首次可验收快照：`snapshot/v1_20261102T115704Z/`，含 MANIFEST.md（逐文件 SHA256）。
- 回归结果 PASS：2187 个仿真周期逐周期比对，**0 个周期不一致**；877 次输入握手，877 次输出发布，868 次被消费 + 9 次被复位取消，守恒闭合；结束时 m_valid=0。
- 故障注入 4/4 被拒绝（数值变异体由 Python 参考拒绝，协议变异体由 testbench 拒绝）。
- 本轮发现的 4 个问题**全部在测试/参考/脚本侧**，RTL 未因此修改；RTL 自首次通过后未再变更（哈希见快照）。

## 1. 契约（实现前冻结）

完整契约见 `docs/contract.md`，要点：

| 量 | 位宽/编码 | 范围 | 依据 |
|---|---|---|---|
| p = s_x*s_k | 24 位有符号，精确 | -4194176 .. 4194304 | 32768*128 < 2^23 |
| r | 18 位有符号（实际 -32767 .. 32768） | 见 §2 | 4194304/128 = 32768 需 17 位数值 + 符号 |
| a | 17 位存储，数学范围 -32768 .. 32767 | 每步 clamp | a+r 极值 ±65536，18 位足够 |
| m_y | 16 位有符号 | -32768 .. 32767 | 与 a 同值 |

逐周期约定：`s_ready = !rst && (!m_valid || m_ready)`；accept 优先于 consume；同拍消费旧结果与接收新输入允许；背压时 m_y/m_valid 保持；消费无替补时 m_valid 清零；复位拍 s_ready=0 且清 a/m_y/m_valid。

## 2. 参考推导（不照抄 RTL）

定义 `r(p) = sign(p) * floor((|p|+64)/128)`，r(0)=0。证明其等于"四舍五入到最近整数、平局远离零"：

- |p| = 128n + m，0 <= m <= 127。floor((128n+m+64)/128) = n + floor((m+64)/128)。
- m < 64 时 m+64 < 128 → 得 n（最近整数 n，距离 m/128 < 0.5）。
- m > 64 时 128 <= m+64 < 192 → 得 n+1（距离 (128-m)/128 < 0.5）。
- m = 64（恰好 n+0.5）时 m+64 = 128 → 得 n+1，即平局向远离零进位；p<0 时取负，同样远离零。
- 量化误差 |p - 128r| <= 64；r(-p) = -r(p)；r 关于 p 单调；r=0 当且仅当 |p| <= 63。

Python 参考 `model/ref_model.py` 的 `r_exact()` **不用**上述 floor 形式，而是用 `Fraction` 精确比较 p/128 的两个相邻整数（最近者胜，距离相等时按符号远离零），因此与 RTL 的 `sign*((|p|+64)>>7)` 是两条不同推导。二者在 271404 个样本（含所有 128n-65..128n+65 边界、全范围等距抽样）上零差异。

可达极值（16 位输入组合下）：r 最小 -32767（x=32767,k=-128），最大 +32768（x=-32768,k=-128）；r = -32768 不可达（需 |p|=4194304 且 p<0，即 x=32768 或 k=128，均越界）。

## 3. 实现

`rtl/sat_accum_stream.sv`，单个 always_ff，无外部 IP：

| 行 | 内容 |
|---|---|
| 40 | `p_w = s_x * s_k`（赋值上下文把两操作数扩到 24 位，乘积精确） |
| 41 | `mag_w = p_w[23] ? (~p_w + 24'd1) : p_w` |
| 42 | `mag_r_w = (mag_w + 24'd64) >> 7`（17 位，最大 32768） |
| 43-44 | `r_w = sign ? -{1'b0,mag_r_w} : {1'b0,mag_r_w}`（18 位补码） |
| 50-52 | `sum_w = a_q + r_w`（18 位）；上下限钳位 |
| 58-60 | `s_ready`/`accept_w`/`consume_w` |
| 66-78 | 复位优先 → accept（写 a/m_y/m_valid）→ consume（仅清 v）→ 否则全部保持 |

逻辑深度（观察，未做时序分析）：乘法 → 取绝对值/移位 → 加 → 比较钳位 → 寄存器。

## 4. 验证方法

1. **独立整数参考**：按 §2 的数学定义实现，含自检（手算表、两式交叉、奇对称、单调、误差界）。
2. **逐周期模型**：状态 (a,y,v)，每拍按契约算 s_ready、accept、consume 与次态，输出与硬件同相位的观测量。
3. **testbench**（`tb/tb_sat_accum_stream.sv`）：在 negedge 后 1ns 驱动并采样（tb:117-123），即每个上升沿前一刻，与模型同相位；逐拍比对 s_ready 公式（tb:125）、复位后清零（tb:141-142）、accept 必发布（tb:145）、消费无替补必清 v（tb:147）、无事务必保持（tb:149-150）、背压必保持（tb:153-154）、事务守恒（tb:174）。
4. **导出比对**：TB 写 `logs/dut_trace.csv`（cyc,rst,s_valid,s_ready,m_ready,m_valid,m_y），Python 模型生成期望轨迹并逐列精确比较，输出首个差异与最小重放行号。
5. **门禁**（`run/run_all.ps1`）：同时要求各步退出码 0、日志含 `TB_PASS`、日志无 ERROR/FATAL 行、Python 比对退出 0。**不信任裸退出码**——故障注入中 M3/M4 的 xsim 退出码为 0 却判定 TB_FAIL，只看退出码会把错误当通过。

## 5. 测试矩阵与实测结果

激励 2187 周期（`stim.txt`，种子 20261102，其中 2000 周期随机；`logs/stim_meta.txt`）：

| 段 | 周期数 | 检查点 |
|---|---|---|
| 空闲/单事务/背压保持/消费 | 12 | s_ready 公式、保持、消费清零 |
| 同拍消费+接收（连续 3 拍） | 4 | 旧值被消费、新值当拍写入 |
| 背压中 s_valid 持续为高 | 4 | 不接收、m_y/m_valid 保持 |
| 舍入边界（0, ±1, ±63/64/65, ±191/192, ±255/256, k=0/±128/127） | 30 | r 精确、-0 输出为 0 |
| 手算例 1-12 重放（每例先复位） | 60 | 契约 §7 逐值 |
| 饱和行走（+sat 保持、-sat 保持、回升） | 53 | 立即饱和、不回绕、饱和后保持 |
| 复位（取消 pending、rst 与 s_valid 同拍、多拍复位、空闲复位） | 15 | 复位取消与优先级 |
| 随机（x/k 含极值与小区间，valid/ready 随机，含随机复位脉冲） | 2000 | 全覆盖 |
| 排空 + 收尾保持 | 6 | 事务守恒、结束时 m_valid=0 |

实测：`cycles=2187 accepts=877 consumes=868 reset_cancels=9 protocol_errors=0 final_m_valid=0`；比对 `accepted_inputs=877 published_results=877 mismatched_cycles=0`；参考自检 `cross_formula_samples=271404 mismatch=0`、`invariant_violations=0`。

## 6. 边界与接口审查（每项给位置或反例）

RTL 侧逐项：

1. **s_ready 与复位互锁（rtl:58）**。rst=1 时 s_ready=0，故复位拍不会接收输入。反例：若写成 `(~v_q || m_ready)` 而漏掉 `~rst`，则 rst 与 accept 同拍，复位会"吞掉"一个已握手输入。测试：reset_tests 段（rst=1 且 s_valid=1 的周期）。
2. **accept/consume 优先级（rtl:71-77）**。accept 分支在前，同拍时新结果覆盖旧结果且 v 保持 1。反例：若把 consume 分支放前面，同拍消费会把 v 清 0，新结果丢失（M4 变异体即清 v 分支反向）。测试：同拍段与 rounding_edges 段（m_ready 恒 1）。
3. **背压保持（rtl:66-78 无 else 赋值）**。无 accept/consume 时不写任何寄存器。反例：若补一个 `else y_q <= y_q;` 无害，但若写成 `else y_q <= acc_w[15:0]` 则背压下 y 会随输入漂移。检查：tb:149-154。
4. **16 位切片（rtl:73）**。acc_w 已钳位到 [-32768,32767]，取低 16 位精确。反例：若上限钳位写成 32768，则 32768 切 16 位得 -32768，符号翻转（M2 变异体是下限侧的同类错误，被参考在 cyc=120 捕获）。
5. **24 位乘积（rtl:40）**。依赖赋值上下文把 16 位与 8 位操作数扩到 24 位再相乘。反例：x=-32768,k=-128 时 |p|=4194304 需 23 位数值位；若乘积按 16 位截断会得 0。手算例 10 覆盖。
6. **取负与符号拼接（rtl:43-44）**。mag_r_w 为 17 位无符号（<=32768），拼 0 后 18 位，取负在 18 位补码内合法（-32768）。反例：若把 mag_r_w 声明成 16 位，32768 会回绕成 -32768，r 的正负颠倒。手算例 10 覆盖。
7. **复位优先（rtl:67-70）**。if (rst) 在最前，与 accept 同拍时复位胜出；且因 s_ready 含 ~rst，复位拍不可能存在 accept，故不会丢失已握手输入。
8. **接口风险（非缺陷，需下游知晓）**：当 m_valid=1、m_ready=1、rst=1 同拍时，消费者在该沿会采到一个随即被复位取消的结果。契约 §4 已规定复位取消在途结果，因此消费者必须与生产者同复位。实测发生 9 次（`reset_cancels=9`）。若下游不能同复位，需要额外的事务标签/epoch，本轮未做。

Testbench 侧：采样点在 negedge+1ns（tb:117-123），位于上升沿之前，与模型观测量同相位；对丢事务（计数）、valid 移位（逐拍 mv 比较）、m_y 陈旧（背压与无事务保持检查）均有断言；M3/M4 证明协议断言具有杀伤力。

## 7. 纠错记录（4 项，均非 RTL 缺陷）

| 编号 | 症状 | 分类 | 最小反例/证据 | 修复 | 回归 |
|---|---|---|---|---|---|
| C1 | `xvlog` 把 .sv 当 Verilog-2001 解析，首次编译失败 | 工具调用脚本 | `docs/evidence/xvlog_without_sv.log`：`VRFC 10-8549 Verilog 2000 keyword 'signed'` @ rtl:19；同命令加 `-sv` 即通过 | `run/run_all.ps1` 编译命令加 `-sv` | xvlog=0 |
| C2 | 参考自检失败 `hand: x=-32768 k=127 want=-32767 got=-32512` | 契约/参考错误（RTL 正确） | p=-4161536 → (4161536+64)/128=32512.5 → r=-32512；-32767 实为 x=32767,k=-128 的值，手算表串行 | 改 `docs/contract.md` 第 11 行与 §2 极值句；改 `model/ref_model.py` HAND | 自检 0 失败 |
| C3 | `accept/consume count mismatch`：accepts=877, consumes=871 | 测试过严（未建模复位取消） | 随机段 9 次复位时 v=1，结果被取消而非消费；契约 §4 明确允许 | tb:131-137 分别计数 consume 与 cancel；tb:174 改为 `accept == consume + cancel` | protocol_errors=0 |
| C4 | 门禁把 `protocol_errors=0` 这一行判成错误行（`errors` 子串命中 `ERROR`） | 门禁脚本 | 修复前 `tool_error_lines=1`，唯一命中行即 TB_SUMMARY | 正则改为行首 `ERROR|FATAL` 或 `TB_ERROR/TB_FATAL`，区分大小写 | tool_error_lines=0 |

失败证据保存：`logs/run2_20261102T115545Z_TB_counters/`（C3 的完整失败轮日志）、`docs/evidence/xvlog_without_sv.log`（C1 可复现最小反例）。所有失败用例保留，未删除测试、未放宽规格。

## 8. 独立代理审查：未完成，不作独立结论

本轮曾启动一个独立子代理，只读审查 RTL / testbench / 参考模型，要求按 file:line 给出反例。该代理在约 17 分钟后仍未返回结果，本轮按 15 分钟预算中断，**没有产出任何审查意见**。

因此：
- 本节不提供、也不声称任何"独立代理审查"或"独立多模型交叉验证"结论。
- §6 的边界与接口审查由实现本模块的同一模型完成，其证据是文件位置与可复现反例，不是第三方意见。
- 独立性的唯一来源是**同一会话内按公式另写的 Python 参考**（§2）：它与 RTL 的位操作形式不同、由 testbench 轨迹逐周期比对，且 4 个变异体证明该比对有杀伤力。这证明"参考与实现不同源"，不等于"由独立评审者复核"。

若需要真正的独立评审，应另起一个代理或由他人复核 §6 的 8 条与 §7 的 4 条。

## 9. 未覆盖项与局限

- 未综合、未实现、未做时序分析：无 Fmax、资源、延迟数据；"逻辑深度"仅为阅读结论。
- 未做跨时钟域、板级、物理闭环验证。
- 仿真只覆盖复位窗口之后的 X 传播；未做形式化等价或代码覆盖率统计。
- 参考模型由本会话按公式推导，与 RTL 不是同一段代码，但**不是第三方独立实现**；独立代理审查见 §8，不声称"独立多模型交叉验证"。
- 复位与消费者同拍的语义依赖下游同复位（§6 第 8 条），未实现 epoch/事务标签。

## 10. 时间、权限与工具等待（单列）

| 项 | 值 |
|---|---|
| 会话 UTC 起 | 2026-11-02T11:40:39Z |
| 首次可验收快照 | 2026-11-02T11:57:04Z（日志 UTC 11:56:55-11:57:04） |
| 最后回归 UTC 止 | 2026-11-02T11:58:30Z |
| 报告定稿 UTC | 2026-11-02T12:00:03Z（总时长约 19 分钟，超出建议的 15 分钟；其中权限审批等待与一次未完成的独立审查代理占主要部分） |
| 权限等待 | 前 3 次写 E: 需要沙箱升级审批（约 19:40-19:51 本地）；19:51 后策略改为完全访问，不再等待 |
| 工具等待 | 每轮 xvlog 约 1-2s；xelab 约 2-4s；xsim 约 1-2s；整轮 run_all 约 9s；故障注入 4 个变异体约 30s |
| 环境偏差 | 本机无 `pwsh`，实际用 Windows PowerShell 5.1 执行；`run_all.ps1` 兼容 5.1 |

## 11. 交付物与复现

| 路径 | 说明 |
|---|---|
| `rtl/sat_accum_stream.sv` | RTL |
| `tb/tb_sat_accum_stream.sv` | 自测平台（协议断言 + 轨迹导出） |
| `model/ref_model.py` | 独立整数参考 + 逐周期模型 + 比对 |
| `model/stim_gen.py` | 确定性激励（种子 20261102） |
| `run/run_all.ps1` | 运行入口（含门禁） |
| `verify/mutation_check.ps1` | 故障注入检查 |
| `logs/` | 实际日志：run_summary.txt、tb_summary.txt、compare.log、xsim/xelab/xvlog.log、dut_trace.csv、stim.txt、transcript.log |
| `snapshot/v1_20261102T115704Z/` | 首个可验收快照 + MANIFEST（SHA256） |
| `docs/contract.md` | 实现前冻结的契约与手算例 |

复现：

    cd E:\Codex\FPGA\workspace\report_targeted_revision_20261102\ai_trial\deepseek_skill
    powershell -NoProfile -ExecutionPolicy Bypass -File run\run_all.ps1

期望输出末尾：`VERDICT=PASS`，`cycles=2187 accepts=877 consumes=868 reset_cancels=9 protocol_errors=0`，`mismatched_cycles=0`。