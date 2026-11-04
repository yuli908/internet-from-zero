# M3 任务清单

- 状态：**已批准**（2026-11-04，含 spec §1.2 追加条款 A）
- 规格：[spec.md](./spec.md)
- 顺序：T0 → **OPT（最高优先级）** → T1 → T2 → T3 → T4 → T5 → T6 → T7

## 任务总览

| ID | 任务 | 文件 | 通过 Gate | 依赖 | 提交信息（建议） |
|---|---|---|---|---|---|
| T0 | 基线复核：确认 1410 项通过、工作区状态、`add_dff` 调用点清单 | 无改动 | — | — | 不提交 |
| OPT | 实现层优化：fanout 邻接表 + 整数线网/门表 + 合并事件队列，目标 100 门@5 ms | `src/sim/sim_circuit.gd`、`src/sim/sim_engine.gd`、`src/sim/sim_delays.gd`、`src/ui/widgets/circuit_editor.gd`、`tests/test_l3.gd`、`data/sim/delays.json` | G14、G15、G13 回归 | T0 | `perf(sim): 数据化热路径，实测门数上限与内容侧卡死` |
| T1 | DFF 行为原语（RESET/setup/hold/METASTABLE） | `src/sim/sim_dff.gd`、`tests/test_l3.gd` | G1–G4 | OPT | `feat(sim): L3 DFF 原语（setup/hold/RESET/亚稳态）` |
| T2 | 寄存器 / 计数器 / 移位寄存器 + SimClock | `src/sim/sim_sequential.gd`、`tests/test_l3.gd` | G5–G8 | T1 | `feat(sim): L3 寄存器/计数器/移位寄存器` |
| T3 | TraceSink 统一事件流 | `src/sim/trace_sink.gd`、`src/sim/sim_circuit.gd`、`ui/widgets/waveform.gd`（只读兼容） | G9 | T1 | `feat(sim): 统一 TraceSink（5 字段 schema + digest）` |
| T4 | 快照 `ifz-sim/2` | `src/sim/sim_circuit.gd`、`tests/test_l3.gd` | G10 | T1–T3 | `feat(sim): 快照 v2（含时序态，兼容 v1）` |
| T5 | 奖励入库机制 + 数据侧留空 | `src/core/player_state.gd`、`src/core/lab_runtime.gd`、`tests/data/ch99_reward_fixture.json`、`tests/test_rewards.gd` | G12 | T2 | `feat(reward): grants.items 幂等入库机制` |
| T6 | L3 基准 + 上限写回 | `tests/bench_l3.gd`、`scripts/bench.ps1`、`data/sim/delays.json`、`tests/test_data.gd` | G11 | T2 | `perf(sim): L3 基准与 GDScript 上限实测` |
| T7 | 回归与文档收尾 | `docs/PROGRESS.md`、`README.md` | G13 | T1–T6 | `docs: M3 交付记录与偏差` |

> T3/T4 与 T5 无代码耦合，可在 T2 后并行；T6 必须在 T2 后立即做（上限影响是否继续在 GDScript 加器件）。

## T0 基线复核（不改代码）

- [ ] `git log --oneline -5`、`git status` 记录当前 HEAD 与未跟踪文件。
- [ ] `grep add_dff` 列出全部调用点（预计：`tests/bench_sim.gd`、`src/sim/sim_circuit.gd`）。
- [ ] 跑一次 `run_tests.ps1` 确认 `FAILED 0`、总数 1410（作为 M3 基线）。
- 完成定义：三项输出粘进任务记录；若基线不为 1410，先停下来报告，不带着红灯开工。

## OPT 实现层优化（G14/G15，最高优先级，先于 T1）

- 只改热路径实现：wire/门用整数 id + `PackedInt32Array`/`PackedByteArray`；fanout 邻接表替代每门闭包；
  gate 求值用整数三值表，不再每事件建 `vals` 数组；gate 事件走整数堆并与通用事件按 `(tick, seq)` 合并出队。
- 语义锁：`test_sim` 的 3 级 relay=9、1 vs 4 tick/帧一致、快照往返、`test_l2` 全部 t_settle 不变。
- 测：`bench.ps1 -Sizes "50,80,100" -Frames 400` 跑 3 次，3 次 p95 全列（G14 证据）。
- 写回：100 档 3/3 ≤5 ms → `gdscript_gates=100`；否则 `50`，并在 PROGRESS 偏差表记「文档估算 200，实测 50/100」+ 原因。
- 内容侧：编辑器 `max_gates` 默认 `SimDelays.gdscript_gate_limit()`；超限提示"该电路需要结构级表示"，`build_sim()` 返回
  `{ok:false, error:"needs_structural_representation"}`（G15 三条断言）。
- **不改** `docs/simulation/` 的 200 门估算。
- 完成定义：G14 + G15 + 全量回归 `FAILED 0`；bench 三张表留在 `artifacts/logs/`。

## T1 DFF（G1–G4）

- 实现 `SimDff`：端口 D/CLK/RESET/Q，行为表见 spec §3.1。
- 替换 `SimCircuit.add_dff`（保留 `add_dff(name, d, clk, reset := "", init := "X")` 兼容旧调用）。
- `tests/test_l3.gd` 首套：G1 3 条、G2 2 条、G3 2 条、G4 3 条。
- setup 用 `Wire.last_change`；hold 用 CLK=1 期间的 D 变化监听；违例写 `X` + sink（T3 前先写 `SimEngine.trace`）。
- 完成定义：10+ 条断言全过；`add_dff` 旧调用（bench）仍能构造电路。
- 禁止：用墙钟/帧数判定边沿；用概率随机模拟亚稳态。

## T2 时序器件（G5–G8）

- `SimClock`（偶数 period、整数 duty/phase）。
- `register`：EN mux + DFF，`t_settle` 实测 ≤9。
- `counter`：register + ripple + load mux，推导 `t_clk_min=6W+20`；测试用 `t_clk_min+5` 与 `10`、`t_clk_min-1` 三档。
- `shift_register`：W DFF + 可选 EN mux；`1011` 序列 8 拍。
- `tests/data/l3_vectors.json`：≥40 条，逐条带 `source`（ref 用例名）与 `doc`（`03#D16` 等）。
- 完成定义：G5–G8 全过；`l3_vectors` 100%；计数器的 `t_clk_min` 与实测一致。
- 若 `t_clk_min` 与 `03` 的 33 不一致：按 R1 记偏差，不把 33 写进测试。

## T3 TraceSink（G9）

- `TraceSink` 类：5 字段、白名单、环形缓冲、`digest()`、`to_array()`、`filter()`。
- `SimCircuit._write` 写 `CHANGE`；同值合并写 `DROP`；`SimDff` 写 `EDGE`/`SAMPLE`/`METASTABLE`。
- `history` 保留；G9 断言 `history` 条数 == CHANGE 条数。
- 确定性：同一序列 1 tick/帧 vs 4 tick/帧 digest 相同。
- 完成定义：G9 5 条断言全过；导出 JSON 可被 `JSON.parse()` 直接读。

## T4 快照 v2（G10）

- `format=ifz-sim/2`，含 `wires/regs/clocks/tick`；`restore` 兼容 `ifz-circuit/1`。
- 非静止态 `snapshot()` 返回 `{ok=false, error="not_quiescent"}`。
- 完成定义：往返 digest 相同；旧格式可恢复；reject 未知 format。
- 注意：不改 `SaveStore` 版本（玩家存档与仿真快照无关）。

## T5 奖励入库（G12）

- `PlayerState.add_items(id, n)` + 未知 id 拒绝；`grant_items(lab_id, grants)` 幂等标记。
- `lab_runtime` 完成分支：先校验全部 item id，再原子发放（金币/XP 同批）。
- 测试数据 `tests/data/ch99_reward_fixture.json`（只测试用，不进 `data/` 正式表）。
- 完成定义：4 条断言 + `git diff data/ch01_levels.json` 为空。
- **阻塞**：真实奖励数值等策划定稿；本任务只交机制与测试，不填数值。

## T6 L3 基准（G11）

- `bench_l3.gd` 三场景（dff_chain / counter / mixed），`bench.ps1 -Scenario l3`。
- 档位 10/20/30/40/50，400 帧；p95 ≤5 ms 才写回 `delays.json`。
- 首个超限档必须报出；若 50 级即超限，写更小上限并记偏差。
- 完成定义：bench PASS 输出 + `test_data` 断言新键；PROGRESS 记实测表。

## T7 回归收尾（G13）

- [ ] `run_tests.ps1`：`FAILED 0`，总数 = 1410 + 新增（写实际数）。
- [ ] `--editor --quit` 无 ERROR；`selfcheck.ps1` PASS。
- [ ] 截图冒烟：若 UI 未改可跳过并注明"未改 UI，未重跑截图"。
- [ ] PROGRESS 更新：M3 状态、每 Gate 实测值、偏差表新增行、未完成项。
- 完成定义：报告先给实测数字，再给结论；未跑的项目标"未运行/需人工"。

## 明确不做（M3 范围内拒绝）

- 门级主从触发器、概率亚稳态、存储器阵列、任意宽度除法器。
- 修改 `docs/design|simulation|curriculum`、`data/ch01_levels.json` 的奖励数值、存档信封版本。
- 用"看起来正确"的动画/截图替代可判定的数值断言。
