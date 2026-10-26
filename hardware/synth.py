#!/usr/bin/env python3
"""CSA与普通累加版本在55nm SS库、指定频率目标下的标准单元映射、OpenSTA时序及翻转率功耗估计；结果保存在.build/synth150。"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import shutil
import argparse
import hashlib
import json
import re
import subprocess
import time

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / '.build/synth150'
LIB = Path('/home/yang/yosys-sta/pdk/icsprout55/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib')
STA = Path(shutil.which('sta') or str(ROOT / '.build/tools/opensta/usr/bin/sta'))
VERSIONS = ['csa','normal']
FREQUENCY_MHZ = 150.0


def run_logged(command, log):
    """保留完整工具日志，退出码非零就停止当前目标。"""
    with log.open('w') as stream:
        result = subprocess.run(command, cwd=log.parent, stdout=stream, stderr=subprocess.STDOUT)
    if result.returncode:
        raise RuntimeError(f'exit={result.returncode}: {log}')


def scalar_netlist(module, top, path):
    """按Yosys位编号导出标量网表，避免iSTA的向量别名/拼接解析问题；不改任何单元。"""
    ports=[]; signal={}; aliases=[]
    # 端口优先作为该位的规范名称，正常连接无需assign别名。
    for name, port in module['ports'].items():
        for i, bit in enumerate(port['bits']):
            label=name if len(port['bits'])==1 else f'{name}_{i}_'
            ports.append((label,port['direction']))
            if isinstance(bit,int):
                if bit in signal: aliases.append((label,signal[bit]))
                else: signal[bit]=label
            elif port['direction']=='output': aliases.append((label,f"1'b{bit}"))
    for cell in module['cells'].values():
        for bits in cell['connections'].values():
            for bit in bits:
                if isinstance(bit,int) and bit not in signal: signal[bit]=f'n{bit}'
    lines=[f"module {top}("+', '.join(name for name,_ in ports)+');']
    lines += [f'  {direction} {name};' for name,direction in ports]
    port_names={name for name,_ in ports}
    lines += [f'  wire {name};' for name in signal.values() if name not in port_names]
    cell_names={}
    for i,(name,cell) in enumerate(module['cells'].items()):
        pins=[]
        for pin,bits in cell['connections'].items():
            if len(bits)!=1: raise RuntimeError(f'non-scalar standard cell pin: {name}/{pin}')
            bit=bits[0]; wire=signal[bit] if isinstance(bit,int) else f"1'b{bit}"
            pins.append(f'.{pin}({wire})')
        inst=f'u{i}'; cell_names[inst]=name
        lines.append(f"  {cell['type']} {inst} ("+', '.join(pins)+');')
    lines += [f'  assign {left} = {right};' for left,right in aliases]
    lines += ['endmodule']
    path.write_text('\n'.join(lines)+'\n')
    (path.parent/'cell_names.json').write_text(json.dumps(cell_names,ensure_ascii=False)+'\n')
    return ports


def measure(scope, version, areas, reuse=False):
    """独立映射一个核心或整块，随后按指定目标时钟执行STA。"""
    target = OUT / scope / version
    target.mkdir(parents=True, exist_ok=True)
    top = 'kwt_core_synth' if scope=='core' else 'kwt_block32'
    sources = [ROOT/'hardware/rtl/kwt_interfaces.sv']
    sources += sorted(p for p in (ROOT/'hardware/rtl').rglob('*.sv') if p!=sources[0])
    sources += sorted((ROOT/'hardware/versions'/version/'rtl').glob('*.sv'))
    sources += [ROOT/'hardware/synth/kwt_core_synth.sv']
    (target/'abc.constr').write_text('set_driving_cell BUFX0P5H7L\nset_load 10\n')
    parameters = f'-GTAIL_CYCLES={10 if version=="csa" else 0}' if scope=='block' else ''
    script = f'''read_slang --top {top} {parameters} {' '.join(map(str,sources))}
synth -top {top} -flatten -noabc
dfflibmap -liberty {LIB}
abc -liberty {LIB} -D {1e6/FREQUENCY_MHZ:.3f} -constr {target/'abc.constr'}
clean
hilomap -singleton -hicell TIEHIH7L Z -locell TIELOH7L Z
setundef -zero
clean
read_liberty -lib {LIB}
check -mapped -assert
tee -o {target/'stat.json'} stat -json -liberty {LIB}
rename -hide w:*
clean -purge
splitnets -ports -format __v
write_verilog -noattr -noexpr -simple-lhs {target/'netlist.v'}
write_json {target/'netlist.json'}
'''
    (target/'synth.ys').write_text(script)
    begin=time.monotonic()
    if not (reuse and (target/'netlist.json').is_file()):
        run_logged(['yosys','-Q','-T','-m','slang','-s',str(target/'synth.ys')],target/'synth.log')
    module=json.loads((target/'netlist.json').read_text())['modules'][top]
    ports=scalar_netlist(module,top,target/'netlist.v')
    cells=module['cells']
    counts={}
    for cell in cells.values():
        kind=cell['type']
        if kind not in areas: raise RuntimeError(f'unmapped cell {kind} in {target}')
        counts[kind]=counts.get(kind,0)+1
    area=sum(areas[k]*count for k,count in counts.items())
    # 输入/输出各预留0.5ns，输入转换0.1ns，输出负载0.01pF，时钟不确定性0.1ns。
    inputs=[name for name,direction in ports if direction=='input' and name!='clk']
    outputs=[name for name,direction in ports if direction=='output']
    sdc=f'create_clock -name clk -period {1000/FREQUENCY_MHZ:.6f} [get_ports clk]\nset_clock_uncertainty 0.1 [get_clocks clk]\n'
    for port in inputs:
        sdc+=f'set_input_delay 0.5 -clock clk [get_ports {{{port}}}]\nset_input_transition 0.1 [get_ports {{{port}}}]\n'
    for port in outputs:
        sdc+=f'set_output_delay 0.5 -clock clk [get_ports {{{port}}}]\nset_load 0.01 [get_ports {{{port}}}]\n'
    (target/'design.sdc').write_text(sdc)
    # 旧OpenSTA对中文绝对路径支持不完整，网表/SDC/报告在目标目录内用相对路径。
    # OpenSTA采用0.1ns时钟转换时间，检查寄存器与I/O路径，不读取未布线的寄生参数。
    (target/'opensta.tcl').write_text(f"""read_liberty {LIB}
read_verilog netlist.v
link_design {top}
read_sdc design.sdc
set_clock_transition 0.1 [get_clocks clk]
check_setup -verbose > coverage.rpt
report_worst_slack -digits 6 > slack.rpt
report_tns -digits 6 > tns.rpt
report_checks -path_delay max -group_count 1 -fields {{capacitance slew}} -digits 6 > critical.rpt
set_power_activity -global -activity 0.1 -duty 0.5
report_power -digits 6 > power_0p1.rpt
set_power_activity -global -activity 0.5 -duty 0.5
report_power -digits 6 > power_0p5.rpt
exit
""")
    run_logged([str(STA),'-exit','opensta.tcl'],target/'opensta.log')
    stat=json.loads((target/'stat.json').read_text())['modules']['\\'+top]
    if abs(stat['area']-area)>0.01 or stat['num_cells']!=sum(counts.values()):
        raise RuntimeError(f'area/count mismatch: {target}')
    timing=timing_result(target,top)
    result={'scope':scope,'version':version,'top':top,'cells':sum(counts.values()),'area_um2':area,
        'area_mm2':area/1e6,'cell_types':counts,'seconds':time.monotonic()-begin,'directory':str(target),
        'lib_sha256':hashlib.sha256(LIB.read_bytes()).hexdigest(), 'frequency_mhz':FREQUENCY_MHZ, **timing}
    (target/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')
    return result


def timing_result(target, top):
    """读取实际setup余量与两档翻转率功耗；功耗是无波形、无布线的库模型估计。"""
    log=(target/'opensta.log').read_text()
    if re.search(r'^Error:',log,re.M): raise RuntimeError(f'OpenSTA error: {target}')
    slack=float(re.search(r'worst slack\s+([+\-\d.eE]+)',(target/'slack.rpt').read_text()).group(1))
    tns=float(re.search(r'tns\s+([+\-\d.eE]+)',(target/'tns.rpt').read_text()).group(1))
    power={}
    for activity in ['0p1','0p5']:
        report=(target/f'power_{activity}.rpt').read_text()
        row=next(line for line in report.splitlines() if line.strip().startswith('Total'))
        values=[float(value) for value in row.split()[1:5]]
        power[activity]={'internal_W':values[0],'switching_W':values[1],'leakage_W':values[2],'total_W':values[3]}
    return {'worst_setup_slack_ns':slack,'setup_tns_ns':tns,'meets_target_pre_layout':slack>=0 and tns==0,
            **({'meets_150mhz_pre_layout':slack>=0 and tns==0} if FREQUENCY_MHZ==150 else {}),
            'timing_report':str(target/'critical.rpt'),'power_estimates':power}


def main():
    """两个独立目标并行执行，任何失败都会保留日志并返回非零状态。"""
    global OUT,FREQUENCY_MHZ
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--frequency',type=float,default=150.0,help='目标频率MHz，SDC与ABC映射同时调整')
    parser.add_argument('--output',type=Path,help='独立结果目录，避免覆盖其他架构快照')
    parser.add_argument('--version',choices=[*VERSIONS,'all'],default='all')
    parser.add_argument('--scope',choices=['core','block','all'],default='all')
    parser.add_argument('--reuse-mapped',action='store_true',help='仅在RTL与映射目标频率未变时复用网表，只重跑STA')
    args=parser.parse_args()
    FREQUENCY_MHZ=args.frequency
    if FREQUENCY_MHZ<=0: parser.error('frequency must be positive')
    if args.output: OUT=args.output.resolve()
    elif FREQUENCY_MHZ!=150: OUT=ROOT/'.build'/f'synth{FREQUENCY_MHZ:g}'
    areas={name:float(area) for name,area in re.findall(r'cell\s*\(([^)]+)\)\s*\{.*?\barea\s*:\s*([0-9.eE+-]+)',LIB.read_text(),re.S)}
    scopes=['core','block'] if args.scope=='all' else [args.scope]
    versions=VERSIONS if args.version=='all' else [args.version]
    OUT.mkdir(parents=True,exist_ok=True)
    manifest={str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest()
              for p in sorted((ROOT/'hardware/rtl').rglob('*.sv'))}
    manifest['hardware/synth/kwt_core_synth.sv']=hashlib.sha256((ROOT/'hardware/synth/kwt_core_synth.sv').read_bytes()).hexdigest()
    manifest.update({str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for version in versions for p in sorted((ROOT/'hardware/versions'/version/'rtl').glob('*.sv'))})
    (OUT/'source_manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
    results=[]; failures=[]
    with ThreadPoolExecutor(max_workers=2) as pool:
        jobs={pool.submit(measure,s,v,areas,args.reuse_mapped):(s,v) for s in scopes for v in versions}
        for job in as_completed(jobs):
            try:
                result=job.result(); results.append(result)
                print(f"MAPPED {result['scope']}/{result['version']} area={result['area_um2']:.3f}um2 cells={result['cells']} slack={result['worst_setup_slack_ns']:.6f}ns target_met={result.get('meets_target_pre_layout',result.get('meets_150mhz_pre_layout'))}",flush=True)
            except Exception as exc:
                failures.append({'target':jobs[job],'error':str(exc)})
                print(f'FAILED {jobs[job]} {exc}',flush=True)
            (OUT/'summary.json').write_text(json.dumps({'results':results,'failures':failures},ensure_ascii=False,indent=2)+'\n')
    return bool(failures)

if __name__=='__main__':
    raise SystemExit(main())
