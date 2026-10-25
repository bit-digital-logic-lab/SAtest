# 当前CSA测量摘要

共享行加法CSA为唯一研发主线：64个A12W10乘法器、每PE驻留sum/carry、每4×4共享四路两拍CPA；无内部反压。

| 项目 | 结果 |
| --- | ---: |
| 32×32×32周期 | 2816 |
| 99×64×256层周期 | 180224 |
| 150MHz有效吞吐 | 2.700 GOPS |
| 8×8核心面积 | 0.23360064 mm² |
| 核心触发器 | 10084 |
| 核心setup余量 | 2.287006 ns |
| 含存储模块面积 | 0.89924492 mm² |
| 含存储模块setup余量 | 2.656639 ns |
| 核心功耗估计，α=0.1 | 23.55978 mW |

面积/时序/功耗来自清理前同一CSA电路的55nm SS/1.08V/125°C映射，尚未布局布线，功耗为统一活动率估计。目录清理后重新运行完整功能回归与Yosys结构检查；此摘要不冒充清理后重新映射的结果。详细统计保留在result.json。

所有旧方案、四方案对比和原始日志保存在Git标签`archive/all-strategies-before-cleanup-20261025`；旧CSA还可用`csa-per-pe`，共享CSA初版为`csa-shared-row`。主目录不保留多份代码。

```bash
git show archive/all-strategies-before-cleanup-20261025:reports/csa_compare/README.md
```
