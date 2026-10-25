# 工程约定

- RTL按 `hardware/rtl/common/` 公共层及 `outside/`、`inside_traditional/`、`inside_csa/` 三种架构分层；顶层通过 `ARCH=0/1/2` 选择。
- 阵列按固定拍数执行，内部不增加ready/反压或按busy等待；零值只关闭数据更新，不改变日程。驻留部分和上传/下载复用原累计寄存器，按4×4块序连续移位、块内按行序。
- 两个驻留版本按算术模块→PE→4×4块→8×8→32×32分层，不引入column管理驻留PE；A/B直达PE，水平及上下行通道由4×4块管理。column仅保留在阵列外加法版。
- 不修改 `model/SA_model.py`，除非用户明确授权。
- 仅使用 Luna 子智能体。
- 注释用简短中文：文件作用及关系、模块/函数用途、关键变量和复杂语法。模块端口、枚举项和逻辑块需有中文注释；逐条说明assign含义，if/else分支解释数据流、条件与优先级，always说明流水和更新职责。
- 旧实验在Git标签 `archive/experiments-20261025`，上一轮双版本草稿在 `archive/two-array-draft-20261025`，不擅自push。原始题目、数据、权重保留。
- 新对话读取 `/home/yang/.codex/skills/quarter-hour-check/SKILL.md`；超过15分钟的任务登记进度和实际结束状态。
