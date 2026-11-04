# 互联网 · 从零重建（Internet From Zero）

> 文明断电之后，从一块电池开始，一层一层把互联网重新造出来。

教育模拟游戏：把"电 → 二进制 → 布尔 → 门 → 信号 → 加法器 → 计算机 → 网络"拆成可动手的实验关。
玩家不是读教材，而是亲手接线、看波形、造出第一台加法器。

- 引擎：Godot 4.4.1（GL Compatibility），语言 GDScript，平台 Windows
- 当前里程碑：**M1 = 第一章 6 节垂直切片**（1.1 电平 / 1.2 二进制 / 1.3 布尔 / 1.4 与或非 / 1.5 信号 / 1.6 半加器）
- 状态：可启动、可操作、可存档；6 节 24 条 gate 可机器判定；L0a–L1 仿真已落地，L2+ 只有接口与 ADR
- 基线日期：2026-11-04。完成度与偏差见 [`docs/PROGRESS.md`](docs/PROGRESS.md)

## 1. 现在能做什么

| 能力 | 证据 |
|---|---|
| 启动、导航（工作台 / 知识树 / 商店 / 档案 / 诊断） | 启动日志 `IFZ_BOOT data_ok=true files=8 chapter=ch01` |
| 6 个实验页、24 条 gate 判定 | `data/chapters/ch01_levels.json` + `src/core/lab_checks.gd`，`tests/test_lab_checks.gd` |
| 点击式电路编辑器（放门 / 连线 / 断线 / 翻转输入） | `src/ui/widgets/circuit_editor.gd` |
| 波形与毛刺、延迟测量 | `src/ui/widgets/waveform.gd`、`src/core/signal_lab_model.gd` |
| 存档（信封 v3 + SHA-256 + 原子写 + `.bak` 回退 + 迁移注册表） | `src/core/save_codec.gd`、`src/core/save_store.gd` |
| 自动测试 1350 项 / 13 套件 / 0 失败 | `scripts/run_tests.ps1` |
| 性能基准（p50/p95/p99/max） | `scripts/bench.ps1`、`tests/bench_sim.gd` |
| 11 张自动截图 | `artifacts/shots/*.png`（workbench / shop / skills / archive / diagnostics + 6 个 lab） |

## 2. 环境要求

- Windows 10/11 + PowerShell 5.1+
- Godot 4.4.1（本机路径 `C:\tools\godot-4.4.1\godot.cmd`；脚本允许用 `-Godot` 覆盖）
- 可选：Python 3.10+（只在需要重新生成参考向量 `tests/data/ref_vectors.json` 时用）
- 可选：CMake + MSVC + godot-cpp（`native/` GDExtension 脚手架，**M1 不编译**，见 ADR 0002）

## 3. 快速开始

```powershell
# 运行游戏（可透传任意用户参数）
powershell -ExecutionPolicy Bypass -File .\scripts\run_game.ps1

# 全量测试（headless）
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1

# 性能基准（N 门 + N DFF 每 tick 全翻转，4 tick/帧，输出 p50/p95/p99/max）
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1

# 自检：导入检查 → 测试 → 启动冒烟（GUI 截图 1 张）
powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1

# 备份（git bundle + robocopy，只增不删）
powershell -ExecutionPolicy Bypass -File .\scripts\backup.ps1
```

不经脚本的等价命令：

```powershell
& "C:\tools\godot-4.4.1\godot.cmd" --path "D:\ai lm\internet_from_zero"

& "C:\tools\godot-4.4.1\godot.cmd" --headless --path "D:\ai lm\internet_from_zero" --editor --quit

& "C:\tools\godot-4.4.1\godot.cmd" --headless --path "D:\ai lm\internet_from_zero" -s "res://tests/run_tests.gd"
```

截图（GUI 后端；headless 无渲染，不能截图）：

```powershell
$root = "D:\ai lm\internet_from_zero"
& "C:\tools\godot-4.4.1\godot.cmd" --path $root --resolution 1600x900 -- `
  "--shot=$root\artifacts\shots\workbench.png" --shot-screen=workbench --fresh
```

`--shot-screen` 取值 `workbench|shop|skills|archive|diagnostics`；
`--shot-lab` 取值 `level|binary|boolean|gate|signal|half_adder`；
`--fresh` 跳过读档、从新档启动。

## 4. 目录结构

```
internet_from_zero/
├─ project.godot          8 个 autoload（EventBus/DataDB/GameState/SaveManager/Knowledge/ChapterFlow/Economy/Tutorial）
├─ scenes/main.tscn       唯一主场景（三种视图在同一场景内切换）
├─ data/                  JSON 数据（章节、实验、物品、价格、配方、技能树、引导、延迟表）
├─ src/
│  ├─ autoload/           壳层服务（存档、流程、经济、知识、引导）
│  ├─ core/               纯逻辑（不依赖 autoload，可 headless 直测）
│  ├─ sim/                确定性仿真（SimValue / SimDelays / SimEngine / SimCircuit / SimModule）
│  └─ ui/                 界面（main.gd、screens/*、widgets/*）
├─ tests/                 run_tests.gd + 13 套件 + data/ref_vectors.json
├─ tools/gen_ref_vectors.py  从 Python 参考实现导出真值向量
├─ docs/                  design / curriculum / simulation（只读）+ adr + PROGRESS.md
├─ specs/m1/              M1 规格与任务清单
├─ scripts/               run_game / run_tests / selfcheck / backup
├─ native/                GDExtension 脚手架（M1 不编译）
├─ artifacts/             截图证据与运行日志（`*.log` 已忽略，截图是否入库待定）
└─ backups/               本地备份（不提交）
```

## 5. 架构一页

- **数据驱动**：章节、实验、gate 用例、物品、价格、配方、技能/知识节点、延迟常量都来自 `data/*.json`；脚本不硬编码数值。
- **逻辑与引擎解耦**：`src/core`、`src/sim` 只依赖 `RefCounted` 与纯数据，**不依赖 autoload**，因此 headless 测试可直接调用（`tests/run_tests.gd` 是 `SceneTree` 脚本，不加载主场景）。
- **判定层独立**：`LabChecks` 吃"配置 + 玩家操作结果"，吐 `GateReport`；UI 只负责采集与展示。
- **仿真**：整数 tick、`(tick, seq)` 最小堆、传输延迟 + 惯性过滤（窄脉冲被滤除）、三值 Kleene 逻辑（X 必须被下游看见）；`SimCircuit.build_graph()` 把编辑器拓扑转成网表。
- **渲染**：纯 Control 节点 + 基础几何 + 文字，`SystemFont`（Microsoft YaHei UI），无外部图片。

## 6. 数据与数值（当前实测）

| 文件 | 内容 |
|---|---|
| `data/manifest.json` | 版本 2，8 个数据文件清单 |
| `data/items/items.json` | 86 项（77 文档物品 + 7 旧别名 + `gold` 货币 + `scrap` 材料） |
| `data/economy/prices.json` | 37 项买价 / 61 项回收价 |
| `data/economy/recipes.json` | 77 条配方（`output` + `output_qty` 结构） |
| `data/skilltree.json` | 36 节点 = 7 里程碑 + 19 知识卡 + 10 技能 |
| `data/chapters/ch01_levels.json` | 6 个实验 / 24 条 gate；初始 `gold=120`、初始物品 `M01/M09` 各 1 |
| `data/labs/ch01_labs.json` | 6 节实验配置（阈值、目标值、门任务、毛刺参数、真值表、gate 用例） |
| `data/sim/delays.json` | 门延迟 buf/not=1、nand/nor=2、and/or=3、xor=4、xnor=5；DFF setup=2/hold=1/clk_to_q=2；帧 60 FPS / 5 ms / 4 tick；上限 200 门 / 200 DFF；继电器 3 tick/级 |
| `data/tutorial.json` | 引导脚本（标题栏下方文档流内的横条，不遮挡实验区） |

延迟值是**归一化教学单位**（1 tick = 1 个反相器延迟），不是真实工艺库；改动必须同步 `docs/simulation/03_components.md` 与 Python 参考实现。

## 7. 测试与截图

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1
```

期望输出（2026-11-04 基线）：

```
RESULT: 902 checks, 0 failures
=== ALL PASS ===
```

12 个套件：`bit_math / logic_gates / circuit / economy / knowledge / chapter / tutorial / save / data / sim / black_box / lab_checks`。
其中 `test_sim.gd` 逐条比对 `tests/data/ref_vectors.json`（30 条门向量 + 9 条半加器向量 + 8 条延迟表），并检查同 tick 顺序、1 vs 4 tick/帧结果一致、静止快照往返与 digest 一致、毛刺宽度与修复。

## 8. 脚本

| 脚本 | 作用 | 失败行为 |
|---|---|---|
| `scripts/run_game.ps1` | 启动游戏，透传 `--shot` 等用户参数 | 引擎返回码非 0 → `exit 1` |
| `scripts/run_tests.ps1` | headless 全量测试，解析 `RESULT: N checks, M failures` | `M>0` 或解析不到结果 → `exit 1` |
| `scripts/selfcheck.ps1` | 导入检查 → 全量测试 → 启动冒烟（GUI 截图 + `IFZ_BOOT data_ok=true` + 日志无 ERROR） | 任一环节 FAIL → `exit 1` |
| `scripts/bench.ps1` | 性能基准跑批，写 `artifacts/logs/bench.json`；只留证，超预算属数据结论不判失败 | 未跑完 → `exit 1` |
| `scripts/backup.ps1` | `git bundle create backups/<ts>.bundle --all` + robocopy 复制工作区 | 复制失败 → `exit 1`；只增不删 |

日志写入 `artifacts/logs/`（`import.log`、`tests.log`、`smoke.log`）。

## 9. 文档

| 位置 | 说明 | 权限 |
|---|---|---|
| `docs/design/` | 体验、章节树、垂直切片、物件、经济、设计系统、技能树、引导、节奏、风险 | **只读** |
| `docs/curriculum/` | 学习目标、讲法、练习、编程线、 onboarding、评估、教学素材 | **只读** |
| `docs/simulation/` | 8 主层 / 11 子层契约、确定性、器件、网络、加密、性能、接口、测试、可行性风险 + Python 参考实现 | **只读** |
| `docs/adr/` | 0001 引擎架构 / 0002 原生边界 / 0003 存档与确定性 / 0004 沙箱与真实集成 / 0005 仿真契约映射 | 工程文档 |
| `docs/PROGRESS.md` | 已完成 / 未完成（需人工）/ 偏差表 / 下一步 | 工程文档 |
| `specs/m1/` | M1 规格与任务清单 | 只读 |

## 10. 已知缺口（摘要，详见 PROGRESS）

- L2–L7（组合优化、时序、CPU、总线、网络、真实主机桥接）：只有接口占位与 ADR，未实现。
- `native/` GDExtension：脚手架，未编译；>200 门的原生路径未验证。
- 性能预算（5 ms/帧、4 tick/帧、≤200 门/200 DFF）：按设计约束实现，**未实测**。
- 沙箱与宿主编译器桥接：仅 ADR 0004 设计。
- 存档：v1→v2 迁移已实现；**v2 之后的前向迁移框架未实现**（新版本需手写分支）。
- 42 道练习题库与逐题评分表：未落地（M1 只做第一章 24 条 gate + 多解黑盒）。
- 手动走查（操作 → 验收 → 知识树完成 → 存档）、真实 CI 运行：**需人工**。

## 11. 约定

- 提交前跑 `scripts/selfcheck.ps1`；不提交 `backups/`、`.godot/`、`artifacts/logs/`（`*.log` 已被忽略）。
  `artifacts/shots/*.png` 是验收证据截图，是否入库由负责人决定（当前 `.gitignore` 未忽略它）。
- 不改 `docs/design`、`docs/curriculum`、`docs/simulation`（团队只读文档）；发现冲突写入 `docs/PROGRESS.md` 并标"需人工"。
- 不删除存档、不静默丢事件、不用浮点进入仿真状态。
