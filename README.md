# SAtest：8×8矩阵计算阵列

当前保留用户指定的两个版本，共用A12W10、三拍乘法器、INT32回绕、8拍整行部分和输入/输出、固定节拍及8bank C存储。

- [CSA版本](hardware/versions/csa/README.md)：PE内驻留sum/carry，每个4×4共享四路两拍最终加法器。
- [普通版本](hardware/versions/normal/README.md)：每个PE用单拍普通32位加法直接累加，无三压二、carry寄存器或最终共享加法。

每个版本目录内均有自己的RTL、面积和150MHz时序报告。`hardware/rtl/`只放共用接口、乘法器及32×32控制器；编译脚本只读取所选版本目录，同名模块不会混合。

```bash
python3 hardware/run.py --version all --full --synth
python3 hardware/synth.py --version all --scope all
```

也可用`--version csa`或`--version normal`单独运行。源码阅读顺序：普通版`kwt_acc32→kwt_pe_mac→kwt_quad4x4→kwt_array_quad→kwt_block32`；CSA版`kwt_csa32→kwt_pe_csa→kwt_quad4x4`及其中的`kwt_row_adder`，再向上读阵列与32×32控制。

阵列部分和接口256位，每拍连续输入/输出一整行8个INT32，共8行。C按列低3位分8个独立bank；顶层主机装载/读回仍为标量，外部DMA时间另计。bias/oldsum作为初始C装入；B跨start驻留。内部无ready/反压，零值只关闭数据更新。

手写`model/SA_model.py`保持原稿，38位饱和协议与本RTL的INT32回绕不同。软件参数与验证数据在`software/`，原始比赛题目和资料继续保留。

[两版实测比较](reports/README.md)。此前单拍加法实验在`reports/row8_adder150.md`及证据包，复现其旧文件布局请切换Git标签`archive/row8-csa-before-normal-20261026`。更早方案只在Git存档，不恢复到当前目录。

## CSA提高频率

[实际频率扫描与时间报告](hardware/versions/csa/reports/frequency/README.md)：按400MHz目标重新映射后，完整模块在实际300MHz通过预布局setup检查，65536拍一层约218.453µs；本次模块边界为308MHz通过、309MHz失败，核心单独352MHz通过。

```bash
python3 hardware/synth.py --version csa --scope all --frequency 400 --output .build/csa400
python3 hardware/frequency.py --mapping .build/csa400 --version csa --output .build/frequency400
```
