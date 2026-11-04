# M4 规格：宏单元接入 + CH02 判定 kind + 题库接口 + 难度三档预留

- 状态：**待批准（2026-11-04 提出；批准前不写实现代码）**
- 日期：2026-11-04
- 作者：技术实现（M3 交付方）
- 上游依据（**只读，不改不提交**）：
  - `docs/design/11-ch02-content-spec.md` §1–§3（CH02 页面结构、20 条 gate、8 种必做判定 kind）
  - `docs/simulation/02_determinism.md` §5（`EXPLAIN/SYNC/MASK` 三档定义与 `pulse_threshold`）
  - `docs/simulation/03_components.md`（D15 译码器 / D21 比较器 / D23 ALU 的结构与三值行为）
  - `docs/simulation/10_l3_timing.md` §6.2（门级交互 50 默认 / 80 绝对上限、`IFZ_E_SCALE`）
  - `docs/curriculum/06-assessment-and-feedback.md`（小测 12 题/章、错因码、提示阶梯、埋点字段）
  - `docs/simulation/ref/vectors/l2_vectors.json`（decoder3 10 / comparator4 17 / alu4 8 行）
  - 已交付事实见 `docs/PROGRESS.md` §2.15、§3 偏差 17

## 1. 目标与范围

| # | 目标 | 交付物 |
|---|---|---|
| M4-1 | **宏单元目录**：decoder3 / comparator4 / alu4 的元数据、只读子视图分页、展开与折叠边界 | `data/sim/macros.json`、`src/sim/sim_macro.gd` |
| M4-2 | **8 种 CH02 trace kind** 扩白名单（schema 不变） | `src/sim/trace_sink.gd`、`src/sim/sim_circuit.gd` 记录点 |
| M4-3 | **题库接入接口**（加载 / 校验 / 评分），题目与数值由教学组提供 | `src/core/question_bank.gd`（接口层） |
| M4-4 | **难度三档预留**（`EXPLAIN/SYNC/MASK`）：名字校验、存档字段、默认值；**不改仿真行为** | `src/core/difficulty.gd`、`src/core/player_state.gd` |
| M4-5 | 上述全部机器可判定 Gate + 回归 | `tests/test_macro.gd`、`tests/test_ch02_kinds.gd`、`tests/test_questions.gd`、`tests/test_difficulty.gd` |

### 1.1 非目标（明确不做）

- **不做** CH02 内容数值：`ch02_levels.json` / `ch02_labs.json` 的标题、金币、题干、选项、期望值**一律不由本规格填写**；
  以 `docs/design/11` 与教学组题库为准，M4 只给接口与校验。
- **不做** 166 门 ALU 的可交互门级网表（超 80 绝对上限）；只做只读子视图。
- **不做** 三档的实际行为差异（`SYNC` 采样吸收、`MASK` 脉冲过滤属 M5）；M4 只保留字段与校验。
- **不做** 42 题的内容判分（`power_calc` 等运算实现随 CH02 数据落地；M4 只做 schema 与评分入口）。
  注：42 是第一章练习（`docs/curriculum/03`），与第二章内容互不替代。
- **不碰** `project.godot`、`src/ui/**`（UI 重构会话独占）；任何需要 UI 才能验证的点记入 §8「待 UI 会话接回」。
- **不碰** `docs/design/`、`docs/simulation/`、`docs/curriculum/`。

## 2. 继承现状（实现前必须认账）

1. `SimModule` 已有 7 种模块（HA / FA / ripple / mux2 / mux4 / **decoder3 11 门** / **comparator4 33 门**），
   `declared_settle` 由延迟表推导（decoder3=4、comparator4=11），`tests/test_l2_vectors.gd` 已逐行 132/132。
2. 门级交互上限：`SimDelays.gdscript_gate_limit()=50`、`gdscript_gate_hard_cap()=80`，超 80 返回 `IFZ_E_SCALE`；
   数据单一来源 `data/sim/delays.json`。
3. `TraceSink` 固定 5 字段 `{tick, layer, kind, subject, payload}`，`KINDS` 现有 7 项；
   扩展方式**只允许**加白名单常量，不改字段与 `digest()` 算法（`tests/test_trace.gd` 的 1 vs 4 tick/帧摘要一致必须保持）。
4. `ChapterRuntime` 只从 `data/chapters/ch01_levels.json` 读一份章节；`DataDB` 只注册 `data/manifest.json` 里的 8 个文件。
5. `PlayerState` 存档信封 v3，未知字段保留；没有难度字段，也没有题库字段。
6. ALU 参考实现（`components.py::ALU`）为 166 门结构级：
   控制 5 + 补码/加法 40 + 逻辑 16 + 选择 96 + 标志 9 = 166（见 §3.1 分解）。

## 3. 设计

### 3.1 宏单元（`src/sim/sim_macro.gd`，`class_name SimMacro`）

**定位**：宏单元是"对外 1 个节点、对内可只在只读视图里看结构"的器件。它不是新的仿真原语：
decoder3 / comparator4 的仿真仍走 `SimModule`；alu4 在 M4 **不提供门级网表**，只提供元数据与只读视图。

**数据（单一来源）**：`data/sim/macros.json`，`format: "ifz-macros/1"`：

```json
{
  "version": 1,
  "format": "ifz-macros/1",
  "source": "docs/simulation/03_components.md; docs/simulation/ref/simcore/components.py",
  "cells": {
    "decoder3":    {"module_kind": "decoder3",    "gate_count": 11,  "expandable": true},
    "comparator4": {"module_kind": "comparator4", "gate_count": 33,  "expandable": true},
    "alu4":        {"module_kind": "",            "gate_count": 166, "expandable": false}
  }
}
```

`t_settle` 不写死在 JSON：decoder3/comparator4 取 `SimModule.declared_settle()`；alu4 由实现时按 §3.1.2
结构推导并在测试断言，**规格不预填数值**（避免编造）。

**接口（M4 只实现这 6 个）**：

```gdscript
class_name SimMacro

static func cells() -> Dictionary            # 全部元数据（深拷贝）
static func meta(kind: String) -> Dictionary # 未知 kind 返回 {}
static func pages(kind: String) -> Array     # 只读子视图分页；每页 gates ≤ gdscript_gate_limit()
static func expand(kind: String, c: SimCircuit, prefix: String) -> Dictionary
    # 仅 expandable=true 且 gate_count ≤ hard_cap；否则 {"ok": false, "error": "IFZ_E_SCALE"}
static func expand_page(kind: String, page_id: String, c: SimCircuit, prefix: String) -> Dictionary
    # 只读视图：可写入临时 SimCircuit 供绘制/测试；不进入玩家可编辑门表
static func fold(kind: String, prefix: String) -> Dictionary
    # 折叠边界：返回 {"ok": true, "ports": {...}, "digest": ...}，调用方丢弃页内线网
```

**展开 / 折叠边界（硬规则）**：

| 情形 | 规则 |
|---|---|
| decoder3（11 门） | 可整块展开为门级视图；展开态按 **11 门**计入预算 |
| comparator4（33 门） | 可整块展开；展开态按 **33 门**计入预算 |
| alu4（166 门） | `expandable=false`：`expand()` 必返回 `IFZ_E_SCALE`；只允许 `expand_page()` 的**只读**视图 |
| 折叠态 | 任何宏单元按 **1 个节点**计入连线与画布，不按内部门数 |
| 展开 ↔ 折叠切换 | 重新走一次预算检查：>50 提示「该电路需要结构级表示」；>80 返回 `IFZ_E_SCALE`；**禁止只画一部分门** |
| 页与页之间 | 只显示端口与级间连线；跨页不重绘内部门（避免"看起来像 50 门、其实 166 门"） |

**alu4 只读子视图（按参考结构分页，每页 ≤50；7 页合计 166）**：

| page_id | 标题 | 组成（参考结构） | 门数 |
|---|---|---|---|
| `alu.ctrl` | 操作码译码 | `nop0/nop1/nop2`、`sub`、`isadd` | 5 |
| `alu.adder` | 补码选择 + 行波加 | `b_neg`×4、`b_sel` mux×4、4 位 FA×4 | 40 |
| `alu.flags` | 标志位 | `flagz`、`v.na/nb/ns/t1/t2/or`、`flagv`、`carry` | 9 |
| `alu.logic` | 逻辑组 | `and/or/xor/not` ×4 位 | 16 |
| `alu.sel1` | 选择级 1（op0） | 移位 mux×4、`gb0`×4、`gb1`×4 | 48 |
| `alu.sel2` | 选择级 2（op1） | `ga`×4、`gb`×4 | 32 |
| `alu.sel3` | 选择级 3（op2） | `y` mux×4 | 16 |

三块语义分组（算术 = `ctrl`+`adder`+`flags`，逻辑 = `logic`，选择 = `sel1`+`sel2`+`sel3`）与分页同时存在：
**玩家看到的是页，不是 166 门整图**。移位是重接线、无门（参考实现明示），不得为它伪造延迟或门。

### 3.2 8 种 CH02 trace kind（`src/sim/trace_sink.gd`）

**命名规则（零发明）**：trace kind = `docs/design/11` §3 的判定 kind 全大写；`build_area` 是可选语法糖，不计入 8 种。

| # | 判定 kind（design 11） | trace kind | payload 固定键（类型） |
|---|---|---|---|
| 1 | `mosfet_region` | `MOSFET_REGION` | `region`(str), `vgs`(float), `vds`(float), `id_ua`(float) |
| 2 | `x_propagation` | `X_PROPAGATION` | `expect`(str), `got`(str) |
| 3 | `static_current` | `STATIC_CURRENT` | `ua`(float), `states`(int) |
| 4 | `rail_margin` | `RAIL_MARGIN` | `v_high`(float), `v_low`(float) |
| 5 | `equiv` | `EQUIV` | `ref`(str), `vectors`(int), `mismatch`(int) |
| 6 | `area_max` | `AREA_MAX` | `gates`(int), `max`(int) |
| 7 | `power_calc` | `POWER_CALC` | `mw`(float), `expect_mw`(float), `tol`(float) |
| 8 | `power_ratio` | `POWER_RATIO` | `ratio`(float), `expect_ratio`(float), `tol`(float) |

约束：
- **不改 5 字段 schema**、不改 `digest()`；`KINDS` 由 7 扩到 15，`LAYERS` 不变。
- 记录点为只读观测：`SimCircuit` 与 `SimMacro` 只 `record()`，不得因 trace 改变求值顺序或事件数。
- 未知 kind / 未知 payload 键仍按现有规则拒绝（`rejected++`），不静默丢弃；payload 缺固定键按拒绝处理。
- 与 `docs/design/11` 的数值（`vth`、`ron`、`max_ua`、`expect_mw` 等）**全部来自数据文件**，M4 不写入任何数字。

### 3.3 题库接入接口（`src/core/question_bank.gd`，`class_name QuestionBank`）

**口径**：`42 道` = 第一章练习题库（`docs/curriculum/03-exercises-multi-solution.md` §2：理解 11 / 计算 14 / 搭建 6 / 调试 5 / 开放 6）；
章节小测 12 题/章（`docs/curriculum/06` §2）是**另一份 bank**，共用本接口但各自计数。M4 **不落任何题目**。

**数据**：`data/questions/<chapter>_<bank>.json`（`bank ∈ {exercises, quiz}`），`format: "ifz-questions/1"`：

```json
{
  "version": 1,
  "format": "ifz-questions/1",
  "chapter": "ch01",
  "bank": "exercises",
  "items": [
    {"id": "1.1-1", "section": "1.1", "task_ids": ["T-1.1"],
     "type": "understanding|compute|build|debug|open|memory",
     "stem": "…",
     "solutions": [{"label": "解法 A", "approach": "…"}],
     "rubric": [{"dim": "观点正确", "weight": 40}],
     "common_errors": ["…"], "hints": []}
  ]
}
```

- `solutions` 至少 2 条（`docs/curriculum/03` §0.3 多解同分规则）；`build` 题的 `solutions` 是"验收行为"而非拓扑。
- 题量与配比**不由本规格写死**：加载器对 `items.size()` 不做断言；42/12 等数字由交付文件与教学组核对。
- 接口：

```gdscript
class_name QuestionBank

static func from_doc(doc: Dictionary) -> QuestionBank
func validate() -> Array                 # 缺 id/stem/type；type 非法；solutions < 2；rubric 权重和 ≠ 100；
                                         # build 题缺 rubric 正确性维；id 重复
func item(id: String) -> Dictionary
func score(id: String, response: Dictionary) -> Dictionary
    # {"ok": bool, "score": int, "max": 100, "detail": str, "error_code": str}
    # 评分只做结构性校验与确定性比较；主观题返回人工 rubric 输入，不自动编分
static func error_codes() -> Array        # C1–C9（docs/curriculum/06 §3），只做常量与校验
```

- `response` 统一形状：`{"choice": int}` / `{"text": str}` / `{"graph": CircuitGraph}` / `{"value": float}`；
  搭建题必须走既有黑盒验收（`tests`/`LabChecks`），**不比对拓扑**；浮点比较只用题目自带 `tol`。
- `DataDB` 只在 `data/manifest.json` 登记该文件后才加载；M4 **不改** `manifest.json`（题目未交付）。
- 埋点字段（`item_start/item_submit/hint_open` 等）留给 UI 会话，M4 不做。

### 3.4 难度三档预留（`src/core/difficulty.gd`，`class_name Difficulty`）

```gdscript
const EXPLAIN := "EXPLAIN"
const SYNC := "SYNC"
const MASK := "MASK"
static func names() -> Array          # [EXPLAIN, SYNC, MASK]
static func normalize(v: String) -> String   # 合法值原样；其余回 EXPLAIN
static func is_valid(v: String) -> bool
```

- `PlayerState` 新增 `difficulty: String = Difficulty.EXPLAIN`，写入存档 `settings.difficulty`；
  读档缺失或非法 → `EXPLAIN`，**不升存档版本**（未知字段保留机制已够用）。
- M4 **不改任何仿真行为**：`SimCircuit` 不引入 `pulse_threshold`、不做边沿采样吸收；
  这些在 M5 实现 `SYNC/MASK` 语义时再接入（`docs/simulation/02` §5 的阈值来自数据，不写死）。
- UI 开关属 UI 会话；M4 只保证"三档名字 + 存档字段 + 默认值"存在且可测。

### 3.5 文件清单

| 路径 | 动作 |
|---|---|
| `data/sim/macros.json` | 新增（3 个宏单元元数据） |
| `src/sim/sim_macro.gd` | 新增 |
| `src/sim/trace_sink.gd` | 修改（`KINDS` 7→15） |
| `src/sim/sim_circuit.gd` | 修改（仅新增 `record` 调用点，不改求值） |
| `src/core/question_bank.gd` | 新增 |
| `src/core/difficulty.gd` | 新增 |
| `src/core/player_state.gd` | 修改（难度字段 + 存档读写） |
| `tests/test_macro.gd` / `test_ch02_kinds.gd` / `test_questions.gd` / `test_difficulty.gd` | 新增 |
| `tests/run_tests.gd` | 修改（注册 4 个套件） |
| `docs/PROGRESS.md` | 修改（§2.16+、偏差 21+） |

**不改**：`project.godot`、`src/ui/**`、`data/chapters/**`、`data/labs/**`、只读文档三目录。

## 4. 可机器判定 Gate

| 关 | 判定方式（命令可复现） |
|---|---|
| M4-G1 | `tests/test_macro.gd`：`cells()` 含 decoder3/comparator4/alu4；`gate_count` = 11/33/166；每页 `gates ≤ gdscript_gate_limit()`；alu4 七页合计 **166** |
| M4-G2 | `expand("alu4")` → `IFZ_E_SCALE`；`expand("decoder3"/"comparator4")` 成功且门数 == 11/33；`fold()` 返回端口摘要，展开→折叠→再展开 `state_digest` 相同 |
| M4-G3 | `tests/test_ch02_kinds.gd`：8 个 kind 全部可 `record()`；`KINDS.size()==15`；仍然只有 5 字段；未知 kind 被拒；含 CH02 kind 的事件流在 **1 tick/帧 与 4 tick/帧** 下 `digest()` 相同 |
| M4-G4 | 同一套件：`docs/design/11` §3 的 8 个判定 kind ↔ trace kind 映射表逐项断言（8/8，`build_area` 显式排除） |
| M4-G5 | `tests/test_questions.gd`：合法 fixture 载入/评分确定性；缺字段、非法 `type`、`build` 题无 `solutions` 各报错；未知题 id 返回 `ok=false`；不改 `manifest.json` |
| M4-G6 | `tests/test_difficulty.gd`：三档合法、未知值归一为 `EXPLAIN`、默认 `EXPLAIN`、存档往返保留、缺失字段读档回落 |
| M4-G7 | L2 向量回归：`tests/test_l2_vectors.gd` 132/132（`alu4` 8 行仍不比对，偏差 17） |
| M4-G8 | 全量回归 `RESULT: N checks, 0 failures`（N 由实现时汇总，不得低于 1621） |
| M4-G9 | `git diff --stat -- project.godot src/ui/ data/chapters/ data/labs/ docs/design/ docs/simulation/ docs/curriculum/` 为空（UI 会话的改动不算本会话） |
| M4-G10 | 预算同源：所有 `>50` 提示与 `>80` 错误均引用 `SimDelays`，测试断言无硬编码数字 |

## 5. 性能与门数预算

- 宏单元不改变门级仿真上限：decoder3 11、comparator4 33 均在 50 内；alu4 166 超 80 → 只读分页，构建期拒绝整块展开。
- 只读视图不参与每帧求值：`expand_page()` 产生的临时电路只在打开视图时构建一次，关闭即释放；
  不得把 166 门塞进 `SimCircuit` 的常驻门表。
- L3 基准（50/80/100 三档 p95）沿用 `data/sim/delays.json` 的 `l3.bench`；M4 不重跑、不改阈值。

## 6. 确定性

- 宏单元展开顺序固定（按页序与参考结构顺序），同一输入 → 同一 `state_digest`。
- 题库评分不得引入时间、随机或字典迭代序；浮点比较只用题目自带 `tol`。
- 难度字段只影响**记录**，M4 不影响任何事件序列；`test_ch02_kinds` 的 1 vs 4 tick/帧摘要一致是硬门槛。

## 7. 与参考向量 / 参考实现的比对

- decoder3 / comparator4 继续以 `l2_vectors.json` 逐行比对（132/132），M4 不新增向量。
- alu4 的 8 行向量**保持不比对**：M4 不实现门级 ALU；等 M5 若做结构级 ALU，再按 `alu4` 8 行补比对。
- 宏单元门数与页面分解以 `components.py` 的 `ALU._build()` 为准；实现时逐页统计并与 166 对账。

## 8. 偏差与风险（实现前预判）

| # | 项 | 处理 |
|---|---|---|
| R1 | 参考文档称 L2 向量 143 行，实测 JSON 140 行 | 已记 `PROGRESS.md` 偏差 17（"143"为笔误），本规格沿用 140/132 口径 |
| R2 | CH02 数值/题目不由本规格提供 | 只定接口；数据未到前测试只用 fixture 与结构断言，不写任何 `docs/design/11` 数值 |
| R3 | 42 道题库的实际条数与配比 | 已核对口径：42 = 第一章**练习**（`docs/curriculum/03` §2，理解 11/计算 14/搭建 6/调试 5/开放 6）；12 = 每章**小测**（`06` §2）；168 = 14 章小测规划。三者是不同 bank，加载器不假设条数，M4 不写死 |
| R4 | 8 种 trace kind 的命名 | 采用"判定 kind 全大写"的机械映射（§3.2），避免自造词；如需改名由负责人一次性裁决 |
| R5 | UI 才能验证的点（视图绘制、难度开关、题库页面） | **待 UI 会话接回**：M4 只交付只读模型与接口，不碰 `src/ui/` |
| R6 | alu4 的 `t_settle` | 规格不预填；实现时按 §3.1 结构推导并在测试中锁定，若与仿真组实测不符记偏差 |
| R7 | 三档行为差异 | M4 只预留字段；`SYNC/MASK` 的真实语义在 M5 接入，避免"开关存在但不生效"被误读 |
| R8 | 超限错误码命名 | 工程内统一 `IFZ_E_SCALE`（M3/M4 共用）；`docs/simulation/10` §6.4 写作 `E_L1_SCALE`，语义相同，**不改只读文档**，在偏差表注明 |

## 9. 验收命令（批准后照此执行）

```powershell
# 1) 全量测试（含新增 4 套件）
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1

# 2) 宏单元与预算（只读日志，不另起引擎）
Select-String -Path artifacts\logs\tests.log -Pattern "M4-G"

# 3) 向量回归（132/132，alu4 不比对）
Select-String -Path artifacts\logs\tests.log -Pattern "参考向量"

# 4) 边界：不碰 UI 与只读文档
git diff --stat -- project.godot src/ui/ data/chapters/ data/labs/ docs/design/ docs/simulation/ docs/curriculum/

# 5) 导入/启动冒烟（不依赖 UI 会话）
powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1
```

## 10. 交付边界

- 只提交：`src/sim/`、`src/core/`、`tests/`、`data/sim/`、`specs/m4/`、`docs/PROGRESS.md`。
- 不提交：`project.godot`、`src/ui/**`、`docs/ui/**`、`mockups/**`、`artifacts/**`、只读文档三目录。
- 每子系统一次提交；`git index.lock` 出现时重试，不删锁。
- 规格批准后才进入 `tasks.md` 的 T0→T5。
