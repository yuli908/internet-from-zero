# M3 规格：L3 时序层 + TraceSink 事件流 + 物品奖励入库

- 状态：**已批准（2026-11-04），含追加条款 A（§1.2，最高优先级）；实现按 T0→OPT→T1…T7 执行**
- 日期：2026-11-04
- 作者：技术实现（接手 M1/M2 交付）
- 上游依据（**只读，不改不提交**）：
  - `docs/simulation/01_model_layers.md` §5 L3 时序电路（原语边界、亚稳态口径）
  - `docs/simulation/03_components.md` D16 DFF / D17 寄存器 / D18 计数器 / D19 移位寄存器
  - `docs/simulation/02` §6 亚稳态、§8.1 快照格式
  - `docs/simulation/06` 性能预算、`docs/simulation/08` 测试口径
  - `docs/simulation/ref/simcore/logic.py` `Circuit.dff`、`ref/tests/test_sequential.py` 7 个时序用例
  - `docs/design/11-ch02-content-spec.md`（第二章，仅用于确认 M3 不越界）
  - 已交付事实见 `docs/PROGRESS.md` §2.2–§2.6

## 1. 目标

| # | 目标 | 交付物 |
|---|---|---|
| M3-1 | L3 时序原语 **DFF**：上升沿采样、异步 RESET、setup/hold 违例 → X + METASTABLE | `src/sim/sim_dff.gd` |
| M3-2 | L3 组合时序器件：**寄存器、计数器、移位寄存器**，结构与参考实现同构 | `src/sim/sim_sequential.gd` |
| M3-3 | 统一 **TraceSink**：`(tick, layer, kind, subject, payload)` 固定 schema，可导出、可摘要比对 | `src/sim/trace_sink.gd` |
| M3-4 | 快照升级到 **`ifz-sim/2`**（含时序态），兼容读取 `ifz-circuit/1` | `src/sim/sim_circuit.gd` |
| M3-5 | **物品奖励入库机制**（数据驱动 `grants.items`，幂等、可存档） | `src/core/player_state.gd`、`src/ui/lab_*` 调用点 |
| M3-6 | 参考向量化验证 + 性能预算实测 | `tests/test_l3.gd`、`tests/data/l3_vectors.json`、`tests/bench_l3.gd` |

### 1.1 非目标（明确不做，避免范围膨胀）

- **不实现** L4 CPU / L5 总线 / L6 网络 / 存储器阵列（属 M4+）。
- **不做** GDExtension 原生下沉（基准已证明 200 门必须原生，另立项；M3 沿用 GDScript 并新测 L3 上限）。
- **不做** 冒险三档（`EXPLAIN/SYNC/MASK`）、错误码编号 0–18、42 道题库。
- **不做** 第二章内容（`docs/design/11` 的 8 种新判定 kind）——M3 只保证 L3 与 TraceSink 能支撑它。
- **不改** `data/ch01_levels.json` 的奖励数值：策划奖励表未定稿，M3 只做机制，数据留空。
- **不碰** `docs/design/`、`docs/simulation/`、`docs/curriculum/`（只读、不提交）。

### 1.2 追加条款 A（批准时新增，**最高优先级**）：性能现实约束

**事实基线**：200 门/200 DFF 实测 p95 = 15.66–17.78 ms（§2 第 7 条）。GDScript 门级仿真**到不了 200 门**，
不得再按 200 门设计内容或验收标准。处理顺序固定如下，前一项不完成不进入下一项：

1. **先做一轮实现层优化（不改语义）**，目标：**5 ms 内稳定跑 100 门 / 100 DFF**。
   手段**只限**：预计算 fanout 邻接表（去掉每门每输入的闭包订阅）、去掉每事件字典查表、
   线网与门表改用 `PackedInt32Array` 等紧凑数组、事件队列批量出队（减少每事件 Dictionary 分配）。
   禁止借优化改三值语义、延迟表、`(tick, seq)` 全序或 `max_events_per_tick` 行为。
   证据：**50 / 80 / 100 三档各 3 次**、400 帧、4 tick/帧，给 p95 对比表（3 次全列，不取最优）。
   （已实测：100 档 3 次 p95 = 3.06 / 3.08 / 2.91 ms，见 `PROGRESS.md` §2.7。性能余量只作记录，
   **不据此抬高交互上限**——交互上限按仿真组硬约束，见下条。）
2. **交互上限按仿真组硬约束（2026-11-04 接口对齐，覆盖原"100 或 50"条款）**：
   门级交互**默认 50 门 / 50 DFF，绝对上限 80**；超过 80 在构建期返回 **`IFZ_E_SCALE`**，
   禁止静默降采样或只画一部分门。`data/sim/delays.json` 的 `limits.gdscript_gates=50`、
   `gdscript_dff=50`、`require_gdextension_above=80`；`PROGRESS.md` 偏差表同时记实测 100 与文档估算 200 的差异。
3. **内容侧硬约束**：玩家可搭建的门级电路上限 = `SimDelays.gdscript_gate_limit()`（默认 50，
   编辑器与判卷共用单一来源）；超限时 UI 明确提示"**该电路需要结构级表示**"并拒绝构建；
   超过绝对上限 80 返回 `IFZ_E_SCALE`，不做静默截断。更大的系统一律走宏单元 / 结构级
   （L2 模块、后续 L4+），与仿真文档「CPU 不展开成门」的结论一致。
4. **只读文档不改**：`docs/simulation/` 的 200 门估算**不改**（仿真组文件），只在 `PROGRESS.md` 偏差表记录实测；
   M3 验收命令中不得出现修改 `docs/simulation/` 的步骤。
5. 该条进入验收：**M3-G14**（优化性能三档×3 次）与 **M3-G15**（内容侧上限与 UI 提示）必须机器可判定。

## 2. 继承现状（实现前必须先认账的事实）

1. `src/sim/sim_circuit.gd` 已有 `add_dff(name, d, clk)`，但**只有** clk→Q=2 tick 与上升沿采样：
   无 RESET、无 setup/hold、无 METASTABLE；`tests/` 里没有任何 DFF 行为测试，只有 bench 用它压测。
   M3 必须**替换**该实现（保留签名兼容或一次性改全部调用点），不能两套并存。
2. `src/sim/sim_module.gd` 只有 L2 组合模块（half_adder/full_adder/ripple/mux2/mux4），
   `t_settle` 由 `SimDelays` 推导；M3 的时序器件必须复用这些组合件（`mux2` 7 tick、`ripple` `6W+4`）。
3. 事件模型是整数 tick + `(tick, seq)` 优先队列；线网写入走 `_write`，同值不重复写（自然合并窄脉冲）。
4. 快照当前为 `ifz-circuit/1`：只有 wire 值 + tick，**没有**时序态；存档（`SaveStore` v3）只存玩家进度，
   不存仿真态 —— M3 的快照改动不影响存档版本。
5. `SimEngine.trace` 只是 `Array`，`SimCircuit` 另有 `history`/`glitches` 两数组，字段不统一；
   UI 波形（`ui/widgets/waveform.gd`）消费的是 `history`。
6. `data/ch01_levels.json` 的 6 节 lab **没有**物品奖励字段；全仓库无 `grants` 实现（已 grep 确认）。
7. 基准结论（`docs/PROGRESS.md` §2.2）：GDScript 在 **50 门/50 DFF** 内 p95 3.32–4.03 ms；
   200 门/200 DFF p95 15.66–17.78 ms；首个超限档 80 门（5.39 ms）。M3 任何新器件都必须重新量。

## 3. 设计

### 3.1 DFF（`src/sim/sim_dff.gd`，`class_name SimDff`）

**行为级原语**（与 `ref/simcore/logic.py` 同构，不用门级主从触发器）；端口：`D`、`CLK`、`RESET`（高有效异步）、`Q`。

| 条件 | 行为 | Tick 语义 |
|---|---|---|
| `RESET=1` 且 CLK 上升沿 | 不采样 D，`Q` 保持为 0（若已被复位置 0，则无新写入） | 只记 `EDGE`，不记 `SAMPLE` |
| `RESET` 由 0→1（任意时刻） | `Q=0` | 边沿后 1 tick 写入（`03` D16「立即 1 tick」） |
| CLK 0/X→1，D 稳定 | `Q=D` | 边沿后 2 tick 写入 |
| CLK 0/X→1，D 在边沿前 `<setup(2)` tick 内变过 | `Q=X` + `METASTABLE` | 边沿后 2 tick 写 X |
| CLK 0/X→1，D 为 X | `Q=X`（不标 METASTABLE） | 同采样 |
| CLK 1 期间 D 变化且 `Δ < hold(1)` | `Q=X` + `METASTABLE` | 变化后 2 tick 写 X |
| CLK 1→0/X | 不动作 | — |
| 上电初值 | `Q=X` | 由 `init` 参数覆盖（寄存器用全 0） |

- 边沿判定只依赖 CLK 线网的 0/X→1 转换监听器，**禁止**墙钟或帧计数。
- setup/hold 用 `Wire.last_change`（现有字段），不另建时间戳表。
- `hold` 语义与参考实现一致：违例条件 `Δ < hold`（`Δ=hold` 不违例）；G3 必须同时断言两侧边界。
- 每个 DFF 的 `Q` 是普通 1 位 wire，可被下游门读取；`SimDff` 不改变 `SimCircuit` 的求值顺序。

### 3.2 时序器件（`src/sim/sim_sequential.gd`，`class_name SimSequential`）

结构与 `ref/simcore/components.py` 的 `Register` / `Counter` / `ShiftRegister` 同构，**全部复用** L2 件：

| 器件 | 结构 | 声明延迟 | 约束 |
|---|---|---|---|
| 寄存器 `register(width, en)` | 每 bit：`EN ? D : Q`（mux2）+ DFF（`init=0`） | `t_settle = mux2(7) + clk_to_q(2) = 9` | EN=X → 该 bit 进 mux 的 D 侧为 X，Q 采样为 X |
| 计数器 `counter(width, en, load)` | 寄存器（含 EN mux）+ `ripple(width)` 加一 + 每 bit load mux2 | `t_clk_min = ripple(6W+4) + load mux(7) + EN mux(7) + setup(2) = 6W+20`（W=4 → 44） | 模 2^W 回绕；`LOAD` 优先级高于 `EN`；见 §8 R1 |
| 移位寄存器 `shift_register(width, en, dir)` | `W` 个 DFF 共用 clk；`sin`→bit0，bit[i]→bit[i+1]；可选 EN mux 在 bit0 前 | 采样沿后 `2` tick 出新值；带 EN 时输入需提前 `7+2=9` tick 建立 | `EN=0` 保持；EN=X 且被选中的 bit 进 X |

- **不允许**在 GDScript 里另写"计数器算式"绕过门结构——否则延迟与冒险就不是算出来的，而是硬编码的。
  计数器的加法必须调 `SimModule` 的 ripple，delay 由其 `t_settle` 与 `SimDelays.delay()` 组合。
- 时钟：提供 `SimClock`（period 必须偶数，duty 默认 `period/2`，phase 可配），写在 `sim_sequential.gd`；
  时钟本身是普通 wire 上的调度写入，不接受浮点。
- 器件对外声明 `name / inputs / outputs / t_settle(or t_clk_min) / build(circuit)`，与 `SimModule` 契约一致；
  `t_clk_min` 由结构推导，测试用 `measure_settle` 实测并断言不超界。

### 3.3 TraceSink（`src/sim/trace_sink.gd`，`class_name TraceSink`）

```json
{"tick": 7, "layer": "L3", "kind": "SAMPLE", "subject": "dff.q", "payload": {"d": "1", "q": "1"}}
```

- 固定 5 字段、固定类型；`kind` 白名单：
  `CHANGE`（线网值变化）、`EDGE`（时钟上升/下降沿）、`DROP`（一次已调度写入被同值合并而取消）、
  `SAMPLE`（DFF 采样）、`METASTABLE`（setup/hold 违例）、`ERR_ADDR`/`ERR_METASTABLE`（后续里程碑用）。
- `layer ∈ {L0a, L1, L2, L3, L4, L5, L6}`；`subject` 非空；`payload` 为只含基础类型的字典。
- 排序：只追加，`tick` 单调不减；同 tick 按写入顺序（`seq` 保证）。
- 容量：默认环形缓冲 `max_events=20000`，超限丢最旧并计数 `dropped_old`（导出时带计数，**不静默截断**）。
- `digest()`：对 `[tick, layer, kind, subject, JSON.stringify(payload, 键排序)]` 逐条拼接后 SHA-256；
  用于"1 tick/帧 vs 4 tick/帧"确定性比对。
- 兼容：`SimCircuit.history` / `glitches` 保留（UI 波形不改），但每次 `_write` 同时写 sink；
  `history` 的条数必须等于 sink 中该线 `CHANGE` 条数（G9 断言）。

### 3.4 快照 `ifz-sim/2`（`src/sim/sim_circuit.gd`）

```json
{"format": "ifz-sim/2", "tick": 17,
 "wires": {"a": "1", "clk": "0"},
 "regs": {"dff0": {"q": "1", "last_edge": 15, "meta": false}},
 "clocks": [{"name": "clk", "period": 10, "duty": 5, "phase": 5}]}
```

- `restore()` 接受 `ifz-circuit/1`（无 `regs`，按全 X 恢复）与 `ifz-sim/2`；
  未知 `format` 明确报错，不猜测。
- `snapshot()` 仅在**静止态**（事件队列为空且无待写）允许，否则返回 `{ok=false, error="not_quiescent"}`。
- 快照不进入存档（`SaveStore` v3 不变）；若将来要存，另开 v4 迁移，M3 不动存档格式。

### 3.5 物品奖励入库（`grants.items`）

- 数据形态（章节/关卡文件，**M3 只读取，不写数值**）：

```json
"grants": {"items": {"M06": 1}, "once": true}
```

- 触发点：lab 首次通过（与 `reward.gold/xp` 同一处，同一个 `complete` 分支）。
- 语义：
  - 幂等：`PlayerState` 记 `granted:<lab_id>` 标记，重复通过不二次发放；
  - 原子性：任一 `item_id` 不在 `data/items.json` → 整单拒绝、`reward` 金币/XP 也不发，返回错误并记日志；
  - 数量必须为 ≥1 的整数；`once=false` 时不写标记（但仍受"仅首次通过"调用点约束）；
  - 入库后进 `PlayerState.inventory`，随存档 v3 往返（现有 items 字段，无需迁移）。
- **阻塞项**：策划奖励表未定稿 → M3 用 `tests/data/ch99_reward_fixture.json`（仅测试用）验证机制；
  `data/ch01_levels.json` 一行不改（G12 用 `git diff` 断言）。

### 3.6 文件清单

新增：`src/sim/sim_dff.gd`、`src/sim/sim_sequential.gd`、`src/sim/trace_sink.gd`、
`tests/test_l3.gd`、`tests/data/l3_vectors.json`、`tests/data/ch99_reward_fixture.json`、`tests/bench_l3.gd`。
修改：`src/sim/sim_circuit.gd`（**OPT 热路径重写** + trace + 快照 + `_write` 接 sink）、
`src/sim/sim_engine.gd`（共享 `seq` 与事件计数接口，仅新增方法不改既有行为）、
`src/sim/sim_delays.gd`（上限读取）、`src/ui/widgets/circuit_editor.gd`（G15 上限与提示）、
`src/core/player_state.gd`（`add_items`/`grant` 标记）、
`src/core/lab_runtime.gd`（完成分支）、`data/sim/delays.json`（新增 L3 实测量）、`tests/run_tests.gd`（注册新套件）、
`scripts/bench.ps1`（加 `-Scenario l3`）、`docs/PROGRESS.md`。

## 4. 可机器判定 Gate（全部可由命令复现）

| Gate | 判据（可观察） | 命令 | 通过条件 |
|---|---|---|---|
| **M3-G1** DFF 采样时序 | 上升沿 t=5 后 Q 在 t=7 变；下降沿不变；t=15 沿 → t=17 更新 | `run_tests.ps1`（`test_l3`） | 3 条时序断言全过，Q 值的 tick 精确匹配 |
| **M3-G2** setup 违例 | D 在边沿前 1 tick 变 → `Q=X` 且 sink 有 `METASTABLE`，subject 含 DFF 名 | 同上 | `Q=="X"` 且 ≥1 条 METASTABLE；边沿前 2 tick 变 → `Q=D` 且 0 条 |
| **M3-G3** hold 违例 | 边沿同 tick 后写 D → `Q=X`+METASTABLE；`Δ=hold` 边界不违例 | 同上 | 两侧边界各 1 条断言 |
| **M3-G4** 异步 RESET | `RESET=1` + 上升沿 → 1–2 tick 内 `Q=0`，D 不被采纳；撤 RESET 后恢复采样 | 同上 | 3 条断言；且 RESET 期间无 `SAMPLE` 事件 |
| **M3-G5** 寄存器 | EN=0 保持、EN=1 载入、EN=X → X、`t_settle` 实测 ≤9 | 同上 | 4 位四组用例全过 |
| **M3-G6** 计数器 | 4 位 18 周期：0..15 全不同、回绕 0、LOAD 生效、EN=0 保持；`period=t_clk_min+5` 全确定；`period=10` 与 `period=t_clk_min-1` 出现 X + METASTABLE | 同上 | 6 条；`t_clk_min` 与推导式一致 |
| **M3-G7** 移位寄存器 | 4 位按 `1011` 逐拍左移 8 拍序列正确；EN=0 保持；建立不足 → X | 同上 | 3 条 |
| **M3-G8** 参考向量 | `l3_vectors.json` ≥40 条，覆盖 4 类器件 + 复位 + 两类违例；逐条比对 tick/值/trace kind | 同上 | **100% 通过**，0 失败 |
| **M3-G9** TraceSink | 每条 5 字段且类型正确；kind 在白名单；tick 单调；`history` 条数 == sink CHANGE 条数；1 tick/帧 与 4 tick/帧的 `digest()` 相同 | 同上 | 5 条断言全过 |
| **M3-G10** 快照 v2 | `ifz-sim/2` 往返 digest 相同（含 regs/tick）；能恢复 `ifz-circuit/1`；非静止态 snapshot 被拒绝 | 同上 | 3 条 |
| **M3-G11** 性能预算 | 新场景（N 级 DFF 链 + 4 位计数器）p95 ≤5 ms @ 4 tick/帧；实测上限写回 `delays.json` 并由 `test_data` 断言 | `bench.ps1 -Scenario l3` | 声明档位 p95 ≤5.00 ms；上限与 `delays.json` 一致 |
| **M3-G12** 奖励入库 | 重复完成不二次发；未知 item 整单拒绝；存档往返保留；`data/ch01_levels.json` 无改动 | `run_tests.ps1` + `git diff data/` | 4 条断言 + diff 为空 |
| **M3-G13** 回归 | 原有 1410 项 + 新增 ≥60 项，0 失败；导入无 ERROR；截图冒烟无回归 | `run_tests.ps1`、`selfcheck.ps1`、`--editor --quit` | `FAILED 0`、`RESULT PASS` |
| **M3-G14** 优化后门数上限 | 实现层优化后 50/80/100 三档、各 3 次、400 帧的 p95 实测；交互上限按仿真组硬约束取 50（默认）/ 80（绝对），与实测 100 的差异记入偏差表 | `bench.ps1 -Sizes "50,80,100" -Frames 400` ×3 | 表格保留 3 次原值；`limits` 三键 = 50/50/80；PROGRESS 偏差行含「文档估算 200 / 实测 100 / 交互取 50/80」 |
| **M3-G15** 内容侧门数卡死 | 编辑器 `max_gates` 默认取 `SimDelays.gdscript_gate_limit()`（50），可放宽到 `gdscript_gate_hard_cap()`（80）；超关卡上限提示"该电路需要结构级表示"且 `build_sim()` 返回 `needs_structural_representation`；超 80 返回 `IFZ_E_SCALE` | `run_tests.ps1`（`test_l3`/`test_circuit`/`test_data`） | 5 条断言：上限同源、绝对上限同源、超限提示精确、两种错误码各 1 条 |

失败处理：任一 Gate 未过 → 标"未完成/需人工"，写入 `docs/PROGRESS.md`，**不得调低阈值**；
若设计阈值与实测冲突（如 §8 R1），只记录偏差，不改只读文档。

## 5. 性能预算与降级路径

### 5.1 先决条件：OPT 优化关（§1.2，最高优先级）

- 现有热路径成本点（`PROGRESS.md` §2.2 已定位）：每事件 Dictionary 事件对象、`Callable.callv`、
  每门每输入的闭包订阅、`probe()` 的字符串→字典查表、每事件堆比较、每次改值写 `history`。
- OPT 只做实现层替换：**fanout 邻接表 + 整数线网/门表（PackedInt32Array）+ 合并事件队列（整数堆）**；
  公开 API（`add_wire/add_gate/add_dff/bind/set_input/probe/history/snapshot/restore`）与语义保持不变。
- 验收档位：50 / 80 / 100（门=DFF=N），每档 3 次、400 帧，p95 全列。
  - 实测结果：50 档 1.34/1.34/1.52 ms、80 档 2.23/3.15/2.38 ms、100 档 3.06/3.08/2.91 ms（3/3 ≤5 ms）。
  - **交互限值不跟实测抬到 100**：按仿真组硬约束 `gdscript_gates=50`、`gdscript_dff=50`、
    `require_gdextension_above=80`；实测 100 只作为"余量"记录在 PROGRESS 偏差表。
  - 超过 80 构建期 `IFZ_E_SCALE`，禁止静默降采样或只画一部分门。

### 5.2 L3 场景预算（OPT 之后再做）

- 预算不变：**5 ms/帧、4 tick/帧**（`docs/simulation/06`）。
- **计数器周期（本项实测裁决，2026-11-04）**：`SimSequential.measure_counter_period()` 在真实 `SimCircuit` 上
  按偶数周期逐档扫描，判据 = 无 METASTABLE + 全周期扫描逐沿值正确（4 位 34 沿、8 位 514 沿）：
  - **4 位最小稳定周期 = 14**（仿真组 `6W+20=44`、`6W+9=33` 均偏保守）；
  - **8 位最小稳定周期 = 26**（仿真组 `6W+9=57`，取 70 更保守）；
  - 差异原因：我们的计数器是紧凑结构（`W-2` 个 AND 进位 + `W` 个 NOT/XOR，组合门合计 `2W-2`
    （8 位 = 14 门）+ `W` 个 DFF），不是参考实现的 104 门展开；clk→Q=2、setup=2 与参考一致。写回 `data/sim/delays.json` 的 `l3`，
    `tests/test_data.gd` 断言 14/26。只读文档不改，偏差记 `PROGRESS.md` 第 16 行。
- 器件实测事件数（仿真组提供，作为预算参照，非本仓库实测）：
  | 器件 | 门/DFF | 事件 | 占 5 ms |
  |---|---|---|---|
  | 8 位行波加法器 | 40 门 | 63 | 1.7% |
  | 3→8 译码器 | 11 门 | 13 | 4.1% |
  | 4 位比较器 | 33 门 | 48 | 7.5% |
  | 4 位 ALU | 166 门 | — | **超限，必须宏单元** |
  | 8 位计数器 | 104 门 | — | **超限，必须宏单元** |
  | 8 位寄存器 | 8 DFF | 10 | — |
  | UART | — | 12 | — |
  结论：玩家门级电路只能承载"几十门"规模；计数器/ALU 必须走 `SimSequential` 宏单元，与 §1.2 条 3 一致。
- 新场景与档位（N = DFF 级数）：
  1. `dff_chain`：N=10 / 20 / 30 / 40 / 50，每帧 4 tick，时钟 period=4；
  2. `counter`：4 位计数器 + 4 位寄存器 + 8 位选择器，period=50；
  3. `mixed`：N 级移位寄存器 + 4 位计数器，各取 1/2 预算。
- 判定：p95 ≤5.00 ms 才可写入 `data/sim/delays.json` 的 `gdscript_l3_dff`；
  若 50 级已超限，实测首个超限档并写回更小上限（同 §2.2 的 80 门做法）。
- 降级路径：超限场景**不假装通过**——在 PROGRESS 写"GDScript 上限 N，超出走 GDExtension（M4）"，
  并把 bench verdict 输出保留在 `artifacts/logs/`。

## 6. 确定性保证

1. 只用整数 tick；无墙钟、无帧率、无随机数（亚稳态是**确定性** X，不掷骰子）。
2. 事件按 `(tick, seq)` 全序；同 tick 的先后由创建顺序固定，测试锁住该顺序。
3. 时钟用调度写入，phase/duty/period 全整数；period 必须偶数。
4. TraceSink 只读观测，不参与求值；容量丢弃只影响导出，不影响电路结果。
5. 同一电路序列跑 1 tick/帧 与 4 tick/帧，wire 值、regs、trace digest 必须逐字节一致（G9）。
6. 快照只在静止态生成；`restore` 后继续跑的 digest 必须等于不中断的 digest（G10）。

## 7. 与参考向量的比对方式

- **来源**（只读运行，不改文件）：在 `docs/simulation/ref/` 下执行 `python -m tests.test_sequential`，
  7 个用例全 PASS；把其中可观察的 tick/值/事件转写进 `tests/data/l3_vectors.json`，
  每条带 `source` 字段（例：`ref:test_dff_samples_on_rising_edge`）与 `doc` 字段（例：`03#D16`）。
- **比对粒度**：每条 case = {器器件, 时钟参数, 输入序列 (tick, wire, value), 观察点 (tick, wire), 期望值/期望 trace kind}。
  逐条断言；差异时以参考实现为准，记录偏差。
- **不可转写的部分**：参考实现自报的 `t_settle`（如计数器 31/33）不是行为，只是估算；
  M3 用自己的结构推导 + 实测，§8 R1 说明差异，**不**把 33 当硬阈值。
- **不做**"抽样通过"：向量数严格计数，报告必须写"通过数 / 总数"。

## 8. 偏差与风险（实现前预判，批准时知情）

| # | 冲突/风险 | 预判 | 处理 |
|---|---|---|---|
| R1 | `03` D18 称 4 位计数器组合 31、周期 ≥33；但该结构含寄存器 EN mux（+7）+ 建立（+2），按现有 L2 件推导为 `6W+20`（W=4 → 44） | 文档估算漏算 EN mux；参考实现的 `test_counter_wrap` 用 period=100、`test_clock_too_fast` 用 10，两者都不受影响 | 以结构推导 + 实测为准，`PROGRESS.md` 偏差表加一行；只读文档不改 |
| R2 | `SimModule.ripple` 的 `t_settle=6W+4` 比参考 `sum` 路径 `6(W-1)+4` 保守 4–6 tick | 只是上界，功能与向量不受影响 | 保留保守值（安全侧），在 §7 注明"上界不同、行为一致" |
| R3 | 现有 `add_dff` 无 RESET/setup/hold 且无测试，bench 依赖它 | 替换会改变 bench 行为 | 先补 `test_l3` 锁行为，再替换；bench 重跑并更新数据 |
| R4 | `DROP` 语义若定义过宽会被读成"吞事件" | 只把"已调度写入因同值合并而取消"记 `DROP`；更窄的脉冲在调度前已合并，由 `_write` 的过滤点统一记录 | G9 断言 `DROP` 条数 == `_write` 过滤次数 |
| R5 | 快照新增 `regs` 可能被误读为存档格式变更 | 存档 v3 只存玩家进度，与仿真态无关 | §3.4 明写；G10 只测仿真快照，不动 `SaveStore` |
| R6 | 奖励机制先于奖励表落地，可能出现"空机制" | 数据侧不改，机制用测试 fixture 证明 | G12 断言 `data/ch01_levels.json` diff 为空；待策划定稿只改数据 |
| R7 | 第二章 8 种新判定 kind 不在 M3 | M3 只保证 TraceSink 的 `kind` 白名单可扩展（新增不改 schema） | 白名单集中定义，CH02 另立项加 kind |
| R8 | 仿真文档估算 200 门，GDScript 实测 100 档可能仍 >5 ms | 优化后先测；到不了就按实测写 50，**不回写 200** | `PROGRESS.md` 偏差表记「文档估算 200，实测 50/100」+ 原因；`docs/simulation/` 不改，由仿真组修正 |
| R9 | OPT 改热路径可能引入顺序/计数偏差 | fanout 保持"按建门顺序订阅"；`seq` 与通用事件共享同一自增源；`max_events_per_tick` 对合并队列同样生效 | G13 全量回归 + G1/G8 时序向量 + `test_sim` 的 1v4 tick 一致；事件顺序断言不变 |
| R10 | 计数器周期：仿真组 `6W+9`（8 位 57，取 70） vs 我们结构推导 44 vs 实测 | **以实测为准**：4 位 14、8 位 26（偶数、无 METASTABLE、全周期逐沿正确）。原因：紧凑自增链 `2W-2` 组合门 + `W` DFF（8 位 14 门），非 104 门展开 | `data/sim/delays.json` 的 `l3` 写 14/26 并被 `test_data`/`test_l3` 断言；`docs/simulation/` 不改，差异记 PROGRESS 第 16 行 |
| R11 | L2 参考向量 JSON 的字段顺序与本地模块声明不同（mux4 为 `[d(4),s1,s0,y]`） | 测试按 JSON 顺序显式映射到 `SimModule.inputs`，不改模块声明 | `test_l2_vectors` 5 组各全量通过（105 行） |
| R12 | 仿真组 L2 向量 143 行含 `decoder3` 10 / `comparator4` 17 / `alu4` 8，本工程无对应 `SimModule` | 只比对已实现 5 组共 **105/105**；其余 35 行记为未覆盖（ALU 166 门 > 80 硬上限，只能宏单元） | 不新增超预算模块；缺口记 `PROGRESS.md` 第 17 行，留待 M4 |

## 9. 验收命令（批准后照此执行，不得换命令）

```powershell
# 0) OPT 优化关：50/80/100 三档各跑 3 次、400 帧（G14；3 次结果全列，不取最优）
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1 -Sizes "50,80,100" -Frames 400
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1 -Sizes "50,80,100" -Frames 400
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1 -Sizes "50,80,100" -Frames 400

# 1) 全量测试（含新增 test_l3）
powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1

# 2) 参考实现时序用例（只读，只在 docs/simulation/ref 下运行）
python -m tests.test_sequential

# 3) L3 性能基准
powershell -ExecutionPolicy Bypass -File .\scripts\bench.ps1 -Scenario l3 -Sizes "10,20,30,40,50" -Frames 400

# 4) 导入/启动冒烟
C:\tools\godot-4.4.1\godot.cmd --headless --path . --editor --quit
powershell -ExecutionPolicy Bypass -File .\scripts\selfcheck.ps1

# 5) 奖励数据未改动
git diff --stat -- data/ch01_levels.json

# 6) 只读文档未被我们改动（仿真组既有改动不算）
git diff --stat -- docs/simulation/ docs/design/ docs/curriculum/
```

期望：0) 三张表都在 `artifacts/logs/`，100 档 3/3 ≤5 ms 才可声明 100；1) `FAILED 0` 且总数 = 1410 + 新增；
3) 声明档位 p95 ≤5 ms、verdict 明确；4) 无 ERROR（`native/.gdignore` 的已知残留按现有 selfcheck 规则剥除）；
5) 输出为空；6) 输出中不含 `src/`/`tests/`/`data/` 以外的本次改动（仿真组文件保持原样）。

## 10. 交付边界

- 提交范围只限 `src/`、`tests/`、`data/`、`scripts/`、`specs/m3/`、`docs/PROGRESS.md`、`README.md`。
- 执行顺序：T0 基线 → **OPT 优化关（最高优先级，G14/G15）** → T1 DFF → T2 器件 → T3 TraceSink → T4 快照 → T5 奖励 → T6 L3 基准 → T7 收尾。
- 每个子系统一次提交（OPT、T1、T2、T3、T4、T5、T6 各一次），提交前跑导入检查。
- 未完成项在 PROGRESS 里标"未完成/需人工"，不写成通过。
