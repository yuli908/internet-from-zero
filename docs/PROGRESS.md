# 进度与偏差（PROGRESS）

- 里程碑：**M1 已验收；M2 已交付（A/B/C/D 全部完成）；M3 规格已批准（2026-11-04，含性能现实约束追加条款，见 `specs/m3/`）**
- 基线日期：2026-11-04
- 口径：只有**跑过、有证据**的项才标"已完成"；没验证的一律标"需人工"或"未完成"，不写成通过。
- 证据目录：`artifacts/shots/`（11 张截图）、`artifacts/logs/`（导入/测试/冒烟/基准日志）

## 1. 一句话结论

M1 已经**可启动、可操作、可存档、可自动测试**：6 节实验 + 24 条 gate + 多解黑盒 + L0a/L0b/L1 仿真；
`RESULT: 1410 checks, 0 failures`。

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

### 2.1 自动测试构成（13 套件，1410 项）

`bit_math` / `logic_gates` / `circuit` / `economy` / `knowledge` / `chapter` / `tutorial` / `save` / `data` / `sim` / `l2` / `black_box` / `lab_checks`

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
  按接口对齐结论须走宏单元（偏差 17）。
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

## 3. 偏差表（原规格 / 实际实现 / 原因）

| # | 原规格 | 实际实现 | 原因 |
|---|---|---|---|
| 1 | L0a 模拟电平：模拟电路求解（RC 固定子步长） | 电压判读带 + 阈值判定（`src/core/voltage_model.gd`、`ui/widgets/level_gauge.gd`），不做连续时间电路求解 | M1 只要求 L0–L1 接口与确定性 tick；连续求解器属后续里程碑 |
| 2 | 门级仿真宿主允许 C++/Rust GDExtension | 纯 GDScript（`src/sim/`）；2026-11-04 实测后修正口径：GDScript 在 **50 门/50 DFF** 内守 5 ms，200 门 p95 17.8 ms；`native/` 仅有脚手架、未编译 | 先保证可运行与可测；实测证明 200 门必须原生（§2.2、偏差 14） |
| 3 | 性能预算：5 ms/帧、4 tick/帧、≤200 门/200 DFF | 预算与 tick 已实测（`tests/bench_sim.gd` + `scripts/bench.ps1`）：50/50 规模 p95 3.32–4.03 ms 达标；细化档 70 门 4.69 ms 仍达标、**80 门 5.39 ms 起超预算**；"降速不丢事件"仍由 `SimEngine` 的 tick 推进与单 tick 上限保证 | 原 200 门来自 `docs/simulation/06` 估算、从未验证；实测后以数据为准 |
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
| 14 | GDScript 门数上限 | 设计写 200 门/200 DFF；实测安全上限取 **50 门/50 DFF**（p95 3.32–4.03 ms）。细化档 70 门 4.69 ms 仍达标、80 门 5.39 ms 超限；因复跑存在抖动（早先一轮 60 门曾 5.03 ms），限值保守定为 50。`data/sim/delays.json` 的 `gdscript_gates/gdscript_dff/require_gdextension_above` 已改为 50，`tests/test_data.gd` 同步断言；ADR 0002 §2.1 判据表同步 | 200 从未实测；按 ADR 0002 §5「实测 <200 即超预算则下调限值并记偏差」执行，避免文档宣称能跑 200 而实际掉帧 |
| 15 | 仿真文档估算 **200 门**/200 DFF（`docs/simulation/06`） | 实测三档：优化前 100 门 p95 7.6 ms、200 门 17.6 ms；**实现层优化后 100 门 3 次 p95 2.91–3.08 ms**（400 帧）。交互限值按仿真组硬约束取 **50 默认 / 80 绝对**（超 80 → `IFZ_E_SCALE`），编辑器同源卡死并由 `test_data`/`test_circuit` 断言 | 200 是未验证的估算；GDScript 解释执行、无 JIT，优化后 100 档仍有约 1.6× 余量，但**交互上限不再按性能余量抬高**，以仿真组 50/80 硬约束为准。**`docs/simulation/` 不改**，由仿真组据本行修正 |
| 16 | 计数器最小时钟周期：仿真组 L3 写 `period ≥ 6W+9`（4 位 33、8 位 57，8 位取 70）；本工程上一轮结构推导 `6W+20`（4 位 44） | **以真实 `SimCircuit` 实测裁决：4 位 14、8 位 26**（`SimSequential.measure_counter_period`；判据 = 偶数周期 + 无 `METASTABLE` + 连续两个完整周期逐沿值正确，4 位扫 34 沿、8 位扫 514 沿）。写回 `data/sim/delays.json` 的 `l3.counter4/8_min_period`，`test_l3`/`test_data` 断言 | 我们的计数器是紧凑自增链（`2W-2` 组合门 + `W` DFF，8 位仅 14 门），不是参考实现的 104 门展开；`6W+9`/`6W+20` 都是按展开结构估的。**`docs/simulation/` 不改**，由仿真组据本行修正 |
| 17 | 仿真组 L2 参考向量 143 行（HA 9 / FA 27 / ripple8 37 / mux2 27 / mux4 5 / decoder3 10 / comparator4 17 / alu4 8） | 已比对 **105/105**（HA/FA/ripple8/mux2/mux4 逐行全等）；`decoder3` 10、`comparator4` 17、`alu4` 8 **未比对**（`SimModule` 未提供这三个器件，且 ALU 166 门超 80 硬上限，按接口对齐须走宏单元） | M3 只交付 L3 时序器件与已有 L2 件；补 decoder3/comparator4 需新增模块与门数预算，ALU 已判定必须宏单元。留待 M4 或单独立项 |

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
| L3 DFF 与亚稳态 / L4 CPU / L5 总线 / L6 网络 | **未完成**（M3 规格已写，待批准） | `SimCircuit.add_dff` 只有 clk→Q=2 tick 的上升沿采样，**无 setup/hold/RESET，也无任何测试**；`delays.json` 的 `dff` 只有常量。见 `specs/m3/spec.md` |
| 统一 `TraceSink`（`(tick, layer, kind, subject, payload)`） | **未完成**（M3 规格已写，待批准） | 现为 `SimCircuit.history` + `glitches` 两数组；`SimEngine.trace` 只被测试读，字段不统一 |
| 第一章每节物品奖励入库 | **未完成**（机制未实现；`ch01_levels.json` 的 6 节均未定义物品奖励，等策划奖励表定稿） | M3 规格含通用 `grants.items` 机制与测试，数据侧不改 |
| 冒险三档（`EXPLAIN/SYNC/MASK`）开关 | **未完成** | 当前固定为 EXPLAIN 行为 |
| 错误码编号（`docs/simulation/07` §5 的 0–18） | **未完成** | 现为字符串错误 |
| 42 道练习题库与逐题评分表 | **未完成** | 只有第一章 24 条 gate + 多解黑盒 |
| 6 节脚本化走查（UI 真实链路 → 验收 → 知识树 → 存档 → 重启读档） | **已完成（2026-11-04）** | 见 §2.5：`--walkthrough` 72 项 0 失败，`--verify-walkthrough` 36 项一致；物品奖励本章未定义，仅断言不变 |
| 6 节真人鼠标走查（操作 → 验收 → 知识树 completed → 存档 → 重启续玩） | **需人工** | 脚本走查绕过鼠标点击/连线动作，真人交互仍需按 `docs/design/08` 走一遍 |
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

## 6. 下一步（M2 已全部交付；M3 规格待批准）

M2 全部完成：A 基准（§2.2）、B L2（§2.3）、C 迁移（§2.4）、D 走查（§2.5）。

M3 规格已写、**未实现**，见 `specs/m3/spec.md` 与 `specs/m3/tasks.md`。建议范围：

1. **L3 时序层**：DFF（setup/hold/RESET/亚稳态即 X）、寄存器、计数器、移位寄存器；`t_settle` 由结构推导 + 实测。
2. **TraceSink 统一**：`(tick, layer, kind, subject, payload)` 固定 schema，先映射 `history/glitches`，再做回放。
3. **物品奖励入库**：通用 `grants.items` 机制 + 幂等/存档测试；**数据侧等策划奖励表定稿**，本轮不改 `ch01_levels.json`。

未纳入 M3（另立项）：原生 GDExtension（基准已证明 200 门必须原生）、冒险三档、错误码编号、42 道题库、CH02 内容（`docs/design/11` 已出规格，依赖 8 种新判定 kind）。

## 7. 验证命令（当前基线的复现方式）

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1     # 期望 RESULT: 1410 checks, 0 failures
powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1     # 导入 + 测试 + GUI 冒烟
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1         # 性能基准（p50/p95/p99/max）
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
