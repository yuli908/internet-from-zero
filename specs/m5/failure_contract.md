# M5 · 结构化失败回传契约（`specs/m5/failure_contract.md`）

> 面向 UI 会话：gate 失败不再只给"未通过"字符串，而是给机器可读的结构化结果。
> 生效版本：M5 基础设施（2026-11-04）。本文件是唯一口径，UI 照此渲染诊断文本。
> 相关代码：`src/core/gate_result.gd`、`src/core/gate_attempts.gd`、`src/core/gate_report.gd`、
> `src/core/lab_checks.gd`、`src/core/black_box.gd`、`src/core/voltage_model.gd`。

## 1. 统一结果形状

`GateReport.cases[]` 每条用例（旧字段 `id/title/ok/detail/required` 全部保留）：

| 字段 | 类型 | 含义 |
|---|---|---|
| `code` | int | 稳定枚举（见 §2）；成功恒为 `0 (OK)` |
| `code_name` | String | `code` 的稳定名字，UI 不要用它做分支，只用于日志 |
| `gate_id` | String | 用例 id，等于 `id`（`T1.1-1` … `T1.6-4`） |
| `input` | Variant | 具体输入：哪一行/哪个值/哪条线，见 §4 |
| `expected` | Variant | 期望值；`null` 表示"无该维度" |
| `actual` | Variant | 实测值；`null` 表示"没测到" |
| `error_tags` | Array[String] | 六类错因标签 `K/S/C/P/M/R`，按 §3 映射 |
| `attempt` | int | 同一 gate 连续失败次数（1 起；通过后归 0） |

取第一条失败（提示阶梯用）：

```gdscript
rep.first_failure()   # 结构化 dict；全部通过时返回 {}
rep.failure_codes()   # Array[int]，失败用例的 code 列表
rep.to_dict()         # {ran_at, passed, cases:[...]}，可直接进存档/日志
```

兼容入口 `GateReport.add(id, title, ok, detail, required)` 仍可用；它会以
`code=E_GENERIC / error_tags=["R"]` 记录失败（兜底，不丢用例）。

## 2. code 枚举（`GateResult`，int 常量）

| code | 常量名 | 默认描述 | 来源 gate 类型 |
|---|---|---|---|
| 0 | `OK` | 通过 | 全部 |
| 1 | `E_MISSING_GRAPH` | 缺少电路 | gate `basic`/`xor`/`second`、half_adder `truth` |
| 2 | `E_BUILD` | 电路无法构建 | 黑盒验收、延迟测量失败 |
| 3 | `E_UNCONNECTED` | 有输入未连接 | `BlackBox.check_outputs` 前置检查 |
| 4 | `E_UNKNOWN_KIND` | 未知判定类型 | 任何 lab 的 `kind` 不在白名单 |
| 5 | `E_UNKNOWN_TARGET` | 未知目标函数 | gate `basic`/`xor`/`second` 的目标不是 and/or/not/xor |
| 6 | `E_TRUTH_ROW` | 真值表某行不正确 | gate `basic`/`xor`/`second`、half_adder `truth`、random_x 外的行比对 |
| 7 | `E_TABLE_CELL` | 填表某格不正确 | boolean `table` / `demorgan` |
| 8 | `E_DELAY_EXCEED` | 稳定时间超出上限 | gate `xor`、half_adder `delay` |
| 9 | `E_DELAY_MISMATCH` | 稳定时间与期望不符 | signal `delay` |
| 10 | `E_OUTPUT_MISMATCH` | 输出与期望不符 | level `voltage_judge` |
| 11 | `E_STRUCTURE_SAME` | 两种结构相同（要求不同结构） | gate `second` |
| 12 | `E_ENCAPSULATION` | 尚未封装 | gate `encapsulation`、half_adder `encapsulation` |
| 13 | `E_COVERAGE` | 覆盖不完整 | binary `coverage` |
| 14 | `E_QUIZ` | 选择题答案错误 | binary / signal 的 `quiz` |
| 15 | `E_TARGET_UNREACHED` | 目标值尚未达成 | binary `target` |
| 16 | `E_GLITCH` | 毛刺仍存在或未达宽度 | signal `glitch` / `fix` |
| 17 | `E_X_ROW` | 含 X 的用例失败 | half_adder `random_x`、CH02 `x_propagation` |
| 18 | `E_REGION` | MOS 工作区判错 | CH02 `mosfet_region` |
| 19 | `E_STATIC_CURRENT` | 静态电流超出上限 | CH02 `static_current`（**唯一 pending**：`T2.2-3`、`T2.4-4`；原因见 §9.5.2） |
| 20 | `E_RAIL_MARGIN` | 输出电平未达轨到轨 | CH02 `rail_margin`（**已实现** `_judge_rail`，不再 pending；口径见 §9.5.1） |
| 21 | `E_EQUIV` | 与参考函数不等价 | CH02 `equiv` |
| 22 | `E_AREA` | 门数超出上限 | CH02 `area_max` / `target` / `build_area` |
| 23 | `E_POWER_CALC` | 功耗计算不符 | CH02 `power_calc` |
| 24 | `E_POWER_RATIO` | 功耗比不符 | CH02 `power_ratio` |
| 25 | `E_PENDING` | 仿真层暂不支持（待接入） | 当前仅 CH02 `static_current`（`T2.2-3`、`T2.4-4`）；`required=false`，不算通过 |
| 99 | `E_GENERIC` | 未分类失败（兜底） | 未知 code、`add()` 兼容入口 |

规则：
- `code` 取 `GateResult.normalize()` 后的值；未知 int 一律归一为 `99 (E_GENERIC)`，不抛错、不静默丢弃。
- **不要用 `code_name` 字符串做业务分支**；用 int 常量或 `GateResult.is_ok()`。
- 新增 code 只增不改：已发布的 int 值不复用。

## 3. error_tags 六类

| 标签 | 口径 | 当前映射的 code |
|---|---|---|
| `K` 概念/知识 | 公式、真值表、选择题 | 6, 7, 14, 17 |
| `S` 结构/连线 | 缺电路、悬空线、构建失败、结构重复 | 1, 2, 3, 11 |
| `C` 计算/取值 | 单点取值/输出不符、目标未达成 | 6, 7, 10, 15 |
| `P` 步骤/流程 | 未知类型/目标、未封装、覆盖不全 | 4, 5, 12, 13 |
| `M` 时序/亚稳 | 延迟、毛刺、X 传播 | 8, 9, 16, 17 |
| `R` 兜底 | 未分类 | 99 |

> **偏差 24（重要）**：教学组诊断表 `docs/curriculum/05-failure-diagnostics.md` **尚未入库**（仓库当前只有
> `05-onboarding-guidance.md`、`06-assessment-and-feedback.md`）。本文件与 `GateResult.TAG_MAP` 的映射
> 是按六类语义的**机器初值**，教学组交付后**只改 `TAG_MAP` 映射表**，不改 code、字段或调用方。

## 4. 每类 gate 的精度（能回传到什么粒度）

| gate / kind | 成功 | 失败 code | 回传精度（`input` / `expected` / `actual`） |
|---|---|---|---|
| level `voltage_judge` | `OK` | 10 | **精确到条**：`input={v}`，`expected` 期望判读（"0"/"1"/"X"），`actual` 实判 |
| binary `coverage` | `OK` | 13 | **精确到值**：`input={"missing":[未覆盖值…]}`，`expected={"missing":[]}` |
| binary `target` | `OK` | 15 | **精确到目标**：`input={"target":"t137"}`，`expected` 目标数值，`actual` 达成布尔 |
| binary / signal `quiz` | `OK` | 14 | **精确到选项**：`input={"chosen":int}`，`expected`/`actual` 正确/所选 |
| boolean `table` | `OK` | 7 | **精确到格**：`input={"gate":"and","row":2}`，`expected` 该格值，`actual` 填错值；缺行时 `actual="(缺)"` |
| boolean `demorgan` | `OK` | 7 | **精确到格**：同上，`gate="demorgan"`，`expected` 左式值，`actual` 填错值 |
| gate `basic` | `OK` | 1/2/3/5/6 | **精确到首个失败任务的行**：`input={a,b}`，`expected/actual` 该行输出字典；缺图/未知目标单独成 code |
| gate `xor` | `OK` | 6/8 | 行错→**精确到行**；延迟超限→`input={inputs}`，`expected` 上限 tick，`actual` 实测 tick |
| gate `encapsulation` | `OK` | 12 | **只到 gate 级**：`expected=true`，`actual` 封装标记（无更细信息可给） |
| gate `second` | `OK` | 1/6/11 | 缺第二结构→code 1（`input={"graph":"t_xor_2"}`）；同结构→code 11；行为错→**精确到行** |
| signal `delay` | `OK` | 2/9 | **精确到 tick**：`expected` 期望值，`actual` 实测值（差几个 tick 直接可见） |
| signal `glitch` | `OK` | 16 | **精确到 tick**：`expected` 最小宽度，`actual` 实测宽度 |
| signal `fix` | `OK` | 16 | **只到 gate 级**：`expected=true`，`actual` 是否仍见毛刺 |
| half_adder `truth` | `OK` | 1/2/3/6 | **精确到行**：`input={a,b}`，`expected/actual` 为 `{sum,carry}` |
| half_adder `delay` | `OK` | 2/8 | **精确到 tick**：`expected` 上限，`actual` 实测 |
| half_adder `encapsulation` | `OK` | 12 | **只到 gate 级**（同上） |
| half_adder `random_x` | `OK` | 3/17 | **精确到首组输入**：`input={a,b}`，`expected/actual` 为 `{sum,carry}`；悬空线→code 3 |
| 任意 `kind` 未知 | — | 4 | `input={"kind":原始值}`，`expected="已知 gate kind"` |

**做不到精确的**：`encapsulation`、`fix`、`second` 的"结构相同"只能给到 gate 级或结构标签级；
这三处 UI 只应展示 code 对应文本，不要假装有行列级证据。

## 5. attempt 计数

```gdscript
var tracker := GateAttemptTracker.new()
...# 每次判定该节时把同一个 tracker 传入 LabChecks.* 的最后一个参数
```

- 失败 `+1` 并从 1 开始；通过立即清零。
- 键是 `gate_id`（同一节内跨重跑连续）；空 id 不计数。
- `attempts(id)` 查询，`reset(id)` 单清，`reset()` 全清。
- 只在内存中，不写存档：每节实验重新开始就新建 tracker。
- 提示阶梯：`attempt==1` 给第 1 级提示，`==2` 第 2 级，`>=3` 第 3 级（阈值由教学组口径决定，工程只保证计数可用）。

## 6. UI 渲染建议

- 诊断正文 = `GateResult.describe(code)` + 具体证据（`input` / `expected` / `actual`）；
  例：`V=0.85 V 判为 X，期望 0（T1.1-4）`。
- 有行列/先后的 code（6/7/13/17）优先展示"哪一行/哪一格/哪些值"；延迟类展示"差 N tick"。
- `actual == null` 表示"没测到"（通常是构建失败），不要显示成 0 或空。
- 标签用于筛选/配色，不要直接给玩家看 `K/S/C/P/M/R` 字母。
- 未知 code（未来新增但 UI 未适配）按 `E_GENERIC` 文本显示即可，不要崩溃。

## 7. 验证

- `tests/test_gate_result.gd`（本契约的机器锁）：每种 gate 类型的成功/失败、`error_tags` 映射、
- `attempt` 递增/重置/往返、未知 code 兜底、`unconnected` 精确回传。
- 全量回归：测试基线以 `docs/PROGRESS.md` 的当前记录为准（本契约不硬编码具体数量）；要求 0 failures，且原有项不降。

## 8. 变更记录

| 日期 | 变更 |
|---|---|
| 2026-11-04 | 首版：18 个稳定 code + 六类标签 + 各类 gate 精度 + attempt 语义；标注偏差 24（诊断文档未入库） |
| 2026-11-04 | 增补 CH02 code 18–25（`E_REGION`…`E_PENDING`），只增不改；`E_PENDING` 固定 `required=false`，用于仿真层暂不支持的 gate，不计为通过 |

## 9. CH02 提示落地前的硬约束（2026-11-04 追加）

> 本节为实现 `LADDER_TEXT` 前的契约补丁。只描述规则，不描述实现代码；`GateResult` 的 code、字段、标签均不变。

### 9.1 `E_AREA`(22) 一码多用：提示键必须是 `(code, gate_id)` 二元

`E_AREA` 在 CH02 至少承载四种证据形状、三种玩家可感知错因：

| 位置 | 实际语义 | `input` 证据 | 玩家该看到的话 |
|---|---|---|---|
| 2.3 / 2.4 `target` 类用例（`_judge_target`） | **门数超上限**（例：4 个 NAND 造 OR，上限 3） | 行/门数与上限（`detail` 形如“行 p/t，门数 n（上限 l）”） | “门太多，先减一层” |
| 2.4 `area` 用例（`_judge_area`） | **门数超上限** | `expected` 上限、`actual` 实测门数 | 同上 |
| 2.5 `build_area` 槽位分支 | **槽位不够**（板子插不下） | `{"slots":4,...}`，`expected` 形如 “n/4 槽” | “这块板放不下，先拆成两块” |
| 2.5 `build_area` 总门数分支 | **总门数预算超** | `{"slots":...,"max_total_gates":...}` | “总门数超预算” |

因此 **`LADDER_TEXT` 不能做成 `code → 文案` 的一维表**。反例：2.5 玩家实际是“板子插不下”，按 code 查 22 会给他一句“你的门太多了”，既不对因、也把他往错误的修法（删逻辑门）上带。

**键形状（定稿）**：二元键 `(code, gate_id)`，`gate_id` 缺省时才回落到 `code` 级文案；回落链固定为：

```
(code, gate_id)  →  code  →  E_GENERIC(99)
```

GDScript 字典没有元组键，落地形态二选一，二选一后不得混用：

```gdscript
# 形态 A：嵌套字典（推荐，查两次）
LADDER_TEXT := {
    22: {
        "T2.3-2": {1: "…", 2: "…", 3: "…"},
        "T2.5-2": {1: "…", 2: "…", 3: "…"},
    },
    6: {1: "…", 2: "…", 3: "…"},   # code 级回落
}
# 形态 B：复合键字符串
# "22|T2.5-2" → 文案组；再回落 "22"
```

约束：
- 同一 `code` 的不同 `gate_id` 允许给出**完全不同**的 L1 方向句，不要求共享措辞。
- 2.5 内部“槽位”与“总门数预算”也必须按 `gate_id` 分开（二者证据键不同：有无 `max_total_gates`）。
- 组别（08 文档 §2.2 的 A–H）仍按 code 分组用于配色/筛选，**不要**用组别反推具体文案。

### 9.2 `20` 已转正、`19` 仍是 pending：`E_PENDING(25)` 的定位

`src/core/ch02_checks.gd` 的 `PENDING_REASONS` 现在**只剩 `static_current`**，在入口把它拦成 `E_PENDING(25)`，并固定 `required=false`；`rail_margin`(20) 已由 `_judge_rail` 实现并直接落 `E_RAIL_MARGIN`，不再被拦截。因此：

- **20 已可见**：会红、计入失败统计，并进玩家提示阶梯（文案按 §9.1 的二元键规则写）。
- **19 是唯一 pending**：`T2.2-3`、`T2.4-4` 两条 gate 当前不可能出现在玩家面前，也不会红、不计入失败统计。
- `E_PENDING(25)` 是**内容未完成占位，不是玩家错误**：永不进提示阶梯、永不进失败率/失败统计；`detail` 只用于开发日志（`pending：<原因>`）。
- UI 遇到 25 不应显示“失败”，也不应计入“本节失败次数”；只可在开发模式显示“待接入”。
- 19 的文案可以先落表，但**必须在 25 拦截生效前保持不可达**；不得复用 25 的“技术故障”措辞。

### 9.3 玩家可见 code 清单（当前版本）

| 范围 | 会进玩家提示阶梯 | 只进日志 / 不可见 | 说明 |
|---|---|---|---|
| CH02 新增 | **18、20、21、22、23、24** | 19、25 | 20 已转正；19 被 `PENDING_REASONS` 拦成 25（`T2.2-3`、`T2.4-4`）；25 是占位 |
| 第一章 0–17 | 1、2、3、6、7、8、11、12、13、14、15、16、17 | 4、5、10、99 | 4/5/10 是配置缺陷，99 是兜底；0 是通过 |
| 例外 | — | 9 | 9 依赖玩家“先猜再测”，当前 1.5 延迟由模型固定测量，**实际打不出来**（08 文档 §3 已注明） |

补充：
- 22 虽“可见”，但必须按 9.1 用 `(code, gate_id)` 选文案；只按 code 查视为实现错误。
- 16 虽在“可见”内，也存在一码两用（见 §9.4），需同样按 gate_id 或证据形状区分。
- 本清单是“当前版本”快照；任何 code 从不可见转为可见，都要同时补 `(code, gate_id)` 文案与回归用例。

### 9.4 其他“一码多用”隐患（点名）

| code | 是否一码多用 | 具体表现 | 建议 |
|---|---|---|---|
| 16 `E_GLITCH` | **是** | `glitch` 语义是“毛刺宽度未达下限”（`expected`/`actual` 为 int）；`fix` 语义是“修复后仍有毛刺”（`expected`/`actual` 为 bool）。两者错因与下一步不同（前者看路径差，后者看修复开关是否生效） | 按 `(16, gate_id)` 分文案；或至少按 `typeof(actual)` 分派（bool=fix，int=glitch）。不得共用一句 |
| 22 `E_AREA` | **是** | 见 9.1，门数/槽位/总预算三种 | 强制 `(code, gate_id)` |
| 2 `E_BUILD` | 弱 | 成环、端口非法、图结构不合法共用一句 | 文案可保持通用（“检查连线是否成环或端口接错”），无需拆 |
| 3 `E_UNCONNECTED` | 否 | 证据本身列出具体线名，文案可通用 | 维持 |
| 6/7/14/17 | 否 | 同一 code 下语义一致，差异只在证据 | 维持 |

除 16 与 22 外，未发现必须拆文案的一码多用；`E_PENDING` 的多原因由 9.2 处理（永不展示）。

### 9.5 `rail_margin` 已实现 + `static_current` 为何仍是唯一 pending

#### 9.5.1 `E_RAIL_MARGIN`(20) 的实现口径（已落地，`src/core/ch02_checks.gd::_judge_rail`）

纯离散算术，**不依赖器件层 / 模拟求解器**：先用黑盒求各稳态逻辑输出，再把逻辑值反查成实际电平，比对轨到轨门限。

```
V_high = Vdd · R_L / (R_L + Ron)
V_low  = Vdd · Ron / (R_L + Ron)
```

- 参数来源：`data/labs/ch02_labs.json` 中 `inverter` 段的 `rail`（`vdd 3.3` / `ron_ohm 50` / `load_ohm 2000`），gate 级可用 `rail` 覆盖；门限默认 `v_high_min 3.2 V`、`v_low_max 0.1 V`，可由用例的 `v_high_min` / `v_low_max` 覆盖。
- 当前参数下的自检值：`V_high ≈ 3.2195 V`（≥3.2 通过）、`V_low ≈ 0.0805 V`（≤0.1 通过）。
- 失败落 `E_RAIL_MARGIN`(20)：输出为 `1` 但 `V_high < v_high_min`，或输出为 `0` 但 `V_low > v_low_max`；输出为 `X`/`?` 落 `E_BUILD`(2)。
- 证据形状：`input={"v_high_min","v_low_max"}`，`expected="V_high ≥ …，V_low ≤ …"`，`actual={"v_high","v_low","states":[…]}`，`detail="N 稳态：V_high=…，V_low=…"`。
- 提示文案按 §9.1 的 `(code, gate_id)` 规则；20 的错因单一（电平余量不足），同一 gate 内可共用措辞。

#### 9.5.2 `static_current` 仍是唯一 pending 的原因

`PENDING_REASONS` 当前只含 `static_current`，对应 `T2.2-3`、`T2.4-4` 两条 gate。**不转正的前置条件一句话**：缺口在编辑器：2.2 调色板仅 NOT 门，无法搭出两管同时导通；补模型会让 T2.2-3/T2.4-4 变成恒绿死判据。

原因展开：2.2 的编辑器调色板只有 NOT 门，玩家搭不出「PMOS 与 NMOS 同时导通」的拓扑；因此即便补上电流模型，也没有能产生非零稳态电流的电路，判据只会恒绿。L1 也没有晶体管级网表，任何电流值只能按门类型查表——两层缺口叠加，所以 19 保持 `E_PENDING(25)` + `required=false`，不红、不计失败统计、不进提示阶梯。

### 9.6 2.4 整节延后（已裁决的设计决定）

2.4 依赖器件级网表，**整节延后**，等网表能力就绪后再开放。落地用三字段锁定，**整节禁入**，不做“四个 gate 逐个 pending 展示”：

| 字段 / 接口 | 形状 | 规则 |
|---|---|---|
| `content_status` | `"ready"` / `"deferred"` | 缺省 `"ready"`；`"deferred"` 表示整节暂不可进入 |
| `deferred_reason` | 字符串 | **玩家可见中文**，不许含内部术语（如“网表”“仿真层”“pending”）；缺省空串，UI 不展示空串 |
| `lab_content_available(lab_id)` | `-> {"available": bool, "reason": String}` | 唯一查询入口；`deferred` 时 `available=false` 且 `reason=deferred_reason` |

约束：
- 延后期间**整节禁入**：不运行任何 gate、不产生 `attempt`、不计失败、不显示逐条 pending；进入入口时只展示 `deferred_reason`。
- **技能树节点照常显示**（看得见、点不进）：节点保留标题与图标，点击给出 `deferred_reason`，不得灰掉或隐藏节点。
- 不得用 `E_PENDING(25)` 表达整节延后：25 是单 gate 占位，整节延后由 `content_status` 表达，二者不要混用。
  - **理由**：25 表示“单个 gate 未完成、节是开着的”；整节延后时玩家根本进不去。混用会让玩家看到四个 gate 全挂“待补”，误以为自己哪里做错了。
- 2.4 转正时只改 `content_status` 与 `deferred_reason`，不新增 code、不改本节契约。
