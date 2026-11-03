# 真实比赛工程独立实际回归
生成UTC：2026-11-02T13:25:49.228013+00:00。工具：Vivado Simulator 2024.1。

输入快照与 source_manifest、原工程逐字节 SHA-256 一致：True（39个文件）。原工程、原日志与输入快照均未写入。未读取两份审查结论。全部新增文件与运行目录位于 validation。

| 回归 | 范围 | 实际完成标记 | 结果 |
|---|---|---|---|
| spectral_existing | 16点缩短FFT参数、29位生产字宽，既有TB | ALL 18 SPECTRAL ESTIMATOR TESTS PASSED | PASS |
| auto_lock_existing | 真实auto_lock_fsm，缩短扫描时序，捕获、失锁重获、平光拒绝 | PASS AUTO_FSM auto-acquire, loss/reacquire, flat-signal rejection | PASS |
| spectral_4096 | 真实spectral_estimator，FFT_LOG2=12、W=29；细测1MS/s复杂输入、粗测250MS/s实输入；默认生产功率阈值 | ALL 19 PRODUCTION 4096 SPECTRAL CASES PASSED | PASS |
| fullchain_5mhz_quoted_args | 真实ADC采样→粗FFT→NCO混频→4级CIC250倍抽取→4096点细FFT→估计器→频率重构 | TEST_DONE passed=1 errors=0 results=1 | PASS |

新增4096点TB独立喂入有效FFT输出格点，没有替换RTL算法。19例覆盖正负频偏、跨DC两侧、DC-only与实通道拒绝、Nyquist、缺失/过早TLAST、bin顺序错误、frame_bad、零输入、valid间隔、post-processing期间重叠违规及每次无效后的恢复。日志记录20个输入帧、79872个有效格点；其中早TLAST帧只有2048格点，其他19帧均4096格点。

细测正频例：bin123、deltaQ16=16384，输出30090Hz；负绕回例：bin4095、deltaQ16=-16384，输出-305Hz；跨DC输出±61Hz。粗测正频同时校验7522583Hz。逐项输出和实际输入计数见 spectral_4096/simulate.console.log。

## 全链范围与依赖
运行直接编译 inputs/rtl/measurement 的五个原始RTL文件。AMD fft_core.vhd（4096点生成包装器）、既有tb_measurement_improved.sv、glbl.v复制到单独依赖目录，哈希见 dependencies_manifest.json。AMD预编译FFT/IP库来自本机Vivado 2024.1。RTL原有绝对路径只读加载原工程 hann_4096.mem 和 ddc_sine_1024.mem，其SHA-256一并记录。

全链使用 ALGORITHM_VERSION=3、FFT_LOG2=12、WINDOW_ENABLE=1、实际模型250MS/s ADC/100MHz处理时钟，5MHz正弦输入，150Hz TB容差。+FULL_FFT_CLOCK=0只在FFT无事务的捕获期暂停AMD行为模型时钟；ADC、处理、CIC与4096个新样本始终按原速运行。本次没有完成FULL_FFT_CLOCK=1交叉回归，不宣称该模式已验证。

实际全链输出：
```text
SIM_CLOCK_POLICY full_fft_clock=0; only idle FFT model may pause, ADC/proc/CIC always full clock
RTL_RESULT version=3 n=4096 window=1 mode=0 target=5000000.000 valid=1 hz=5000000 coarse=82 peak=4076 delta=-9 fine_hz=-4883 power=34684531037 noise=3879 flags=08
TEST_DONE passed=1 errors=0 results=1
```

对实际spectrum.csv追加独立复核：8192行，粗/细各4096格点，两组bin均严格0..4095且实虚分量均为数字；结果True。完整证据及CSV哈希见fullchain_spectrum_evidence.json。

## 可重跑入口和证据
`run_validation.py`执行三组模块测试；`run_fullchain.py`执行单例全链；`collect_report.py`校验哈希并汇总。每组目录的commands.jsonl包含真实命令、工作路径、UTC、退出码、耗时；compile/elaborate/simulate.console.log保留真实输出；result.json仅在完成PASS标记存在且没有fatal/error/FAIL且各步退出码为0时标为通过。

初次全链尝试 fullchain_5mhz 的展开命令因Windows批处理把未引用的NAME=VALUE拆开而失败（Cannot find design unit work.3）。该尝试和日志完整保留；只修正运行入口参数引用，未改RTL，随后在新目录fullchain_5mhz_quoted_args重跑。该启动器失败不是RTL反例。

自动锁频TB属于数字状态机功能回归，使用简化光响应方程与加速时间参数；没有真实光学系统、PI2D闭环、DAC/ADC模拟器件或板卡验证。单例测频全链通过也不能扩展为动态跳频、全部故障恢复、硬件时序或实际精度验收。
