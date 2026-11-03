import json, pathlib, re, shutil
from run_validation import ROOT, INPUT, execute, sha, utc

PROJECT=pathlib.Path('E:/Codex/FPGA/projects/adc_fft_tracking_20261014')
WORK=ROOT/'fullchain_5mhz_quoted_args'
DEPS=WORK/'dependencies'
DEPS.mkdir(parents=True,exist_ok=True)
copies=[(PROJECT/'sim/tb_measurement_improved.sv',DEPS/'tb_measurement_improved.sv'),
 (PROJECT/'projects/v3_n4096_w1/v3_n4096_w1.gen/sources_1/ip/fft_core/sim/fft_core.vhd',DEPS/'fft_core.vhd'),
 (pathlib.Path('E:/Xilinx/Vivado/2024.1/data/verilog/src/glbl.v'),DEPS/'glbl.v')]
manifest=[]
for source,target in copies:
 shutil.copyfile(source,target)
 manifest.append(dict(source=str(source),copy=str(target),source_sha256=sha(source),copy_sha256=sha(target)))
rtl=[INPUT/'rtl/measurement'/p for p in ['ddc_decimator.v','iq_snapshot.v','fft_stream_improved.v','spectral_estimator.v','measurement_improved.v']]
for source in rtl:
 manifest.append(dict(source=str(source),source_sha256=sha(source),usage='compiled unchanged snapshot'))
for filename in ['hann_4096.mem','ddc_sine_1024.mem']:
 source=pathlib.Path('E:/Codex/FPGA/projects/sensor_integrated_20261018/coefficients')/filename
 manifest.append(dict(source=str(source),source_sha256=sha(source),usage='read-only RTL absolute coefficient dependency'))
(WORK/'dependencies_manifest.json').write_text(json.dumps(manifest,indent=2),encoding='utf-8')
libs=['xbip_utils_v3_0_13','axi_utils_v2_0_9','c_reg_fd_v12_0_9','xbip_dsp48_wrapper_v3_0_6','xbip_pipe_v3_0_9',
 'xbip_dsp48_addsub_v3_0_9','xbip_addsub_v3_0_9','c_addsub_v12_0_18','c_mux_bit_v12_0_9','c_shift_ram_v12_0_17',
 'xbip_bram18k_v3_0_9','mult_gen_v12_0_21','cmpy_v6_0_24','floating_point_v7_0_23','xfft_v9_1_12',
 'unisims_ver','unimacro_ver','secureip','xpm']
libargs=[item for lib in libs for item in ['-L',lib]]
commands=[]
steps=[(['xvlog','--sv',*[str(p) for p in rtl],str(DEPS/'tb_measurement_improved.sv'),str(DEPS/'glbl.v')],'compile_rtl',180),
 (['xvhdl',str(DEPS/'fft_core.vhd')],'compile_fft',180),
 (['xelab','--relax','--mt','2','-generic_top','ALGORITHM_VERSION=3','-generic_top','FFT_LOG2=12','-generic_top','WINDOW_ENABLE=1',*libargs,'-s','fullchain_snapshot','work.tb_measurement_improved','work.glbl'],'elaborate',300),
 (['xsim','fullchain_snapshot','-testplusarg','MODE=0','-testplusarg','FREQ=5000000','-testplusarg','TOLERANCE=150','-testplusarg','FULL_FFT_CLOCK=0','-testplusarg',f'SPECTRUM={(WORK/"spectrum.csv").as_posix()}','-runall'],'simulate',600)]
for args,name,timeout in steps:
 print(f'{utc()} starting {name}',flush=True)
 item=execute(WORK,args,name,timeout)
 commands.append(item)
 print(f'{utc()} ended {name}: {item["returncode"]}',flush=True)
 if item['returncode']!=0:break
log=(WORK/'simulate.console.log').read_text(encoding='utf-8',errors='replace') if (WORK/'simulate.console.log').exists() else ''
done='TEST_DONE passed=1 errors=0 results=1' in log
fatal=bool(re.search(r'(?im)^\s*(fatal:|error:|FAIL:)',log))
result=dict(utc=utc(),test='fullchain_5mhz',commands=commands,dependencies=manifest,
 completion_marker_found=done,fatal_or_error_found=fatal,
 passed=done and not fatal and all(x['returncode']==0 for x in commands),
 full_fft_clock=False,fft_pause_policy='Only idle FFT behavioral model clock pauses during capture. ADC/proc/CIC clocks remain 250MS/s/100MHz; all 4096 samples freshly captured.',
 result_lines=[line for line in log.splitlines() if line.startswith(('RTL_RESULT','TEST_DONE','FAIL:','SIM_CLOCK_POLICY'))])
(WORK/'result.json').write_text(json.dumps(result,indent=2),encoding='utf-8')
print(json.dumps(dict(passed=result['passed'],lines=result['result_lines'])),flush=True)
