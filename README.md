# SAtest：共享行加法CSA阵列

当前只保留一套RTL：8×8阵列由四个4×4块组成，64个A12W10乘法器；PE内驻留sum/carry，每个4×4共享四路两拍最终加法器。相邻两块交替完成最终加法，结果写回原PE；部分和每拍8个INT32整行传输，输入与输出各8拍。内部按固定时钟执行，无反压。

## 工程目录

- `hardware/rtl/`：8个RTL文件，接口、乘法器、压缩器、PE、行加法器、4×4、8×8、32×32顶层。
- `hardware/tb/`：逐点验证和固定周期检查。
- `hardware/run.py`：功能回归入口。
- `hardware/synth.py`、`hardware/synth/`：150MHz映射与时序入口、核心封装。
- `model/SA_model.py`：手写参考模型，保持原稿。
- `software/`：量化参数、真实验证数据和软件模型。
- `reports/`：当前方案测量摘要。
- `题目/`、`资料/`：原始比赛题目与参考资料。

数据流：`kwt_block32` → `kwt_array_quad` → `kwt_quad4x4` → `kwt_pe_csa` → `kwt_mul` / `kwt_csa32`；`kwt_quad4x4`内的`kwt_row_adder`负责最终两数相加。模块之间的部分和通道由`kwt_interfaces.sv`定义，A12与B10使用独立输入端口。

## 运行

```bash
python3 hardware/run.py --full --synth
python3 hardware/synth.py --scope all
```

仿真结果在`.build/simulation/`，映射结果在`.build/synth150/`。`--full`覆盖12层各2个真实样本，另含随机尾块、零值、稀疏、补码极值和驻留重复累计。综合使用本机ICsprout55库与OpenSTA，库/工具位置见`hardware/synth.py`。

阵列部分和接口为256位：每拍一行8个INT32，按第0～7行连续输入/输出。C存储按列低3位划分8个bank，各bank每拍提供一个字；顶层现有主机装载/读回接口仍为标量，外部DMA时间另计。

每个32×32块执行`C += A×B`，B跨任务保留；bias由外部作为初始C装入，DMA负责全局边界与补零。RTL采用INT32回绕，手写Python模型的38位饱和规则另行保留。

当前32×32任务1024拍，99×64×256层65536拍（不含外部DMA搬运）。面积、时序及估计功耗见[当前测量摘要](reports/README.md)。

## 旧版存档

其他方案和原始对比报告仅保存在Git标签`archive/all-strategies-before-cleanup-20261025`，不在当前目录保留副本；旧逐PE加法CSA标签为`csa-per-pe`，共享CSA初版为`csa-shared-row`。

```bash
git show archive/all-strategies-before-cleanup-20261025:reports/csa_compare/README.md
```
