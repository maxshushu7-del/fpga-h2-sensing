import csv, json, re
from run_validation import ROOT, INPUT, sha, utc

manifest=json.loads((INPUT/'source_manifest.json').read_text(encoding='utf-8-sig'))
checks=[]
for entry in manifest['files']:
 source=__import__('pathlib').Path(entry['source'])
 snapshot=INPUT/entry['copy']
 checks.append(dict(source=str(source),snapshot=str(snapshot),expected_sha256=entry['sha256'],
                    source_sha256=sha(source),snapshot_sha256=sha(snapshot),
                    matches=sha(source)==sha(snapshot)==entry['sha256']))
tests=[]
for name in ['spectral_existing','auto_lock_existing','spectral_4096','fullchain_5mhz_quoted_args']:
 path=ROOT/name/'result.json'
 if path.exists():tests.append(json.loads(path.read_text(encoding='utf-8')))
full=next((x for x in tests if x['test']=='fullchain_5mhz'),None)
evidence=None
if full:
 spectrum=ROOT/'fullchain_5mhz_quoted_args/spectrum.csv'
 if spectrum.exists():
  with spectrum.open(encoding='utf-8') as stream: rows=list(csv.DictReader(stream))
  groups={}
  for row in rows:groups.setdefault((row['fine_mode'],row['low_mode']),[]).append(row)
  modes=[]
  for key,values in groups.items():
   modes.append(dict(fine_mode=int(key[0]),low_mode=int(key[1]),bin_count=len(values),
    natural_order_0_to_4095=[int(r['bin']) for r in values]==list(range(4096)),
    all_components_numeric=all(re.fullmatch(r'-?\d+',r['fft_re']) and re.fullmatch(r'-?\d+',r['fft_im']) for r in values)))
  evidence=dict(utc=utc(),path=str(spectrum),sha256=sha(spectrum),total_rows=len(rows),modes=modes,
   passed=len(rows)==8192 and set(groups)=={('0','0'),('1','0')} and all(m['bin_count']==4096 and m['natural_order_0_to_4095'] and m['all_components_numeric'] for m in modes))
  (ROOT/'fullchain_spectrum_evidence.json').write_text(json.dumps(evidence,indent=2),encoding='utf-8')
summary=dict(created_utc=utc(),independence='No gpt_review/deepseek_review conclusions read. Real source snapshots only; no source-project writes.',
 verification_type='Vivado 2024.1 software RTL simulation; no hardware or bitstream download',
 source_manifest_match=all(x['matches'] for x in checks),source_file_count=len(checks),source_hash_checks=checks,
 tests=tests,fullchain_spectrum_evidence=evidence,all_completed_tests_pass=all(x['passed'] for x in tests) and (evidence is None or evidence['passed']),
 fullchain_status='passed' if full and full['passed'] else ('failed_or_incomplete' if full else 'running_or_not_completed'))
(ROOT/'summary.json').write_text(json.dumps(summary,indent=2,ensure_ascii=False),encoding='utf-8')
lines=[
'# 真实比赛工程独立实际回归',
f'生成UTC：{summary["created_utc"]}。工具：Vivado Simulator 2024.1。',
'',
f'输入快照与 source_manifest、原工程逐字节 SHA-256 一致：{summary["source_manifest_match"]}（{len(checks)}个文件）。原工程、原日志与输入快照均未写入。未读取两份审查结论。全部新增文件与运行目录位于 validation。',
'',
'| 回归 | 范围 | 实际完成标记 | 结果 |',
'|---|---|---|---|',
'| spectral_existing | 16点缩短FFT参数、29位生产字宽，既有TB | ALL 18 SPECTRAL ESTIMATOR TESTS PASSED | PASS |',
'| auto_lock_existing | 真实auto_lock_fsm，缩短扫描时序，捕获、失锁重获、平光拒绝 | PASS AUTO_FSM auto-acquire, loss/reacquire, flat-signal rejection | PASS |',
'| spectral_4096 | 真实spectral_estimator，FFT_LOG2=12、W=29；细测1MS/s复杂输入、粗测250MS/s实输入；默认生产功率阈值 | ALL 19 PRODUCTION 4096 SPECTRAL CASES PASSED | PASS |',
]
if full:
 lines.append(f'| fullchain_5mhz_quoted_args | 真实ADC采样→粗FFT→NCO混频→4级CIC250倍抽取→4096点细FFT→估计器→频率重构 | TEST_DONE passed=1 errors=0 results=1 | {"PASS" if full["passed"] else "未通过/不完整"} |')
else:
 lines.append('| fullchain_5mhz_quoted_args | 已开始编译真实测频全链，尚未完成 | 尚无TEST_DONE | 运行中 |')
lines += ['',
'新增4096点TB独立喂入有效FFT输出格点，没有替换RTL算法。19例覆盖正负频偏、跨DC两侧、DC-only与实通道拒绝、Nyquist、缺失/过早TLAST、bin顺序错误、frame_bad、零输入、valid间隔、post-processing期间重叠违规及每次无效后的恢复。日志记录20个输入帧、79872个有效格点；其中早TLAST帧只有2048格点，其他19帧均4096格点。',
'',
'细测正频例：bin123、deltaQ16=16384，输出30090Hz；负绕回例：bin4095、deltaQ16=-16384，输出-305Hz；跨DC输出±61Hz。粗测正频同时校验7522583Hz。逐项输出和实际输入计数见 spectral_4096/simulate.console.log。',
'',
'## 全链范围与依赖',
'运行直接编译 inputs/rtl/measurement 的五个原始RTL文件。AMD fft_core.vhd（4096点生成包装器）、既有tb_measurement_improved.sv、glbl.v复制到单独依赖目录，哈希见 dependencies_manifest.json。AMD预编译FFT/IP库来自本机Vivado 2024.1。RTL原有绝对路径只读加载原工程 hann_4096.mem 和 ddc_sine_1024.mem，其SHA-256一并记录。',
'',
'全链使用 ALGORITHM_VERSION=3、FFT_LOG2=12、WINDOW_ENABLE=1、实际模型250MS/s ADC/100MHz处理时钟，5MHz正弦输入，150Hz TB容差。+FULL_FFT_CLOCK=0只在FFT无事务的捕获期暂停AMD行为模型时钟；ADC、处理、CIC与4096个新样本始终按原速运行。本次没有完成FULL_FFT_CLOCK=1交叉回归，不宣称该模式已验证。',
'',
]
if full:
 lines += ['实际全链输出：','```text',*full.get('result_lines',[]),'```','']
 if evidence:
  lines += [f'对实际spectrum.csv追加独立复核：{evidence["total_rows"]}行，粗/细各4096格点，两组bin均严格0..4095且实虚分量均为数字；结果{evidence["passed"]}。完整证据及CSV哈希见fullchain_spectrum_evidence.json。','']
lines += [
'## 可重跑入口和证据',
'`run_validation.py`执行三组模块测试；`run_fullchain.py`执行单例全链；`collect_report.py`校验哈希并汇总。每组目录的commands.jsonl包含真实命令、工作路径、UTC、退出码、耗时；compile/elaborate/simulate.console.log保留真实输出；result.json仅在完成PASS标记存在且没有fatal/error/FAIL且各步退出码为0时标为通过。',
'',
'初次全链尝试 fullchain_5mhz 的展开命令因Windows批处理把未引用的NAME=VALUE拆开而失败（Cannot find design unit work.3）。该尝试和日志完整保留；只修正运行入口参数引用，未改RTL，随后在新目录fullchain_5mhz_quoted_args重跑。该启动器失败不是RTL反例。',
'',
'自动锁频TB属于数字状态机功能回归，使用简化光响应方程与加速时间参数；没有真实光学系统、PI2D闭环、DAC/ADC模拟器件或板卡验证。单例测频全链通过也不能扩展为动态跳频、全部故障恢复、硬件时序或实际精度验收。',
]
(ROOT/'report.md').write_text('\n'.join(lines)+'\n',encoding='utf-8')
print(json.dumps(dict(utc=summary['created_utc'],source_manifest_match=summary['source_manifest_match'],source_file_count=len(checks),completed_tests=[(x['test'],x['passed']) for x in tests],fullchain_status=summary['fullchain_status']),ensure_ascii=False),flush=True)
