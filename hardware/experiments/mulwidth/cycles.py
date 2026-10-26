#!/usr/bin/env python3
"""KWT-1 FFN1 周期/流量账：当前 dual、K64 C 驻留、A/B/C 理想流量、16 位输出。"""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[3]

def layer_cycles(tiles_per_layer, load, run, wait, flush, store):
    return tiles_per_layer*(load+run+wait+flush+store)

# 8x8 tile，K32/K64，dual 2MAC/拍
tiles_8x8=416          # 13 个 8 行条 ×32 个 8 列条
tiles_8x8_k32=1024     # 4x8 块 ×2 K32 ×16 tile
cur=tiles_8x8_k32*(8+16+5+1+8)  # 38,912
k64_no=32*16*(8+32+5+1+8)      # 32 个 32×32 任务，不裁剪
k64=tiles_8x8*(8+32+5+1+8)      # 13×32=416 tile，含 8 行裁剪
# 4/8/16x16 核心的 K64 计算账（含 C 8/16 拍，不含 A/B）
four=tiles_8x8*(8+16+5+1+8)
eight=tiles_8x8*(8+8+5+1+8)
sixteen=112*(16+64+5+1+16)
sixteen32=56*(16+64+5+1+16)
# 理想外部流量（值），A/B 2值/32位，输出 1值/32位（32位）或 2值/32位（16位）
vals={'A':99*64,'B':64*256,'bias':256,'Y':99*256}
in_words=(vals['A']+vals['B']+vals['bias']+1)//2
w32=in_words+vals['Y']
w16=in_words+(vals['Y']+1)//2
mac=99*64*256
def gops(cycles): return mac*2*150e6/cycles/1e9
out={
 'current_dual_8x8_k32':{'cycles':cur,'gops':gops(cur)},
 'dual_8x8_k64_no_prune':{'cycles':k64_no,'gops':gops(k64_no),'gain_vs_current':cur/k64_no},
 'dual_8x8_k64_prune':{'cycles':k64,'gops':gops(k64),'gain_vs_current':cur/k64},
 'four_mul_8x8_k64':{'cycles':four,'gops':gops(four)},
 'eight_mul_8x8_k64':{'cycles':eight,'gops':gops(eight)},
 'sixteen_x16_k64':{'cycles':sixteen,'gops':gops(sixteen)},
 'sixteen_x32_k64':{'cycles':sixteen32,'gops':gops(sixteen32)},
 'traffic_values':vals,
 'traffic_words_32bit_out':w32,
 'traffic_words_16bit_out':w16,
 'bus_cycles_32bit_out':w32,
 'bus_cycles_16bit_out':w16,
 'endtoend_gops_32bit_out':gops(w32),
 'endtoend_gops_16bit_out':gops(w16),
}
target=ROOT/'.build/experiments/mulwidth/model/endtoend.json'
target.parent.mkdir(parents=True,exist_ok=True)
target.write_text(json.dumps(out,indent=2)+'\n')
print(json.dumps(out,indent=2))
