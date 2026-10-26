#!/usr/bin/env python3
"""对已映射网表扫描真实OpenSTA频率；不重算逻辑，不增加false path或多周期例外。"""
from pathlib import Path
import argparse,json,math,re,shutil
import synth as flow


def scan(source: Path, target: Path, frequencies: list[float]) -> dict:
    """网表只读一次，各频率重新施加完整SDC并输出时序；额外验证估计边界两侧。"""
    original=json.loads((source/'result.json').read_text())
    mapped_mhz=original.get('frequency_mhz',150.0)
    block_cycles={'csa':1024,'normal':864,'dual':608}[original['version']]
    layer_cycles=64*block_cycles
    limit=1000/(1000/mapped_mhz-original['worst_setup_slack_ns'])
    frequencies=sorted(set([*frequencies,mapped_mhz,float(math.floor(limit)),float(math.floor(limit)+1)]))
    target.mkdir(parents=True,exist_ok=True)
    shutil.copy2(source/'netlist.v',target/'netlist.v')
    constraints=(source/'design.sdc').read_text()
    script=f'read_liberty {flow.LIB}\nread_verilog netlist.v\nlink_design {original["top"]}\n'
    for mhz in frequencies:
        label=f'{mhz:g}'
        sdc=re.sub(r'create_clock -name clk -period [\d.]+',f'create_clock -name clk -period {1000/mhz:.9f}',constraints)
        sdc+='set_clock_transition 0.1 [get_clocks clk]\n'
        (target/f'{label}.sdc').write_text(sdc)
        script+=f'''read_sdc {label}.sdc
check_setup -verbose > {label}_coverage.rpt
report_worst_slack -digits 6 > {label}_slack.rpt
report_tns -digits 6 > {label}_tns.rpt
report_checks -path_delay max -group_count 1 -fields {{capacitance slew}} -digits 6 > {label}_timing.rpt
'''
    (target/'sweep.tcl').write_text(script+'exit\n')
    flow.run_logged([str(flow.STA),'-exit','sweep.tcl'],target/'opensta.log')
    assert not re.search(r'^Error:',(target/'opensta.log').read_text(),re.M)
    rows=[]
    for mhz in frequencies:
        label=f'{mhz:g}';slack=float(re.search(r'worst slack\s+([+\-\d.eE]+)',(target/f'{label}_slack.rpt').read_text()).group(1))
        tns=float(re.search(r'tns\s+([+\-\d.eE]+)',(target/f'{label}_tns.rpt').read_text()).group(1))
        assert not (target/f'{label}_coverage.rpt').read_text().strip()
        rows.append({'frequency_mhz':mhz,'setup_slack_ns':slack,'tns_ns':tns,'pass':slack>=0 and tns==0,'layer_us':layer_cycles/mhz,'block_us':block_cycles/mhz,'layer_GOPS':3244032*mhz/layer_cycles/1000})
    at_mapping=next(r for r in rows if r['frequency_mhz']==mapped_mhz)
    assert abs(at_mapping['setup_slack_ns']-original['worst_setup_slack_ns'])<2e-6
    result={'scope':original['scope'],'mapping_frequency_mhz':mapped_mhz,'area_mm2':original['area_mm2'],'linear_setup_limit_mhz':limit,'verified_pass_mhz':max(r['frequency_mhz'] for r in rows if r['pass']),'rows':rows}
    (target/'results.json').write_text(json.dumps(result,indent=2)+'\n')
    return result


def main() -> int:
    """只扫描选定版本已有核心/模块网表，输出目录独立于映射目录。"""
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--mapping',type=Path,required=True)
    p.add_argument('--version',default='csa',choices=['csa','normal','dual'])
    p.add_argument('--output',type=Path,required=True)
    p.add_argument('--frequencies',type=float,nargs='+',default=[150,200,250,300,350,400])
    a=p.parse_args();result=[]
    for scope in ('core','block'):
        source=a.mapping.resolve()/scope/a.version
        if (source/'result.json').exists():
            r=scan(source,a.output.resolve()/scope,a.frequencies);result.append(r)
            print(f'{scope}: mapping={r["mapping_frequency_mhz"]:g}MHz setup_limit={r["linear_setup_limit_mhz"]:.3f}MHz verified_pass={r["verified_pass_mhz"]:g}MHz',flush=True)
    a.output.mkdir(parents=True,exist_ok=True)
    (a.output/'summary.json').write_text(json.dumps(result,indent=2)+'\n')
    return 0


if __name__=='__main__':raise SystemExit(main())
