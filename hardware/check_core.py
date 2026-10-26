#!/usr/bin/env python3
"""乘法隔离与三种PE连线的逐拍检查；--matrix可追加原阵列完整块回归。"""
import argparse,hashlib,json,subprocess,sys
from pathlib import Path
ROOT=Path(__file__).resolve().parent.parent
HW=ROOT/'hardware'

def main():
    """只实例化已有核心，所有生成文件写.build，不改算术、流水级或接口。"""
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--matrix',action='store_true',help='追加三个版本的矩阵尾块/零值/稀疏/边界回归')
    a=p.parse_args();out=ROOT/'.build/core_isolation';out.mkdir(parents=True,exist_ok=True)
    src=[HW/'rtl/kwt_interfaces.sv',HW/'rtl/kwt_mul.sv']
    for version,names in {'normal':['kwt_acc32','kwt_pe_mac'],'csa':['kwt_csa32','kwt_pe_csa'],
                          'dual':['kwt_csa28','kwt_acc28','kwt_pe_dual']}.items():
        src += [HW/'versions'/version/'rtl'/f'{name}.sv' for name in names]
    src += [HW/'tb/tb_kwt_core_isolation.sv'];binary=out/'Vtb_kwt_core_isolation'
    cmd=['verilator','--binary','--timing','--assert','-Wno-fatal','-j','4',
         '--top-module','tb_kwt_core_isolation','--Mdir',str(out/'obj'),'-o',str(binary),*map(str,src)]
    with (out/'compile.log').open('w') as log:
        subprocess.run(cmd,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    with (out/'run.log').open('w') as log:
        subprocess.run([str(binary)],cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    marker=next(line for line in (out/'run.log').read_text().splitlines() if line.startswith('ISOLATION_PASS'))
    result={'compile_exit':0,'run_exit':0,'marker':marker,'source_sha256':{str(p.relative_to(ROOT)):hashlib.sha256(p.read_bytes()).hexdigest() for p in src}};print(marker,flush=True)
    if a.matrix:
        with (out/'matrix.log').open('w') as log:
            subprocess.run([sys.executable,str(HW/'run.py'),'--version','all','--synth','--output',str(out/'matrix')],
                cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
        result['matrix_cases']=json.loads((out/'matrix/results.json').read_text())
        print(f"MATRIX_PASS cases={len(result['matrix_cases'])}",flush=True)
    (out/'result.json').write_text(json.dumps(result,ensure_ascii=False,indent=2)+'\n')

if __name__=='__main__':main()
