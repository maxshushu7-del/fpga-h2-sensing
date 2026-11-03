# sat_accum_stream 实现与自测报告

## 1. 结论

`sat_accum_stream` 已按需求实现，并通过两层自测：

- Vivado xsim 自检 testbench：**PASS**（12173 次检查，0 错误）
- Python 独立回放校验（不复用 RTL 代码）：**PASS**（4041 拍全量训练/比对）
- Vivado `synth_design` 综合冒烟：**PASS**（0 error / 0 critical warning；无黑盒、无实例化 IP）

首次宣布可验收的版本与当次日志已快照到
`artifacts/acceptance_20261102T120353Z/`（含源码、脚本、日志、trace、SHA256 清单）。

## 2. 时间与可见模型版本

| 项 | 值 |
|---|---|
| 开始（UTC） | 2026-11-02T11:34:43Z |
| 开始（本地） | 2026-11-02T19:34:43+08:00 |
| 首次可验收（UTC） | 2026-11-02T12:03:34Z（xsim+Python 双 PASS） |
| 含综合的完整 PASS（UTC） | 2026-11-02T12:03:53Z → 12:05:15Z（82.2 s） |
| 本报告完成（UTC） | 2026-11-02T12:05:56Z |
| 墙钟总时长 | 约 31 分钟（其中约 16 分钟为沙箱提权等待，单列于第 8 节） |
| 工具实际计算时长 | xsim 三轮 + 综合一轮，合计约 2.5 分钟 |
| 可见模型版本 | deepseek-flash（DeepSeek Harness 运行上下文；profile=desktop，session=session-761fd6e8-be08-4665-a0cf-a6a8ab027c60，GUI http://127.0.0.1:54261） |
| 工具版本 | Vivado v2024.1（xsim/xvlog build 5076996，2024-05-22）；Python 3（C:/Users/dell/.cache/codex-runtimes/.../python.exe） |

## 3. 交付文件与哈希（本组目录内）

| 文件 | 作用 | SHA256（首次可验收版本） |
|---|---|---|
| `rtl/sat_accum_stream.sv` | RTL 实现 | `0E03B696282CE88E2A833BA25CC048A3BD58FADA49BB56206F8716D2E6B98714` |
| `tb/tb_sat_accum_stream.sv` | 自检 testbench（golden model + 定向 + 随机 + trace） | `FC47C135C6DBD3E6AD11767C45C3542560B1FF05350D460537388353223F60CF` |
| `tools/check_trace.py` | 独立 Python 模型回放/校验 | `A827B3AC52734D57BBF2AB7B46B7BF5E02EA42F0204E22F14EDD7C6EFC46726D` |
| `tools/synth_check.tcl` | 综合冒烟脚本（仅读 1 个 RTL 文件） | 见 `artifacts/manifest_20261102T120353Z.txt` |
| `run.ps1` | 运行入口（编译→精化→仿真→Python 回放→可选综合） | `7A13D3A084BB6B5C3DF79AC0D73647CFC114AF89295109F3BD975629345CBFF1` |
| `logs/` | 每次运行的真实原始日志（失败与成功都保留） | — |
| `artifacts/acceptance_20261102T120353Z/` | 首次可验收版本快照 | 全量清单见 `artifacts/manifest_20261102T120353Z.txt` |

## 4. 实现说明（不使用外部 IP）

纯 RTL，单个 `always_ff` + 组合数据通路，无 IP、无厂商原语：

- **乘积**：`p = s_x * s_k`，24 位有符号精确表示（|p| ≤ 4194304）。
- **Q1.7 舍入**：`|p|+64` 后右移 7 位（`floor`），再按 `p` 符号取反。恰好半值（|p|=64,192,…）
  因先加 64 而进 1，即“正负半值都远离零”；`p=0` 时结果为 0。`r` 用 18 位有符号，
  最大 `+32768`（`-32768 * -128` 的情形）。
- **累加饱和**：`sum = a + r` 用 20 位有符号（最大 65535），比较后钳位到
  `-32768..32767`，每个输入握手都立即饱和，状态 `a` 为 16 位有符号。
- **握手/输出级**：`s_ready = !rst && (!m_valid || m_ready)`；
  接受输入（`s_valid && s_ready`）时同一上升沿写 `m_y <= 新累加值`、置 `m_valid`；
  接受优先于同拍消费，因此“同拍消费旧结果 + 接收新输入”时 `m_valid` 保持 1、`m_y` 更新为新值；
  仅消费（无替补输入）时清 `m_valid`，`m_y` 保持；背压时两者都保持。
- **复位**：同步高有效，复位沿清 `a/m_y/m_valid`，丢弃待输出结果；复位期间 `s_ready=0`，即使
  `s_valid=1` 也不握手。

## 5. 自测内容

`tb/tb_sat_accum_stream.sv`：

- 逐拍 golden model 比对 `m_y`、`m_valid`、`s_ready`（每个时钟沿前采样）。
- 定向用例：`+0.5/-0.5` 远离零、`63/64/65` 边界、`p=0`、`128` 整 LSB、`200*127`、
  正/负饱和与从饱和回退、`-32768*-128` 产生 `r=+32768`、背压保持、消费无替补清零、
  同拍消费+接受、复位取消待输出结果、复位后从 0 重新累加。
- 4000 拍受限随机（85% 有效/75% 就绪加权，极端值 `±32767/-32768/0/±1/±64/±127/-128` 偏置）。
- 覆盖率计数断言：同拍吞吐、双向饱和、复位周期、握手次数均有最低覆盖要求。
- 逐拍导出 `sim_run/trace.txt`，由 `tools/check_trace.py` 用**独立实现**的 Python 模型
  重新推导 `s_ready/s_accept/m_fire/m_y/m_valid` 与累加值并全量比对。

## 6. 实际运行结果（原文引用）

`logs/xsim_20261102T120353Z.log`：

```
RESULT: PASS checks=12173 accepts=2296 fires=2296 both=1608 sat_pos=172 sat_neg=185 rst_cycles=9
```

`logs/tracecheck_20261102T120353Z.log`：

```
trace cycles      : 4041
accepted inputs   : 2296
consumed results  : 2296
consume+accept    : 1608
sat +32767 / -32768: 172 / 185
reset cycles      : 9
RESULT: PASS independent replay matched the trace
```

`logs/synth_20261102T120353Z.log` + `logs/synth_utilization.rpt`：

```
Synthesis finished with 0 errors, 0 critical warnings and 1 warnings.
Slice LUTs 71, Slice Registers 17, DSP48E1 1, Black Boxes 0, Instantiated Netlists 0
```

（那条 warning 是 `Synth 8-7080 Parallel synthesis criteria is not met`，属小设计无法并行的提示，不影响结果。）

运行入口 `run.ps1` 的汇总：`RESULT: PASS`，`start_utc=2026-11-02T12:03:53Z`，
`end_utc=2026-11-02T12:05:15Z`，`elapsed_s=82.2`。

## 7. 实际发生的失败与修正（原始日志均保留）

| # | 现象 | 原始日志 | 定位与修正 |
|---|---|---|---|
| 1 | `xvlog` 编译失败：`ERROR: [VRFC 10-1103] net type must be explicitly specified for 'clk' when default_nettype is none`（6 个输入端口全部报错） | `logs/xvlog_20261102T120231Z.log`、`logs/run_20261102T120231Z.log` | Vivado 的 ANSI 端口 + `` `default_nettype none`` 组合限制。移除 RTL/TB 中的该编译指令，端口声明不变。 |
| 2 | 仿真 8 条定向检查失败（逐拍 golden 比对全部通过，说明 RTL 行为正确、期望值写错）：`200*127/128...`、`back-pressure keeps m_y`、`same-cycle replacement value`、`large positive increment`、`10*127/128...` 等 | `logs/xsim_20261102T120242Z.log`、`logs/run_20261102T120242Z.log` | 测试序列缺陷：单级输出寄存器下，`m_ready=1` 且连续 `s_valid=1` 时每拍都留下一个待输出结果，紧接 `m_ready=0` 的那拍会被反压（`s_ready=0`）而丢输入；另外“复位沿前 `m_y` 不变”的检查写在时钟沿之后。修正：背压测试前先排空流水（drain），复位取消测试前先复位保证状态干净，复位检查改为验证沿后清零；RTL 未因该问题改动。 |

两次失败之后，第三次运行（`12:03:34Z`）即 xsim + Python 双 PASS；第四次（`12:03:53Z`）追加综合亦 PASS。

## 8. 权限与工具等待（单列）

- 11:34:50Z 左右首次在 E: 盘建目录被沙箱 ACL 拒绝（`workspace-write` 只允许会话工作区），
  原始报错为 `New-Item : 对路径"rtl"的访问被拒绝`。
- 提权重试获批后于 11:50:48Z 完成目录创建；**该等待约 15 分 58 秒，未计入实现与工具时间**。
- 之后会话文件策略切换为 `danger-full-access`，`edit` 工具不再需要逐次提权。
- 工具执行等待：Vivado 启动约 20–30 s/次；xsim 仿真 2–4 s；综合约 40 s。无超时、无工具崩溃。

## 9. 如何复跑

```powershell
cd E:\Codex\FPGA\workspace\report_targeted_revision_20261102\ai_trial\deepseek_ordinary
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1          # 编译+仿真+独立回放
powershell -NoProfile -ExecutionPolicy Bypass -File .\run.ps1 -Synth   # 额外做综合冒烟
```

- 全部临时文件、`sim_run/`（xsim 工作目录、`trace.txt`、`sim_sat_accum.wdb`）都在本组 E 盘目录；
  `TMP/TEMP/XILINX_TMPDIR` 在脚本内指向 `tmp/`。
- 失败时脚本返回非 0，并保留原始工具输出，不生成成功日志。

## 10. 未验证项（如实说明）

- 只做了 RTL 功能仿真（xsim）与 `synth_design` 综合；未运行 `opt_design/place_design/route_design`、
  未做时序收敛/门级仿真/上板验证。
- 综合目标器件 `xc7a35tcsg324-1` 仅为冒烟验证用假定器件，不代表竞赛板选型。
- 未使用跨时钟域、未使用 `m_ready` 组合前馈之外的时序假设；输出级到下游的组合路径只有 `s_ready`。
