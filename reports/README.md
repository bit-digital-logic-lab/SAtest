# 当前CSA结果

主线为8×8共享行加法CSA，部分和每拍8个INT32，输入/输出各8拍。每个32×32×32任务1024拍，99×64×256层65536拍，150MHz计算侧7.425GOPS（外部DMA时间另计）。

[完整实验报告](row8_adder150.md)｜[结构化结果](result.json)｜[源码、综合及时序证据](row8_adder150_evidence.zip)

当前主线保留两拍共享CPA；独立实验已验证32+32位加法及相关4×4写回路径可以在150MHz单拍完成。面积/时序为55nm SS预布局映射，功耗为统一活动率估计。

旧方案、原始四方案对比在Git标签`archive/all-strategies-before-cleanup-20261025`；64拍标量部分和版本在`archive/csa-scalar-psum-20261026`。主目录仅保留当前一套RTL。
