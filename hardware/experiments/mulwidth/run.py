#!/usr/bin/env python3
"""多乘PE、直接16×16阵列与输出量化的独立功能回归；生成物统一放.build。"""
import subprocess,json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]
HERE=Path(__file__).resolve().parent
OUT=ROOT/'.build/experiments/mulwidth/check'

def main():
    """按测试顶层选择源码，错误立即停止；不将测试结果当整块SoC验证。"""
    common=[ROOT/'hardware/rtl/kwt_interfaces.sv',ROOT/'hardware/rtl/kwt_mul.sv',
            ROOT/'hardware/versions/dual/rtl/kwt_acc28.sv']
    suites={
        'tb_kwt_pe_m4':['kwt_csa3','kwt_pe_m4'],
        'tb_kwt_pe_m8':['kwt_csa3','kwt_pe_m8'],
        'tb_kwt_pe_m1':['kwt_pe_m1'],
        'tb_kwt_flat16':['kwt_pe_m1','kwt_flat16'],
        'tb_requant8':['kwt_requant8'],
    }
    results=[]
    for top,names in suites.items():
        target=OUT/top;target.mkdir(parents=True,exist_ok=True)
        binary=target/top
        cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','-j','4',
             '--top-module',top,'--Mdir',str(target/'obj'),'-o',str(binary)]
        cmd += list(map(str,common+[HERE/'rtl'/f'{name}.sv' for name in names]+[HERE/'tb'/f'{top}.sv']))
        with (target/'compile.log').open('w') as log:
            subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
        with (target/'run.log').open('w') as log:
            subprocess.run([str(binary)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
        content=(target/'run.log').read_text()
        if 'PASS' not in content or 'FAIL' in content: raise RuntimeError(f'no accepted marker: {target}')
        lines=[line for line in content.splitlines() if 'PASS' in line]
        results.append(dict(top=top,compile_exit=0,run_exit=0,markers=lines))
        print(top,lines,flush=True)
    (OUT/'results.json').write_text(json.dumps(results,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
