# ADR 0005 · 仿真契约 ↔ 数据驱动 / 类 ECS 映射

- 状态：已接受（M1 只落地 L0a–L1；L2+ 为接口占位）
- 日期：2026-11-04
- 关联：`docs/simulation/01_model_layers.md`、`02_determinism.md`、`06_performance.md`、`08_testing.md`、`07_api_contract.md`、[0002](0002-native-boundary.md)、[0003](0003-save-and-determinism.md)

## 1. 背景

`docs/simulation` 定义了 8 主层 / 11 子层（L0a、L0b、L1–L5、L6a–L6c、L7）的仿真契约，并要求
"所有层在同一整数 tick 基上推进、有统一 `TraceSink`、有参考实现与测试"。主工程必须给出**一份可执行的映射**：
哪一层现在用哪个 JSON、哪个类、哪个引擎、哪个 UI 采集点；没实现的层如何"占位而不撒谎"。

## 2. 映射表（契约 → 工程实体）

| 契约层 | M1 落地 | 数据结构 | 引擎/推进 | UI 采集点 | 状态 |
|---|---|---|---|---|---|
| **L0a** 模拟电平 | `src/core/voltage_model.gd` + `src/ui/widgets/level_gauge.gd` | `data/labs/ch01_labs.json` 的 `voltage{v_low_max,v_high_min,min,max,step}` + `gate_cases` | **无求解器**：阈值判读 `judge(v, low, high) -> "0"/"1"/"X"`，纯静态 | 滑杆 → 实时判读条、灯泡、预设按钮；`LabChecks.voltage` 判定 4 条用例 | ✅ 已落地（判读带，非 RC 求解） |
| **L0b** 数字电平 | `src/sim/sim_value.gd` | `String` 位串（`"0"/"1"/"X"` 或位串）；`GATE_DELAY` 常量 | 三值 Kleene：`X AND 0 = 0`、`X OR 1 = 1`，其余含 X → X | 探针值、`SimCircuit.history`、`glitches` | ✅ 已落地 |
| **L1** 门级 | `src/sim/sim_circuit.gd`、`sim_engine.gd`、`sim_delays.gd`；拓扑来自 `src/core/circuit_graph.gd` | `data/sim/delays.json`（唯一延迟来源）+ `CircuitGraph.nodes{kind,gate,a,b}` | `SimEngine`：整数 tick + `(tick, seq)` 最小堆；传输延迟 + 惯性过滤（输出不变则不写线网） | `circuit_editor` 采集拓扑与输入；`waveform` 画波形；`BlackBox` 跑向量 | ✅ 已落地（≤50 门/50 DFF，实测） |
| **L2** 组合电路 | `src/sim/sim_module.gd`：半加器 / 全加器 / 8 位行波加法器 / 2:1 与 4:1 选择器，`t_settle` 由延迟表推导；`BlackBox` 继续做模块级行为验收 | 模块 `name/inputs/outputs/t_settle` + 内部展开为 L1 门 | 复用 L1 的 `settle()`；`measure_settle()` 实测稳定时间 | `LabChecks.gate / half_adder`（只判行为，不看拓扑） | ✅ 已落地（`tests/test_l2.gd`） |
| **L3** 时序电路 | 只有延迟表里的 `dff{setup,hold,clk_to_q}` | `delays.json` 的 `dff` 段 | 无 DFF/时钟实现 | 无 | ⚠️ **占位**（仅常量） |
| **L4** 寄存器/ALU/CPU | 无 | 无微码表 | 无 | 无 | ⚠️ **占位**（`docs/simulation/01` §6 微码表为准） |
| **L5** 总线/IO | 无 | 无 | 无 | 无 | ⚠️ **占位** |
| **L6a/b/c** 网络 | 无 | 无 | 无 | 无 | ⚠️ **占位**（09 风险 2：只做 TCP-lite，不真 TCP） |
| **L7** 真实主机桥接 | 无 | 无 | 无 | 无 | ⚠️ **设计**（ADR 0004：伴生进程 + 「转发」标记） |

统一观测接口：契约要求单一 `TraceSink`（`(tick, layer, kind, subject, payload)`，kind ∈ `CHANGE/EDGE/DROP/ERR_*/SAMPLE`）。
M1 的实际形态是 `SimCircuit.history`（`{t, wire, old, new}`）+ `glitches`（`{t, wire, value}`），**没有** `TraceSink` 抽象与 `layer/kind` 字段。
这是已知偏差：UI 直接消费这两个数组。迁移到 TraceSink 时，`history` 可映射为 `kind=CHANGE`，`glitches` 映射为 `SAMPLE/ERR_*`。

## 3. 为什么用"数据 + 纯逻辑 + 类 ECS"而不是完整 ECS

M1 的实体只有三种：输入节点、门、输出节点；组件只有 `{kind, gate, a, b, delay}`；系统只有"事件调度 + 三值求值"。
在这个规模上引入通用 ECS（archetype、稀疏集、系统调度）只会增加间接层与每帧开销，且会掩盖确定性顺序。

因此采用**类 ECS 的最小形态**：

- **实体** = `CircuitGraph.nodes` 的字符串 id（也是 `SimCircuit` 的线网名）；
- **组件** = `Dictionary` 里的扁平字段（`kind/gate/a/b`）——不建组件类，避免构造开销；
- **系统** = `SimEngine` 的单一事件循环（schedule → pop → 求值 → 写线网 → 触发下游）；
- **查询** = "按键排序后遍历"（`snapshot()` 与 `build_graph()` 输出前都排序），不依赖哈希顺序。

数据驱动边界：**关卡/向量/延迟/价格全部在 JSON**；GDScript 只做语义与判定，不硬编码数值（`specs/m1/spec.md` §1 第 2 条）。

## 4. Python 参考实现：oracle 与固定向量策略

- oracle 唯一来源：`docs/simulation/ref/simcore/logic.py`（**只读**）。
- 导出器：`tools/gen_ref_vectors.py` → `tests/data/ref_vectors.json`：
  - `gates`：and / or / xor 各 9 组 + not 3 组 = **30 条**三值向量；
  - `half_adder`：**9 条**（A/B ∈ {0,1,X} 的 sum/carry）；
  - `gate_delay`：**8 条**（buf/not/nand/nor/and/or/xor/xnor）。
- 消费方：`tests/test_sim.gd` 逐条 `ctx.eq` 比对 `SimValue.gate()` / `not3()` / `bin3()` / `SimDelays.delay()`；
  另有 `LabChecks.half_adder` 的 `random_x` 用例：`data/labs/ch01_labs.json` 配 `count=8`、`seed=1`，
  用 `DeterministicRng` 抽 8 组含 X 的三值输入，逐组比对 `BlackBox.tri_eval` 与 `half_adder_tri`（由 `tests/test_lab_checks.gd` 驱动）。
- 策略要点：
  1. **比语义，不比实现**：Python 是"语义规范的可执行副本"，GDScript 是产品实现；不移植 Python 代码结构。
  2. **向量进仓库**：`ref_vectors.json` 是 golden，CI 直接比对；Python 只用于重新生成。
  3. **随机必须固定种子**：任何随机用例都写死 seed（M1 用 1），失败可逐条复现。
  4. **不做 digest 跨语言比对**：digest 依赖内部排序/字段集合，跨语言对不上不是 bug；跨语言只比**真值**。
  5. **改延迟必须三处同步**：`data/sim/delays.json` ↔ `docs/simulation/03` ↔ Python `logic.py`（当前靠人工核对，CI 未校验，属缺口）。

## 5. 性能预算与"降速不丢事件"

- 预算：60 FPS、仿真 5 ms/帧、4 tick/帧；2026-11-04 实测后 GDScript 上限为 **50 门 / 50 DFF**（200 门 p95 17.78 ms，见 ADR 0002 §2.1 与 `docs/PROGRESS.md` §2.2）。
- 实现方式：
  - `SimDelays.configure(data/sim/delays.json)` 在启动期读入 `gate_delay / dff / frame / limits` 四段；
    `ticks_per_frame()` / `budget_ms()` / `max_events_per_tick()` / `gdscript_gate_limit()` 是唯一访问口。
  - `SimEngine` 的单 tick 事件上限取 `SimDelays.max_events_per_tick()`（当前 20000）。
  - 正常路径：每帧推进 `k = ticks_per_frame()` 个 tick，事件堆跨帧保留。
  - 预算不足时：**只减少本帧推进的 tick 数**（降速），事件不丢、顺序不变 ⇒ 与"全速跑"的轨迹一致（`test_sim.gd` 有"1 tick/帧 vs 4 tick/帧一致"断言）。
  - 病态路径：单 tick 事件超限 → 显式失败并保留现场（"电路自激/存在环"），不做静默截断。
- 未验证的部分（需人工）：真实机器上的 ms 级耗时、最大门数、UI 重绘成本、截图/读档的帧内开销。

## 6. 已知冲突与偏差（本文档不修改代码，只记录）

| 项 | 契约要求 | 本工程 | 处理 |
|---|---|---|---|
| 快照格式 | `ifz-sim/1`（含 regs/memory/timers/next_seq） | `ifz-circuit/1`（只含 tick + wires + digest） | M1 无需寄存器/内存；升 L3 时再换格式（ADR 0003 §5） |
| 错误码 | 07 §5 固定 0–18 | 仅字符串错误（`{"ok":false,"error":"..."}`），未采用编号 | 下沉原生时必须采用编号；当前 UI 只显示文本 |
| TraceSink | 单一流 + 固定 kind 域 | `history` + `glitches` 两数组 | 见 §2 末段 |
| 冒险三档 | `EXPLAIN/SYNC/MASK` | 固定"EXPLAIN 行为"（毛刺可见并可高亮） | 档位开关未实现 |
| L0a | 固定子步长 RC 求解（`dt = 1/16 tick`） | 阈值判读带，无时间演化 | 见 `docs/PROGRESS.md` 偏差 1 |
| DFF/亚稳态 | setup/hold/clk_to_q + METASTABLE | 仅常量表 | L3 未实现 |

## 7. 复审触发条件

1. 开始实现 L2 模块封装 → 需先定 `t_settle` 声明与模块等价性测试。**（已于 2026-11-04 完成：`src/sim/sim_module.gd`、`tests/test_l2.gd`；`t_settle` 由 `SimDelays` 推导并实测校验）**
2. 开始实现 L3 → 需同时改存档格式（ADR 0003）与 `TraceSink`。
3. 下沉原生（ADR 0002）→ 错误码与 `ifz-sim/1` 必须同时落地，并保证 GDScript/C++ 同向量一致。
