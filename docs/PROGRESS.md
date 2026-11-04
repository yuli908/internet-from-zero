# 进度与偏差（PROGRESS）

- 里程碑：**M1 · 第一章 6 节垂直切片**
- 基线日期：2026-11-04
- 口径：只有**跑过、有证据**的项才标"已完成"；没验证的一律标"需人工"或"未完成"，不写成通过。
- 证据目录：`artifacts/shots/`（11 张截图）、`artifacts/logs/`（导入/测试/冒烟日志）

## 1. 一句话结论

M1 已经**可启动、可操作、可存档、可自动测试**：6 节实验 + 24 条 gate + 多解黑盒 + L0a/L0b/L1 仿真；
`RESULT: 920 checks, 0 failures`。**没有**做到：L2–L7、原生 GDExtension、沙箱与真实集成、性能实测、题库与逐题评分、
更远版本的前向迁移（当前只有 v1→v2→v3 迁移链）、真实 CI 验证——这些要么只有 ADR，要么完全没有。

## 2. 已完成（附验证方式）

| 项 | 内容 | 验证 |
|---|---|---|
| 数据层 | 8 个 JSON（manifest 版本 2）：86 物品（77 正式 + 7 旧别名 + `scrap` 材料 + `gold` 货币）、37 买价 / 61 回收价、77 配方、36 节点（7 里程碑 / 19 知识 / 10 技能）、6 实验 / 24 gate、延迟表、引导、manifest | `tests/test_data.gd`；启动日志 `IFZ_BOOT data_ok=true files=8 chapter=ch01` |
| 纯逻辑层 | `src/core`：`SimValue`/`VoltageModel`/`LabChecks`/`BlackBox`/`CircuitGraph`/`KnowledgeGraph`/`EconomyCore`/`ChapterRuntime`/`PlayerState`/`SaveCodec`/`SaveStore`…（不依赖 autoload） | headless 直测；`tests/run_tests.gd` 是 `SceneTree` 脚本，不加载主场景 |
| 仿真 L0b/L1 | `src/sim`：Kleene 三值 + 整数 tick + `(tick, seq)` 堆 + 传输延迟/惯性过滤 + 毛刺 + 静止快照 + digest | `tests/test_sim.gd`：30 条门向量 + 9 条半加器向量 + 延迟表、同 tick 顺序、1 vs 4 tick/帧一致、快照往返 digest 一致、毛刺宽度与修复 |
| 判定层 | `LabChecks` 输出 `GateReport`，UI 只采集与展示；24 条 gate 逐条判定 | `tests/test_lab_checks.gd`：每种 lab 的"正确解全过 + 错误解失败"两条路径 |
| 多解验收 | `BlackBox` 只判行为不判拓扑；XOR 两种结构、半加器 | `tests/test_black_box.gd`：多解通过、错误拓扑失败、`signature` 区分结构 |
| 存档 | 信封 v3 + SHA-256 + 原子写 tmp→校验→`.bak`→rename；主文件坏则回退 `.bak`；迁移注册表串联 v1→v2→v3（未知字段保留） | `tests/test_save.gd`：篡改检测、坏 JSON 拒绝、`.bak` 回退、往返一致、v1/v2 迁移（含 `scrap`→`gold`）、v4+ 拒绝 |
| 经济/知识/章节/引导 | 金币 + XP、商店与配方、技能树四态、章节目标与奖励、引导步骤 | `tests/test_economy/test_knowledge/test_chapter/test_tutorial.gd` |
| UI | 工作台（6 实验卡）、6 个实验页、知识树、商店、档案、诊断；点击式电路编辑器；波形与判读条 | `artifacts/shots/*.png`（workbench/shop/skills/archive/diagnostics + lab_level…lab_half_adder） |
| 工程化 | `README.md`、5 篇 ADR、本文件、4 个 PowerShell 脚本、CI 草案、`native/` 脚手架 | 本文档与 `scripts/selfcheck.ps1` |

### 2.1 自动测试构成（12 套件，920 项）

`bit_math` / `logic_gates` / `circuit` / `economy` / `knowledge` / `chapter` / `tutorial` / `save` / `data` / `sim` / `black_box` / `lab_checks`

## 3. 偏差表（原规格 / 实际实现 / 原因）

| # | 原规格 | 实际实现 | 原因 |
|---|---|---|---|
| 1 | L0a 模拟电平：模拟电路求解（RC 固定子步长） | 电压判读带 + 阈值判定（`src/core/voltage_model.gd`、`ui/widgets/level_gauge.gd`），不做连续时间电路求解 | M1 只要求 L0–L1 接口与确定性 tick；连续求解器属后续里程碑 |
| 2 | 门级仿真宿主允许 C++/Rust GDExtension | 纯 GDScript（`src/sim/`），≤200 门满足预算；`native/` 仅有脚手架、未编译 | 先保证可运行与可测；性能实测与原生移植列为需人工/后续 |
| 3 | 性能预算：5 ms/帧、4 tick/帧、≤200 门/200 DFF | 按设计约束实现，**尚未实测**；超标策略"降速不丢事件"已体现在 `SimEngine` 的 tick 推进与单 tick 上限 | 未建立基准关；数值来自 `docs/simulation/06` 的估算 |
| 4 | 内嵌 Linux、宿主编译器桥接（汇编/C/Java/Python）、沙箱进程隔离与资源限制 | 均未实现，仅有 ADR 设计（0004） | M1 范围克制在 L0–L1 |
| 5 | 存档版本迁移 | 信封 v3 + **迁移注册表**（`SaveCodec.MIGRATIONS`，v1→v2→v3 串联）；`tests/test_save.gd` 断言 `migrated_from=1/2`、`scrap`→`gold` 改名、未知字段保留；v4+ 存档被明确拒绝而非尝试迁移 | 只有一次结构调整时不做框架是克制；货币改名带来第二次结构变化，遂补注册式迁移器 |
| 6 | 练习：文档 42 道、每题 ≥2 解 | 第一章 24 条 gate（每节 4 条）+ 黑盒多解验收（XOR 两种结构、半加器）；题库与逐题评分表未落地 | M1 只覆盖第一章 |
| 7 | 电路编辑：设计台 HUD/自由布线（拖拽、吸附、撤销重做） | 点击式编辑器（点空白放门、点端口连线、右键断线/删门），不支持拖拽 | 先保证可操作与可判定 |
| 8 | 引导浮层：原实现为右下浮动面板 | 会遮挡实验操作区；已改为标题栏下方文档流内横条（`main.gd::_build_tutorial`） | 浮层遮挡与"提示不覆盖工作台"的设计硬规则冲突 |
| 9 | 截图（无明确后端要求） | 截图只能在 GUI 后端生成（headless 无渲染）；验收用窗口模式 1600×900 自动截图后退出 | headless 的 viewport 无纹理可读 |
| 10 | 以 `--editor --quit` 作为可启动性检查 | 不会编译"运行时才 `load()`"的脚本，曾漏掉 `lab_binary.gd` 语法错误；已改为"跑 11 张截图 + 扫描日志 ERROR"作为可启动性冒烟 | 导入检查只覆盖被引用/被扫描到的资源 |
| 11 | CH01 里程碑额外奖励 | CH01 里程碑不额外给金币（奖励在 lab 的 `reward` 里）；章末 `complete_reward` 为 `gold 0 / xp 50`，另由 `data/skilltree.json` 的 `CH01` 节点发放 `gold_award 25 / xp_award 50` | 里程碑奖励与 lab 奖励分开配置，避免重复发放 |
| 12 | 首位玩家初始资源 | 初始金币 120，初始物品 M01/M09 各 1（`ch01_levels.json` 的 `start_gold/start_items`） | 与 `docs/design/03` §3 的初始 120 对齐 |
| 13 | 货币单位 | 货币单位曾是 `scrap`（废铁），已按负责人裁决改为 **`gold`（金币，单位 g）**；`scrap` 降级为普通材料/回收物（`kind=material`）；旧档通过存档 v3 迁移（`scrap`→`gold`）兼容 | 与 `docs/design/03` §3「金币 g」口径统一；单字货币让材料与通货语义混淆 |

### 3.1 偏差 11 的数值组成（避免"25 金币/50 XP"读成单一来源）

- 六节 lab 奖励合计：`20+30+25+35+20+30 = 160` 金币，`10+15+10+20+10+15 = 80` XP（`ch01_levels.json`）。
- 章末 `complete_reward`：`gold 0`、`xp 50`、`badge CH01-FIRST-ADDER`。
- 章末 `Knowledge.unlock("CH01")`（`skilltree.json` 的 `CH01` 节点）：`gold_award 25`、`xp_award 50`。
- 合计章末额外：**25 金币 / 100 XP**（50 来自 `complete_reward` + 50 来自节点）。

## 4. 未完成（需人工）/ 未完成

| 项 | 状态 | 说明 |
|---|---|---|
| 性能基准关（64/256/1024 门、全翻转场景、5 ms/帧实测） | **需人工** | 数值仍是 `docs/simulation/06` 的估算；未实测就不能对外宣称 200 门 |
| 原生 GDExtension（编译、与 GDScript 同向量、接入 `project.godot`） | **未完成** | `native/` 只有脚手架：核心自检 `ifz_selftest` 已在 MinGW g++ 15.1 + CMake 下编译并通过（1/1），但 **GDExtension 动态库未构建**，MSVC 未验证，未接入 `project.godot` |
| 延迟常量三方一致校验（`delays.json` == `docs/simulation/03` == 原生头文件） | **未完成** | 当前靠人工核对，CI 无此步骤 |
| 存档前向迁移框架（注册式迁移器 + fixture + 迁移链契约测试） | **未完成** | 见偏差 5；v2→v3 之前必须补 |
| 沙箱、编译器桥接、L7 伴生进程与「转发」标记 | **未完成** | 仅 ADR 0004 设计，无代码 |
| L2 组合模块封装 / `t_settle` 声明 / L3 DFF 与亚稳态 / L4 CPU / L5 总线 / L6 网络 | **未完成** | 仅接口占位（ADR 0005 §2）；`delays.json` 里 `dff` 只是常量 |
| 统一 `TraceSink`（`(tick, layer, kind, subject, payload)`） | **未完成** | 现为 `SimCircuit.history` + `glitches` 两数组 |
| 冒险三档（`EXPLAIN/SYNC/MASK`）开关 | **未完成** | 当前固定为 EXPLAIN 行为 |
| 错误码编号（`docs/simulation/07` §5 的 0–18） | **未完成** | 现为字符串错误 |
| 42 道练习题库与逐题评分表 | **未完成** | 只有第一章 24 条 gate + 多解黑盒 |
| 6 节手动走查（操作 → 验收 → 知识树 completed → 存档 → 重启续玩） | **需人工** | 自动测试只验证判定层与数据，不覆盖真实点击路径 |
| 截图冒烟之外的交互验证（拖拽/撤销不出现在 M1）、引导 6 步真实走查 | **需人工** | 需真人按 `docs/design/08` 走一遍 |
| `.github/workflows/ci.yml` 在真实 GitHub Actions 上运行 | **需人工** | 本地无法验证；文件内已注明"未在真实 CI 上验证" |
| 知识卡内容补全（设计目标 ~180 张） | **未完成** | 当前 `skilltree.json` 只有 19 个知识节点（多为一句话摘要），设计文档已标【假设】 |
| 波形光标测量（`docs/design/03` T1.5 要求测量光标差值） | **需人工** | 波形控件存在，光标/测量功能未在本文档验证，需人工检查后再定论 |

## 5. 已知文档 ↔ 工程冲突（不自行改代码，交负责人裁决）

| 冲突 | 文档侧 | 工程侧 | 建议 |
|---|---|---|---|
| 配方条数 | 早期盘点写"80 配方" | `data/economy/recipes.json` 实为 **77 条**；`tests/test_data.gd` 断言 `recipes >= 77` | **已裁决：以实测 77 条为准**（04 表合计即 77；05 无配方计数）。历史上的 80 来源于早期盘点未按章节去重 |
| gate 测试文件名 | `specs/m1/spec.md` §4.4.4 写 `tests/test_gate_cases.gd` | 实际由 `tests/test_lab_checks.gd` 覆盖 24 条 gate（无独立文件） | 已解决：规格措辞改为 `tests/test_lab_checks.gd`，并注明 24 条 gate 与黑盒多解均在该套件内 |
| 货币命名 | `docs/design/03` §3 用"金币 g" | 工程、数据与 UI 已统一为"金币 g"（id `gold`）；废铁 `scrap` 仅为材料/回收物 | 已裁决并落地（偏差 13）；旧档经 v3 迁移兼容 |
| 快照格式 | `docs/simulation/02` §8.1 `ifz-sim/1`（含 regs/memory/timers/next_seq） | `SimCircuit.snapshot()` 为 `ifz-circuit/1`（tick + wires + digest） | M1 无寄存器/内存，属合理子集；升 L3 时要换格式（ADR 0003 §5） |
| 电路编辑交互 | `docs/design/03` §1.2：拖拽放置、吸附 24 px、直角绕线、`Z/Y` 撤销重做 50 步 | 点击式，无拖拽/无撤销 | 偏差 7；若坚持拖拽需单独立项 |
| 引导位置 | 设计未明确要求浮动，但原实现浮在右下 | 已改为文档流横条（偏差 8） | 已解决，记录备查 |
| 知识卡规模 | `docs/design/07`：~180 张 | 19 个知识节点 | 教学内容待补（未完成） |
| 原生脚手架与启动日志 | 需求：`native/ifz_native.gdextension` 必须存在 | Godot 会自动扫描项目里所有 `.gdextension`，dll 未构建时会打印 3 行 `ERROR: GDExtension dynamic library not found`（实测）；已加 `native/.gdignore` 抑制（实测带/不带：0 vs 5 处 ERROR） | 属脚手架副作用；启用原生时必须删 `.gdignore`。`scripts/selfcheck.ps1` 会剥掉这条已知残留并单独提示 |
| 文本编码 | — | `tests/test_lab_checks.gd` 首字节为 BOM（`\ufeff`），其余脚本无 BOM；`scripts/*.ps1` 必须带 BOM（PowerShell 5 否则按 ANSI 解码，中文注释会导致解析失败，已实测） | 不阻塞运行；统一编码需与代码负责人协调 |

## 6. 下一步（M2 建议顺序）

1. **性能基准关**（需人工，1 天）：固定场景 + 计时，产出 `artifacts/logs/bench.log`，回填上限。
2. **手动走查 + 存档续玩**（需人工，0.5 天）：按 6 节各跑一遍"操作 → 验收 → 知识树 → 重启读档"。
3. **存档迁移框架**：注册式迁移器 + v1/v2 fixture + 迁移链测试（为 M2 新字段做准备）。
4. **L2 模块化**：半加器/全加器/加法器的 `t_settle` 声明与等价性测试；把 `BlackBox` 升级为可复用模块。
5. **原生下沉评估**：仅在基准关超标时启动（ADR 0002 §5）。
6. **TraceSink 统一**：先把 `history/glitches` 映射进统一流，再谈回放。
7. **题库接入**：把 `docs/curriculum/03` 的 42 道练习数据化，接 `LabChecks` 同构判定。

## 7. 验证命令（当前基线的复现方式）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1     # 期望 RESULT: 902 checks, 0 failures
powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1     # 导入 + 测试 + GUI 冒烟
powershell -ExecutionPolicy Bypass -File .\scripts\run_game.ps1      # 手动操作
```

截图证据（已存在，作为验收依据；是否入库由负责人决定）：

```
artifacts/shots/workbench.png  shop.png  skills.png  archive.png  diagnostics.png
artifacts/shots/lab_level.png  lab_binary.png  lab_boolean.png  lab_gate.png  lab_signal.png  lab_half_adder.png
```
