import concurrent.futures, datetime, hashlib, json, pathlib, re, subprocess, time

ROOT = pathlib.Path(__file__).resolve().parent
INPUT = ROOT.parent / 'inputs'
BIN = pathlib.Path('E:/Xilinx/Vivado/2024.1/bin')

def utc(): return datetime.datetime.now(datetime.timezone.utc).isoformat()
def sha(path): return hashlib.sha256(path.read_bytes()).hexdigest()

def execute(work, args, name, timeout=180):
    work.mkdir(parents=True, exist_ok=True)
    cmd = [str(BIN / (args[0]+'.bat')), *args[1:]]
    # Windows batch-file parameter parsing treats unquoted '=' as a delimiter.
    # Quote every fixed argument so xelab receives NAME=VALUE as one argument.
    cmdline = ' '.join('"'+str(item)+'"' for item in cmd)
    start, tick = utc(), time.monotonic()
    with (work / (name+'.console.log')).open('w', encoding='utf-8') as log:
        try:
            result = subprocess.run(cmdline, cwd=work, stdout=log, stderr=subprocess.STDOUT, timeout=timeout)
            code = result.returncode
        except subprocess.TimeoutExpired:
            code = 'TIMEOUT'
    info = dict(start_utc=start, end_utc=utc(), duration_seconds=round(time.monotonic()-tick,3),
                cwd=str(work), command=cmdline, returncode=code)
    with (work / 'commands.jsonl').open('a', encoding='utf-8') as stream:
        stream.write(json.dumps(info, ensure_ascii=False)+'\n')
    return info

def run_unit(name, rtl, tb, top, marker):
    work=ROOT/name
    work.mkdir(exist_ok=True)
    paths=[INPUT/rtl, pathlib.Path(tb) if pathlib.Path(tb).is_absolute() else INPUT/tb]
    hashes=[dict(path=str(p), sha256=sha(p)) for p in paths]
    commands=[]
    for args,label in [(['xvlog','--sv',*[str(p) for p in paths]],'compile'),
                       (['xelab',top,'-s','unit_snapshot'],'elaborate'),
                       (['xsim','unit_snapshot','-runall'],'simulate')]:
        item=execute(work,args,label)
        commands.append(item)
        if item['returncode'] != 0: break
    simulation=(work/'simulate.console.log').read_text(encoding='utf-8',errors='replace') if (work/'simulate.console.log').exists() else ''
    fatal=bool(re.search(r'(?im)^\s*(fatal:|error:|FAIL:)',simulation))
    complete=marker in simulation
    report=dict(test=name, started_utc=commands[0]['start_utc'], finished_utc=utc(), source_hashes=hashes,
                commands=commands, completion_marker=marker, completion_marker_found=complete,
                fatal_or_error_found=fatal, passed=complete and not fatal and all(x['returncode']==0 for x in commands))
    (work/'result.json').write_text(json.dumps(report,indent=2,ensure_ascii=False),encoding='utf-8')
    print(json.dumps(dict(test=name,passed=report['passed'],completion_marker_found=complete)),flush=True)
    return report

if __name__=='__main__':
    jobs=[('spectral_existing','rtl/measurement/spectral_estimator.v','existing_tests/fft/tb_spectral_estimator.sv','tb_spectral_estimator','ALL 18 SPECTRAL ESTIMATOR TESTS PASSED'),
          ('auto_lock_existing','rtl/laser/auto_lock_fsm.v','existing_tests/laser/tb_auto_lock_fsm.v','tb_auto_lock_fsm','PASS AUTO_FSM auto-acquire, loss/reacquire, flat-signal rejection')]
    extended=ROOT/'tb_spectral_estimator_4096.sv'
    if extended.exists(): jobs.append(('spectral_4096','rtl/measurement/spectral_estimator.v',str(extended),'tb_spectral_estimator_4096','ALL 19 PRODUCTION 4096 SPECTRAL CASES PASSED'))
    with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
        results=list(pool.map(lambda job:run_unit(*job),jobs))
    (ROOT/'unit_summary.json').write_text(json.dumps(dict(utc=utc(),tests=results),indent=2,ensure_ascii=False),encoding='utf-8')
