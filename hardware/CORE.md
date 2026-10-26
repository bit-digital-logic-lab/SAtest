# 核心及PE连接：零值隔离、有效位与固定节拍

本页说明已有核心的实际连线，并给出可执行回归入口。没有改变乘法流水级数、阵列节拍、算术或外部接口。

## 源码入口

| 层次 | 文件 | 职责 |
| --- | --- | --- |
| 三级乘法 | [kwt_mul.sv](rtl/kwt_mul.sv) | 接收A12/W10，逐级冻结无效/零位置的数据，控制标记照常推进 |
| CSA PE | [kwt_pe_csa.sv](versions/csa/rtl/kwt_pe_csa.sv) | `mul_valid && mul_enable`驱动驻留CSA |
| 驻留CSA | [kwt_csa32.sv](versions/csa/rtl/kwt_csa32.sv) | 非零乘积才更新sum/carry；行装载和最终写回有独立优先级 |
| 4×4连接 | [kwt_quad4x4.sv](versions/csa/rtl/kwt_quad4x4.sv) | A/B广播、原和行链、四路共享最终加法器 |
| 分段最终CPA | [kwt_row_adder.sv](versions/csa/rtl/kwt_row_adder.sv) | 低16/高16两拍相加，结果回写原PE |
| 8×8阵列 | [kwt_array_quad.sv](versions/csa/rtl/kwt_array_quad.sv) | 四个4×4块的连接、交替出行及8拍整行下载 |
| 32×32块 | [kwt_block32.sv](rtl/kwt_block32.sv) | A/B/C驻留、固定核任务调度 |
| 普通PE | [kwt_pe_mac.sv](versions/normal/rtl/kwt_pe_mac.sv) | 同样用延迟后的非零标记更新单拍ACC32 |
| 双乘PE | [kwt_pe_dual.sv](versions/dual/rtl/kwt_pe_dual.sv) | 两个独立三级乘法器、逐路屏蔽旧积、组合CSA+ACC28 |
| 行接口 | [kwt_interfaces.sv](rtl/kwt_interfaces.sv) | 部分和通道；A/B是独立端口 |

## 用户方案与现有RTL的对应

```text
当前A/B → nonzero=(A!=0 && B!=0)
             ↓
in_valid → valid_q[0] → valid_q[1] → valid_q[2] → out_valid
in_valid & nonzero → enable_q[0] → enable_q[1] → enable_q[2] → out_enable
             ↓              ↓              ↓
       操作数a_q/b_q     部分积low_q/high_q    product
```

| 位置 | 真正的数据更新条件 | 零值/空拍时 |
| --- | --- | --- |
| 第一级 | `in_valid && nonzero` | A/B原操作数保持，阻止外部无效变化进入部分积算术 |
| 第二级 | 边沿前的`enable_q[0]` | 部分积寄存器保持 |
| 第三级 | 边沿前的`enable_q[1]` | 乘积寄存器保持旧值 |
| 普通/CSA累加 | `out_valid && out_enable` | 不把保持的旧乘积再次累加 |
| 双乘累加 | 两路有效且至少一路非零 | 全零组保持ACC；零lane先屏蔽成0，另一lane仍正常参与 |

用户的`zero_pipe`是延迟的零标记；这里`enable_q`是包含有效位的延迟非零标记。它同时处理零乘数和`in_valid=0`的空拍，不额外增加一套重复流水寄存器。

**不要把每一级都与当前拍输入使能相与。** 例如前一拍接收非零输入，本拍`in_valid=0`：首级应保持，前一项仍必须进入第二级；再下一拍进入第三级。输入有效位不是暂停整条流水的全局时钟使能。

乘法器无效时可能保留旧非零product，因此PE端的使能屏蔽不可省略。双乘PE尤其不能因一路零而丢弃另一条非零乘积。

## 固定日程与功耗边界

- 零值也占原来的流水位置，发射节拍不变；CSA/普通/E2的32×32任务仍分别1024/864/608拍。
- C上传与下载分别8拍、每拍8字；零乘积不能阻止合法的旧和装载、最终CPA写回或结果行移位。
- 冻结首级可以阻止该零位置带来新的乘法组合翻转；此前已进入流水的非零项仍须完成。
- 此处是数据寄存器使能/操作数隔离，不是ICG时钟门控。有效位、使能和时钟网络仍可能翻转，不能据此声称整PE零功耗或实测功耗降低某个百分比。

## 实际验证

```bash
# 独立整数参考、真实寄存器保持与三种PE连线
python3 hardware/check_core.py
# 追加三个正式阵列的尾块、全零、稀疏、极值矩阵与结构检查
python3 hardware/check_core.py --matrix
```

测试台：[tb_kwt_core_isolation.sv](tb/tb_kwt_core_isolation.sv)。

逐拍检查包含1024组混合输入、连续零段、交错空拍、独立双乘零lane、原和装载、在飞行中复位；比较普通整数乘加参考与普通/CSA/双乘PE输出，不在参考中复制CSA逐位算法。另直接断言真实操作数、部分积、乘积和PE状态在各自无使能时保持。

本次逐拍结果：1070次检查；首级保持603次、第二级604次、第三级604次、普通/CSA PE保持602次，全部通过。矩阵复测结果与源文件指纹见[结构化记录](../reports/core_isolation.json)。

本次对原算术RTL只进行检查，没有为重命名零标记而修改核心，原有综合结果仍对应同一份核心源码。CPU/NICE外层不在这份核心测试的验收范围内。
