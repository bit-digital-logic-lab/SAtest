#!/usr/bin/env python3
"""4/8 乘法器 PE 与 16×16 直接扩展的统一定向映射/时序实验。

所有变体共用 kwt_mul、kwt_acc28、28 位模 2^28 语义；只改变每 PE 乘法器数
和输出 tile 形状。面积是 Yosys 标准单元映射面积，不含布线与 A/B/C 存储。
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import time
from concurrent.futures import ThreadPoolExecutor, as_completed
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
OUT = ROOT / '.build/experiments/mulwidth/synth'
LIB = Path('/home/yang/yosys-sta/pdk/icsprout55/IP/STD_cell/ics55_LLSC_H7C_V1p10C100/ics55_LLSC_H7CL/liberty/ics55_LLSC_H7CL_ss_rcworst_1p08_125_nldm.lib')
STA = Path(ROOT / '.build/tools/opensta/usr/bin/sta')
sys.path.insert(0, str(ROOT / 'hardware'))
import synth as flow  # 复用标量网表导出，避免 iSTA 对向量别名的解析问题

COMMON = [
    ROOT/'hardware/rtl/kwt_interfaces.sv',
    ROOT/'hardware/rtl/kwt_mul.sv',
    ROOT/'hardware/versions/dual/rtl/kwt_acc28.sv',
    ROOT/'hardware/versions/dual/rtl/kwt_csa28.sv',
    ROOT/'hardware/versions/dual/rtl/kwt_pe_dual.sv',
]
DS = [
    HERE/'rtl/kwt_csa3.sv',
    HERE/'rtl/kwt_pe_m4.sv',
    HERE/'rtl/kwt_pe_m8.sv',
    HERE/'rtl/kwt_pe_m1.sv',
]
MAIN = [HERE/'rtl/kwt_flat_core.sv']

TOPS = {
    'kwt_core_8_m1':  (8, 8, 1),
    'kwt_core_8_m2':  (8, 8, 2),
    'kwt_core_8_m4':  (8, 8, 4),
    'kwt_core_8_m8':  (8, 8, 8),
    'kwt_core_16_m1': (16, 16, 1),
    'kwt_core_16x32_m1': (16, 32, 1),
    'kwt_core_32x16_m1': (32, 16, 1),
}


def synth_one(top: str) -> dict:
    target = OUT / top
    target.mkdir(parents=True, exist_ok=True)
    all_sources = [*COMMON, *DS, *MAIN]
    sources = [p for p in all_sources if p.is_file()]
    missing = [p for p in all_sources if not p.is_file()]
    if missing:
        # 先允许只综合已齐备的 M=2；缺 DS 模块时由 Yosys 对目标 top 报错。
        print('WARN missing sources: ' + ', '.join(map(str, missing)), flush=True)
    (target/'abc.constr').write_text('set_driving_cell BUFX0P5H7L\nset_load 10\n')
    script = f'''read_slang --top {top} {' '.join(map(str,sources))}
synth -top {top} -flatten -noabc
dfflibmap -liberty {LIB}
abc -liberty {LIB} -D 6666.667 -constr {target/'abc.constr'}
clean
hilomap -singleton -hicell TIEHIH7L Z -locell TIELOH7L Z
setundef -zero
clean
read_liberty -lib {LIB}
check -mapped -assert
tee -o {target/'stat.json'} stat -json -liberty {LIB}
write_json {target/'netlist.json'}
'''
    (target/'synth.ys').write_text(script)
    begin = time.monotonic()
    flow.run_logged(['yosys', '-Q', '-T', '-m', 'slang', '-s', str(target/'synth.ys')],
                     target/'synth.log')
    module = json.loads((target/'netlist.json').read_text())['modules'][top]
    ports = flow.scalar_netlist(module, top, target/'netlist.v')
    # 关键路径只用内部寄存器路径；I/O 约束与主线一致。
    inputs = [n for n, d in ports if d == 'input' and n != 'clk']
    outputs = [n for n, d in ports if d == 'output']
    sdc = 'create_clock -name clk -period 6.666667 [get_ports clk]\nset_clock_uncertainty 0.1 [get_clocks clk]\n'
    for port in inputs:
        sdc += f'set_input_delay 0.5 -clock clk [get_ports {{{port}}}]\nset_input_transition 0.1 [get_ports {{{port}}}]\n'
    for port in outputs:
        sdc += f'set_output_delay 0.5 -clock clk [get_ports {{{port}}}]\nset_load 0.01 [get_ports {{{port}}}]\n'
    (target/'design.sdc').write_text(sdc)
    (target/'opensta.tcl').write_text(f'''read_liberty {LIB}
read_verilog netlist.v
link_design {top}
read_sdc design.sdc
set_clock_transition 0.1 [get_clocks clk]
check_setup -verbose > coverage.rpt
report_worst_slack -digits 6 > slack.rpt
report_tns -digits 6 > tns.rpt
report_checks -path_delay max -group_count 1 -fields {{capacitance slew}} -digits 6 > critical.rpt
exit
''')
    flow.run_logged([str(STA), '-exit', 'opensta.tcl'], target/'opensta.log')
    stat = json.loads((target/'stat.json').read_text())['modules']['\\' + top]
    slack = float(re.search(r'worst slack\s+([+\-\d.eE]+)', (target/'slack.rpt').read_text()).group(1))
    tns = float(re.search(r'tns\s+([+\-\d.eE]+)', (target/'tns.rpt').read_text()).group(1))
    rows, cols, mult = TOPS[top]
    macs = rows * cols * mult
    feed = rows * mult * 12 + cols * mult * 10
    return {
        'top': top, 'rows': rows, 'cols': cols, 'multipliers_per_pe': mult,
        'outputs': rows * cols, 'macs_per_cycle': macs,
        'multiplier_cells': macs, 'operand_bits': feed,
        'area_um2': stat['area'], 'cells': stat['num_cells'],
        'setup_slack_ns': slack, 'tns_ns': tns,
        'area_per_mac_um2': stat['area'] / macs,
        'operand_bits_per_mac': feed / macs,
        'seconds': time.monotonic() - begin,
        'directory': str(target),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--tops', nargs='*', default=list(TOPS))
    parser.add_argument('--jobs', type=int, default=2)
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    results, failures = [], []
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        jobs = {pool.submit(synth_one, top): top for top in args.tops}
        for job in as_completed(jobs):
            top = jobs[job]
            try:
                result = job.result()
                results.append(result)
                print(f"MAPPED {top} area={result['area_um2']:.1f}um2 cells={result['cells']} "
                      f"slack={result['setup_slack_ns']:.3f}ns", flush=True)
            except Exception as exc:
                failures.append({'top': top, 'error': str(exc)})
                print(f'FAILED {top} {exc}', flush=True)
            (OUT/'results.json').write_text(json.dumps({'results': results, 'failures': failures},
                                                      ensure_ascii=False, indent=2) + '\n')
    return bool(failures)


if __name__ == '__main__':
    raise SystemExit(main())
