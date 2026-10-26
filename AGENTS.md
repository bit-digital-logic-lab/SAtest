# 工程约定

- 当前有用户要求的两个版本：`hardware/versions/csa/`共享行加法CSA；`hardware/versions/normal/`单拍普通累加。共用接口、乘法器和32×32控制位于`hardware/rtl/`；编译时只选一个版本，不混读同名模块。
- 阵列按固定拍数执行，内部不增加ready/反压或按busy等待；零值只关闭数据更新，不改变日程。驻留部分和上传/下载复用原累计寄存器，每拍8个INT32按整行移位，8×8上传与下载各8拍。
- 按算术模块→PE→4×4块→8×8→32×32分层；CSA版PE内为乘法和两数压缩，最终CPA由4×4共享；普通版PE为乘法加单拍普通累加；A/B直达PE，水平及上下行通道由4×4块管理。
- 不修改 `model/SA_model.py`，除非用户明确授权。
- 可使用Luna子智能体；用户已允许调用本地OpenCode DeepSeek，结果须由主智能体独立验收。
- 注释用简短中文：文件作用及关系、模块/函数用途、关键变量和复杂语法。模块端口、枚举项和逻辑块需有中文注释；逐条说明assign含义，if/else分支解释数据流、条件与优先级，always说明流水和更新职责。
- 清理前全部方案及报告在Git标签 `archive/all-strategies-before-cleanup-20261025`。旧实验在Git标签 `archive/experiments-20261025`，上一轮双版本草稿在 `archive/two-array-draft-20261025`，不擅自push。原始题目、数据、权重保留。
- 新对话读取 `/home/yang/.codex/skills/quarter-hour-check/SKILL.md`；超过15分钟的任务登记进度和实际结束状态。
