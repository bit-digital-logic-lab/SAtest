# SAtest：量化矩阵阵列

A12W10，模块按算术→PE→4×4→8×8→32×32分层；A/B独立输入，interface连接部分和。正式阵列按固定节拍执行，无内部反压，8×8旧和上传和结果排出各8拍、每拍8个字。

## 正式版本与选择

| 版本 | 优势 | 主要代价 | 适用方向 |
| --- | --- | --- | --- |
| **[CSA切分流水、集中最终加法](hardware/versions/csa/README.md)** | PE反馈只做3:2；每4×4共享4路两拍CPA，已测300MHz预布局通过 | sum/carry双份状态，末尾10拍收尾；150MHz面积和周期不如普通版 | 压缩累加、高频和共享加法研究，重点保留 |
| [普通单拍累加](hardware/versions/normal/README.md) | 150MHz三个完整模块中面积最小，结构直接、无最终收尾 | 每拍反馈经过32位CPA，单K吞吐 | 面积、可读性和低供数预算的基线 |
| [双独立乘法E2](hardware/versions/dual/README.md) | 每PE两个三级乘法器，完整任务608拍，计算最快 | 双倍A/B带宽，面积增加；ACC28 | 保留8×8布局，提高K并行度 |

CSA/普通版是ACC32回绕，双乘版为ACC28回绕，均非手写模型的38位饱和协议。三个版本各有源码、数值验证、周期、面积和时序报告；[统一结果表](reports/README.md)区分核心与含存储模块。

## CSA重点入口

[PE](hardware/versions/csa/rtl/kwt_pe_csa.sv) → [驻留三压二](hardware/versions/csa/rtl/kwt_csa32.sv) → [4×4集中加法与行通道](hardware/versions/csa/rtl/kwt_quad4x4.sv) → [低16/高16两拍CPA](hardware/versions/csa/rtl/kwt_row_adder.sv) → [8×8固定日程](hardware/versions/csa/rtl/kwt_array_quad.sv)。集中指每4×4四路共享，不是整个阵列仅一个累加器。

## 实验候选

[4/8乘PE、16×16/16×32扩展、16位输出和K64驻留模型](hardware/experiments/mulwidth/README.md)集中保存在`hardware/experiments/mulwidth/`。每个候选写明优势、带宽代价、测量范围；原始日志压缩保存，构建目录不提交。

```text
hardware/rtl/          共用接口、三级乘法器、32×32块存储与调度
hardware/versions/     csa / normal / dual，各自RTL、README与reports
hardware/experiments/  独立候选源码、测试和测量快照
hardware/tb/           正式32×32与整层回归台
software/              A12W10参考、冻结参数与验证样本
model/SA_model.py      用户手写原稿，保持不动
reports/               跨版本对照和历史测量入口
```

## 复现

```bash
python3 hardware/run.py --version all --full --synth
python3 hardware/synth.py --version csa --scope all
python3 hardware/experiments/mulwidth/run.py
```

`--version normal`、`--version dual`可单独选择。综合使用55nm SS/1.08V/125°C库；面积为标准单元面积，未布局布线，不能作为硅片功耗或时序签核。正式周期不含主机装载、外部DMA和CPU等待；当前尚未完成NICE/SoC接入。

[CSA频率实测](hardware/versions/csa/reports/frequency/README.md)：按400MHz目标映射后，实际300MHz通过；核心352MHz、完整模块308MHz分别为本次整数MHz边界通过点。更早方案保存在Git标签，当前目录不恢复冗余旧版本。
