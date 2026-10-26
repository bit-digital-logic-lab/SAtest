# 普通单拍累加版

64个PE各自使用单拍普通32位加法器，每拍sum←sum＋符号扩展乘积。没有CSA模块、carry驻留寄存器、行选择加法组或最终carry合并。

共用A12W10、三拍乘法、INT32回绕、K向量II=1、8×8部分和输入/输出各8拍、8bank C存储。A/B独立端口；上传、计算和下载采用固定节拍，无反压。bias/oldsum直接装入原部分和寄存器。

## 面积与150MHz时序实测

| 范围 | 标准单元面积mm² | 单元数 | 触发器数 | setup余量ns | TNSns |
| --- | ---: | ---: | ---: | ---: | ---: |
| 8×8计算核心 | 0.18469920 | 84966 | 7303 | 2.784992 | 0.0 |
| 含A/B/C存储32×32模块 | 0.85146208 | 353412 | 62619 | 2.734381 | 0.0 |

- [核心面积明细](reports/core/area.json) · [核心关键路径](reports/core/timing.rpt) · [核心SDC](reports/core/constraints.sdc)
- [完整模块面积明细](reports/block/area.json) · [完整模块关键路径](reports/block/timing.rpt) · [完整模块SDC](reports/block/constraints.sdc)

两项均满足本次150MHz映射后setup约束。工艺为ICsprout55 H7CL SS/1.08V/125°C，周期6.666667ns；clock uncertainty/transition各0.1ns，输入/输出延时0.5ns、输入transition0.1ns，输出负载0.01pF。没有false path或multicycle。尚未布局布线、插入时钟树或提取寄生，不能视作芯片时序签核。

完整模块的55296位A/B/C存储均映射为触发器与选择器，没有使用SRAM宏；面积不能直接等同采用SRAM宏后的芯片面积。

## 周期与验证

- 32×32×32任务：**864拍**；99×64×256层（64任务）：**55296拍**，150MHz计算侧**8.800GOPS**。
- 完整回归28例、612728个最终输出逐点对齐，含随机尾块、零值、稀疏、补码极值、12层各2个真实样本及保留B/C重复累计。
- 测试台检查每个任务512次连续K向量发射，LOAD/STORE各128拍；逐拍检查下载行号。输入/输出8拍指阵列内部一整行8个INT32，顶层主机标量装载/回读和外部DMA时间不计入上述周期。

## 目录与复现

`rtl/`只放本版本的阵列、4×4块和PE算术；共用接口、乘法器、32×32控制在`hardware/rtl/`。两个版本虽有同名模块，脚本只读取所选版本目录，不同时混编。普通版编译32×32控制器时使用`TAIL_CYCLES=0`，CSA版为10，决定是否执行最终共享加法收尾。

在工程根目录运行：

```bash
python3 hardware/run.py --version normal --full --synth
python3 hardware/synth.py --version normal --scope all
```

[结构化结果](reports/result.json) · [完整综合/STA日志及验证记录](reports/raw_evidence.zip)。功耗字段仅为统一活动率库估计，未进行真实波形功耗测量。
