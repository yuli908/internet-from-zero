# M4 · UI 接线契约（`specs/m4/ui_contract.md`）

> 一页纸，给 UI 会话照单接线，避免各自猜。实现方只交付接口与事件名；**视图绘制 / 难度开关 / 题库页面 / 埋点由 UI 会话完成**。
> 生效版本：M4（2026-11-04）。改动须在本文件留一行记录。

## 1. 宏单元（只读视图）

| 你要做的 | 调什么 | 拿到什么 |
|---|---|---|
| 列出可展开器件 | `SimMacro.cells()` | `{kind: {module_kind, width, gate_count, expandable}}`（深拷贝） |
| 取单元元数据 | `SimMacro.meta(kind)` | 上述字段 + `pages: Array` + `t_settle: int`；未知 kind 返回 `{}` |
| 画只读分页 | `SimMacro.pages(kind)` | `[{id, title, group, gates, cells}]`；`group ∈ arith/logic/select/comb` |
| 打开一页 | `SimMacro.expand_page(kind, page_id, 临时SimCircuit, prefix)` | `{ok, error, gates, built, read_only, page_data}`；alu4 `built=false`（不建门），decoder3/comparator4 `built=true` |
| 整块展开 | `SimMacro.expand(kind, c, prefix)` | `{ok, error, gates, total, scale_warn, inputs, outputs}`；`ok=false` 时 `error` 见 §5 |
| 折叠 | `SimMacro.fold(kind, prefix)` | `{ok, ports:{inputs,outputs}, digest}`；调用方丢弃页内线网 |

硬规则（UI 不得绕过）：
- `>50` 门只提示"该电路需要结构级表示"（`scale_warn=true`），仍可构建；`>80` 必须显示错误并**不画**（`IFZ_E_SCALE`）。
- `alu4` 只能开分页视图（每页 5/40/9/16/48/32/16）；**禁止**把它当 166 门整图或只画一部分门。
- 只读视图用**临时** `SimCircuit`，关闭即释放；不要塞进玩家可编辑门表。

## 2. CH02 判定事件（trace）

写入（唯一入口，位于 `SimCircuit`）：

```gdscript
sim.record_judgement(judgement_kind, subject, payload, at_tick := -1) -> bool
```

| UI 里的判定（小写） | trace kind | payload 固定键（类型） |
|---|---|---|
| `mosfet_region` | `MOSFET_REGION` | `region`(str), `vgs`(float), `vds`(float), `id_ua`(float) |
| `x_propagation` | `X_PROPAGATION` | `expect`(str), `got`(str) |
| `static_current` | `STATIC_CURRENT` | `ua`(float), `states`(int) |
| `rail_margin` | `RAIL_MARGIN` | `v_high`(float), `v_low`(float) |
| `equiv` | `EQUIV` | `ref`(str), `vectors`(int), `mismatch`(int) |
| `area_max` | `AREA_MAX` | `gates`(int), `max`(int) |
| `power_calc` | `POWER_CALC` | `mw`(float), `expect_mw`(float), `tol`(float) |
| `power_ratio` | `POWER_RATIO` | `ratio`(float), `expect_ratio`(float), `tol`(float) |

- `build_area` **没有** trace：不要订阅，也不要画；它由 `AREA_MAX` / 门数统计派生。
- 缺固定键或类型不符 → 返回 `false` 且 `sink.rejected++`；UI 不要"先写一半再补"。
- 时序：`at_tick` 传 `-1` 用当前 tick；事件流 `digest()` 在 1 tick/帧 与 4 tick/帧 下必须一致（已由 `test_ch02_kinds` 锁定），UI 不要按帧重组事件。
- 展示层需要的值（`vth/ron/max_ua/expect_mw`）**全部来自数据文件**，M4 不内置任何数字。

## 3. 题库

```gdscript
var bank := QuestionBank.from_doc(json)   # 或等 DataDB 登记后加载
bank.load_errors                          # Array[String]，空 = 通过；有值 UI 显示"题库未通过校验"
bank.items.size()                         # 不要假设 42/12，按实际条数翻页
bank.item(id)                             # {} = 不存在
bank.score(id, response)                  # {ok, score, max, detail, error_code, manual, correct?}
bank.error_codes()                        # C1–C9
```

`response` 按题型传：`{"choice": int}` / `{"text": str}` / `{"graph": Variant}` / `{"value": float}`。
搭建题只走黑盒验收（`LabChecks`），`score()` 返回 `manual=true`、`score=0`，**不要**当成判错。

## 4. 难度

`Difficulty.names()` = `["EXPLAIN","SYNC","MASK"]`；`PlayerState.difficulty` 存 `settings.difficulty`；
读档缺失/非法回落 `EXPLAIN`。M4 三档**行为完全相同**，UI 可先出开关（默认 EXPLAIN），不要提示"已生效"的采样差异。

## 5. 错误码 → UI 文案

| 码 | 触发 | UI 显示 |
|---|---|---|
| `IFZ_E_SCALE` | 展开/分页超 80 门，或 alu4 整块展开 | "该电路需要结构级表示（≤50 门交互 / ≤80 门上限）" |
| `IFZ_E_UNKNOWN_MACRO` | `meta/expand/fold` 遇到未知 kind | "未知器件"（属于接线错误，记日志） |
| `IFZ_E_UNKNOWN_PAGE` | `expand_page` 页 id 不存在 | "该页不存在"（属于接线错误，记日志） |
| `E_UNKNOWN_ITEM` | `score()` 题 id 不存在 | 不弹窗，按"题目已下线"处理 |
| `E_RESPONSE` | `score()` 的 response 形状不符 | "提交格式异常"，不要显示给学生的原始报错 |
| `C1`–`C9` | 判错后的错因码（题库/评分层） | 按 `docs/curriculum/06` §3 文案展示 |

## 6. 事件名（埋点，UI 负责发；M4 只留名字）

`item_start` / `item_submit` / `hint_open` / `lab_check` / `scale_warn` / `view_page_open` / `view_fold`。
字段名与 `docs/curriculum/06` 保持一致；M4 不实现上报通道。

## 7. 本轮不提供（等 UI 会话接回）

- 视图绘制（宏单元页、ALU 七页）；
- 难度开关与存档设置页；
- 题库页面、错因反馈卡；
- 埋点上报；
- `project.godot` / `src/ui/**` 的任何改动。
