# 进度与偏差（PROGRESS）

- 里程碑：**M1 已验收；M2 已交付（A/B/C/D 全部完成）；M3 已交付（T0→T8 + 验收表）；M4 已交付（T0→T5：宏单元 / 8 种 CH02 kind / 题库接口 / 难度三档）；M5 基础设施已交付（结构化失败回传）**
- 基线日期：2026-11-04
- 口径：只有**跑过、有证据**的项才标"已完成"；没验证的一律标"需人工"或"未完成"，不写成通过。
- 证据目录：`artifacts/shots/`（11 张截图）、`artifacts/logs/`（导入/测试/冒烟/基准日志）

## 1. 一句话结论

M1 已经**可启动、可操作、可存档、可自动测试**：6 节实验 + 24 条 gate + 多解黑盒 + L0a/L0b/L1 仿真；
当前基线 `RESULT: 2033 checks, 0 failures`（23 套件，含 M3/M4/M5 追加）。

M2 进度（顺序固定，不跳步）：

1. 三处文档裁决（77 配方 / `test_gate_cases` 并入 `test_lab_checks` / 货币「金币 g」）——**已完成**（提交 `9807371`）。
2. **A 性能基准关——已完成**：实测 **200 门/200 DFF p95 = 15.7–17.8 ms**（两次复跑），远超 5 ms/帧；
   GDScript 安全上限取 **50 门/50 DFF**（p95 3.6–4.0 ms）；本轮细化档首次超预算在 **80 门**（p95 5.39 ms）。
   `data/sim/delays.json` 的 `gdscript_gates/gdscript_dff/require_gdextension_above` 由 200 下调为 50（偏差 2、3、14 见下）。
3. **B L2 组合层——已完成**：半加器 → 全加器 → 8 位行波加法器 → 2:1 / 4:1 选择器；
   `t_settle` 由延迟表推导并经实测校验（HA 4 / FA 10 / ripple8 52 / mux2 7 / mux4 13 tick），
   `tests/test_l2.gd` 逐向量等价（含 X），L1/L2 混合可仿真（§2.3）。
4. **C 存档迁移框架补全——已完成**：迁移契约可执行（`registry_errors()` + `migrate()` 自检），v1/v2 fixture 经 `SaveStore` 真实落盘读档，进度字段逐项保留（§2.4）。
5. **D 6 节脚本走查——已完成**：`--walkthrough` 驱动真实 UI 走完 6 节，72 项断言 0 失败；
   重启进程 `--verify-walkthrough` 36 项一致；6 张 GUI 截图（§2.5）。

M1 **没有**做到：L3–L7、原生 GDExtension、沙箱与真实集成、题库与逐题评分、真实 CI 验证——这些要么只有 ADR，要么完全没有。

## 2. 已完成（附验证方式）

| 项 | 内容 | 验证 |
|---|---|---|
| 数据层 | 8 个 JSON（manifest 版本 2）：86 物品（77 正式 + 7 旧别名 + `scrap` 材料 + `gold` 货币）、37 买价 / 61 回收价、77 配方、36 节点（7 里程碑 / 19 知识 / 10 技能）、6 实验 / 24 gate、延迟表、引导、manifest | `tests/test_data.gd`；启动日志 `IFZ_BOOT data_ok=true files=8 chapter=ch01` |
| 纯逻辑层 | `src/core`：`SimValue`/`VoltageModel`/`LabChecks`/`BlackBox`/`CircuitGraph`/`KnowledgeGraph`/`EconomyCore`/`ChapterRuntime`/`PlayerState`/`SaveCodec`/`SaveStore`…（不依赖 autoload） | headless 直测；`tests/run_tests.gd` 是 `SceneTree` 脚本，不加载主场景 |
| 仿真 L0b/L1 | `src/sim`：Kleene 三值 + 整数 tick + `(tick, seq)` 堆 + 传输延迟/惯性过滤 + 毛刺 + 静止快照 + digest | `tests/test_sim.gd`：30 条门向量 + 9 条半加器向量 + 延迟表、同 tick 顺序、1 vs 4 tick/帧一致、快照往返 digest 一致、毛刺宽度与修复 |
| 仿真 L2 组合层 | `src/sim/sim_module.gd`：半加器 → 全加器 → 8 位行波加法器 → 2:1/4:1 选择器；`t_settle` 由 `SimDelays` 推导 | `tests/test_l2.gd`：参考真值表逐向量（含 X）、实测稳定时间、L1/L2 混合 |
| 判定层 | `LabChecks` 输出 `GateReport`，UI 只采集与展示；24 条 gate 逐条判定 | `tests/test_lab_checks.gd`：每种 lab 的"正确解全过 + 错误解失败"两条路径 |
| 多解验收 | `BlackBox` 只判行为不判拓扑；XOR 两种结构、半加器 | `tests/test_black_box.gd`：多解通过、错误拓扑失败、`signature` 区分结构 |
| 存档 | 信封 v3 + SHA-256 + 原子写 tmp→校验→`.bak`→rename；主文件坏则回退 `.bak`；迁移注册表串联 v1→v2→v3（未知字段保留） | `tests/test_save.gd`：篡改检测、坏 JSON 拒绝、`.bak` 回退、往返一致、v1/v2 fixture 落盘读档后进度逐项保留、迁移注册表契约、`scrap`→`gold`、v4+ 拒绝 |
| 经济/知识/章节/引导 | 金币 + XP、商店与配方、技能树四态、章节目标与奖励、引导步骤 | `tests/test_economy/test_knowledge/test_chapter/test_tutorial.gd` |
| UI | 工作台（6 实验卡）、6 个实验页、知识树、商店、档案、诊断；点击式电路编辑器；波形与判读条 | `artifacts/shots/*.png`（workbench/shop/skills/archive/diagnostics + lab_level…lab_half_adder） |
| 工程化 | `README.md`、5 篇 ADR、本文件、4 个 PowerShell 脚本、CI 草案、`native/` 脚手架 | 本文档与 `scripts/selfcheck.ps1` |

### 2.1 自动测试构成（23 套件，2033 项）

`bit_math` / `logic_gates` / `circuit` / `economy` / `knowledge` / `chapter` / `tutorial` / `save` / `data` / `sim` / `l2` / `black_box` / `lab_checks` / `l3` / `l3_vectors` / `l2_vectors` / `trace` / `rewards` / `macro` / `ch02_kinds` / `questions` / `difficulty` / `gate_result`
（M3 追加 `l3` / `l3_vectors` / `l2_vectors` / `trace` / `rewards`；M4 追加 `macro` / `ch02_kinds` / `questions` / `difficulty`；M5 追加 `gate_result`，+223 checks）

### 2.2 A 性能基准关实测（2026-11-04）

复现命令（headless，Godot 4.4.1）：

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1
# 细化档位：.\scripts\bench.ps1 -Sizes "50,60,70,80,90,100" -Frames 400
```

场景定义（最坏全翻转，`tests/bench_sim.gd`）：N 个门全部挂在同一条 `fast` 线上、每 tick 翻转一次，
门类型按 buf/not/nand/and/xor/or/nor/xnor 轮换（覆盖 1–5 tick 延迟）；另建 N 级 DFF 移位链，每帧一个时钟沿。
4 tick/帧，预热 80 帧后统计 600 帧，取每帧 `SimCircuit.run(4)` 的墙钟耗时。

| 规模（门 / DFF） | p50 ms | p95 ms | p99 ms | max ms | 每帧事件峰值 | 判定（p95 ≤ 5 ms） |
|---|---|---|---|---|---|---|
| 50 / 50 | 2.645 | **3.318** | 4.036 | 5.411 | 206 | OK |
| 100 / 100 | 5.795 | 7.594 | 9.058 | 10.240 | 406 | OVER |
| 200 / 200 | 13.902 | **17.644** | 20.594 | 23.540 | 806 | OVER |
| 300 / 300 | 21.434 | 26.012 | 28.811 | 31.657 | 1206 | OVER |
| 400 / 400 | 29.894 | 37.094 | 41.982 | 48.063 | 1606 | OVER |

以上为 `artifacts/logs/bench.log` 最后一次 600 帧运行值。同日另有两次复跑：50 门 p95 为 3.32 / 4.03 ms，
200 门 p95 为 15.66 / 17.64 / 17.78 ms —— 属可观测的机器抖动，结论不变（均远超 5 ms 或稳定低于 5 ms）。

细化档位（400 帧，`artifacts/logs/bench_refine.log`）用于定位临界点：
50 → p95 **3.463 ms**（OK）；60 → 4.103（OK）；70 → 4.689（OK）；**80 → 5.387（首个 OVER）**；
90 → 6.201。同日早先一轮曾出现 60 门 5.03 ms 的抖动样本，故安全上限仍保守取 50。

**结论（只陈述实测）**：

- GDScript **守不住** 设计目标 200 门/200 DFF @ 4 tick/帧：p95 为预算的 3.1–3.6 倍（15.66–17.78 ms vs 5 ms）。
- 安全边界取 **50 门 / 50 DFF**；本轮细化档首个超限档为 **80 门**（p95 5.390 ms），70 门仍为 4.723 ms，
  但两次复跑间存在抖动，故仍按 50 保守设限。>50 门或 >50 DFF 即触发原生下沉（ADR 0002 §2.1）。
- 成本近似线性：200 规模 806 事件/帧 ≈ 15.6 µs/事件，瓶颈在事件引擎热路径（字典事件对象 + `Callable.callv` + 堆比较 + 每次改值写 `history`），不是单个门函数。
- 玩法影响：第一章每节网表 ≤12 门、半加器 ≤8 门，均在 50 以内，M1 交互不受影响。
- 未做：原生 GDExtension（按指令"先测后做"）；也未做引擎热路径重写（预估 1.5–2× 提升，未实测，不作为结论）。

### 2.3 B L2 组合层实测（2026-11-04）

新增 `src/sim/sim_module.gd`（契约：`name / inputs / outputs / t_settle / build(circuit)`）与 `tests/test_l2.gd`，共 **430 项**新检查（当时总计 1350）。

| 模块 | 结构 | 声明 `t_settle` | 实测最坏稳定时间 |
|---|---|---|---|
| 半加器 | xor + and | 4 | 4（sum 路径） |
| 全加器 | 2×半加器 + or | 10 | 10（a→cout） |
| 8 位行波加法器 | 8×全加器 | 52 | 52（0xFE+0x00+1 后仅翻 a0，进位穿 8 级） |
| 2:1 选择器 | not + 2×and + or | 7 | 7（选择端） |
| 4:1 选择器 | 3×2:1 选择器 | 13 | 13（s0 经两级） |

- 等价性（逐向量，全部通过）：

| 模块 | 向量构成 | 通过 / 总数 |
|---|---|---|
| 半加器 | `ref_vectors.json` 的 9 条三值向量（0/1/X 组合） | **9 / 9** |
| 全加器 | 8 条二进制真值 + 27 条三值（3³，与 `simcore/components.py` 的 s1/c1/s/c2/cout 同构公式比对） | **35 / 35** |
| 8 位行波加法器 | 256 条扫掠（`a=0..255`、`b=0x5A`、cin 交替）+ 32 条 fixed-seed(7) 随机，对整数加法 | **288 / 288** |
| 2:1 选择器 | 8 条二进制 + 27 条三值（`S=X → Y=X`，禁止默认选 D0） | **35 / 35** |
| 4:1 选择器 | 4 组数据 × 4 个选择值 = 16 条二进制 | **16 / 16** |
| 合计 | — | **383 / 383** |

- `tests/test_l2.gd` 共 **430 项**检查（余下为端口声明、`t_settle` 推导式、最坏路径实测、混合仿真）。
- 进位链：文档原写"cout 延迟 6n=48"，那是从 **cin** 起的路径；从 **a/b** 起经第一级 s1 生成进位多 4 tick，
  故 `t_settle` 上界为 `xor+and+or+(n-1)(and+or)=52`，实测同为 52。声明值由 `SimDelays.delay()` 推导，测试同时断言推导式。
- L1/L2 混合验证方式：同一张 `SimCircuit` 里展开 L2 半加器 + L2 2:1 选择器，中间插一个 L1 `xor` 门
  （输入取半加器的 sum/carry），门的输出用 `bind(delay=0)` 接到选择器的 d0。断言 4 组 a/b 输入下
  选择器输出等于 `a|b`（半加器 sum/carry 的 XOR 化简），再把选择端切到 d1=1，断言输出恒为 1
  —— 即 L1 与 L2 在同一事件队列内、同一 tick 语义下互通，不是两套模型拼接。

### 2.4 C 存档迁移实测（2026-11-04）

- 迁移契约变成可执行检查：`SaveCodec.registry_errors()` 校验 `MIGRATIONS` 覆盖 `1..FORMAT_VERSION-1` 且无越界键；
  `migrate()` 入口先自检，注册表残缺时返回 `ok=false`，不返回半迁移数据。
- 新增 fixture：`tests/data/saves/legacy_v1.json`（`player` 内嵌 + 未知字段）与 `legacy_v2.json`（扁平 + 未知字段）。
- 不只测 `decode()`：把 fixture 编码后**真实写入 `SaveStore` 槽位再 `load_slot()`**，覆盖"旧档落盘 → 读档 → 迁移 → `PlayerState`"整条路径。
- v1/v2 逐项断言不丢进度：`gold`（由 `scrap` 改名）、`xp`、`slot`、`created_at`、`chapter_id`、物品数量、知识、目标、
  `labs_completed`、gate/lab/chapter 三类 flag、教程完成项、`stats`（saves/seconds/ticks）、`rng`（seed/state）；
  未知字段（v1 内嵌、v2 顶层）原样保留，`scrap` 键已消失。
- 新增 **60 项**检查，总计 **1410 checks / 13 套件 / 0 failures**。

用例与结果（`tests/test_save.gd`，逐条断言）：

| 用例 | 做法 | 结果 |
|---|---|---|
| 注册表契约 | `registry_errors()`、`MIGRATIONS.size()`、v1/v2 分别 `migrate()` | errors=0、entries=2（v1→v2、v2→v3），两条链均到 v3 且 `from` 正确 |
| v2 键改名 | `scrap`→`gold` + 未知字段 `legacy_extra` | gold=45、未知字段保留、`scrap` 键消失（10 项） |
| v2 进度保留 | 含 gate/lab/chapter 三类 flag、2 个知识、目标、lab 的 v2 档 | 7 项进度全部保留 |
| v1 fixture 真实落盘 | `legacy_v1.json` 编码后写 `SaveStore` 槽位 6 → `load_slot()` | `migrated_from=1`、gold=120、xp=40、created_at、物品 5/2、知识 2、目标 2、lab 2、3 类 flag、教程、stats(3/99/1234.5)、rng(42/12345)、未知字段保留、`scrap` 消失（25 项） |
| v2 fixture 真实落盘 | `legacy_v2.json` → 槽位 7 | `migrated_from=2`、gold=88、xp=30、物品 4/1、知识 2、目标 1、lab 1、gate/lab flag、教程、stats(5/111/777)、rng(9/54321)、顶层未知数组保留、`scrap` 消失（23 项） |
| 未来版本 | v4 存档 | 明确拒绝（“高于当前版本”），不尝试降级 |
| 旧版 payload 直接解码 | 旧 v1 内嵌 `player` 结构 | gold=12、wire=2、知识保留、rng 默认 seed=1 |

### 2.5 D 6 节脚本走查实测（2026-11-04）

- 入口：`--fresh --walkthrough=user://walkthrough.json` 与 `--verify-walkthrough=user://walkthrough.json`（`src/ui/main.gd`）。
- 每节走真实链路：`WorkbenchScreen.select_lab` → 实验页 `scripted_solve()` → 页面自己的 `_run_cases()` → `pass_report` → `complete_lab` 发奖；
  逐节断言目标完成、4 条 gate 记账、金币/XP 增量与数据预期一致、物品不出现未定义变化。
- 实测：`WALKTHROUGH_DONE checks=72 failures=0`；重启进程后 `WALKTHROUGH_VERIFY_OK checks=36 failures=0`。
  终局状态：金币 **315**、XP **315**、等级 **4**、知识节点 **34**、24 条 gate 全记账、章节完成标记 `true`。
- 各节增量（金币 / XP）：level 120→150 / 0→25；binary 150→180 / 25→60；boolean 180→205 / 60→90；
  gate 205→240 / 90→135；signal 240→260 / 135→170；half_adder 260→315 / 170→315（含章末 25 金币 / 100 XP，偏差 11）。
- 物品：`ch01_levels.json` 的 6 节均**未定义** lab 物品奖励（仅初始 `M01/M09` 各 1），故走查断言"物品不变"并在快照记 `item_rewards_defined=false`；
  「每节物品入库」在本章不适用，不能写成已验证。
- 截图：`artifacts/shots/lab_{level,binary,boolean,gate,signal,half_adder}.png`，6 次 GUI 进程 `--shot`（1440×900，`err=0`）。
- 走查中发现并修复 3 个真实 UI 缺陷：`LabGate._switch_task` 在 `setup()` 触发 `changed` 时把空图写回当前任务（导致 5 个任务图被覆盖）；
  `_final_snapshot` 误把 `objectives` 字典的键当字典节点；binary 脚本只覆盖 0–15 未摆出 137/0x2F 两个目标值。

### 2.6 M2 A/B/C 数据摘要（一页取数）

| 子系统 | 要回答的问题 | 答案（实测） | 证据 |
|---|---|---|---|
| A 性能基准 | p95 多少？200 门/200 DFF 守得住 5 ms 吗？临界门数？ | 50 门/50 DFF：p95 **3.318 ms**（600 帧，另两次 3.46 / 4.03）→ 守住；200 门/200 DFF：p95 **17.644 ms**（另两次 15.66 / 17.78）→ **守不住**，约为预算 3.5 倍；细化档首个超限 **80 门**（5.387 ms），70 门 4.689 ms 仍 OK | `artifacts/logs/bench.log`、`bench_refine.log`、`bench.json`、§2.2 |
| B L2 组合层 | 四级各多少向量通过？L1/L2 混合怎么验？ | 半加器 9/9、全加器 35/35、8 位行波 288/288、2:1 选择器 35/35、4:1 选择器 16/16，**合计 383/383**；混合验证：同一 `SimCircuit` 内 L2 半加器 → L1 xor 门 → `bind(0)` → L2 选择器，4 组输入 + 选择端切换全对 | `tests/test_l2.gd`、§2.3 |
| C 存档迁移 | 旧档载入会不会丢进度？ | v1/v2 fixture 经真实 `SaveStore` 落盘再 `load_slot()`：`migrated_from` 正确、金币/XP/槽位/时间戳/物品/知识/目标/lab/三类 flag/教程/stats/rng 逐项保留，未知字段原样保留，`scrap`→`gold` 改名生效，v4 明确拒绝；新增 60 项，总计 1410 项 0 失败 | `tests/test_save.gd`、`tests/data/saves/*.json`、§2.4 |

### 2.7 OPT 实现层优化实测（2026-11-04，M3 追加条款 A）

- 改动范围（语义不变）：`src/sim/sim_circuit.gd` 热路径数据化——线网/门用整数 id + `PackedInt32Array`/`PackedByteArray`、
  fanout 邻接表在 `add_gate` 时预计算（去掉每门每输入的闭包订阅）、门求值走整数三值表、
  门事件与 DFF 写事件进整数堆并与通用事件按 `(tick, seq)` 合并出队；`src/sim/sim_engine.gd` 只新增
  `next_seq/peek/pop_next/advance`（共享 seq 与限额记账）。
- 复现命令（3 次，每次 400 帧、4 tick/帧、50/80/100 三档）：
  `powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1 -Sizes "50,80,100" -Frames 400`
- 实测（p95 ms，3 次原值全列，不取最优；证据 `artifacts/logs/bench_opt_run1..3.log`）：

| 规模（门 / DFF） | 优化前 p95（600 帧） | 第 1 次 | 第 2 次 | 第 3 次 | 判定（p95 ≤5 ms） |
|---|---|---|---|---|---|
| 50 / 50 | 3.318 | **1.341** | **1.344** | **1.518** | OK 3/3 |
| 80 / 80 | 5.387（优化前首个超限） | **2.227** | **3.154** | **2.384** | OK 3/3 |
| 100 / 100 | 7.594 | **3.063** | **3.076** | **2.913** | OK 3/3 |

- 结论：100 门/100 DFF 三档 3 次全部 ≤5 ms（最差 3.154 ms，余量约 1.6×）。**交互限值不据此抬高**：
  按仿真组硬约束（2026-11-04 接口对齐）`gdscript_gates/gdscript_dff = 50/50`、`require_gdextension_above = 80`，
  超过 80 构建期 `IFZ_E_SCALE`；`tests/test_data.gd` 同步断言。100 档实测只作性能余量记录。
- 内容侧硬约束（M3-G15）：`CircuitEditor.max_gates` 默认取 `SimDelays.gdscript_gate_limit()`（50），
  可显式放宽到 `gdscript_gate_hard_cap()`（80）；超关卡上限不落门、状态栏显示"…该电路需要结构级表示"，
  `build_sim()` 返回 `needs_structural_representation`；超 80 返回 `IFZ_E_SCALE`，不做静默截断。
- 全量回归：**1449 checks, 0 failures**（1410 基线 + OPT 9 项 + T1 DFF 30 项）。
- 只读文档：`docs/simulation/` 的 200 门估算**未改**，偏差见 §3 第 15 行，由仿真组修正。

### 2.8 T2 L3 时序器件 + L2 参考向量（2026-11-04）

- 器件（`src/sim/sim_sequential.gd`，全部复用 `SimDff`）：
  - `create_register`：W 个 DFF，初值 0，`p.d<i>` 为输入、`p.q<i>` 为输出；
  - `create_counter`：寄存器 + 紧凑自增链（`q0' = !q0`、`qi' = qi ^ carry`、`ci = qi & carry`），
    共 `2W-2` 个组合门（8 位 = 14 门）+ `W` 个 DFF，而非参考实现的 104 门展开，故 8 位计数器**不超限**；
  - `create_shift_register`：`q<i>` 由 `q<i-1>`/`din` 在时钟沿串行移入。
  - `drive_clock(sim, wire, period, cycles, high_ticks=-1, start_tick=-1)`：period 强制偶数，
    采用**绝对 tick** 相位（`base + i*p`），避免读到滞后 `now()` 造成的 t=0 伪 setup 违例。
- 计数器周期**实测裁决**（`SimSequential.measure_counter_period`，`tests/test_l3.gd::_test_counter_period`
  断言 14/26）：扫描偶数周期，取满足"无 `METASTABLE` 记录 + 连续两个完整周期（4 位扫 34 个沿、8 位扫 514 个沿）
  每个采样点都等于 `k mod 2^W`"的最小值。结果：**4 位 14 tick、8 位 26 tick**（见偏差 16）。
- L2 参考向量（`tests/test_l2_vectors.gd`，只读读 `docs/simulation/ref/vectors/l2_vectors.json`）：
  校验 `format == "ifz-l2-vectors/1"`、行数 9 / 27 / 37 / 27 / 5、`gate_delay` 与本工程 `SimDelays.delay` 一致，
  再逐行比对 **105/105**：HA 9、FA 27、ripple8 37、mux2 27、mux4 5（`mux4` 行字段序为 `[d0..d3, s1, s0, y]`）。
  `decoder3` 10 / `comparator4` 17 / `alu4` 8 **未比对**：对应 `SimModule` 未实现，且 ALU 166 门超 80 硬上限，
  按接口对齐结论须走宏单元（偏差 17）。**后续已在 §2.15 补至 132/132（仅剩 alu4 8 行）。**
- 全量回归：**1493 checks, 0 failures**（比 T1 的 1452 项新增 41 项：器件/周期 + 向量 + 上限对齐断言）。
  `tests/test_data.gd` 同步断言 `limits` 50/50/80 与 `delays.json` 的 `l3.counter4_min_period=14` / `counter8_min_period=26`。

### 2.9 T3 TraceSink 统一事件流（2026-11-04）

- `src/sim/trace_sink.gd`（`class_name TraceSink`）：固定 5 字段 `{tick, layer, kind, subject, payload}`；
  `kind` 白名单 7 项（`CHANGE/EDGE/DROP/SAMPLE/METASTABLE/ERR_ADDR/ERR_METASTABLE`）、`layer` 白名单 7 项；
  环形缓冲（默认 20000，超限丢最旧并累计 `dropped_old`，`export()` 带计数）；`digest()` 对
  `tick|layer|kind|subject|canonical(payload)` 拼接后 SHA-256（payload 键排序、基础类型）。
- 接入点（只读观测，不改求值）：`SimCircuit._write_id` 写 `CHANGE`、同值合并写 `DROP`、`note_metastable` 写
  `METASTABLE`；`SimDff._on_clk` 写 `EDGE`（rise/fall）与 `SAMPLE`（含 reset/meta 标记）。
  `SimCircuit.enable_trace(cap)` 显式开启（默认关闭，避免影响既有性能）；`history`/`glitches` 保留给 UI。
- G9 五条断言（`tests/test_trace.gd`）全过：5 字段形状与类型、kind 全在白名单、tick 单调不减、
  `history` 条数 == sink `CHANGE` 条数（逐线同样成立）、**1 tick/帧 与 4 tick/帧的 `digest()` 逐字节相同**
  （同一事件序列下 `run_until` 绝对 tick 分步，事件条数与 q 值也相同）。
- 另测：环形缓冲 8 容量写 10 条 → 保留 8 / `dropped_old=2` / 最新 tick=9；未知 kind·layer、空 subject、
  tick 回退各被拒并计 `rejected`；`ERR_ADDR` 可写入（第二章扩展用，不改 schema）。
- 全量回归：**1527 checks, 0 failures**（T2 的 1493 + T3 34 项）。

### 2.10 T4 快照 `ifz-sim/2`（2026-11-04）

- `SimCircuit.snapshot()` 升级为 `ifz-sim/2`：在 `ifz-circuit/1` 的 `wires` 之外增加
  `regs = {dff名: {q, last_edge, meta}}` 与 `clocks`（本引擎时钟由 `set_input` 事件驱动，
  没有时钟对象，**字段保留但恒为空数组**，偏差 18）；`state_digest()` 同步纳入 `regs`。
- `restore()` 接受 `ifz-sim/2` 与 `ifz-circuit/1`（后者无 regs，仅恢复 wires/tick），未知格式明确报错；
  恢复 DFF 状态用"静默写"路径（不触发监听者），保持恢复后队列为空。
- G10 断言（`tests/test_l3.gd::_test_snapshot`）全过：4 位计数器跑到静止态 → `ifz-sim/2` 快照
  regs 含 4 个 DFF 且带 q/last_edge/meta → 恢复 → 再快照 **digest/tick 相同**；
  旧 `ifz-circuit/1` 可恢复；非静止态快照被拒；**新实例恢复后继续跑 与 不中断跑 的 `state_digest` 相同**
  （新实例建门时的初始求值事件需先 `settle()` 清空，否则 restore 按"队列非空"拒绝——已写入注释）。
- 全量回归：**1540 checks, 0 failures**（T3 的 1527 + T4 13 项）。

### 2.11 T5 奖励入库机制（2026-11-04）

- `PlayerState.grant_items(lab_id, grants, catalog, dry_run=false)`：只做**机制**，数值不动。
  - 幂等：成功入库后写 `granted:<lab_id>`，重复调用返回 `already=true` 且不二次发放（跨存档保持）；
  - 原子校验：任一 `item_id` 不在 `items.json`、或数量非 ≥1 整数 → **整单拒绝**，一件不发、标记不写；
  - `dry_run=true` 只校验；`once=false` 不写标记（仍由调用点"仅首次通过"约束）。
- `ChapterFlow.complete_lab`：`grants` 校验放在**任何状态变更之前**（避免目标已记完成、奖励却发不出），
  通过后才在 `newly` 分支与金币/XP 一起入库，并 toast `奖励入库：N 件物品`。
- G12 断言（`tests/test_rewards.gd`，夹具 `tests/data/ch99_reward_fixture.json`，仅测试用）全过：
  首次入库数量正确并写标记、重复完成不二次发（含存档往返后仍判重复）、未知物品整单拒绝（合法项也不发）、
  数量 0/1.5 拒绝、`once=false` 可重复、`dry_run` 不变更。
- **`data/chapters/ch01_levels.json` 一行未改**（`git diff --stat -- data/chapters/ch01_levels.json` 为空，
  验收命令见 §9）。
- 全量回归：**1568 checks, 0 failures**（T4 的 1540 + T5 28 项）。

### 2.12 T6 L3 性能基准（2026-11-04）

- `bench_sim.gd` 新增 `--scenario=l3`：在 gate 场景（N 门每 tick 翻转 + N 级 DFF 链）之上再挂一个
  **4 位计数器**（+6 门 / +4 DFF），时钟周期 16 tick（> 实测 14），仍 4 tick/帧；
  `bench.ps1` 加 `-Scenario` 参数透传。
- 三次复跑（`-Sizes "50,80,100" -Frames 400`，p95 ms）：

  | 规模（含计数器） | 第 1 次 | 第 2 次 | 第 3 次 | 结论 |
  |---|---|---|---|---|
  | 50 门 / 54 DFF | 1.778 | 1.645 | 1.537 | ≤5 ms |
  | 80 门 / 84 DFF | 2.714 | 2.555 | 2.625 | ≤5 ms |
  | 100 门 / 104 DFF | 3.323 | 3.306 | 3.209 | ≤5 ms |

- 最差 p95 写回 `data/sim/delays.json` 的 `l3.bench.p95_ms_worst`（50→1.78 / 80→2.71 / 100→3.32），
  `test_data` 断言三档齐全且均 ≤ `frame.budget_ms`（5.0）。
- 全量回归：**1573 checks, 0 failures**（T5 的 1568 + T6 5 项）；基准日志 `artifacts/logs/bench.{log,json}`。

### 2.13 T7 收尾：EN/LOAD 补全与验收汇总（2026-11-04）

- L3 器件补齐 EN/LOAD（`mux` 为新增 L2 组合门：`sel=X → X`、`sel=0 → a`、`sel=1 → b`，延迟 3）：
  - `create_register(..., en)`：每 bit 一个 mux，EN=0 保持、EN=1 装载、EN=X → Q=X；
  - `create_counter(..., en, load, load_srcs)`：EN mux 内层 + LOAD mux 外层；
  - `create_shift_register(..., en)`。
- 新增断言：G5（EN 三态 + t_settle=2 ≤9）、G6（18 沿 0..15 全覆盖并回绕、LOAD 装入 9、
  放开后自增 10、EN=0 两个沿保持、`cnt_en` 无 METASTABLE）、G6 短周期（period=10 → 出现
  METASTABLE 且至少一位 Q=X）。
- 两次踩到的实现约束（已写进测试注释）：
  1. `set_input(delay)` 的 delay 是**相对当前 `now`**，分批排事件会错位 → 事件必须一次性按绝对 tick 预排；
  2. `measure_settle()` 内部 `settle()` 会排空**未来已预排**的事件 → 预排场景下改用 `wires[..]["last_change"]` 直接算。
  3. 两级 mux 串联引入 6 tick 延迟，切换 EN/LOAD 需离下一个时钟沿 ≥6 tick，否则触发 hold（这本身是正确语义）。
- 全量回归：**1610 checks, 0 failures**。

### 2.14 T8（G8 补齐）：`l3_vectors.json` 24 用例 / 51 条期望

- `tests/data/l3_vectors.json`（`ifz-l3-vectors/1`）：dff 8 / register 5 / counter 7 / shift 4，
  含复位 3 条、setup 违例 2 条、hold 违例 1 条；每条期望 = `{tick, Q 值（MSB 在前）, 最后一条 L3 kind, 亚稳态 reason}`。
- `tests/test_l3_vectors.gd`：按 `kind` 构建器件、按绝对 tick 预排事件、`drive_clock(start)` 定时钟；
  kind 只认 `EDGE/SAMPLE/METASTABLE`（跳过写线的 CHANGE/DROP），复位/违例另断 `metastable.reason`。
- **发现并修复缺陷**：`create_register` / `create_shift_register` 先建 EN mux 再 attach DFF，Q 线网被门输入
  隐式初始化为 X（移位寄存器首个沿就把 X 移入下一级）→ 改为先建 Q 线网（`SimValue.ZERO`），再建 mux 与 DFF。
  计数器原本就先行建网，未受影响。

### 2.15 M4 准备（A）：decoder3 / comparator4 接入与向量闭合（2026-11-04）

- `src/sim/sim_module.gd` 新增 `KIND_DECODER3` / `KIND_COMPARATOR4`（结构化展开，接口与参考实现
  `docs/simulation/ref/simcore/components.py` 的 `Decoder` / `Comparator` 同构）：
  - decoder3：3 个共享 not + 8 个多输入 and = **11 门**；`inputs=[en,a0,a1,a2]`、`outputs=[y0..y7]`；
    `t_settle = not + and = 4`（en 路径仅 3）；
  - comparator4：4 xor + 8 not + 8 项 and + 6 gtt/ltt + EQ/GT/LT = **33 门**；
    `inputs=[a0..a3,b0..b3]`、`outputs=[EQ,GT,LT]`；`t_settle = xor+not+and+or = 11`。
  - 两者均在 50 门交互默认上限内（测试断言），不触发 `IFZ_E_SCALE`；ALU 仍不做（166 门，宏单元）。
- `tests/test_l2_vectors.gd` 扩展：`decoder3` 10 行 + `comparator4` 17 行逐行比对，
  **132/132 全等**；另断言 `t_settle` 4/11 与 JSON `t_settle` 一致、门数 11/33 且 ≤ `gdscript_gate_limit()`。
- **实测**：`l2_vectors.json` 实际 **140 行**（`determinism.rows` 计数同 140，测试逐键对账并断言总数 140、种子 539365636）；
  接口消息与偏差 17 原写的"143 行"系笔误，已更正。余下只有 `alu4` 8 行不比对。
- 全量回归：**1631 checks, 0 failures**（T8 的 1610 + 21 项）。
- **ALU 宏单元方案**（M4 准备阶段只写规格；实现见 §2.16）：ALU 166 门不进可交互门级视图，按参考结构拆 7 个只读页
  （5/40/9/16/48/32/16，每页 ≤50），三块语义分组算术/逻辑/选择；展开/折叠边界与 `IFZ_E_SCALE` 口径见
  `specs/m4/spec.md` §3.1。

### 2.16 M4 T0：宏单元接口与 ALU 七页只读视图（2026-11-04）

- 新增 `data/sim/macros.json`（`ifz-macros/1`）：decoder3 **11 门**、comparator4 **33 门**、alu4 **166 门**（`expandable=false`）；
  alu4 七页 `alu.ctrl/adder/flags/logic/sel1/sel2/sel3` = **5/40/9/16/48/32/16**，合计 **166**，单页最大 **48 ≤ 50**。
- 新增 `src/sim/sim_macro.gd`：`cells()/meta()/pages()/expand()/expand_page()/fold()`；
  `expand()` 先查 `c.gate_count()`，`> gdscript_gate_limit()` 返回 `scale_warn`（提示结构级表示），
  `> gdscript_gate_hard_cap()` 返回 `IFZ_E_SCALE` 且**一个门都不写**（禁止只画一部分）；
  alu4 整块展开必返 `IFZ_E_SCALE`，只能 `expand_page()` 只读查看。
- **实测**：decoder3 展开后电路门数 11、comparator4 33；alu4 整块展开被拒后门数仍为 0；
  预置 45 门 + decoder3 11 = 56 → `ok=true, scale_warn=true`；预置 70 门 + 11 = 81 → `IFZ_E_SCALE` 且门数不变 70；
  展开→折叠→再展开 `state_digest` 相同；`fold()` 摘要稳定。
- `alu4 t_settle` 按 `SimDelays` 结构推导锁定 **61 tick**（推导见 `specs/m4/spec.md` §3.1.2），测试用公式重算，不硬编码。
- 测试：`tests/test_macro.gd`（M4-G1/G2/G10）；回归后 **1810 checks / 0 failures**。

### 2.17 M4 T1：8 种 CH02 判定 trace kind（2026-11-04）

- `TraceSink.KINDS` 7 → **15**：新增 `MOSFET_REGION / X_PROPAGATION / STATIC_CURRENT / RAIL_MARGIN / EQUIV / AREA_MAX / POWER_CALC / POWER_RATIO`，
  5 字段 schema 与 `digest()` 未改；`LAYERS` 未改。
- 新增 `TraceSink.REQUIRED_KEYS`：8 种 kind 的固定 payload 键与类型；缺键/类型不符 → `rejected++` 并拒绝；
  既有 7 种 kind 不受影响。
- `SimCircuit` 新增 `JUDGEMENT_KINDS`（小写判定 kind → 全大写 trace kind，8 项）与
  `record_judgement(kind, subject, payload, at_tick=-1)`；`build_area` 不在映射内，不产生事件；
  `SimCircuit` 另加只读 `gate_count()/dff_count()` 供预算检查。
- **实测**：8 种 kind 各写 1 条 → 8 条、无拒绝、每条仍恰好 5 字段；缺键与类型不符各拒绝 1 次；
  1 tick/帧 与 4 tick/帧 的事件流 `digest()` 相同、事件逐条相同；开/关 trace 的末态 `state_digest` 相同。
- 测试：`tests/test_ch02_kinds.gd`（M4-G3/G4）；`tests/test_trace.gd` 的白名单条数断言由 7 改为 15。

### 2.18 M4 T2：题库接入接口（只接口，不落题目）（2026-11-04）

- 新增 `src/core/question_bank.gd`：`from_doc()/validate()/item()/score()/error_codes()`；
  校验缺 `id/stem/type`、`type` 非法、`solutions < 2`、`rubric` 权重和 ≠ 100、`build` 题缺"正确性"维、`id` 重复、
  `answer`/`answer_value` 类型与 `tol` 合法性；条数不假设（`items.size()` 不做断言）。
- 评分只做确定性比较：`{"choice": int}` 与 `{"value": number}` 满分 100；无自动判分字段的题（含 `build`）
  返回 `manual=true, score=0`，交人工 rubric；未知题 → `ok=false, error_code=E_UNKNOWN_ITEM`；
  形状不符 → `E_RESPONSE`。错因码常量 **C1–C9**。
- **不落数据**：`data/questions/` 未创建、`data/manifest.json` 未改；fixture 仅
  `tests/fixtures/questions/ch01_exercises.json`（3 条自造样本），正式 42 题等教学组交付。
- 测试：`tests/test_questions.gd`（M4-G5）。

### 2.19 M4 T3：难度三档预留（2026-11-04）

- 新增 `src/core/difficulty.gd`：`EXPLAIN/SYNC/MASK`、`names()/is_valid()/normalize()`；未知/空串归一 `EXPLAIN`。
- `PlayerState` 新增 `difficulty`（默认 `EXPLAIN`），写存档 `settings.difficulty`；读档缺失、非法或 `settings` 非字典
  → 回落 `EXPLAIN`；**不升存档版本**（v1 旧档读档后仍为 v1）。
- M4 **不改仿真行为**：`SimCircuit` 未引入 `pulse_threshold` / 采样吸收；`SYNC/MASK` 语义留 M5。
- 测试：`tests/test_difficulty.gd`（M4-G6）。

### 2.20 M5 基础设施：结构化失败回传（2026-11-04）

- 新增 `src/core/gate_result.gd`：18 个稳定 int code（`OK=0`、`E_*` 1–17、`E_GENERIC=99`）、
  六类标签 `K/S/C/P/M/R`、中文兜底描述、`make()` 统一形状。
- 新增 `src/core/gate_attempts.gd`：`GateAttemptTracker`（失败 +1、通过清零、单/全重置、字典往返），
  只在内存，不写存档。
- `GateReport` 每条 case 增加 `code/code_name/gate_id/input/expected/actual/error_tags/attempt`；
  旧字段与 `add()` 入口保留（失败按 `E_GENERIC` 兜底）。新增 `first_failure()/failure_codes()/summary()/to_dict()`。
- `BlackBox`：`check_outputs/check_target/tri_eval` 返回 `code` + 结构化 `failure`；
  前置检查悬空线 → `E_UNCONNECTED`（`input.unconnected` 列出具体门端口，如 `g_carry.b`）。
- `LabChecks` / `VoltageModel`：6 节全部 kind 走统一 `_emit` 出口；能精确到"行/格/值/tick/线"的均回传具体输入，
  封装与 fix 只到 gate 级（详见 `specs/m5/failure_contract.md` §4）。
- 测试：`tests/test_gate_result.gd`（223 checks）覆盖每类 gate 成功/失败、标签映射、attempt 递增/重置、
  未知 code 兜底、悬空线精确回传。回归 **2033 checks / 0 failures**（23 套件）。
- **未接 UI**：`src/ui/` 未改；UI 按 `specs/m5/failure_contract.md` 自行渲染。

### 2.21 M5 CH02 数据落地 + CH01 奖励补发（2026-11-04）

- CH01 奖励真正发放：`data/labs/ch01_labs.json` 的 `gate` 段发 `G01/G02/G03`、`half_adder` 段发 `G04`，
  均带 `"bound_first": true`；读取路径统一为 `ChapterRuntime.grants(lab_id, labs_doc)`
  （章节内联字段只作覆盖，奖励表只有一份），`ChapterFlow.complete_lab` 改走该入口。
- 物品侧 `bound_first`：`G01–G04` 四件教学奖励与 `M01/M09/G12` 同口径（首件绑定标记）。
  现状：`bound_first` 只是数据声明，回收/出售逻辑尚未读取该字段（见偏差 26）。
- 旧档补发：`PlayerState.backfill_lab_grants()` 在 `SaveManager.load_game` 后调用一次；
  只补"已通关 + 无 `granted:<lab>` 标记 + 有 grants"的 lab，走 `grant_items` 的 once 路径写标记，
  因此连续多次读档也只发一次。补发后立即 `save_game(1, true)` 固化。
- CH02 数据：新增 `data/chapters/ch02_levels.json`（5 节 / 5 目标 / 5 项技能节点引用 / 章末 25 g）、
  `data/labs/ch02_labs.json`（20 条 gate）；`data/manifest.json` 8 → 10；`tests/test_data.gd` 同步。
- 判定：新增 `src/core/ch02_checks.gd`，11 种 kind 全部经 `GateResult`/`GateReport` 出口；
  **落地 17 条 / pending 3 条**（`T2.2-3`、`T2.2-4`、`T2.4-4` 全部因 `static_current`/`rail_margin`
  仿真层缺口，标 `E_PENDING` 且 `required=false`，不算通过）。
  新增 code 18–25（只增不改），`specs/m5/failure_contract.md` §2/§8 已同步。
- 测试：新增 `tests/test_ch01_grants.gd`、`tests/test_ch02.gd`，共 **+120 checks**；
  全量 **2235 checks / 0 failures**（25 套件）。

### 2.22 金币口径纠偏（2026-11-04）

- CH01 结余：**277–337 g【估值】**（原 252 g 漏算章末技能节点 `CH01` 的 25 g，见偏差 11/§3.1）；
- CH02 必需支出：**≈70 g**（M13 30 + M14 20 + 线缆/电阻 20）；原 88 g 重复计了 M06 的 18 g
  （M06 由 2.1 赠送，M14 买成品不耗库存 M06）；
- CH02 收入 175 g（lab 150 + 章末节点 25），章末结余 382–442 g；已写入 `ch02_levels.json` 的 `economy`
  块并加 `tests/test_ch02.gd` 断言。**未改** `docs/design/04`、`05` 的 77 配方口径。

### 2.23 M5 补修：bound_first 真读 / 2.1 第四测点 / rail_margin 落地（2026-11-04）

- **偏差 26 真修**：`ChapterRuntime.grants(lab_id, labs_doc, state)` 现在真正读取 `bound_first`——
  该 lab 已有 `granted:<lab>` 标记时返回空奖励表，重复刷同一关不再发放第二件；
  `ChapterFlow.complete_lab` 与 `PlayerState.backfill_lab_grants` 均传 `state`，旧档补发仍只补一次。
  物品侧回收（`EconomyCore.sell`）仍未读取 `bound_first`，但重复刷关入口已关闭。
- **2.1 第四测点**：新增 Vgs=3.3 V / Vds=6.0 V（Id 仍 5000 µA），`measure_conditions` 四点按 Vds 升序；
  `T2.1-3` 增 `equal_id_vds [3.0, 6.0]` + `equal_id_tol 0`，断言"再加大 Vds 也不涨"，容差 0。
- **`rail_margin` 落地**（`E_RAIL_MARGIN`(20)，`_judge_rail` 30 行）：
  "逻辑值 → 电平反查"——先由 `BlackBox.tri_eval` 得到各稳态逻辑输出，再按 `V_high = Vdd·R_L/(R_L+Ron)`、
  `V_low = Vdd·Ron/(R_L+Ron)` 反算电平，比对 `v_high_min/v_low_max`；纯离散算术，**无器件层/仿真层依赖**。
  `PENDING_REASONS` 只剩 `static_current`；CH02 落地 **18/20，pending 2**（`T2.2-3`、`T2.4-4`）。
- 测试：新增 17 checks（bound_first 回收路径 6、2.1 四点 6、rail 合法/越界 4、RAIL_MARGIN trace 1）；
  全量 **2252 checks / 0 failures**（25 套件）。

### 2.24 M5 收尾：绑定件禁卖 + 2.4 内容锁定（2026-11-04）

- **偏差 26 售出端收口**：`EconomyCore.sell` 读取 `bound_first`，绑定件返回明确拒绝原因
  「「X」是绑定物品，无法出售」，不扣件、不加金币；非绑定件照常出售。
  测试覆盖绑定件被拒且留包、M01（材料但标绑定）同口径、非绑定件正常、混合背包逐个判定。
- **2.4 内容锁定**（字段名按任务书定稿）：lab 条目 `content_status`（`ready`/`deferred`，缺省 `ready`）
  与玩家可见 `deferred_reason`；新增 `ChapterRuntime.lab_content_available(lab_id) -> {available, reason}`，
  并让既有 `lab_unlocked` / `lab_lock_reason` 先判内容可用性——**整节禁入**，不是让 4 个 gate 显示 pending。
  `replace` 段已标 `deferred`，技能树节点 `SK-REPLACE` 保留（看得见、点不进）。
- 注意：`power`（2.5）的 `requires` 已由 `replace` 改为 `nand`——2.5 只教功耗计算（`P=αCV²f`），
  只需"手上有一个门"，不依赖被优化过的电路；2.4 因此成为侧枝而非主链必经（见 §2.25）。
- 测试：新增 **22 checks**（售出端 11、内容锁定 11）；全量 **2274 checks / 0 failures**（25 套件）。

### 2.25 2.5 解耦 + 版本内可完成度（2026-11-04）

- `ch02_levels.json`：`power` 的 `requires` 改为 `["nand"]`。结构错误修正，不是放水：
  2.4 教的是结构优化（更少门实现同样功能），2.5 教的是功耗计算，把 2.4 当 2.5 前置等于把侧枝塞进主链中间。
- **完成度口径**：`ChapterRuntime.progress/all_done/next_objective` 只统计
  `content_status == "ready"` 的节（`active_objective_ids`/`objective_active`）。
  当前 CH02 是 **4/4 可完成**，章末 25 g 与 `CH02-CMOS` 可正常发放。
  > 该口径有漏洞（2.4 转正后分母 4→5，会追着玩家补选修课），已由 §2.26 的
  > `requirement == "MUST"` ∧ `content_status == "ready"` 取代。
- **拒绝占位通过**：`complete_objective` 对 deferred 节直接返回 `ok=false`（"该实验内容暂未开放"），
  不写任何完成记录。
- 奖励一次性：新增 `chapter_reward_claimable`（`all_done` 且未领），`ChapterFlow._finish_chapter` 改用之；
  章节知识节点按 `runtime().id()` 解锁（原先硬编码 `CH01`，CH02 完成会错解锁）。
- **2.4 分支类型**：`docs/design/02-chapter-tree.md` 的 MUST/OPT/CHAL 只作用于章节，lab 级没有类型字段，
  本轮**未自造字段**；UI 目前可用依赖图判定侧枝（2.4 已无后继），正式标注字段缺口见偏差 29。
- 测试：新增 **22 checks**（2.5 解耦 2 + 完成度 14 + 面积口径 6）；
  全量 **2296 checks / 0 failures**（25 套件）。

### 2.26 lab 级 requirement + 完成度口径替换（2026-11-04）

- **新字段**：lab 条目 `requirement`（`MUST` / `OPT` / `CHAL`，**缺省 `MUST`**，旧数据不写不破坏存档）。
  读取入口 `ChapterRuntime.requirement(lab_id)`。`ch02_levels.json` 的 `replace`(2.4) 标 `"OPT"`，其余不动。
  未加显式分支边，侧枝仍由 `requires` 依赖图推断（2.4 已无后继）。
- **完成度口径（覆盖 §2.25）**：分母 = `requirement == "MUST"` **且** `content_status == "ready"`。
  `CHAL` 与 `OPT` 只给奖励、不进分母；`deferred` 也不进。
  - `objective_ready`：只看 `content_status == "ready"`（决定能否进入/记完成）。
  - `objective_active`：= `objective_ready` ∧ `requirement == "MUST"`（决定是否进分母）。
  - `active_objective_ids` / `progress` / `all_done` / `next_objective` / `chapter_reward_claimable`
    全部继承该口径；`complete_objective` 的禁入守卫仍用 `objective_ready`，所以 OPT/CHAL 的 ready 节照样能做，只是不计数。
  - CH02 恒为 **4/4**：2.4 无论 deferred 还是日后转 ready，都因 `OPT` 不进分母。
- **两维独立**：`content_status` 只表达"内容做出来没有"，`requirement` 只表达"是否必修"，代码里不存在任一方推导另一方。
  测试用 `_ch02_variant(status, req)` 构造 `{ready,deferred} × {MUST,OPT}` 四种组合各自断言。
- 测试：完成度块由 14 checks 扩到 30（四种组合各 3 项、转正/一次性奖励 5 项）；
  全量 **2312 checks / 0 failures**（25 套件）。

### 2.27 章节注册表：扫目录 + 按章节号排序（2026-11-04）

- 新增 `src/core/chapter_registry.gd`（纯静态、无 autoload 依赖）：扫 `res://data/chapters/*_levels.json`，
  用文档内的 `id` / `number` / `title` 建条目，按 `number` 升序（缺号排末尾、同号按 ID），**不用文件名字典序**；
  `data/labs/<id>_labs.json` 存在则记 `has_labs=true` 并缓存 labs 段。
- `DataDB`：`load_all(only_chapters=[])` 建注册表（`chapters` / `chapter_order` / `labs_by_chapter`），
  新增 `chapter_ids` / `has_chapter` / `chapter_meta` / `default_chapter_id` / `labs_for` / `runtime_for`。
  兼容层：`labs` / `labs_doc` / `lab_data` / `gate_cases` 仍指默认章节，既有调用点不改。
- `PlayerState.chapter_id` 默认值与 `SaveCodec` 迁移补的 `chapter_id` 改为 `ChapterRegistry.default_id()`；
  首个章节就是 `ch01`，旧档行为不变。
- 测试：`test_data.gd` 新增 15 checks，从 `DataDB` 入口取到 ch02 的 5 段 labs / 20 条 gate 与 `runtime_for("ch02")`；
  反向用 `TestUtil.data_db(["ch01"])` 排除 ch02 后同一入口取不到，证明断言真的在读注册表。
  全量 **2327 checks / 0 failures**（25 套件）。

### 2.28 补齐章节节点数据：SK-DEMORGAN + 整套 CH02（2026-11-04）

- **CH01 回到 36 格**：`skilltree.json` 补回 `SK-DEMORGAN`（德摩根改写，pos col 3 / row 6，
  前置 `SK-BOOL` + `T1.3-4`），并在 `ch01_levels.json` 的 boolean 节加入
  `skill_nodes: ["SK-BOOL", "SK-DEMORGAN"]`，地图节点数 35 → 36。
- **CH02 新增 26 个节点**：`CH02-1..5`（里程碑）、`CH02`（章节）、`CH02-CMOS`（章末徽章，25 g / 50 xp）
  + 13 张知识卡（`KN-TR-01..04` / `KN-CMOS-01..03` / `KN-NAND-01..02` / `KN-EQUIV-01` / `KN-COST-01` /
  `KN-PWR-01..02`）+ 5 个技能（`SK-TR` / `SK-CMOS` / `SK-NAND` / `SK-REPLACE` / `SK-POWER`）。
  `skilltree.json` 36 → 62 节点（progress 14 / knowledge 32 / skill 16）。
- **ID 与 UI 派生一致**：里程碑取 `lab.milestone`（`CH02-1..5`），章节点 `CH02`，徽章 `CH02-CMOS`，
  每节挑战由 UI 派生为 `CH02-CH-<order>`，章末验收 `CH02-CH-FINAL`——未另起命名。
  2.4 虽 `OPT`+`deferred`，其 `CH02-4` / `SK-REPLACE` 节点照常存在、可见，但不进必修分母。
- **章末奖励走真节点**：`ChapterRuntime.chapter_finish_reward(skill_graph)`（badge → 章节 ID → 兜底），
  `ChapterFlow._finish_chapter` 改用该结果；CH02 的 25 g 由 `CH02-CMOS` 节点发放，
  `economy.chapter_end_gold` 只在节点缺失（如只装部分章节的探针）时生效。
- **数据债**：`ch02_levels.json` 五个 lab/objective 的 `knowledge` 由占位 id（transistor/cmos/nand/equiv/power）
  改为首张知识卡，避免指向不存在的节点。
  `DataDB._validate` 改为逐章节校验（gate_ids 取全部已装章节），`load_all(only_chapters)` 的探针模式跳过跨章节 gate 条件。
- 测试 +41：ch01 地图 36 / ch02 地图 31、节点 ID 唯一、前置与 gate 引用无悬空、
  CH02 节点齐全（13 卡 / 6 引用技能）、奖励取自 `CH02-CMOS` 且删节点副本才回落兜底。
  全量 **2368 checks / 0 failures**。

### 2.29 接任巡检：CH05–CH19 课文、CH05/06 数据、waveform_align、题库与实验室编辑器（2026-11-05）

- 全量测试实测：**37 套件 / `SUITE_TOTAL 4090` + runner 自检 2 = 4092 checks，0 failures**（`scripts/run_tests.ps1`，Godot 4.4.1 console exe，headless）。此前文档写的 2033 已过期。
- **CH05/CH06 数据与判定**：`data/labs/ch05_labs.json`（4 节 / 21 段）、`data/labs/ch06_labs.json`（6 节 / 30 段）可读；`src/core/ch05_checks.gd`、`ch06_checks.gd` 的 16 个已落地 kind 与 5 个 pending kind 由 `tests/test_ch05.gd`（210 checks）、`tests/test_ch06.gd`（307 checks）逐条判绿/判红，含 P1 判据反例、分母现算与 sections 回退。
- **章节注册 / UI 可达性**：**未完成**。`data/chapters/` 仍只有 `ch01_levels.json`、`ch02_levels.json`；`ChapterRegistry` 只认 `*_levels.json`，因此 `ch05_labs.json` / `ch06_labs.json` 虽在磁盘上，却不会进入 `labs_by_chapter`，`DataDB.use_chapter("ch05"/"ch06")`、`--chapter=ch05` 与 UI 切章均不可达；两份 labs 也未登记进 `data/manifest.json`。补齐需要 `ch05/ch06_levels.json` + `skilltree.json` 的 CH05/CH06 知识/技能/里程碑节点；CH03/CH04 尚未落库，本章进度链也接不过去。
- **waveform_align**：已完成。`src/core/waveform_align.gd` 导出期望模型（终值/四阶段起止拍/逐拍拍号），`tests/test_waveform_align.gd` 35 checks 覆盖全对、单拍错、终值错、区间错、填表式提交被拒与 `Ch05Checks` 分发；5.1 的 `pending_kinds` 为空。
- **实验室编辑器真实文件系统**：已完成。`tests/test_lab_phase2_ui.gd` 120 checks 中 `editor_fs` 组要求根为宿主绝对路径（非 `user://` 兜底）、相对路径被拒、不可用不降级，并实际校验种子文件 `home/user/main.c`、`home/user/notes.txt`、`etc/hostname` 存在；UI 源码断言显示实际根路径。
- **42 题题库**：已完成。`data/questions/ch01_exercises.json` 恰 42 题、id 唯一、section 在 1.1–1.6、校验零错；`QuestionBank.score` 对选项题/数值题判 100/0 且确定性，未知题与搭建题不自动编分；`data/manifest.json` 已登记该文件（`tests/test_questions.gd` 221 checks）。
- **CH07 之后课文**：已完成。`docs/curriculum/18–31` 覆盖 CH07 4 单元、CH08 3、CH09 5、CH10 4、CH11 4、CH12 5、CH13 3、CH14 3、CH15 4、CH16 4、CH17 3、CH18 4、CH19 5、终章 F1–F3，与 `docs/design/15-curriculum-master-outline.md` 幕 III–V 的 16/19/19 单元逐节对齐；各自带 lab 提案、前置与校验口径。这些课文对应的 `data/labs/ch07+` 与 `ch07+_checks.gd` 尚未落库（课文文件内已注明 gate 为提案）。

## 3. 偏差表（原规格 / 实际实现 / 原因）

| # | 原规格 | 实际实现 | 原因 |
|---|---|---|---|
| 1 | L0a 模拟电平：模拟电路求解（RC 固定子步长） | 电压判读带 + 阈值判定（`src/core/voltage_model.gd`、`ui/widgets/level_gauge.gd`），不做连续时间电路求解 | M1 只要求 L0–L1 接口与确定性 tick；连续求解器属后续里程碑 |
| 2 | 门级仿真宿主允许 C++/Rust GDExtension | 纯 GDScript（`src/sim/`）；2026-11-04 实测后修正口径：GDScript 在 **50 门/50 DFF** 内守 5 ms，200 门 p95 17.8 ms；`native/` 仅有脚手架、未编译 | 先保证可运行与可测；实测证明 200 门必须原生（§2.2、偏差 14） |
| 3 | 性能预算：5 ms/帧、4 tick/帧、≤200 门/200 DFF | 预算与 tick 已实测（`tests/bench_sim.gd` + `scripts/bench.ps1`）：50/50 规模 p95 3.32–4.03 ms 达标；细化档 70 门 4.69 ms 仍达标、**80 门 5.39 ms 起超预算**；"降速不丢事件"仍由 `SimEngine` 的 tick 推进与单 tick 上限保证 | 原 200 门来自 `docs/simulation/06` 估算、从未验证；实测后以数据为准 |
| 4 | 内嵌 Linux、宿主编译器桥接（汇编/C/Java/Python）、沙箱进程隔离与资源限制 | 均未实现，仅有 ADR 设计（0004） | M1 范围克制在 L0–L1 |
| 5 | 存档版本迁移 | 信封 v3 + **迁移注册表**（`SaveCodec.MIGRATIONS`，v1→v2→v3 串联）；`tests/test_save.gd` 断言 `migrated_from=1/2`、`scrap`→`gold` 改名、未知字段保留；v4+ 存档被明确拒绝而非尝试迁移 | 只有一次结构调整时不做框架是克制；货币改名带来第二次结构变化，遂补注册式迁移器 |
| 6 | 练习：文档 42 道、每题 ≥2 解 | 第一章 24 条 gate（每节 4 条）+ 黑盒多解验收（XOR 两种结构、半加器）；**CH01 42 题题库与逐题评分已落地**（§2.29），其余章节题库未交付 | 题库接口在 M4 已就绪；CH01 本体 2026-11-05 已登记进 manifest，其余等教学组 |
| 7 | 电路编辑：设计台 HUD/自由布线（拖拽、吸附、撤销重做） | 点击式编辑器（点空白放门、点端口连线、右键断线/删门），不支持拖拽 | 先保证可操作与可判定 |
| 8 | 引导浮层：原实现为右下浮动面板 | 会遮挡实验操作区；已改为标题栏下方文档流内横条（`main.gd::_build_tutorial`） | 浮层遮挡与"提示不覆盖工作台"的设计硬规则冲突 |
| 9 | 截图（无明确后端要求） | 截图只能在 GUI 后端生成（headless 无渲染）；验收用窗口模式 1600×900 自动截图后退出 | headless 的 viewport 无纹理可读 |
| 10 | 以 `--editor --quit` 作为可启动性检查 | 不会编译"运行时才 `load()`"的脚本，曾漏掉 `lab_binary.gd` 语法错误；已改为"跑 11 张截图 + 扫描日志 ERROR"作为可启动性冒烟 | 导入检查只覆盖被引用/被扫描到的资源 |
| 11 | CH01 里程碑额外奖励 | CH01 里程碑不额外给金币（奖励在 lab 的 `reward` 里）；章末 `complete_reward` 为 `gold 0 / xp 50`，另由 `data/skilltree.json` 的 `CH01` 节点发放 `gold_award 25 / xp_award 50` | 里程碑奖励与 lab 奖励分开配置，避免重复发放 |
| 12 | 首位玩家初始资源 | 初始金币 120，初始物品 M01/M09 各 1（`ch01_levels.json` 的 `start_gold/start_items`） | 与 `docs/design/03` §3 的初始 120 对齐 |
| 13 | 货币单位 | 货币单位曾是 `scrap`（废铁），已按负责人裁决改为 **`gold`（金币，单位 g）**；`scrap` 降级为普通材料/回收物（`kind=material`）；旧档通过存档 v3 迁移（`scrap`→`gold`）兼容 | 与 `docs/design/03` §3「金币 g」口径统一；单字货币让材料与通货语义混淆 |
| 14 | GDScript 门数上限 | 设计写 200 门/200 DFF；实测安全上限取 **50 门/50 DFF**（p95 3.32–4.03 ms）。细化档 70 门 4.69 ms 仍达标、80 门 5.39 ms 超限；因复跑存在抖动（早先一轮 60 门曾 5.03 ms），限值保守定为 50。`data/sim/delays.json` 的 `gdscript_gates/gdscript_dff/require_gdextension_above` 已改为 50，`tests/test_data.gd` 同步断言；ADR 0002 §2.1 判据表同步 | 200 从未实测；按 ADR 0002 §5「实测 <200 即超预算则下调限值并记偏差」执行，避免文档宣称能跑 200 而实际掉帧 |
| 15 | 仿真文档估算 **200 门**/200 DFF（`docs/simulation/06`） | 实测三档：优化前 100 门 p95 7.6 ms、200 门 17.6 ms；**实现层优化后 100 门 3 次 p95 2.91–3.08 ms**（400 帧）。交互限值按仿真组硬约束取 **50 默认 / 80 绝对**（超 80 → `IFZ_E_SCALE`），编辑器同源卡死并由 `test_data`/`test_circuit` 断言 | 200 是未验证的估算；GDScript 解释执行、无 JIT，优化后 100 档仍有约 1.6× 余量，但**交互上限不再按性能余量抬高**，以仿真组 50/80 硬约束为准。**`docs/simulation/` 不改**，由仿真组据本行修正 |
| 16 | 计数器最小时钟周期：仿真组 L3 写 `period ≥ 6W+9`（4 位 33、8 位 57，8 位取 70）；本工程上一轮结构推导 `6W+20`（4 位 44） | **以真实 `SimCircuit` 实测裁决：4 位 14、8 位 26**（`SimSequential.measure_counter_period`；判据 = 偶数周期 + 无 `METASTABLE` + 连续两个完整周期逐沿值正确，4 位扫 34 沿、8 位扫 514 沿）。写回 `data/sim/delays.json` 的 `l3.counter4/8_min_period`，`test_l3`/`test_data` 断言 | 我们的计数器是紧凑自增链（`2W-2` 组合门 + `W` DFF，8 位仅 14 门），不是参考实现的 104 门展开；`6W+9`/`6W+20` 都是按展开结构估的。**`docs/simulation/` 不改**，由仿真组据本行修正 |
| 17 | 仿真组 L2 参考向量声明 143 行（HA 9 / FA 27 / ripple8 37 / mux2 27 / mux4 5 / decoder3 10 / comparator4 17 / alu4 8） | **实测 JSON 共 140 行**（`determinism.rows` 计数同为 140，"143"为文档笔误）；已比对 **132/132**：HA 9、FA 27、ripple8 37、mux2 27、mux4 5、decoder3 10、comparator4 17（`tests/test_l2_vectors.gd`，另断言 decoder3 11 门 / comparator4 33 门、`t_settle` 4/11）；仅 `alu4` 8 行不比对 | ALU 内部 166 门超 80 绝对上限，按接口对齐必须走宏单元（M4 只给 ≤50 门子视图），不做 166 门可交互网表 |
| 18 | 快照 `ifz-sim/2` 示例含 `clocks: [{name, period, duty, phase}]` | 字段保留但**恒为空数组**：本引擎没有时钟对象，时钟全部由 `set_input` 的定时事件驱动（`SimSequential.drive_clock` 也只排事件） | 不为"对齐示例"引入未使用的时钟抽象；恢复后的时钟事件仍按绝对 tick 排定，`state_digest` 已证明续跑一致 |
| 19 | G6 写 `period = t_clk_min + 5`（4 位 = 19） | 实测用 **`min+6 = 20`**（Clock 要求偶数，19 非法）；G6 的"周期=10 时 X+METASTABLE"仍按要求断言 | `min+5` 与"偶数"约束冲突；取满足两者的最小偶数 20，语义（确定性）不变 |
| 20 | G8 写 `tests/data/l3_vectors.json` ≥40 条（4 类器件 + 复位 + 两类违例） | **已补齐**：`tests/data/l3_vectors.json` 24 个用例 / 51 条期望，`tests/test_l3_vectors.gd` 逐条比对 tick / Q 值 / 最后一条 L3 trace kind / 亚稳态 reason。补齐过程中发现真实缺陷：`create_register`/`create_shift_register` 先建 EN mux、后建 Q 线网，Q 初值被门输入隐式初始化为 X（移位寄存器首个沿即采样到 X）→ 已改为先建 Q 线网，回归全过 | 先前的"上下文预算"原因已消除；G8 现在是机器可判定的 |
| 21 | `docs/simulation/10` §6.4 超限错误码写作 `E_L1_SCALE` | 工程内统一为 **`IFZ_E_SCALE`**（`SimDelays`/`SimCircuit`/M3 验收口径一致） | 错误码前缀统一到 `IFZ_E_*`，避免同一约束两个名字；**`docs/simulation/` 不改**，由仿真组据本行统一 |
| 22 | alu4（166 门）无门级网表，`t_settle` 没有可实测的对象 | 按 `components.py::ALU._build()` 关键路径结构推导为 **61 tick**（控制 4 + 补码选择 7 + 行波加 28 + 两级选择 12 + V 标志 10），`tests/test_macro.gd` 用 `SimDelays` 公式重算断言、不硬编码 | 80 门硬上限决定了 ALU 不能进可交互门级视图；没有网表就没有实测条件。若仿真组日后给出 ALU 实测值，以实测为准并改本行，**`docs/simulation/` 不改** |
| 23 | `docs/design/11` §3 的 8 种判定 kind 为英文小写（`mosfet_region` … `power_ratio`） | trace kind 取**全大写机械映射**（`MOSFET_REGION` … `POWER_RATIO`），映射表在 `SimCircuit.JUDGEMENT_KINDS`；`build_area` 是语法糖，不产生 trace，也不计入 8 种 | 避免自造词、避免小写/大写两套事件名；映射只有一处（`docs/design/11` → 工程常量），UI 按 `specs/m4/ui_contract.md` 接线 |
| 24 | 教学组失败诊断表 `docs/curriculum/05-failure-diagnostics.md` 定义 code 与 `K/S/C/P/M/R` 语义（任务书要求"按它设计，不要自己发明"） | **该文件未入库**（仓库只有 `05-onboarding-guidance.md`、`06-assessment-and-feedback.md`），全库 grep 无 `error_tags`/诊断表内容。已按六类语义落地机器初值：18 个 code + `GateResult.TAG_MAP`；结构与字段不依赖映射 | 不能凭空等待文档而阻塞 M5 基础设施；文档交付后**只改 `GateResult.TAG_MAP` 一表**（必要时新增 code），不改 `GateReport` 字段、调用方与 UI 契约形状。详见 `specs/m5/failure_contract.md` §3 |
| 25 | 2.1 的 MOS 器件参数 | **教学归一化值**：`vth 0.9 V / Ron 50 Ω / Id_sat 5 mA / Id_off 1 nA`，不是真实工艺；已调到"同一 Vds 下线性区电流 < 饱和区电流"（Vds=0.2 V 时线性 4000 µA < 饱和 5000 µA），并在 lab 文案写死四组测量条件（Vgs/Vds，含 Vds=6.0 的"不再上涨"点） | 原 `Id_sat=1000 µA` 低于线性区 4000 µA，与"饱和=封顶"矛盾；教学只需单调关系，不追求 SPICE 精度。见 §2.21 与 `ch02_labs.json` 的 `measure_conditions` |
| 26 | `bound_first` 首件绑定不可回收 | **已真修（2026-11-04）**：`ChapterRuntime.grants(lab_id, labs_doc, state)` 读取 `granted:<lab>`，已领过的 lab 返回空奖励表，重复刷关不再发放（见 §2.23）；`G01–G04` 与 `M01/M09/G12` 同口径；**售出端已收口**（§2.24：`EconomyCore.sell` 拒卖绑定件，不扣件、不加金币） | 原 `test_economy` 的 "sell M01" 断言与绑定数据冲突，已改用非绑定 `M08` 验证出售路径，check 数不减 |
| 27 | CH02 技能树 24 个节点 / `start_gold_mode: carry` | 只在 `ch02_levels.json` 引用 `SK-TR…SK-POWER` 与 `milestone CH02-1…5`，**未新增 `skilltree.json` 节点**；`start_gold_mode` 字段已写入但 `ChapterRuntime` 未实现 carry 逻辑，按规格回落 `start_gold 0` | 新增 24 节点会让 `tests/test_data.gd` 的"36 节点"断言退；M5 任务只授权 ch02 两份数据 + manifest |
| 28 | CH02 `static_current` / `rail_margin` | **`rail_margin` 已落地**（18/20）：`_judge_rail` 按逻辑输出反算 V_high/V_low，落 `E_RAIL_MARGIN`(20)，无器件层依赖；`static_current` 仍 `E_PENDING` + `required=false`（2 条 gate：`T2.2-3`、`T2.4-4`，**不算通过**） | 不写永远通过的假 gate；`rail_margin` 只需离散分压算术，故先落地；稳态电流仍等最小 L1 电流模型 |
| 29 | 2.4 正式内容延后（等器件级网表），需在配置里标"待解锁" | lab 条目新增 `content_status`（`ready`/`deferred`，缺省 `ready`）与玩家可见 `deferred_reason`；`ChapterRuntime.lab_content_available` 返回 `{available, reason}`，`lab_unlocked`/`lab_lock_reason` 先判内容可用性 → **整节禁入**，不是 gate 全 pending；`replace` 已置 `deferred`，技能树 `SK-REPLACE` 保留（见 §2.24） | 半开的节会让玩家做完看不到分；`deferred_reason` 只写面向玩家的话。**已处置**：`power` 前置改 `["nand"]`，2.4 变侧枝；已补 lab 级 `requirement`（`MUST`/`OPT`/`CHAL`，缺省 `MUST`），2.4 标 `OPT`，完成度按 `MUST` ∧ `ready` 计（CH02 恒 4/4，见 §2.26） |
| 30 | 2.5 `build_area` 的 8 门预算 | 门数按**展开后**统计：成品 XOR 记 4 门（`GATE_EXPAND_WEIGHTS`），`BUILD_AREA_GATE_BUDGET = 8` 为唯一来源；槽位（`slots`）与门数（`max_total_gates`）两条约束分开判定 | 顶层件数口径会把成品 XOR 记 1，`4 ≤ 8` 恒真、预算静默失效；已用测试钉死（成品 XOR=4、全用现成门=7 过、4 个成品 XOR=16 落 `E_AREA`） |

### 3.1 偏差 11 的数值组成（避免"25 金币/50 XP"读成单一来源）

- 六节 lab 奖励合计：`20+30+25+35+20+30 = 160` 金币，`10+15+10+20+10+15 = 80` XP（`ch01_levels.json`）。
- 章末 `complete_reward`：`gold 0`、`xp 50`、`badge CH01-FIRST-ADDER`。
- 章末 `Knowledge.unlock("CH01")`（`skilltree.json` 的 `CH01` 节点）：`gold_award 25`、`xp_award 50`。
- 合计章末额外：**25 金币 / 100 XP**（50 来自 `complete_reward` + 50 来自节点）。

## 4. 未完成（需人工）/ 未完成

| 项 | 状态 | 说明 |
|---|---|---|
| 性能基准关（全翻转场景、5 ms/帧实测） | **已完成（2026-11-04）** | 见 §2.2：200 门/200 DFF p95 17.78 ms（超预算 3.6×）；安全上限 50 门/50 DFF（p95 4.11 ms）。`scripts/bench.ps1` 可复现，产物 `artifacts/logs/bench.json` |
| 原生 GDExtension（编译、与 GDScript 同向量、接入 `project.godot`） | **未完成** | `native/` 只有脚手架：核心自检 `ifz_selftest` 已在 MinGW g++ 15.1 + CMake 下编译并通过（1/1），但 **GDExtension 动态库未构建**，MSVC 未验证，未接入 `project.godot` |
| 延迟常量三方一致校验（`delays.json` == `docs/simulation/03` == 原生头文件） | **未完成** | 当前靠人工核对，CI 无此步骤 |
| 存档前向迁移框架（注册式迁移器 + fixture + 迁移链契约测试） | **已完成（2026-11-04）** | 见 §2.4：`SaveCodec.registry_errors()`、`tests/data/saves/legacy_v1.json`、`legacy_v2.json`、`tests/test_save.gd` |
| 沙箱、编译器桥接、L7 伴生进程与「转发」标记 | **未完成** | 仅 ADR 0004 设计，无代码 |
| L2 组合模块封装 / `t_settle` 声明 | **已完成（2026-11-04）** | 见 §2.3：`src/sim/sim_module.gd` + `tests/test_l2.gd`（半加器/全加器/8 位行波加法器/2:1/4:1 选择器） |
| L3 DFF 与亚稳态 / L4 CPU / L5 总线 / L6 网络 | **L3 已完成（2026-11-04）**；L4–L6 未完成 | 见 §2.6–§2.13：`SimDff`（setup/hold/RESET→X+METASTABLE）+ `SimSequential`（寄存器/计数器/移位寄存器，含 EN/LOAD）+ `tests/test_l3.gd`（63 项）。L4–L6 仅规格 |
| 统一 `TraceSink`（`(tick, layer, kind, subject, payload)`） | **已完成（2026-11-04）** | 见 §2.9：5 字段 schema、kind 白名单、环形缓冲、`digest()`、1 vs 4 tick/帧摘要一致；`tests/test_trace.gd` 34 项 |
| 第一章每节物品奖励入库 | **机制已完成（2026-11-04）；数据待策划** | 见 §2.11：`PlayerState.grant_items` 幂等 + 原子校验 + `dry_run`，`tests/test_rewards.gd` 28 项；`ch01_levels.json` 一行未改，等策划奖励表定稿 |
| 冒险三档（`EXPLAIN/SYNC/MASK`）开关 | **字段已完成（M4，2026-11-04）；行为与 UI 开关未完成** | 见 §2.19：`Difficulty` + `PlayerState.settings.difficulty` + 存档往返/回落测试；**不改仿真行为**，`SYNC/MASK` 语义留 M5；开关绘制待 UI 会话 |
| 错误码编号（`docs/simulation/07` §5 的 0–18） | **未完成** | 现为字符串错误 `IFZ_E_*` |
| 42 道练习题库与逐题评分表 | **已完成（2026-11-05）** | 见 §2.18、§2.29：`data/questions/ch01_exercises.json` 恰 42 题，`QuestionBank` 加载/校验/评分经 `tests/test_questions.gd` 221 checks 验证，`manifest.json` 已登记；其余章节题库未交付 |
| CH05/CH06 章节注册与 UI 可达性 | **未完成** | 两份 labs 数据与判定已落地（§2.29），但缺 `ch05/ch06_levels.json`、`skilltree.json` 的 CH05/CH06 节点与 manifest 登记；CH03/CH04 未落库，章节进度链无法到达 |
| 6 节脚本化走查（UI 真实链路 → 验收 → 知识树 → 存档 → 重启读档） | **已完成（2026-11-04）** | 见 §2.5：`--walkthrough` 72 项 0 失败，`--verify-walkthrough` 36 项一致；物品奖励本章未定义，仅断言不变 |
| 6 节真人鼠标走查（操作 → 验收 → 知识树 completed → 存档 → 重启续玩） | **需人工** | 脚本走查绕过鼠标点击/连线动作，真人交互仍需按 `docs/design/08` 走一遍 |
| 截图冒烟之外的交互验证（拖拽/撤销不出现在 M1）、引导 6 步真实走查 | **需人工** | 需真人按 `docs/design/08` 走一遍 |
| `.github/workflows/ci.yml` 在真实 GitHub Actions 上运行 | **需人工** | 本地无法验证；文件内已注明"未在真实 CI 上验证" |
| 知识卡内容补全（设计目标 ~180 张） | **未完成** | 当前 `skilltree.json` 只有 19 个知识节点（多为一句话摘要），设计文档已标【假设】 |
| 波形光标测量（`docs/design/03` T1.5 要求测量光标差值） | **需人工** | 波形控件存在，光标/测量功能未在本文档验证，需人工检查后再定论 |

### 4.1 M3 验收项（G1–G15）

| 关 | 判定方式（机器可跑） | 结果 |
|---|---|---|
| G1 | `tests/test_l3.gd::_test_m2_baseline` + `_test_chain`：M2 行为不回归、链式 DFF 逐沿右移 | 通过 |
| G2 | `tests/test_l3.gd::_test_setup`：D 在沿前 <2 tick 变化 → Q=X + `METASTABLE(setup)` | 通过 |
| G3 | `tests/test_l3.gd::_test_hold`：沿后 <1 tick 变化 → Q=X + `METASTABLE(hold)` | 通过 |
| G4 | `tests/test_l3.gd::_test_reset`：RESET 高有效、沿上优先、释放后正常采样 | 通过 |
| G5 | `tests/test_l3.gd::_test_register_en`：EN=0 保持 / EN=1 装载 / EN=X → X，t_settle=2 ≤9 | 通过 |
| G6 | `_test_counter_wrap`（18 沿 0..15 回绕）、`_test_counter_en_load`（LOAD/EN）、`_test_counter_too_fast`（period=10 → X+METASTABLE） | 通过（周期用 min+6=20，偏差 19） |
| G7 | `tests/test_l3.gd::_test_shift_register`：串行移入、复位、位宽 | 通过 |
| G8 | `tests/data/l3_vectors.json` 24 用例 / 51 条期望（dff 8、register 5、counter 7、shift 4；含复位 3 条、setup 2 条、hold 1 条），`tests/test_l3_vectors.gd` 逐条比对 tick/值/trace kind | 通过（偏差 20 已闭合） |
| G9 | `tests/test_trace.gd`：5 字段、kind 白名单、tick 单调、`history`==CHANGE 数、1 vs 4 tick/帧 digest 相同 | 通过 |
| G10 | `tests/test_l3.gd::_test_snapshot`：`ifz-sim/2` 往返 digest/tick 相同、兼容 `ifz-circuit/1`、非静止态拒绝 | 通过 |
| G11 | `scripts/bench.ps1 -Scenario l3 -Sizes "50,80,100" -Frames 400`，p95 1.78/2.71/3.32 ms ≤5；值回写 `delays.json` 且 `test_data` 断言 | 通过 |
| G12 | `tests/test_rewards.gd`：重复不二次发、未知物品整单拒绝、存档往返保留 | 通过 |
| G13 | `tests/test_l2_vectors.gd`：只读 `l2_vectors.json` 逐行比对 132/132（decoder3 10 + comparator4 17 已补） | 通过（仅 alu4 8 行走宏单元，偏差 17） |
| G14 | 三档 3 次 p95 + `limits` 50/50/80 + 偏差 15 行 | 通过（§2.7） |
| G15 | `tests/test_circuit.gd` G15 段：上限来自 `SimDelays`、>50 提示结构级、>80 报 `IFZ_E_SCALE` | 通过 |

### 4.2 M4 验收项（G1–G10）

| 关 | 判定方式（机器可跑） | 结果 |
|---|---|---|
| M4-G1 | `tests/test_macro.gd`：3 个宏单元、门数 11/33/166、alu4 七页 5/40/9/16/48/32/16 合计 166、每页 ≤ `gdscript_gate_limit()`、`t_settle` 4/11/61 | 通过 |
| M4-G2 | 同套件：`expand("alu4")` → `IFZ_E_SCALE`；decoder3/comparator4 展开门数 11/33；`fold()` 端口摘要；展开→折叠→再展开 `state_digest` 相同 | 通过 |
| M4-G3 | `tests/test_ch02_kinds.gd`：8 种 kind 可写、`KINDS.size()==15`、每条 5 字段、未知 kind 拒绝、1 vs 4 tick/帧 `digest()` 相同、开/关 trace 末态相同 | 通过 |
| M4-G4 | 同套件：8 个判定 kind ↔ trace kind 逐项断言 8/8，`build_area` 显式排除 | 通过 |
| M4-G5 | `tests/test_questions.gd`：fixture 3 条载入、评分确定性、8 类非法文档报错、未知 id `ok=false`、`manifest.json` 未改 | 通过 |
| M4-G6 | `tests/test_difficulty.gd`：三档命名/归一/默认/存档往返/缺字段回落（含 v1 旧档不升版本） | 通过 |
| M4-G7 | `tests/test_l2_vectors.gd` 132/132（`alu4` 8 行不比对，偏差 17） | 通过 |
| M4-G8 | `RESULT: 1810 checks, 0 failures`（22 套件） | 通过 |
| M4-G9 | `git diff --stat -- project.godot src/ui/ data/chapters/ data/labs/ docs/design/ docs/simulation/ docs/curriculum/` 为空（仅统计本会话提交；UI 会话改动不计） | 通过（按本会话提交路径核对） |
| M4-G10 | `test_macro` 预算段：45+11=56 → `scale_warn`；70+11=81 → `IFZ_E_SCALE` 且门数不变；阈值均来自 `SimDelays`，测试无硬编码 50/80 | 通过 |

**待 UI 会话接回**（不计入机器 Gate，M4 只留接口与事件名，见 `specs/m4/ui_contract.md`）：
宏单元页绘制、ALU 七页只读视图、难度开关、题库页面、错因反馈卡、埋点上报（`item_start/item_submit/hint_open/lab_check/scale_warn/view_page_open/view_fold`）。

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

## 6. 下一步（M4 与 M5 基础设施已交付；等 CH02 内容与 UI 会话接回）

M4 已按 `specs/m4/tasks.md` 的 T0→T5 交付：宏单元接口 + ALU 七页只读视图、8 种 CH02 trace kind、题库接口、
难度三档字段（§2.16–§2.19）。M5 第一项基础设施（结构化失败回传）已交付（§2.20，
契约 `specs/m5/failure_contract.md`）。**未完成且不在本会话范围**：

- UI 按新契约渲染诊断文本与提示阶梯：**待 UI 会话接回**（`src/ui/` 本会话未改）；
- 正式 `docs/curriculum/05-failure-diagnostics.md` 交付后，只重映射 `GateResult.TAG_MAP`（偏差 24）；
- CH02 的 gate 与奖励数值：等 `docs/design/11-ch02-content-spec.md` 定稿；
- CH05/CH06 章节注册与 UI 可达：等 `ch05/ch06_levels.json` 与 `skilltree.json` 的 CH05/CH06 节点；CH03/CH04 未落库，当前只能停在 ch02；
- `SYNC/MASK` 的实际采样语义：留 M5 后续；
- 原生 GDExtension、ALU 8 行向量比对（`alu4` 仍只比对 0/8，见偏差 17/22）。

`alu4` 整块展开按 80 门硬上限拒绝（`IFZ_E_SCALE`），只提供 ≤50 门只读页。

## 7. 验证命令（当前基线的复现方式）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1     # 期望 RESULT: 5862 checks, 0 failures（55 套件；基线见 §10）
powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1     # 导入 + 测试 + GUI 冒烟
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1         # 性能基准（gate 场景）
.\scripts\bench.ps1 -Scenario l3 -Sizes "50,80,100" -Frames 400       # L3 场景（DFF 链 + 计数器）
git diff --stat -- docs/simulation/ docs/design/ docs/curriculum/    # 期望为空（只读文档不改）
powershell -ExecutionPolicy Bypass -File .\scripts\run_game.ps1      # 手动操作

# 6 节脚本走查 + 重启读档校验（无窗口，快照写入 user://walkthrough.json）
& "C:\tools\godot-4.4.1\godot.cmd" --path . --fresh "--walkthrough=user://walkthrough.json"   # 期望 failures=0
& "C:\tools\godot-4.4.1\godot.cmd" --path . "--verify-walkthrough=user://walkthrough.json"     # 期望 WALKTHROUGH_VERIFY_OK failures=0

# 每节一张截图（GUI 后端）
& "C:\tools\godot-4.4.1\godot.cmd" --path . "--shot=<abs>\artifacts\shots\lab_level.png" --shot-screen=workbench --shot-lab=level
```

截图证据（已存在，作为验收依据；是否入库由负责人决定）：

```
artifacts/shots/workbench.png  shop.png  skills.png  archive.png  diagnostics.png
artifacts/shots/lab_level.png  lab_binary.png  lab_boolean.png  lab_gate.png  lab_signal.png  lab_half_adder.png
```

## 8. CH03–CH06 数据落地与章节注册（2026-11-05）

本节覆盖 §1 / §7 的旧基线数字：全量测试现为 **41 套件、SUITE_TOTAL 4643 + runner 自检 2 = 4645 checks、0 failures**
（日志 `artifacts/logs/tests.log`，复现命令同 §7）。

- CH03（4 节 `full_adder` / `adder8` / `clock_edge` / `bistable_reg`，段数 5/5/5/6，共 16 条 gate）：
  `data/labs/ch03_labs.json`、`src/core/ch03_checks.gd`、`tests/test_ch03.gd`（216 项检查）。
- CH04（5 节 `mux` / `alu8` / `control_unit` / `memory` / `io_bus`，各 5 段，共 20 条 gate）：
  `data/labs/ch04_labs.json`、`src/core/ch04_checks.gd`、`tests/test_ch04.gd`（265 项检查）。
- 章节注册：新增 `data/chapters/ch03_levels.json` … `ch06_levels.json`（labs 的 `id`/`data_key`/`requires`/`gate_ids`/`reward`、
  `objectives`、`complete_reward`、`next_chapter` 链已对齐 ch02）；`data/skilltree.json` 追加 CH03–CH06 里程碑/知识/技能节点，
  总节点 **142**（progress 41 / knowledge 67 / skill 34）；`data/manifest.json` 登记 4 章 levels + labs，共 **19** 个文件。
- 数据层红绿验证：`tests/test_chapters_03_06.gd`（63 项）断言四章可装载、`use_chapter` 可达、`labs_by_chapter` 非空、
  manifest 无漏登记、`gate_ids` 无悬空；并含 5 条"改坏数据必须变红"自证（删进度节点 / 造悬空 gate /
  删 manifest 登记 / 删 lab 条目 / 删 `SK-VM` 引用）。
- 判定红绿：每个 gate 各有"正确解判绿"与"错误解判红"用例（`test_ch03` / `test_ch04` 的 `judge_*` 组）。

仍未完成 / 落 pending：

- CH04 `area_check`（4.2「展开门数 ≤ 预算」）预算数值未定，写入 `pending_kinds`，不进分母、不判红。
- CH03 延迟判定只断言"报告有延迟且级数 = 8"，延迟上限口径未定，未做上限判红。
- CH05 / CH06 仅做数据层注册与 gate 引用对齐（CH05 既有 4 节共 17 条 gate，其中 `clock_limit` 为 5 条）；
  章节 UI 可达性与既有 `ch05/ch06_labs.json` 的文案联动仍待 UI 会话。
- `src/ui/` 与 `project.godot` 未改（不在本次范围）。

## 9. CH07–CH08 数据落地与章节注册（2026-11-05）

本轮新增 3 个套件、共 403 项检查；当次全量实测（工作区同时含并行会话的 CH09–CH11 提交）：

- `SUITE test_ch07 expected=208 actual=208`
- `SUITE test_ch08 expected=157 actual=157`
- `SUITE test_chapters_07_08 expected=38 actual=38`
- `SUITE_TOTAL expected=5265 actual=5265`，`RESULT: 5267 checks, 0 failures`，46 套件。
- 按 §8 基线 4645 + 本轮 403 = 5048；其余增量为并行会话的 `test_ch09` 83 + `test_ch10` 68 +
  `test_ch11` 68 = 219，不计入本轮提交。

CH07（4 节 `serial_basics` / `frame4` / `uart` / `two_machine`，各 5 段、共 16 条 gate）：

- `data/labs/ch07_labs.json`、`src/core/ch07_checks.gd`、`tests/test_ch07.gd`（208 项）。
- 每节 `after` 序列均为 `0,0,1,2,3`，末段 `after=3`，`required=4`。
- `T7.1-1`（`sample_phase`）落 `pending_kinds`：位窗口/采样 tick 接口与 ±10% 位宽容差未校准，
  不进分母、不判红；`serial_basics` 分母 3，其余 3 节分母 4。
- 其余判据（`edge_sample` / `period_calc` / `frame_fields` / `stop_low` / `parity_calc` / `uart_offset` /
  `single_point_shift` / `offset_calc` / `two_machine` / `baud_mismatch` / `no_checksum` / `quiz`）
  全部判绿/判红，失败码限定在 `E_UNCONNECTED(3)` / `E_TABLE_CELL(7)` / `E_DELAY_MISMATCH(9)` /
  `E_OUTPUT_MISMATCH(10)` / `E_COVERAGE(13)` / `E_QUIZ(14)`。

CH08（3 节 `protocol_editor` / `handshake` / `capture`，各 5 段、共 12 条 gate）：

- `data/labs/ch08_labs.json`、`src/core/ch08_checks.gd`、`tests/test_ch08.gd`（157 项）。
- `T8.1-3`（`field_start_spec`）落 `pending_kinds`：8.1 字段位宽 `field_spec` 未定，无法给出机器起始位真值，
  不进分母、不猜数补 gate；`protocol_editor` 分母 3，`handshake` / `capture` 分母 4。
- 其余判据（`protocol_replay` / `skip_layer` / `handshake_fsm` / `timeout_idle` / `self_heal_path` /
  `capture_layers` / `single_snapshot` / `capture_start` / `quiz`）全部判绿/判红。

章节注册：

- `data/chapters/ch07_levels.json`（badge `CH07-SERIAL`，`next_chapter: ch08`）、
  `data/chapters/ch08_levels.json`（badge `CH08-PROTO`，`next_chapter: ch09`）；
  `ch06_levels.json` 的 `next_chapter` 由空改为 `ch07`，链路 `ch06→ch07→ch08→ch09` 闭合。
- `data/skilltree.json` 追加 25 个节点，总节点 **167**（progress 52 / knowledge 74 / skill 41）。
- `data/manifest.json` 登记 4 个新文件，共 **23** 个文件。
- `tests/test_chapters_07_08.gd`（38 项）断言装载、`use_chapter` 可达、`labs_by_chapter` 数量、
  manifest 无漏登记、`gate_ids` 无悬空、节点引用、全量 `validate()`；并含 5 条内存副本红证：
  删 `CH07-1`、加悬空 `T7.1-9`、删 ch08 levels 登记、删 `two_machine`、删 `SK-CAPTURE`。

仍未完成 / 落 pending：

- CH07 `T7.1-1`、CH08 `T8.1-3` 仍为 `pending`（判定口径未定），未做硬阈值判定。
- CH04 `area_check` 仍 pending（沿用 §8）。
- CH09/CH10 的 levels、manifest、skilltree 注册不在本轮范围。
- `src/ui/`、`project.godot`、`docs/design/`、`docs/curriculum/` 未改。

## 10. 全书内容总账（CH01–CH19 + 终章，2026-11-05）

口径（与 `tools/lab_account.py` 文件头的规则同文，改口径必须同时改这两处）：

> 进分母 = `required==true` 且 gate 自身 `status`/`content_status=="ready"` 且所在 lab 的 `content_status=="ready"`（lab 未写则取 `data/chapters/*_levels.json`）的 gate 数。

恒等式（脚本每次运行末尾自动验算，不闭合就以退出码 1 结束）：

`334 gate = 316 进分母 + 14 pending + 3 节级 deferred + 1 required=false`

- `labs` = 文件内 `labs` 键的条目数；
- `段` = 各 lab `sections` 长度之和；
- `gate` = 各 lab `gate_cases` 条目数（CH01/CH02 的 gate 也在这张表里，故两章 `p1_gates` 为空不影响计数）；
- `pending` = `required` 且 `content_status`/`status != "ready"` 的条目数（不进分母、不判红）；
- `进分母` = 上述规则；
- `节级 deferred` = `required` 且 gate 自身 ready，但所在 lab 非 ready（整节被内容侧延后）；
- `required=false` = 可选 gate，始终不进分母、也不算 pending。

脚本落点：`tools/lab_account.py`（一次遍历 20 个 `data/labs/*_labs.json` + 19 个 `data/chapters/*_levels.json`；终章 `final_labs.json` 没有 levels 文件，脚本**显式打印「该章无声明、跳过」**，不静默忽略）。

### 10.1 逐章统计原文（2026-11-05 脚本实扫 20 个 lab 文件 + 19 个 levels 文件，非手工加总）

```
file                     labs  data_gates  level_gates  data_segs  level_segs  pending  section_def  optional  counted
ch01                        6          24           24         34          34        0            0         0       24
ch02                        5          20           20         25          25        2            3         0       15
ch03                        4          16           16         21          21        0            0         0       16
ch04                        5          20           20         25          25        1            0         0       19
ch05                        4          17           17         21          21        0            0         1       16
ch06                        6          24           24         30          30        2            0         0       22
ch07                        4          16           16         20          20        1            0         0       15
ch08                        3          12           12         15          15        1            0         0       11
ch09                        5          20           20         25          25        1            0         0       19
ch10                        4          16           16         20          20        1            0         0       15
ch11                        4          16           16         20          20        1            0         0       15
ch12                        5          20           20         25          25        1            0         0       19
ch13                        3          12           12         15          15        0            0         0       12
ch14                        3          12           12         15          15        0            0         0       12
ch15                        4          16           16         20          20        0            0         0       16
ch16                        4          16           16         20          20        1            0         0       15
ch17                        3          12           12         15          15        0            0         0       12
ch18                        4          16           16         20          20        1            0         0       15
ch19                        5          20           20         25          25        1            0         0       19
final                       3           9            0          9           0        0            0         0        9
TOTAL                      84         334          325        420         411       14            3         1      316

章节 final：无 levels 声明（data/chapters/final_levels.json 不存在），该章无声明、跳过（不参与 gates/segs 比对）
完整性：gate 数据 334 / levels 声明 325（已声明 lab 81/84）；segs 数据 420 / levels 声明 411
验算：闭合
```

`level_gates` / `level_segs` 的合计比数据小，是因为终章 3 个 lab 没有 levels 声明（`334-9=325`、`420-9=411`），不是比对失败；该章已逐行打印「跳过」。


### 10.1b 4 条明列不计（既不进分母、也不算 pending，逐条可查）

| 文件 | lab | gate id | 不计原因 | 依据 |
|---|---|---|---|---|
| `data/labs/ch02_labs.json` | `replace` | `T2.4-1` | 节级 deferred | `e3706ed`（提交信息「2.4 内容锁定」）把 `data/chapters/ch02_levels.json` 的 `replace` 标 `content_status: deferred`，`deferred_reason` 写明「这一节需要更底层的器件模型，正在搭建中」；`docs/design/20` 的已批准结论是「不建静态电流模型」，故保留不计 |
| `data/labs/ch02_labs.json` | `replace` | `T2.4-2` | 节级 deferred | 同上 |
| `data/labs/ch02_labs.json` | `replace` | `T2.4-3` | 节级 deferred | 同上 |
| `data/labs/ch05_labs.json` | `clock_limit` | `T5.4-5` | `required=false` | `9773238` 首次入库即 `required:false`，非后续改动；该节 `practice` 行 `judge` 原文「answer 对照；非唯一 gate」；`tests/test_ch05.gd` 断言每节 `required` 恰 4 条（这条是第 5 条可选 quiz） |

### 10.1c 总账进收工判定 + `same_symbol`/`abi_ok` 跨源证据（2026-11-05）

- **入口**：`scripts/run_tests.ps1` 在测试跑完后调用 `tools/lab_account.py`，总账先于测试终结判定报错。
  - 测试红 = **1**（原有）；账不闭合 = **8**；总账没跑起来 / 无 `TOTAL` 行 = **9**（三者互不冲突）。
  - 四桶恒等式按定义恒成立（任一 gate 必落在 counted / pending / 节级 deferred / optional 之一），**因此它只作展示、不作判据**；判据是脚本用 `data/chapters/*_levels.json`（19 章 84 lab，终章无声明已显式跳过）逐 lab 对账两列：
    - `gate_ids`＝**内容侧声明**，集合必须相等（只比条数会漏掉「换了一条 id」）；
    - `segs`＝**冻结快照**（来源：提交 `ac1c428` 时刻各 lab 的 `sections` 数），用途＝**漂移提醒**，**不是内容侧应有值**。它与 gate 声明性质不同：改了数据却没同步锁值会红，这是提醒；"数据本身对不对"仍由课件「校验口径」表（74/84 lab 有逐行段数，已核对完全一致；其余 10 个课件表无逐 lab 行：ch01 的晶体管系列 4 个、ch09 的 `arp`、终章 f1–f3）与各章 `test_chNN.gd` 的 `section_count` 断言负责。
    - 维护规则：**内容侧若有意改段数，必须同时改 levels 的 `segs` 声明**，否则这条会一直红——这是预期行为，不许当误报关掉。将来若把课件表解析成机器声明，应以课件值为准并替换本快照。
  - 注入实测（两个不同章节，各改 1 条）：
    - 改 gate：`ch14/dynamic_type` 的 `T14.2-1` → `T14.2-1-X`，恒等式仍闭合（`334 = 313 + 17 + 3 + 1`），完整性报「`ch14/dynamic_type: gate 与 levels 声明不符（数据 ['T14.2-1-X', ...] / levels ['T14.2-1', ...]`）」，入口 **exit=8**；
    - 改 segs：`ch19/embedded_budget` 删末段（5 → 4），恒等式仍闭合（`334 = 313 + 17 + 3 + 1`），完整性报「`ch19/embedded_budget: 段数与 levels 声明不符（数据 4 / levels 5）`」，入口 **exit=8**；
    - 两处复原后 **exit=0**，`84 lab / 420 段 / 334 gate / 313 进分母` 不变。
  - 无 `TOTAL` 行实测：临时让脚本只输出非 TOTAL 文本 → **exit=9**，提示「总账脚本没有输出 TOTAL 行」。
- **`same_symbol` / `abi_ok` 不是自己跟自己比**：`same_symbol` 比 P1/P2 各自 `declares`（两份程序数据）；`abi_ok` 比「程序声明 vs 库 `symbols` 导出」并查 `abi_types` 词表（三份数据）。注入时库导出与表行都不动，只改声明：

```
RED-PROBE CH15 T15.1-1 P2 声明 area(int,char,int)（库导出/行不变）-> same_symbol=false abi_ok=false
RED-PROBE CH15 T15.1-1 同符号声明不一致 -> code=10
RED-PROBE CH15 T15.1-1 P1/P2 都声明 area(...)->B（与库导出 A 不符）-> same_symbol=true abi_ok=false
RED-PROBE CH15 T15.1-1 abi_ok 不符 -> code=10
```

- **15.3 接线**：`T15.3-1` 的 6 行由 `SymbolTable.compat_report(case_sources.version_pairs)` 现算（旧/新符号表成对写在课件数据 `ch15_labs.json` 里，不是期望表里的数字）；`reason` 逐格比对，五类各一条（area `ret_changed` / scale `order_changed` / sum `arity_changed` / peek `name_changed` / emit `type_changed`），未变的 tick 一行 `compatible=true` 但主版本 1.0→2.0 仍 `rejected`。五类各一条负例把 `reason` 改错 → 均 7：

```
RED-PROBE CH15 T15.3-1 area 行 reason 改错(ret_changed→type_changed) -> code=7
RED-PROBE CH15 T15.3-1 scale 行 reason 改错(order_changed→type_changed) -> code=7
RED-PROBE CH15 T15.3-1 sum 行 reason 改错(arity_changed→type_changed) -> code=7
RED-PROBE CH15 T15.3-1 peek 行 reason 改错(name_changed→type_changed) -> code=7
RED-PROBE CH15 T15.3-1 emit 行 reason 改错(type_changed→ret_changed) -> code=7
```

### 10.2 20 行总账（一章一行，数字全部来自 10.1）

| 章 | lab | 段 | gate | pending | 进分母 | 入库日期 | 提交 |
|---|---|---|---|---|---|---|---|
| CH01 | 6 | 34 | 24 | 0 | 24 | 2026-11-04 | `0d63b67` |
| CH02 | 5 | 25 | 20 | 2 | 15 | 2026-11-04 | `cd057cf` |
| CH03 | 4 | 21 | 16 | 0 | 16 | 2026-11-05 | `de7bc7a` |
| CH04 | 5 | 25 | 20 | 1 | 19 | 2026-11-05 | `42e2911` |
| CH05 | 4 | 21 | 17 | 0 | 16 | 2026-11-05 | `9773238` |
| CH06 | 6 | 30 | 24 | 2 | 22 | 2026-11-05 | `9773238` |
| CH07 | 4 | 20 | 16 | 1 | 15 | 2026-11-05 | `e22432b` |
| CH08 | 3 | 15 | 12 | 1 | 11 | 2026-11-05 | `d425c59` |
| CH09 | 5 | 25 | 20 | 1 | 19 | 2026-11-05 | `c065c68` |
| CH10 | 4 | 20 | 16 | 1 | 15 | 2026-11-05 | `1134677` |
| CH11 | 4 | 20 | 16 | 1 | 15 | 2026-11-05 | `f408b0e` |
| CH12 | 5 | 25 | 20 | 1 | 19 | 2026-11-05 | `09e08d4` |
| CH13 | 3 | 15 | 12 | 0 | 12 | 2026-11-05 | `5369bae` |
| CH14 | 3 | 15 | 12 | 0 | 12 | 2026-11-05 | `2b4ebb9` |
| CH15 | 4 | 20 | 16 | 0 | 16 | 2026-11-05 | `0183c8d` / 15.2 转正 |
| CH16 | 4 | 20 | 16 | 1 | 15 | 2026-11-05 | `6c1b051` |
| CH17 | 3 | 15 | 12 | 0 | 12 | 2026-11-05 | `080b693` / 17.1 转正 |
| CH18 | 4 | 20 | 16 | 1 | 15 | 2026-11-05 | `04f2483` |
| CH19 | 5 | 25 | 20 | 1 | 19 | 2026-11-05 | `5164c4c` |
| 终章 | 3 | 9 | 9 | 0 | 9 | 2026-11-05 | `f4452d9` / F1 转正 |
| **合计** | **84** | **420** | **334** | **14** | **316** | — | — |

交叉校验：`test_gate_result` 的 `EXPECT = 315` 是**该套件自身 15 个分组的检查数**，与"进分母 gate 数"无关（此前一版把它误写成"与脚本合计一致"，已更正）。进分母数只能以 10.1 的脚本读数为准：**316**。

### 10.2b 与上一版（`19 pending / 315 进分母`）的逐项对照

| 项 | 旧值 | 新值（实扫） | 变化来源 |
|---|---|---|---|
| CH05 进分母 | 17 | 16 | 旧版按 `gate − pending` 算，把 `required=false` 的 `T5.4-5`（quiz）也算进了分母；按 `deferred_gates` 口径应排除 |
| CH02 进分母 | 18 | 15 | **本轮复核新发现**：`replace` 整节在 `ch02_levels.json` 里是 `content_status: deferred`，`deferred_gates` 把该节 3 条非 pending 的 required 全排除；旧版按 gate 级口径多算了 3 条 |
| CH13 pending / 进分母 | 1 / 11 | 0 / 12 | 13.1 源码行映射已转正（`4fc45ec` 前后），旧表未同步 |
| CH14 pending / 进分母 | 1 / 11 | 0 / 12 | 本会话 `2b4ebb9`：`T14.2-1` 逐值标签导出转正 |
| 全书 pending | 19 | 17 | 上两项各 −1 |
| 全书进分母 | 315 | 313 | CH13 +1、CH14 +1、CH05 −1、**CH02 −3** |
| 全书 pending / 进分母（本轮） | 17 / 313 | 14 / 316 | 15.2、17.1、F1 各转正一条：pending −1、进分母 +1 |
| gate / 段 / lab | 334 / 420 / 84 | 334 / 420 / 84 | 无变化 |

### 10.3 全量检查（2026-11-05 复跑，原文）

```
SUITE_TOTAL expected=7431 actual=7431
RESULT: 7433 checks, 0 failures
```

60 个套件；`SUITE_TOTAL` 只统计套件自身（7431），`RESULT` 多出的 2 条是打印之后才跑的两道自检：
`[guard] 自测：故意中断的 suite 被判红` 与 `[guard] 防线自检探针存在`（`tests/run_tests.gd` §runner 尾部）。
（本轮相对上一版文字读数 7376 / 7378 为 +55：`test_ch17` 55→75（+20，17.1 的 12 条真判据 + 7 条负例）、`test_final` 54→63（+9，F1 的 9 条）；其余 +26 是上一版读数未随 `test_ch15` 79→90（+11）、`test_ch16` 71→78（+7）、`test_ch14` +5、`test_ch19` +3 更新造成的欠记，以本轮实测为准。）

### 10.4 口径错因（两版差异必须点名，不允许"以最新版为准"）

- **581 段 / 340 gate 那一版是错的**，错在把课件稿里尚未落库的内容当成已落库计入：`docs/curriculum/*.md` 里的 JSON 块合计 **78 lab / 386 段 / 312 gate**，`data/labs` 合计 **84 lab / 420 段 / 334 gate**，两组数各自、以及相加（806 段 / 646 gate）都得不到 581 / 340，即该版在仓库里**无任何可复现来源**。
- **415 段 / 335 gate 那一版也是错的**，错在 20 行表上手工逐行加总（段少 5、gate 多 1），不是脚本读数。
- 唯一有效值：**84 lab / 420 段 / 334 gate / 14 pending / 316 进分母**，与 `SUITE_TOTAL 7431` / `RESULT 7433` 同时在库。恒等式 **334 = 316 + 14 + 3 节级 deferred + 1 required=false** 由 `tools/lab_account.py` 每次运行自动验算；本轮对 20 个 lab 文件 + 20 个 levels 文件整扫，316 为按 `deferred_gates` 逐节算出的读数（4 条明列不计见 §10.1b）。

### 10.5 套件期望数变化溯源（CH15 / CH16 / CH17）

- `test_ch15`：首次入库 **74**（positive 4 / t15_2_interface 3 / negative 8）→ 本会话上一轮 **79**（positive 4 / t15_1_real 3 / t15_2_interface 3 / negative 10）→ 本轮 **90**（positive 4 / t15_1_real 3 / t15_2_interface 4 / t15_3_real 3 / negative 17）。
  74→79：+3 = `t15_1_real` 三条真判据；+2 = 两条负例（`T15.1-1` 符号类型写错→7、参数顺序颠倒→7）。
  79→90：+3 = `t15_3_real` 三条真判据（兼容表逐行对数据、五类 reason 各命中一条、主版本规则拒绝）；+7 = 七条负例（`same_symbol` 声明不一致→10、`abi_ok` 与库导出不符→10、五类 reason 改错各→7）；+1 = `t15_2_interface` 的捕获源真实性（客户端 send/recv 字节与 payload 同一串、fd 与 socket_calls 一致）。
- `test_ch16`：`6c1b051` 时 `EXPECT = 69`（positive 4 / negative 6）→ `4fc45ec` 后 **71**（positive 5 / negative 7，+2 为 `delay` 上限正负探针）→ 本会话 **78**（positive 5 / t16_3_real 3 / negative 11）。
  +3 = `t16_3_real` 三条真判据（逐行对数据、时间戳来自时钟事件、时延逐条由 got−sent 且非固定常数）；
  +4 = 四条新负例（时延改固定 12→9、`got_at` 抄 `sent_at`→9、`req_id` 绑错→7、`client_seq` 绑错→7）。
- `test_ch17`：`080b693` 时 **55**（positive 3 / negative 7）→ 本轮 **75**（positive 3 / t17_1_fields 12 / negative 15）。
  +20 = 17.1 的 12 条真判据（行数/唯一键/现算 accepted/reason 枚举/S2·S3 闭区间/S4/S7/S5/S8/位宽一致/meta 五项/reason 分布 3·1·2·1·1）+ 7 条负例（S1 误拒、S4 `reason="len"`、S5 首错顺序、S7 判绿、S8 判绿、S3 off-by-one、S1 `payload_bytes` 漏核），`pending_total` 分母 1→12。
  （`080b693` 那次「从 54 到 55 的 +1 是第 7 条时延负例」的记载保留，属于上一版口径。）
- `test_final`：`f4452d9` 时 **54**（positive 3 / negative 6）→ 本轮 **63**（positive 3 / f1_outbound_real 9 / negative 6）。
  +9 = F1 的 9 条真判据（桥成功、两行、两读取点同字节、随输入变并可解码回原文、拓扑端口、时延 1..50000 us、字节改写→10、顺序颠倒→10、端口写错→7），`pending_total` 分母 1→9。

### 10.6 未写入的承诺

`docs/design/19-interface-extension-proposal.md`：原文 **10 项**字段级接口扩展（表格行号 17–26），合计 42 人日。当前状态：**10 项已实施**（§2.1 13.1、§2.2 13.2、§2.3 14.1、§2.4 15.1、§2.5 15.2、§2.6 16.3、§2.7 17.1、§2.8 18.4、§2.9 19.3、§2.10 F1；其中 15.2 由本会话用本机 loopback 真实捕获转正（Python socket，客户端 fd=332、send/recv 同一 12 B，原始 10 条调用与 `bytes_hex` 冻结在 `socket_api.capture`；ch15 进分母 15→16、全章 pending 1→0，见 §2.5 实现落点）；16.3 由本会话落成逐请求事件时钟时延；15.1 由本会话落成符号签名表，并把 15.3 的 `diff_sig` 接线为 `compat_report`——`T15.3-1` 六行现算、五类 reason 各一条负例，见 §10.1c；13.2 由本会话落成对象图，边语义见 §2.2，`T13.2-1` 现读 `{nodes, edges}` 并给三条负例/两道规模上限实测，见 `8e6164c`/`f8068e0`；18.4 由本会话落成剧本开关与证书结果可指认：`T18.4-1` 表行加 `switch/cert_verify/result/reason/chain[]`，判据 `src/core/cert_script.gd` 在逐格比对前校验两遍相反剧本，失败码只用 3/7/10，下游读 `report.cases[].actual.rows`，见 §2.8 实现落点；19.3 由本会话落成五段采样链路：`T19.3-1` 不再读 `expect_rows`，真值来自 `src/sim/sim_sampling.gd::trace` 真跑链，逐段 `{stage,node,in_raw,out_raw,code,sample_ms}` + `meta`，四条负例实测 10/7/13/10，上限 32 段（当前 5 段，6.4×），满规模 32/32 绿，见 §2.9 实现落点）；**另补录第 11 项 §2.11（14.2 逐值标签导出）并已实施**（`2b4ebb9`）。§2.4 里仍未落的是调用点 `call_sites`（`pc/argc`）与 `order`/`from` 三列——提案字段未齐，不代表 15.1/15.3 判据是布尔位。**§2.7 17.1** 由本轮落成消息字段边界：`T17.1-1` 8 行、`keys` 含独立 `payload_bytes`/`payload_hex` 列（四字段真的核四列），`accepted/reason` 由 `src/core/msg_fields.gd::evaluate` 按 type→len 16 位→256 B 上限→负载字节数→ts 24 位首错即止现算，四类原因（`bad_type`/`too_long`/`bad_length`/`bad_ts`）各一条负例命中，另补 S5「16 位溢出 vs 超上限」首错顺序负例（实测 detail 含 `len_out_of_field`）；ch17 进分母 11→12、pending 1→0。**§2.10 F1** 由本轮落成本机 loopback 真 TCP 出网：`src/sim/world_port.gd::deliver` 真跑 `listen(127.0.0.1:7777)`/`connect`/`put_data`/`take_connection`/`get_data`，另把 `F1-1` 落成 9 条判据——同一份字节在 `sent_hex`（发送侧 buffer）与 `local_bytes`（服务端读到）两个读取点逐字节相同，负例覆盖字节改写（sum16 对不上→10）、输出顺序颠倒（→10）、端口写错（→7）；终章进分母 8→9、pending 1→0。**全书 10 项已全部实施，无未批准项**。
这 10 项对应 CH13–CH19 与终章里"课文要求玩家能指认、数据侧却只有布尔位/汇总数"的 gate：**课文里有这些要求，判据目前只是布尔位**。任一项落地必须同时给单测（越限/缺失各一例）、一条 `RED-PROBE ... -> code=N` 实测原文，并同步删除对应章降级清单里的该条。

### 10.7 仍缺四样

| 缺项 | 卡在哪一侧 | 需要什么才能动 |
|---|---|---|
| 其余各章练习题库（42 题题库仅 CH01 有） | 内容侧（教学组出题与判分口径） | 每章题面 + 选项/数值判分表；`QuestionBank` 与 `data/questions/*.json` 接口已就绪，CH01 的 42 题已登记进 manifest |
| `static_current` 器件级网表 | 仿真侧（无最小 L1 电流模型） | 器件级网表 + 稳态电流求解；当前 `T2.2-3`、`T2.4-4` 实测为 `status=pending`、`required=true`（旧文误写 `required=false`，已更正），待机挂账不算通过 |
| 原生 GDExtension | 构建侧（`native/` 只有脚手架） | 编译 `.gdextension` 动态库（需 `godot-cpp`，MSVC 未验证）、与 GDScript 跑同向量、接入 `project.godot`；`ifz_selftest` 已在 MinGW g++ 15.1 + CMake 下 1/1 通过 |
| 真实 CI | 基础设施侧（无远程仓库/runner，本地验不了） | `.github/workflows/ci.yml` 已存在但从未在 GitHub Actions 上跑过；需要远程仓库与 runner 才能把"本地 0 失败"升级为"CI 0 失败" |

### 10.8 未提交的其他工作流改动登记（2026-11-05 盘点，不留无主改动）

| 位置 | 谁留下的 | 规模 | 内容状态 | 处置 |
|---|---|---|---|---|
| `docs/simulation/**` | 「硬件与系统仿真」工作流（另一会话；其约定写入范围仅 `docs/simulation/`） | 已跟踪改动 12 文件（+565/−106）：`01_model_layers.md`、`02_determinism.md`、`03_components.md`、`06_performance.md`、`07_api_contract.md`、`08_testing.md`、`09_feasibility_risks.md`、`README.md`、`ref/run_all.py`、`ref/simcore/components.py`、`ref/verify_report.md`、`ref/simcore/__pycache__/components.cpython-313.pyc`；另有未跟踪 7 项：`10_l3_timing.md`、`ref/event_counts.json`、`ref/export_vectors.py`、`ref/measure_events.py`、`ref/tests/test_devices.py`、`ref/tests/__pycache__/test_devices.cpython-313.pyc`、`ref/vectors/` | 不是失效代码，是该工作流的文档与参考实现增量；**本会话没有该工作流的验收口径，未复跑** | 不入库，登记为**未完成/待续**；由该工作流会话复跑 `docs/simulation/ref/run_all.py` 后自行提交（提交信息需说明范围） |
| `docs/simulation/ref/simcore/__pycache__/components.cpython-313.pyc` | 同上 | 二进制 | 误入版本库的生成物（该文件已被跟踪） | 待该工作流决定是否从库中清出；本轮不动 |
| `artifacts/shots/selfcheck.png` | 某会话自检工具输出 | 1 图 | 与本轮无关 | 保留，不入库 |
| `artifacts/probe_{en,framing,period,snap}.gd`(+`.uid`) | 某会话临时取证脚本 | 8 个未跟踪文件 | 临时探针，工程文件不删 | 保留，登记为待续 |

`.gitignore` **不加 `*.uid`**：仓库已跟踪 111 个 `.uid`（Godot 4.4 稳定资源 ID 需入库）；本轮为 14 个**已跟踪**源码/测试补齐 `.uid`（`src/core/chapter_registry.gd`、`src/ui/widgets/section_reader.gd` 与 12 个 `tests/*.gd`），避免每轮冒出来。`artifacts/probe_*.gd.uid` 属未跟踪探针，随探针一并登记。

