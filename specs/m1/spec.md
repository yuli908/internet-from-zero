# M1 实施规格：第一章垂直切片（可运行）

- 状态：待批准
- 日期：2026-11-04
- 范围：M0 仓库骨架收尾 + M1 第一章 6 节竖切
- 依据：`docs/design/03`、`04`、`05`、`07`；`docs/curriculum/02`、`03`、`05`、`07`；`docs/simulation/README.md`、`01_model_layers.md`、`09_feasibility_risks.md`、`ref/`
- 约束：`docs/design`、`docs/curriculum`、`docs/simulation` 只读；本规格不改动三处文档。

## 1. 目标

1. 工程可启动、可操作、可存档；第一章 6 节逐节可玩。
2. 章节、物品、配方、价格、技能/知识节点、gate 用例全部来自 JSON，脚本不硬编码数值。
3. 仿真只打通 L0a（电平判读）、L0b（三值数字信号）、L1（门级事件仿真）与确定性 tick；L2 以上仅保留接口与 ADR。
4. 判定为行为黑盒：同一目标允许多种电路拓扑；gate 结果写入知识树与存档。
5. 自动测试覆盖真值表、进制转换、存档往返、gate 用例、仿真与参考实现同向量一致。

## 2. 现状盘点

已完成（本轮之前）：
- `data/`：85 物品（77 文档物品 + 1 货币 + 7 旧别名）、37 项买入价 / 61 项回收价、80 条配方、36 节点三树、6 实验 + 6 目标、6 段实验数据与 24 条 gate 用例、延迟表、引导配置、manifest。
- `src/core`：`SimValue`（Kleene 三值）、`SimDelays`、`SimEngine`（(tick,seq) 最小堆）、`SimCircuit`（线网/延迟/毛刺/快照）、`BlackBox`（多解验收）、`SignalLabModel`、`GateReport`、`CircuitGraph`、`KnowledgeGraph`、`EconomyCore`、`ChapterRuntime`、`PlayerState`。
- `src/autoload`：EventBus / DataDB / GameState / SaveManager / Knowledge / ChapterFlow / Economy / Tutorial。
- 已有 UI：`main.gd`、`ui.gd`、`ui_theme.gd`、`LabBase`、`GameScreen`、`lab_level.gd`（**有解析错误，需重写**）、`LevelGauge`（单阈值，需重写）、商店/档案/诊断（子代理产出，未运行验证）。

阻断项：
- `src/ui/screens/workbench_screen.gd`、`skill_screen.gd` 缺失，但 `main.gd` 已 preload。
- `lab_level.gd` 两处未闭合括号。
- `Catalog` 缺 `recipe_ids()`；商店页按 `outputs` 读配方，而数据用 `output`。
- 旧测试按旧数据/旧 API（8 物品、3 配方、`HalfAdder` 等），需更新。

## 3. 架构决策

### 3.1 分层与职责

| 层 | M1 实现 | 说明 |
|---|---|---|
| L0a 模拟电平 | `VoltageModel` + `LevelGauge` | 纯 UI 判读，阈值来自 `labs.level.voltage`；不进入离散事件队列 |
| L0b 数字信号 | `SimValue` | 0/1/X Kleene 三值 |
| L1 门级 | `SimCircuit` + `SimEngine` | 线网传输延迟、整数 tick、毛刺监视、静止快照 |
| L2+ | 仅 ADR 与占位说明 | 不实现，避免「全门级仿真」误入 |

`docs/simulation` 契约映射：`CircuitGraph`（编辑器拓扑/人类可读）→ `SimCircuit.build_graph()`（线网+延迟）→ `SimEngine`（事件）→ `BlackBox`（向量验收）。存档只存 `CircuitGraph.to_dict()` + 结果 flags，不存仿真堆。

### 3.2 判定层必须可无头测试

新增 `src/core/lab_checks.gd`（`class_name LabChecks`），把 24 条 gate 用例的判定从 UI 抽离：
- 输入：实验配置字典 + 玩家操作结果（电压、visited、表格、电路图、quiz 选项、延迟/毛刺测量）。
- 输出：`GateReport`（逐条 `ok/detail/required`）。
- UI 只负责采集与展示，`LabChecks` 不依赖 autoload / 场景树。

### 3.3 帧与确定性

- `SimDelays.frame`：60 FPS、5 ms、4 tick/帧；每帧最多跑 4 tick。
- 超预算只减少本帧 tick 数（降速），事件堆不丢；单 tick 事件数超 `limits.max_events_per_tick` 时显式失败并保留事件。
- 所有实验动作以 tick 计数；存档存 `flags`（含 `labstate:<lab>`、`gate:<id>`、`lab:<id>`），不存瞬时堆状态。

### 3.4 UI

- 低饱和深色、硬朗、大字号、基础几何 + 文字；复用 `UiTheme` / `Ui`。
- 自由电路编辑器采用**点击式**画布（非拖拽）：调色板选门 → 画布落点；点输出端口 → 点输入端口连线；右键删除；点输入节点翻转电平。
- 不使用外部图片；字体用 `SystemFont`（Microsoft YaHei UI）。

## 4. 实施清单

### 4.1 数据与索引

1. `src/core/catalog.gd`：新增 `recipe_ids() -> Array`、`recipe_for_output(id) -> String`（支持 `output` 字符串与旧 `outputs` 字典）。
2. `src/ui/screens/shop_screen.gd`：
   - `_recipe_for_output` 改用 `Catalog.recipe_for_output`；
   - `_format_entries` 支持 `output` + `output_qty`；
   - 层级分组排序改为 `L0a,L0b,L0,L1...L7` 后其他（按现有 `layer` 值容错）。
3. `src/autoload/data_db.gd` 复查：`validate()` 已存在；实验室数据、gate_ids、技能条件、sim 表校验保留。
4. 数据不改数值；若发现 JSON 结构错误，修 JSON 并在 `docs/PROGRESS.md` 记录。

### 4.2 纯逻辑核心（新增/修正）

1. `src/core/voltage_model.gd`（新）
   - `static judge(v: float, low_max: float, high_min: float) -> String` 返回 `"0"/"1"/"X"`，边界：`v <= low_max → 0`，`v >= high_min → 1`，其余 X。
   - `static label(v) -> String`、`static cases_report(cfg: Dictionary) -> GateReport` 执行 `voltage_judge` 用例。
2. `src/core/lab_checks.gd`（新）
   - `voltage(cfg, values_seen) -> GateReport`
   - `binary(cfg, visited: Dictionary, current_value: int, quiz_answer: int) -> GateReport`
   - `boolean(cfg, filled: Dictionary) -> GateReport`（每门逐行比对；demorgan 用 `SimValue.bin3` 计算四行）
   - `gate(cfg, graphs: Dictionary, checkpoints: Dictionary) -> GateReport`（and/or/not/xor/封装/second/delay）
   - `signal(cfg, measured_delay: int, glitch_width: int, fix_clean: bool, quiz_answer: int) -> GateReport`
   - `half_adder(cfg, graph: CircuitGraph, measured_delay: int, encapsulated: bool, random_rows: Array) -> GateReport`
   - 所有函数只依赖数据与核心类，供 headless 测试直接调用。
3. `src/core/black_box.gd`：最小修正（`check_outputs` 去掉多余重建；`depth` 返回稳定值；`signature` 对 X 也稳定）。
4. `src/core/signal_lab_model.gd`：保持 `measure_chain=9`、`pulse_after_c_fall`、`run_fixed("equalize", 20)`。

### 4.3 UI 页面与控件

1. `src/ui/widgets/level_gauge.gd`（重写）：双阈值带（0–0.8 低、0.8–2.0 禁区、2.0–3.3 高），灯泡亮/灭/X；刻度 0–3.3。
2. `src/ui/widgets/bit_switches.gd`（新）：8 位开关，返回 `value`；信号 `changed(value)`。
3. `src/ui/widgets/waveform.gd`（新）：按 `SimCircuit.history` 绘制数字波形与毛刺高亮。
4. `src/ui/widgets/circuit_editor.gd`（新）：点击式编辑器；`setup(inputs, outputs, palette, max_gates)`；`graph`、`changed`、`evaluate()`、`build_sim(delay)`、`set_input()`、`add_gate_at()`、`link()/unlink()`、`to_dict()/from_dict()`、`gate_count()`；绘制门符号（AND/OR/NOT/XOR 基本几何）。
5. `src/ui/screens/workbench_screen.gd`（新）：左侧 6 实验卡（锁定原因、进度）；右侧嵌入实验页；`select_lab(id, announce)`；`on_show()` 刷新；`EventBus.fire("lab_opened:<id>")`；连接实验页 `solved` → `ChapterFlow.complete_lab(id)` → 刷新 → 自动存档。
6. `src/ui/screens/skill_screen.gd`（新）：三列（进度/知识/技能），节点四态配色；可解锁节点给「解锁」按钮；详情面板显示 title/desc/前置。
7. `src/ui/screens/lab_level.gd`（重写）：数据驱动滑杆/预设/双阈值；实时判读；「运行验收」按钮调用 `LabChecks.voltage`；全部 required 通过才 `complete_once()`。
8. `src/ui/screens/lab_binary.gd`（新）：8 位开关；十进制/十六进制/二进制；覆盖 0–15；两个目标；三进制 quiz；验收按钮。
9. `src/ui/screens/lab_boolean.gd`（新）：AND/OR/NOT 真值表可点击循环 0→1→X；德摩根验证；逐门验收。
10. `src/ui/screens/lab_gate.gd`（新）：CircuitEditor 复用；任务 A–D；XOR 延迟 ≤12（`SimDelays`）；封装按钮；第二结构用 `BlackBox.signature` 去重；验收。
11. `src/ui/screens/lab_signal.gd`（新）：三级非门测延迟；毛刺波形；equalize 修复 20 次；quiz；验收。
12. `src/ui/screens/lab_half_adder.gd`（新）：双输出编辑器；4 行真值；延迟 ≤12；封装；8 组含 X 随机；验收。
13. `src/ui/screens/lab_base.gd` 增补：`save_state(dict)` / `load_state()`（写 `labstate:<lab_id>`）、`gate_flags()`、`pass_report(report)`（只在 required 全过时置 flags 并 `complete_once`）。
14. `src/ui/main.gd`：仅在必要时修正 `show_lab` 兼容；不改变导航结构。

### 4.4 测试

1. 更新旧测试：`tests/test_data.gd`（manifest 8；非 legacy 77；配方完整性；节点四态条件；6 实验/24 用例）、`test_chapter`、`test_economy`、`test_knowledge`、`test_save`、`test_tutorial`（按新 API）。
2. 新增 `tests/test_sim.gd`：Kleene 表、AND/OR/XOR/NAND/NOR/XNOR 真值、`SimEngine` 同 tick 顺序、1 vs 4 tick/帧结果一致、snapshot/restore、digest 稳定、毛刺宽度。
3. 新增 `tests/test_black_box.gd`：AND/OR/NOT/XOR/半加器多解通过；错误拓扑失败；`signature` 区分结构。
4. 新增 `tests/test_gate_cases.gd`：对 6 节各构造「正确解」与「错误解」，`LabChecks.*` required 全过/失败；覆盖 24 个 case id。
5. 新增 `tests/data/ref_vectors.json` + `tools/gen_ref_vectors.py`：从 `docs/simulation/ref` 导出真值向量；测试逐条与 `SimCircuit` 结果比较（同向量一致）。
6. `tests/run_tests.gd` 注册新套件；`tests/test_util.gd` 如需补读取 ref_vectors。

### 4.5 工程化

1. `README.md`：项目简介、目录、运行/测试/截图/备份命令、M1 操作说明。
2. ADR：`docs/adr/0001-engine-architecture.md`、`0002-native-boundary.md`、`0003-save-and-determinism.md`、`0004-sandbox-and-real-integration.md`、`0005-simulation-contract.md`（含 L0–L7 契约→ECS/数据驱动映射与 Godot 冲突偏差）。
3. `docs/PROGRESS.md`：已完成/未完成、偏差表（原规格/实际实现/原因）、下一步。
4. `scripts/run_game.ps1`、`run_tests.ps1`、`selfcheck.ps1`、`backup.ps1`。
5. `.github/workflows/ci.yml`（headless 测试；本地无法完整验证则标注「需人工」）。
6. `native/` GDExtension 脚手架（CMake + register_types + `.gdextension`），M1 不编译，ADR 说明门数 >200 时才启用。
7. Git：每个子系统一次提交，信息含「做了什么/为什么」；不做破坏性操作。

## 5. 验收命令

```powershell
$godot = "C:\tools\godot-4.4.1\godot.cmd"
& $godot --headless --path "D:\ai lm\internet_from_zero" --editor --quit
& $godot --headless --path "D:\ai lm\internet_from_zero" -s res://tests/run_tests.gd
& $godot --path "D:\ai lm\internet_from_zero" -- --fresh --shot="artifacts/shots/workbench.png" --shot-screen=workbench
```

逐实验截图：`--shot-lab=level|binary|boolean|gate|signal|half_adder`；另截 `shop|skills|archive|diagnostics`。

通过标准：
- 启动日志 `IFZ_BOOT data_ok=true`，无脚本解析错误、无资源缺失、无 `ERROR:`。
- 测试 `ALL PASS`，含 ref 向量一致。
- 6 节 gate 用例在 UI 中可执行；通过后知识树节点变 `completed`、gate flags 入库。
- 存档保存/读取往返后 `scrap/xp/inventory/flags/knowledge` 一致。

## 6. 计划内偏差（写入 `docs/PROGRESS.md`）

1. 第一章教学脚本用「继电器 3 tick/级」；M1 用 `SimDelays.relay.delay_per_stage_ticks=3` 映射到信号实验，但门级 lab 用归一化门延迟（AND 3 / OR 3 / XOR 4 等），因此 `T1.4-2 延迟≤12 tick` 按归一化延迟判定。
2. 仿真规格要求 L2–L7 契约；M1 只实现接口说明与数据映射，不实现 CPU/总线/网络/加密。
3. 22 个参考器件不全量移植；仅移植 M1 涉及的 and/or/not/xor/nand/nor/xnor/buf/半加器/全加器/4 位加法器向量。
4. 「封装」在 M1 只做端口行为复核 + 存档标记，不产出可复用子电路资源。
5. 6 节中的「第二结构」用签名去重；只要求与第一解结构不同，不限定具体拓扑。
6. 42 道练习未全部数据化；M1 落地 6 节 gate（24 条）+ 多解黑盒；其余练习在 M2 接入。
7. 自由电路编辑器为点击式（非拖拽连线），以可用性优先。

## 7. 假设

- Godot 可执行文件为 `C:\tools\godot-4.4.1\godot.cmd`；首次需 `--editor --quit` 生成类缓存。
- 工程已在 `D:\ai lm\internet_from_zero` 且 `git` 可用；若未初始化则执行 `git init` + 基线提交。
- 截图输出目录 `artifacts/shots/` 可被创建（不作为交付源码提交）。
- GDExtension 本机缺少 MSVC/CMake 时不编译，M1 全部 GDScript 满足 ≤200 门。

## 8. 不做（M1 范围外）

- L2 组合优化、L3 DFF/寄存器、L4 微码 CPU、L5 总线、L6 网络 TCP-lite、L7 主机桥接。
- 内嵌真实 Linux、宿主编译器桥接、沙箱运行玩家代码（仅 ADR 设计）。
- 完整 42 题练习、第二章内容、美术资源与动画。
