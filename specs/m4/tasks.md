# M4 任务清单（规格批准后执行）

> 状态：**全部待开始**。规格 `spec.md` 未批准前不得写实现代码。
> 每完成一个 T 提交一次；提交只 add 本 T 列出的路径。`git index.lock` 出现时等待重试，**不删锁**。
> 边界：不碰 `project.godot`、`src/ui/**`、`docs/design/`、`docs/simulation/`、`docs/curriculum/`、
> `data/chapters/**`、`data/labs/**`。需要 UI 才能验证的项标「待 UI 会话接回」。

## 依赖顺序

```
T0 (宏单元数据+引擎) ── T1 (8 种 trace kind) ── T5 (全量回归/验收/收尾)
T2 (题库接口) ────────────────────────────────┘
T3 (难度预留) ────────────────────────────────┘
T4 (Gate 测试) 依赖 T0/T1/T2/T3
```

## T0 — 宏单元目录与展开/折叠（spec §3.1）

| 项 | 内容 |
|---|---|
| 新增 | `data/sim/macros.json`（decoder3 11 / comparator4 33 / alu4 166；alu4 7 页） |
| 新增 | `src/sim/sim_macro.gd`：`cells/meta/pages/expand/expand_page/fold` |
| 修改 | 无（`SimModule` 已支持 decoder3/comparator4） |
| 验收 | 页门数 ≤ `SimDelays.gdscript_gate_limit()`；alu4 七页合计 166；`expand("alu4")` → `IFZ_E_SCALE`；展开→折叠→再展开 `state_digest` 相同 |
| 提交 | `feat(sim): 宏单元目录（decoder3/comparator4/alu4 只读分页）` |
| 不做 | 不实现 166 门 ALU 网表；不做 ALU 仿真 |

## T1 — 8 种 CH02 trace kind（spec §3.2）

| 项 | 内容 |
|---|---|
| 修改 | `src/sim/trace_sink.gd`：`KINDS` 7→15（仅加常量，不改 schema / `digest`） |
| 修改 | `src/sim/sim_circuit.gd`：新增只读记录点（不改求值顺序与事件数） |
| 新增 | `tests/test_ch02_kinds.gd` |
| 验收 | 8 kind 全可写入；5 字段不变；未知 kind 被拒；1 vs 4 tick/帧摘要一致；`docs/design/11` 8 个判定 kind ↔ trace kind 映射 8/8 |
| 提交 | `feat(sim): CH02 8 种 trace kind 白名单扩展` |
| 不做 | 不写 CH02 阈值/期望值（数值来自后续数据文件） |

## T2 — 题库接入接口（spec §3.3）

| 项 | 内容 |
|---|---|
| 新增 | `src/core/question_bank.gd`：`from_doc/validate/item/score/error_codes` |
| 新增 | `tests/test_questions.gd` + `tests/fixtures/questions/` 最小合法 fixture |
| 修改 | 无（`data/manifest.json` 不动） |
| 验收 | 合法 fixture 通过；缺字段/`type` 非法/`solutions < 2`/rubric≠100/重复 id 各报错；未知 id 返回 `ok=false`；评分确定性（同输入两次同分） |
| 提交 | `feat(core): 题库加载/校验/评分接口（不含题目数据）` |
| 不做 | 不写 42 道题干与答案；不改 `manifest.json`；不做 UI |

## T3 — 难度三档预留（spec §3.4）

| 项 | 内容 |
|---|---|
| 新增 | `src/core/difficulty.gd`：`EXPLAIN/SYNC/MASK`、`names/normalize/is_valid` |
| 修改 | `src/core/player_state.gd`：`difficulty` 字段 + 存档 `settings.difficulty` 读写（不升版本） |
| 新增 | `tests/test_difficulty.gd` |
| 验收 | 三档合法；未知值归一 `EXPLAIN`；默认 `EXPLAIN`；存档往返；缺字段读档回落 |
| 提交 | `feat(core): 难度三档预留（字段/校验/存档，无行为差异）` |
| 不做 | 不改 `SimCircuit` 采样或脉冲过滤（M5）；不做 UI 开关 |

## T4 — Gate 测试与套件注册（spec §4）

| 项 | 内容 |
|---|---|
| 修改 | `tests/run_tests.gd`：注册 `test_macro` / `test_ch02_kinds` / `test_questions` / `test_difficulty` |
| 新增 | `tests/test_macro.gd`（M4-G1/G2/G10） |
| 验收 | M4-G1…G7、G10 在本套件内可判定，输出带 `M4-G` 前缀便于日志检索 |
| 提交 | `test(m4): 宏单元/trace/题库/难度 Gate` |

## T5 — 回归、偏差表与收尾

| 项 | 内容 |
|---|---|
| 修改 | `docs/PROGRESS.md`：新增 §2.16–§2.19、偏差 21+、§4.1 M4 表、§6/§7 更新 |
| 验收 | `powershell -ExecutionPolicy Bypass -File .\scripts\run_tests.ps1` → `RESULT: N checks, 0 failures`（N ≥ 1621） |
| 验收 | `git diff --stat -- project.godot src/ui/ data/chapters/ data/labs/ docs/design/ docs/simulation/ docs/curriculum/` 为空 |
| 提交 | `docs(m4): PROGRESS 收尾（含验收与偏差）` |
| 不做 | 不改只读文档；不提交 `artifacts/`、`mockups/` |

## 人工裁决点（实现中遇到必须停）

1. `alu4` 的 `t_settle`：按 §3.1 结构推导，若与仿真组实测不符 → 记偏差，不改文档。
2. 8 种 trace kind 命名如需改名 → 负责人一次性裁决（spec R4）。
3. 题库条数/配比与交付件不符 → 教学组裁决，加载器不改（spec R3）。
4. 任何必须改 `src/ui/` 或 `project.godot` 才能验证的项 → 记「待 UI 会话接回」，不直接改（spec R5）。
