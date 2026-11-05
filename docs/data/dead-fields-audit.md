# 数据字段 / 常量死字段审计

> 状态：**只读审计**。本轮**未删任何字段、未改任何代码**。
> 范围：`data/**` 全部 JSON 的 schema 字段；`src/**` 的三类声明——`GateResult` 失败码、`JUDGEMENT_KINDS` 判定 kind、全部 `const` 声明。
> 日期：2026-11-05。审计对象版本：`main` @ `52bf984`。

## 0. 结论（先给数）

| 类别 | 总数 | 活 | 半死 | 死 |
|---|---|---|---|---|
| `data/**` schema 字段（去重键名） | 285 | 231 | 22 | 32 |
| `GateResult` 失败码 | 28 | 27 | 0 | **1** |
| `JUDGEMENT_KINDS` 判定 kind | 8 | 7 | **1** | 0 |
| `src/**` `const` 声明 | 375 | 356 | 0 | **19** |
| **合计** | — | 594 | **23** | **52** |

- **死 52 条**：数据 32 + 失败码 1（`E_STATIC_CURRENT`，在 `gate_result.gd:101,133` 只有 TAG_MAP/DESCRIBE 自引用，从未被任何判定产生）+ 常量 19。
- **半死 23 条**：数据 22 + 判定 kind 1（`static_current`）。
- 32 条死字段里，高频重复的是 9 个 `items.json` 字段（各 86 个实例）、`source_recipe`（77）、`task_ids`（42）、`source`（33）、`source_note`（18）、`grants_note`（17）；其余多为单处。

## 1. 方法与口径

1. 递归解析 `data/**/*.json`（41 个文件）。**schema 字段**定义为：
   - 根对象的属性，或**任何含 `id` 的对象**的属性；键名必须匹配 `^[a-z][a-z0-9_]*$`（排除 `G01`、`T2` 这类字典 ID）。
   - `expected` / `rows` / `cells` / `states` 里的键是**期望值内容**，不是 schema，单列进 §3（动态比较）。
2. 对每个字段名，在 `src/**/*.gd`、`tests/**/*.gd`、`scripts/**` 搜索两种字面量读法：`"key"`、`'key'`。
3. 分档：
   - **活**：`src` 有命中，且命中点确属该字段（见下面的误判风险）。
   - **半死**：`src` 零命中，`tests`/`scripts` 有命中——**只有测试/探针/工具在读**。
   - **死**：零命中。
   - **动态读**：经变量键、字典遍历、整表装载访问，静态扫不到，不参与上面三档计数（§3 单列）。
4. 对所有死/半死条目做了关键词反查（字面量零命中即维持判定）；对 20 余个高频/歧义项另用 `Grep` 单独复核（如 `acquire|unlock_chapter|recipe_consume|craft_ops|sell_ratio|task_ids|require_second|region_model` 在 `src` 全部 0 命中）。

**已规避的误判风险**

- **同名键跨文件合并**：本表按**键名去重**，同名但不同位置的字段会合并成一个条目。已知至少 1 处因此虚高（`ports`，见 §4-①）。
- **整表装载 ≠ 消费**：`SimDelays.configure`（`src/sim/sim_delays.gd:33-43`）把 `gate_delay/dff/frame/limits` 整表搬进字典，但只有具名 getter 取到的键才算活。
- **整对象透传**：`Catalog.from_data` 把整个 item dict 存进 `items`（`src/core/catalog.gd:21`），任何按变量键取字段的位置静态扫不到（见 §4-③）。

## 2. 点名四条（用户指定必进表）

| 项 | 定义（文件:行） | 读取点 | 档 | 说明 |
|---|---|---|---|---|
| `static_current_max_ua` | `data/labs/ch02_labs.json:73`（inverter）、`:131`（replace） | **无**（`src`/`tests`/`scripts` 均 0 命中） | **死** | 与 gate 内 `max_ua`（`:80`、`:138`，同为死）重复；唯一规格来源本该是它，但代码从未读。删前需先定"规格放 gate 还是 lab" |
| `STATIC_CURRENT`（判定 kind 常量） | 映射 `src/sim/sim_circuit.gd:215`；白名单 `src/sim/trace_sink.gd:15`；payload schema `src/sim/trace_sink.gd:24` | 假 payload 喂料 `tests/test_ch02_kinds.gd:13`；零生产者断言 `tests/test_ch02.gd:250` | **半死** | `src` 的映射与白名单校验是活的，但**零生产者**：`ch02_checks.gd` 从不记该 kind（`:15` 只是 `PENDING_REASONS`）。已按本轮决定保留 + 标 `# PLACEHOLDER`（`sim_circuit.gd:214`） |
| `rules` | `data/labs/ch01_labs.json:16-20`（全库唯一 1 处） | 读取 `src/ui/teaching.gd:17`、`:106`；UI 调用 `src/ui/screens/lab_base.gd:322` | **半死（产品不可达）** | `fallback_note`（`teaching.gd:116-117`）在 `has_sections` 为真时短路；该 lab 有 5 段 sections（`:9-15`）→ 产品 UI 不渲染。已按缺陷处置：保留字段与分支，新增 `tests/test_teaching.gd::legacy_no_sections` 4 条断言，证明"无 sections 的老数据"真的走到兜底（见 §6） |
| `gate.body` | **不存在**：`data/**` 无任何 `gate_cases[].body`；`body` 只在 lab 级（82 个 lab，如 `ch02_labs.json:11,63,90,119,146`） | lab 级 `body` 由 `src/ui/screens/lab_ch02.gd:133,190,305` 直接渲染（`Ui.wrap`），另有探针 `lab_base.gd:537-538` | **lab.body = 活**；`gate.body` 无定义 | 用户点名的 `gate.body` 在数据中不存在，不需要处置；lab 级 `body` 是活字段，**不能删** |

**同口径旧归因已统一**（2026-11-05 裁决）：`data/labs/ch02_labs.json:5`、`src/core/ch02_checks.gd:15`、`specs/m5/failure_contract.md:244` 与本文件 §2 的两处 gate 已改为同一句：

```
缺口在编辑器：2.2 调色板仅 NOT 门，无法搭出两管同时导通；补模型会让 T2.2-3/T2.4-4 变成恒绿死判据
```

例外：`data/chapters/ch02_levels.json:33` 的 `deferred_reason` 是玩家可读文案，受内部术语断言约束，不套用这句。

## 3. 动态读（静态扫不到，单列）

脚本共记录 **631 处**变量键/遍历/整表装载。归三类：

| 机制 | 代表位置 | 怎么手工核实 |
|---|---|---|
| id 作键 | `src/core/catalog.gd:24-28`（`buy_doc.keys()`）、`src/autoload/data_db.gd:149,152`（价格表） | 键名是物品 id（`gate_not/gate_or/...`），不会出现字面量。核实法：列出 `items.json` 全部 id，与 `prices.buy/sell` 的键做差集；差集为空即活 |
| 整表装载后具名取 | `src/sim/sim_delays.gd:33-43`（`for key in gates.keys()`） | 只认 getter 里出现的具名字符串：`delay(kind)`、`dff_delay()`、`limit()`。核实法：在 `sim_delays.gd` 搜 `_table.get(` 的字面量参数 |
| 整行比较 / 期望值内容 | `src/core/net_lab_kit.gd:129`（`row.get(key)` 逐键比）、`src/core/ch04_checks.gd:215-228`（`for sig in row.keys()`） | 这些键来自 `expected/rows/cells`，属期望值不是 schema。核实法：确认键只在 JSON 的 `expected` 块内出现，且消费端用同一行字典比较 |

**结论**：`data` 里没有发现"整份 JSON 无人加载"的情况；所有死字段都处在**已加载但无人取**的位置。

## 4. 最不确定的 3 条

**① `ports` 被判"活"，但这是同名键合并的假活**
`data/labs/ch04_labs.json:34` 的 `gate_cases[].ports` 确实被 `src/core/ch04_checks.gd:114-115` 读（活）；但 `data/labs/ch01_labs.json:119` 的 `labs.encapsulation.ports` **没有任何读取点**——封装判定用的是 checkpoint 标记 `encapsulated`（`src/core/lab_checks.gd:186-190,293-296`），不是这份端口表。
不确定原因：键名去重后两条合并成一条，无法在汇总表里区分。**手工核实**：分别搜 `encapsulation.get("ports")` 与 `c.get("ports")`，前者零命中。

**② `task_ids`（42 处，`data/questions/ch01_exercises.json:11`）——「预留·无消费者（截至 2026-11-05）」**
`src`/`tests`/`scripts` 全部零命中。按裁决不删、降级标注，处置期限见 §6。

**③ `items[].acquire / unlock_chapter`（各 86 处，`data/items/items.json:5`）被判"死"**
字面量零命中，但 `Catalog.from_data` 把整条 item dict 原样存进 `c.items`（`src/core/catalog.gd:21`），后续任何 `catalog.item(id).get(<变量>)` 都无法静态排除。
不确定原因：这是"整对象透传"的固有盲区；要确认只能靠运行时插桩或人工通读 `shop_screen.gd` / `main.gd` 的全部取字段点。

## 5. 本轮不删的说明

- 用户明确要求"不许直接删任何东西"，本文件只出清单与建议。
- `static_current_max_ua`、`max_ua` 等字段与"第二章转正"绑定：转正时 `STATIC_CURRENT` 实现会第一次真正读 `max_ua`。**先别删**，否则转正要重新补数据。
- `rules` 与 lab 级 `body` 是教学内容，价值在文案不在读取点；删了等于删课程。
- 19 条零引用 `const` 里，多数是 UI 布局常量（`ui_theme.gd` 的 `S1/S4/S5/S6`、`shop_screen.gd` 的颜色/坐标），属于"设计留白"，不宜批量清。

## 6. 处置记录与防增长守卫

| 项 | 处置 | 理由 |
|---|---|---|
| `task_ids`（42 处） | 降级标注为 **「预留·无消费者（截至 2026-11-05）」**；**处置期限：若下一个内容批次（2026-11-05 之后第一批）仍无人读，随该批次删除** | 不删是给题库路由留余地，但不允许无限期挂着 |
| `rules` / `fallback_note` | 按缺陷处置：**保留字段与分支**，在 `tests/test_teaching.gd::legacy_no_sections` 增加 4 条断言，证明"无 sections 的老数据"真的走兜底（`section_list` 合成单段、`fallback_note` 出 rules、有 sections 时仍短路） | `rules` 定义在 `data/labs/ch01_labs.json`，删它等于动 CH01 数据（本轮明令禁止）；且 `section_list` 的 body 兜底是 `lab_base.gd` 渲染非 CH02 正文的唯一路径 |
| `static_current_max_ua` / `max_ua` | 只登记，不删 | 第二章转正时 `static_current` 实现要用 |
| 其余死字段 | 只登记，不删 | 用户要求"不许删任何数据字段" |

### 6.1 接口批次（2026-11-05）：旧布尔位「已删·理由」与新增字段

| 旧字段 | 登记 | 理由 |
|---|---|---|
| `T13.1-1` 的 `line_map_ok` / `stack_ok` / `output_ok` | **已删·理由**：被 `line_map`（pc→src_line 逐条）、`lines_covered`、`unmapped_pc`、`output`（实跑输出数组）替代；栈深已由 `expect_rows[].stack_after` 逐行判 | 布尔位可以填 true 冒充；删一条映射即红 |
| `T14.1-1` 的 `tokens_match` / `ast_ok` / `values_ok` | **已删·理由**：被行级 `tokens[]` / `ast` / `value` / `stages_exported` 替代 | 只记数量（13/8）不能证明逐段；逐条 token 与逐层 AST 可指认 |
| `T15.2-1` 的 `frames_match` | **已删·理由**：被 `handles` / `frames` / `unmatched_frames` 替代；gate 已由本机 loopback 真实捕获转正 | 布尔位无法逐帧对齐 `frame_id`/`fd`/`call_n` |

**新增字段（均已登记进附录 D）**：

| 字段 | 定义 | 生产者 | 消费者 |
|---|---|---|---|
| `labs.*.program` | `data/labs/ch13_labs.json` | `src/core/bytecode_trace.gd`（`run`） | `tests/test_ch13.gd` → table gate |
| `labs.*.source_lines` | `data/labs/ch13_labs.json` | 数据侧 | 同上（逐行可指认的源码侧） |
| `labs.*.case_sources` | `data/labs/ch14_labs.json` | 数据侧 | `src/core/mini_interp.gd` → `tests/test_ch14.gd` |
| `labs.*.socket_calls` | `data/labs/ch15_labs.json` | 数据侧 | `src/core/socket_trace.gd` → `tests/test_ch15.gd` |
| `labs.*.capture` | `data/labs/ch15_labs.json` | 数据侧（2026-11-05 本机 loopback 原始捕获冻结） | `tests/test_ch15.gd`（真实字节/调用顺序、`text_roundtrip` 推导） |

**转正账**：`T13.1-1` 由 pending → ready；ch13 进分母 11→12（`bytecode_vm` 3→4），全章 pending 1→0。不是凑数：5 条 pc 的行映射与输出 `[5]` 都由参考执行器实跑，删一条映射判红（code 10）。
**转正账（15.2）**：`T15.2-1` 由 pending → ready；ch15 进分母 15→16（`socket_api` 3→4），全章 pending 1→0。不是凑数：句柄/帧编号来自 2026-11-05 本机 loopback 真实捕获（Python socket，客户端 fd=332、send/recv 同一 12 B 字节），原始 10 条调用与 `bytes_hex` 冻结在 `socket_api.capture`；手改 `frame2` 的 `call_n` 仍判 10、删一帧判 10。

**防增长守卫**：`tests/test_field_registry.gd`（已注册进 `tests/run_tests.gd`）。口径是 **`文件 :: 路径`**，含 `id` 的对象归一成 `*`，数组元素归一成 `[]`——不按键名去重，避免重蹈 `ports` 的合并盲区。数据里新增未登记路径 → **判红并打印路径**；登记了但数据已不存在 → 只打印条数、不判红。登记表见附录 D。

## 附录 A　`data/**` schema 字段逐条（285 条）


### A.1 死（32 条）

| # | 字段 | 定义（文件:行） | 实例数 | 消费者 |
|---|---|---|---|---|
| 1 | `acquire` | data/items/items.json:5 | 86 | 无 |
| 2 | `bench_note` | data/sim/delays.json:44 | 1 | 无 |
| 3 | `contract` | data/labs/ch05_labs.json:43 | 1 | 无 |
| 4 | `craft_cost` | data/items/items.json:5 | 86 | 无 |
| 5 | `craft_ops` | data/items/items.json:5 | 86 | 无 |
| 6 | `derived` | data/items/items.json:67 | 3 | 无 |
| 7 | `f_from` | data/labs/ch02_labs.json:161 | 1 | 无 |
| 8 | `f_to` | data/labs/ch02_labs.json:161 | 1 | 无 |
| 9 | `flip_nibble` | data/labs/ch07_labs.json:157 | 1 | 无 |
| 10 | `generated_from` | data/items/items.json:3 | 1 | 无 |
| 11 | `grants_note` | data/labs/ch05_labs.json:54<br>data/labs/ch06_labs.json:45<br>data/labs/ch07_labs.json:45<br>（共 4 处） | 17 | 无 |
| 12 | `level_note` | data/labs/ch05_labs.json:137 | 1 | 无 |
| 13 | `max_ua` | data/labs/ch02_labs.json:80<br>data/labs/ch02_labs.json:138 | 2 | 无 |
| 14 | `price` | data/items/items.json:5 | 86 | 无 |
| 15 | `random_cases` | data/labs/ch01_labs.json:182 | 1 | 无 |
| 16 | `recipe_consume` | data/items/items.json:5 | 86 | 无 |
| 17 | `reference` | data/labs/ch02_labs.json:127 | 1 | 无 |
| 18 | `region_model` | data/labs/ch02_labs.json:33 | 1 | 无 |
| 19 | `require_second` | data/labs/ch01_labs.json:117 | 1 | 无 |
| 20 | `reusable` | data/items/items.json:5 | 86 | 无 |
| 21 | `sell_ratio` | data/economy/prices.json:5 | 1 | 无 |
| 22 | `source` | data/chapters/ch01_levels.json:7<br>data/chapters/ch02_levels.json:7<br>data/chapters/ch03_levels.json:7<br>（共 33 处） | 33 | 无 |
| 23 | `source_note` | data/labs/ch03_labs.json:4<br>data/labs/ch04_labs.json:4<br>data/labs/ch05_labs.json:4<br>（共 18 处） | 18 | 无 |
| 24 | `source_recipe` | data/economy/recipes.json:17 | 77 | 无 |
| 25 | `static_current_max_ua` | data/labs/ch02_labs.json:73<br>data/labs/ch02_labs.json:131 | 2 | 无 |
| 26 | `tags` | data/items/items.json:5 | 86 | 无 |
| 27 | `task_ids` | data/questions/ch01_exercises.json:11 | 42 | 无（**预留·无消费者（截至 2026-11-05）**，处置见 §6） |
| 28 | `timing` | data/labs/ch05_labs.json:180 | 1 | 无 |
| 29 | `trees` | data/skilltree.json:4 | 1 | 无 |
| 30 | `unlock_chapter` | data/items/items.json:5 | 86 | 无 |
| 31 | `uses` | data/items/items.json:5 | 86 | 无 |
| 32 | `waveform_note` | data/labs/ch05_labs.json:42 | 1 | 无 |

### A.2 半死（22 条）

| # | 字段 | 定义（文件:行） | 测试/工具调用点 |
|---|---|---|---|
| 1 | `blueprint` | data/items/items.json:5 | tests/test_ch11.gd:237<br>tests/test_ch11.gd:308<br>tests/test_ch12.gd:276<br>（共 5 处） |
| 2 | `codes` | data/labs/ch03_labs.json:21<br>data/labs/ch04_labs.json:23<br>data/labs/ch05_labs.json:21<br>（共 18 处） | tests/test_ch03.gd:358<br>tests/test_ch03.gd:361<br>tests/test_ch04.gd:442<br>（共 36 处） |
| 3 | `common_errors` | data/questions/ch01_exercises.json:23<br>data/questions/ch02_exercises.json:28<br>data/questions/ch03_exercises.json:70<br>（共 5 处） | tests/test_qbank_ch02.gd:114<br>tests/test_qbank_ch02.gd:169<br>tests/test_qbank_ch03.gd:114<br>（共 8 处） |
| 4 | `concept` | data/questions/ch02_exercises.json:14<br>data/questions/ch03_exercises.json:14<br>data/questions/ch04_exercises.json:14<br>（共 4 处） | tests/test_qbank_ch02.gd:113<br>tests/test_qbank_ch03.gd:113<br>tests/test_qbank_ch04.gd:113<br>（共 4 处） |
| 5 | `fixed` | data/labs/ch11_labs.json:722 | tests/test_ch11.gd:257<br>tests/test_ch11.gd:259<br>tests/test_ch11.gd:261<br>（共 5 处） |
| 6 | `group` | data/sim/macros.json:28 | tests/test_macro.gd:74 |
| 7 | `hints` | data/questions/ch01_exercises.json:24<br>data/questions/ch02_exercises.json:29<br>data/questions/ch03_exercises.json:74<br>（共 5 处） | tests/test_qbank_ch02.gd:114<br>tests/test_qbank_ch03.gd:114<br>tests/test_qbank_ch04.gd:114<br>（共 4 处） |
| 8 | `judge` | data/labs/ch03_labs.json:21<br>data/labs/ch04_labs.json:23<br>data/labs/ch05_labs.json:21<br>（共 18 处） | tests/test_ch03.gd:132<br>tests/test_ch04.gd:129<br>tests/test_ch05.gd:165<br>（共 18 处） |
| 9 | `keyboard` | data/labs/ch06_labs.json:47 | tests/test_ch06.gd:7<br>tests/test_ch06.gd:8<br>tests/test_ch06.gd:77<br>（共 4 处） |
| 10 | `l3` | data/sim/delays.json:31 | tests/bench_sim.gd:48<br>tests/test_data.gd:195<br>tests/test_data.gd:196<br>（共 5 处） |
| 11 | `measure_conditions` | data/labs/ch02_labs.json:19 | tests/test_ch02.gd:103<br>tests/test_ch02.gd:104 |
| 12 | `p1_gates` | data/labs/ch03_labs.json:19<br>data/labs/ch04_labs.json:21<br>data/labs/ch05_labs.json:19<br>（共 18 处） | tests/test_ch03.gd:140<br>tests/test_ch04.gd:137<br>tests/test_ch05.gd:171<br>（共 30 处） |
| 13 | `pending_kinds` | data/labs/ch02_labs.json:4<br>data/labs/ch03_labs.json:5<br>data/labs/ch04_labs.json:5<br>（共 19 处） | tests/test_ch03.gd:61<br>tests/test_ch04.gd:65<br>tests/test_ch05.gd:62<br>（共 4 处） |
| 14 | `practice` | data/labs/ch03_labs.json:20<br>data/labs/ch04_labs.json:22<br>data/labs/ch05_labs.json:20<br>（共 18 处） | tests/test_ch03.gd:23<br>tests/test_ch03.gd:46<br>tests/test_ch03.gd:127<br>（共 102 处） |
| 15 | `produce` | data/labs/ch03_labs.json:21<br>data/labs/ch04_labs.json:23<br>data/labs/ch05_labs.json:21<br>（共 18 处） | tests/test_ch03.gd:132<br>tests/test_ch04.gd:129<br>tests/test_ch05.gd:165<br>（共 18 处） |
| 16 | `rules` | data/labs/ch01_labs.json:16 | tests/_expect_probes.gd:228<br>tests/test_ch01_sections_ui.gd:268<br>tests/test_teaching.gd:42 |
| 17 | `section` | data/questions/ch01_exercises.json:10<br>data/questions/ch02_exercises.json:10<br>data/questions/ch03_exercises.json:10<br>（共 5 处） | tests/test_qbank_ch02.gd:53<br>tests/test_qbank_ch02.gd:113<br>tests/test_qbank_ch03.gd:53<br>（共 10 处） |
| 18 | `source_excerpt` | data/questions/ch02_exercises.json:15<br>data/questions/ch03_exercises.json:15<br>data/questions/ch04_exercises.json:15<br>（共 4 处） | tests/test_qbank_ch02.gd:113<br>tests/test_qbank_ch02.gd:140<br>tests/test_qbank_ch03.gd:113<br>（共 8 处） |
| 19 | `start_gold_mode` | data/chapters/ch02_levels.json:8<br>data/chapters/ch03_levels.json:8<br>data/chapters/ch04_levels.json:8<br>（共 7 处） | tests/test_ch02.gd:84 |
| 20 | `thresholds` | data/labs/ch06_labs.json:174<br>data/labs/ch07_labs.json:30<br>data/labs/ch08_labs.json:35<br>（共 15 处） | tests/test_ch06.gd:183<br>tests/test_ch07.gd:198<br>tests/test_ch08.gd:229 |
| 21 | `value_before` | data/labs/ch11_labs.json:720 | tests/test_ch11.gd:256<br>tests/test_ch11.gd:258<br>tests/test_ch11.gd:260<br>（共 5 处） |
| 22 | `value_expected` | data/labs/ch11_labs.json:721 | tests/test_ch11.gd:257<br>tests/test_ch11.gd:259<br>tests/test_ch11.gd:261<br>（共 5 处） |

### A.3 活（231 条）

| # | 字段 | 定义（文件:行） | 产品消费点（首个） |
|---|---|---|---|
| 1 | `a` | data/labs/ch03_labs.json:71 | src/core/black_box.gd:119<br>（共 64 处） |
| 2 | `actions` | data/labs/ch08_labs.json:30 | src/core/ch08_checks.gd:67<br>（共 2 处） |
| 3 | `alpha` | data/labs/ch02_labs.json:154 | src/core/ch02_checks.gd:499<br>（共 2 处） |
| 4 | `answer` | data/questions/ch02_exercises.json:47<br>data/questions/ch03_exercises.json:24<br>data/questions/ch04_exercises.json:244<br>（共 4 处） | src/core/ch02_checks.gd:156<br>（共 27 处） |
| 5 | `answer_value` | data/questions/ch01_exercises.json:149<br>data/questions/ch05_exercises.json:450 | src/core/question_bank.gd:143<br>（共 5 处） |
| 6 | `auto` | data/skilltree.json:10 | src/core/knowledge_graph.gd:54<br>（共 2 处） |
| 7 | `b` | data/labs/ch03_labs.json:71 | src/core/black_box.gd:119<br>（共 54 处） |
| 8 | `bank` | data/questions/ch01_exercises.json:5<br>data/questions/ch02_exercises.json:5<br>data/questions/ch03_exercises.json:5<br>（共 5 处） | src/core/question_bank.gd:47<br>（共 2 处） |
| 9 | `bit_count` | data/labs/ch01_labs.json:44 | src/ui/screens/lab_binary.gd:23 |
| 10 | `board` | data/labs/ch02_labs.json:155 | src/ui/screens/lab_ch02.gd:325 |
| 11 | `body` | data/labs/ch01_labs.json:8<br>data/labs/ch02_labs.json:11<br>data/labs/ch03_labs.json:10<br>（共 20 处） | src/ui/screens/lab_ch02.gd:133<br>（共 4 处） |
| 12 | `bound_first` | data/items/items.json:9 | src/core/chapter_runtime.gd:57<br>（共 4 处） |
| 13 | `boundary` | data/labs/ch03_labs.json:69 | src/core/ch03_checks.gd:167<br>（共 2 处） |
| 14 | `buy` | data/economy/prices.json:6 | src/core/catalog.gd:23<br>（共 10 处） |
| 15 | `byte` | data/labs/ch07_labs.json:114 | src/core/ch07_checks.gd:212<br>（共 3 处） |
| 16 | `byte_a` | data/labs/ch07_labs.json:151 | src/core/ch07_checks.gd:290 |
| 17 | `byte_b` | data/labs/ch07_labs.json:151 | src/core/ch07_checks.gd:291 |
| 18 | `c8` | data/labs/ch03_labs.json:71 | src/core/ch03_checks.gd:180<br>（共 6 处） |
| 19 | `c_f` | data/labs/ch02_labs.json:154 | src/core/ch02_checks.gd:500<br>（共 2 处） |
| 20 | `cadence_tol` | data/labs/ch02_labs.json:48 | src/core/ch02_checks.gd:186<br>（共 2 处） |
| 21 | `cash` | data/economy/recipes.json:10 | src/core/economy_core.gd:78<br>（共 6 处） |
| 22 | `cells` | data/sim/macros.json:6 | src/core/ch04_checks.gd:211<br>（共 3 处） |
| 23 | `chain` | data/labs/ch01_labs.json:141 | src/ui/screens/lab_signal.gd:18<br>（共 3 处） |
| 24 | `chapter` | data/questions/ch01_exercises.json:4<br>data/questions/ch02_exercises.json:4<br>data/questions/ch03_exercises.json:4<br>（共 5 处） | src/core/question_bank.gd:45<br>（共 5 处） |
| 25 | `complete_reward` | data/chapters/ch01_levels.json:10<br>data/chapters/ch02_levels.json:11<br>data/chapters/ch03_levels.json:11<br>（共 8 处） | src/autoload/chapter_flow.gd:77<br>（共 3 处） |
| 26 | `content_status` | data/chapters/ch02_levels.json:33 | src/core/ch02_checks.gd:49<br>（共 12 处） |
| 27 | `count` | data/labs/ch01_labs.json:190 | src/core/ch03_checks.gd:194<br>（共 6 处） |
| 28 | `coverage_max` | data/labs/ch01_labs.json:45 | src/ui/screens/lab_binary.gd:112 |
| 29 | `currency` | data/economy/prices.json:4 | src/core/catalog.gd:29<br>（共 2 处） |
| 30 | `data` | data/labs/ch07_labs.json:70 | src/core/ch04_checks.gd:356<br>（共 3 处） |
| 31 | `data_key` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/data_db.gd:131<br>（共 5 处） |
| 32 | `datapath` | data/labs/ch05_labs.json:7 | src/core/ch05_checks.gd:132 |
| 33 | `deferred_reason` | data/chapters/ch02_levels.json:33 | src/core/chapter_runtime.gd:106 |
| 34 | `delay` | data/labs/ch16_labs.json:473<br>data/labs/ch17_labs.json:307<br>data/labs/ch18_labs.json:674<br>（共 5 处） | src/core/ch02_checks.gd:108<br>（共 8 处） |
| 35 | `demorgan` | data/labs/ch01_labs.json:86 | src/core/lab_checks.gd:89<br>（共 16 处） |
| 36 | `desc` | data/items/items.json:5<br>data/skilltree.json:5 | src/core/catalog.gd:49<br>（共 5 处） |
| 37 | `device` | data/labs/ch02_labs.json:25 | src/core/ch02_checks.gd:147<br>（共 5 处） |
| 38 | `devices` | data/labs/ch04_labs.json:186 | src/core/ch04_checks.gd:416 |
| 39 | `dff` | data/sim/delays.json:15 | src/sim/sim_delays.gd:35 |
| 40 | `distractor_notes` | data/questions/ch02_exercises.json:48<br>data/questions/ch03_exercises.json:25<br>data/questions/ch04_exercises.json:245<br>（共 4 处） | src/core/question_bank.gd:104 |
| 41 | `drivers` | data/labs/ch04_labs.json:184 | src/core/ch04_checks.gd:387 |
| 42 | `economy` | data/chapters/ch02_levels.json:13 | src/core/chapter_runtime.gd:230<br>（共 2 处） |
| 43 | `effects` | data/skilltree.json:182 | src/core/economy_core.gd:13<br>（共 2 处） |
| 44 | `encapsulation` | data/labs/ch01_labs.json:119 | src/core/ch04_checks.gd:42<br>（共 3 处） |
| 45 | `equal_id_tol` | data/labs/ch02_labs.json:49 | src/core/ch02_checks.gd:210<br>（共 2 处） |
| 46 | `equal_id_vds` | data/labs/ch02_labs.json:49 | src/core/ch02_checks.gd:197<br>（共 4 处） |
| 47 | `events` | data/labs/ch08_labs.json:68<br>data/labs/ch10_labs.json:301 | src/core/ch08_checks.gd:147<br>（共 14 处） |
| 48 | `expect` | data/labs/ch01_labs.json:26<br>data/labs/ch02_labs.json:79<br>data/labs/ch03_labs.json:33<br>（共 8 处） | src/core/ch02_checks.gd:265<br>（共 11 处） |
| 49 | `expect_accum_bits` | data/labs/ch07_labs.json:119 | src/core/ch07_checks.gd:263 |
| 50 | `expect_bit_us` | data/labs/ch07_labs.json:36 | src/core/ch07_checks.gd:90<br>（共 2 处） |
| 51 | `expect_bytes` | data/labs/ch06_labs.json:31<br>data/labs/ch10_labs.json:660 | src/core/ch06_checks.gd:85<br>（共 4 处） |
| 52 | `expect_cases` | data/labs/ch09_labs.json:873<br>data/labs/ch10_labs.json:514 | src/core/net_lab_kit.gd:157 |
| 53 | `expect_chars` | data/labs/ch06_labs.json:31 | src/core/ch06_checks.gd:86 |
| 54 | `expect_final` | data/labs/ch05_labs.json:101 | src/core/ch05_checks.gd:184 |
| 55 | `expect_freqs` | data/labs/ch06_labs.json:106 | src/core/ch06_checks.gd:207 |
| 56 | `expect_half_us` | data/labs/ch07_labs.json:36 | src/core/ch07_checks.gd:91 |
| 57 | `expect_hi` | data/labs/ch06_labs.json:37 | src/core/ch06_checks.gd:115 |
| 58 | `expect_jumps` | data/labs/ch05_labs.json:147 | src/core/ch05_checks.gd:357 |
| 59 | `expect_keycode` | data/labs/ch06_labs.json:71 | src/core/ch06_checks.gd:125<br>（共 2 处） |
| 60 | `expect_lines` | data/labs/ch05_labs.json:46 | src/core/ch05_checks.gd:131 |
| 61 | `expect_lo` | data/labs/ch06_labs.json:37 | src/core/ch06_checks.gd:114 |
| 62 | `expect_meta` | data/labs/ch09_labs.json:136<br>data/labs/ch10_labs.json:140<br>data/labs/ch11_labs.json:152<br>（共 12 处） | src/core/net_lab_kit.gd:136<br>（共 5 处） |
| 63 | `expect_mode` | data/labs/ch03_labs.json:108 | src/core/ch03_checks.gd:262<br>（共 2 处） |
| 64 | `expect_mw` | data/labs/ch02_labs.json:160 | src/core/ch02_checks.gd:379<br>（共 3 处） |
| 65 | `expect_offset_us` | data/labs/ch07_labs.json:119 | src/core/ch07_checks.gd:262 |
| 66 | `expect_opcodes` | data/labs/ch05_labs.json:113 | src/core/ch05_checks.gd:280 |
| 67 | `expect_out` | data/labs/ch05_labs.json:144 | src/core/ch05_checks.gd:318<br>（共 2 处） |
| 68 | `expect_prefix` | data/labs/ch06_labs.json:31 | src/core/ch06_checks.gd:104 |
| 69 | `expect_pressed` | data/labs/ch06_labs.json:75 | src/core/ch06_checks.gd:180 |
| 70 | `expect_ratio` | data/labs/ch02_labs.json:161<br>data/labs/ch06_labs.json:110 | src/core/ch02_checks.gd:391<br>（共 4 处） |
| 71 | `expect_region` | data/labs/ch02_labs.json:44 | src/core/ch02_checks.gd:158 |
| 72 | `expect_regs` | data/labs/ch05_labs.json:144 | src/core/ch05_checks.gd:319 |
| 73 | `expect_repeatable` | data/labs/ch10_labs.json:312 | src/core/net_lab_kit.gd:390 |
| 74 | `expect_rows` | data/labs/ch09_labs.json:114<br>data/labs/ch10_labs.json:113<br>data/labs/ch11_labs.json:115<br>（共 12 处） | src/core/net_lab_kit.gd:73<br>（共 3 处） |
| 75 | `expect_state_after_drop` | data/labs/ch10_labs.json:311 | src/core/net_lab_kit.gd:371 |
| 76 | `expect_sum` | data/labs/ch03_labs.json:100 | src/core/ch03_checks.gd:224 |
| 77 | `expect_text` | data/labs/ch06_labs.json:31 | src/core/ch06_checks.gd:84 |
| 78 | `expect_ticks` | data/labs/ch05_labs.json:101 | src/core/ch05_checks.gd:191 |
| 79 | `expect_values` | data/labs/ch10_labs.json:689<br>data/labs/ch11_labs.json:195<br>data/labs/ch12_labs.json:170<br>（共 11 处） | src/core/net_lab_kit.gd:292 |
| 80 | `expected` | data/labs/ch01_labs.json:82<br>data/labs/ch02_labs.json:78 | src/core/black_box.gd:51<br>（共 21 处） |
| 81 | `expected_path` | data/labs/ch08_labs.json:73 | src/core/ch08_checks.gd:214 |
| 82 | `extra_stages` | data/labs/ch03_labs.json:106 | src/core/ch03_checks.gd:248 |
| 83 | `f_hz` | data/labs/ch02_labs.json:154 | src/core/ch02_checks.gd:502<br>（共 2 处） |
| 84 | `fields` | data/labs/ch07_labs.json:68 | src/core/ch07_checks.gd:105<br>（共 6 处） |
| 85 | `files` | data/manifest.json:3 | src/autoload/data_db.gd:37<br>（共 2 处） |
| 86 | `final_signal` | data/labs/ch05_labs.json:35 | src/core/waveform_align.gd:53<br>（共 2 处） |
| 87 | `fix` | data/labs/ch01_labs.json:143 | src/core/lab_checks.gd:247<br>（共 3 处） |
| 88 | `flip_bit` | data/labs/ch07_labs.json:157 | src/core/ch07_checks.gd:359 |
| 89 | `format` | data/questions/ch01_exercises.json:3<br>data/questions/ch02_exercises.json:3<br>data/questions/ch03_exercises.json:3<br>（共 6 处） | src/core/question_bank.gd:43<br>（共 6 处） |
| 90 | `frame` | data/sim/delays.json:20 | src/core/ch06_checks.gd:417<br>（共 3 处） |
| 91 | `gate` | data/labs/ch01_labs.json:94<br>data/questions/ch02_exercises.json:12<br>data/questions/ch03_exercises.json:12<br>（共 5 处） | src/autoload/data_db.gd:253<br>（共 24 处） |
| 92 | `gate_cases` | data/labs/ch01_labs.json:25<br>data/labs/ch02_labs.json:42<br>data/labs/ch03_labs.json:29<br>（共 20 处） | src/autoload/data_db.gd:132<br>（共 30 处） |
| 93 | `gate_delay` | data/sim/delays.json:5 | src/autoload/data_db.gd:232<br>（共 2 处） |
| 94 | `gate_ids` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/chapter_flow.gd:29<br>（共 5 处） |
| 95 | `gates` | data/labs/ch01_labs.json:81<br>data/labs/ch03_labs.json:21<br>data/labs/ch04_labs.json:23<br>（共 20 处） | src/core/ch02_checks.gd:292<br>（共 22 处） |
| 96 | `gold_award` | data/skilltree.json:16 | src/core/chapter_runtime.gd:233<br>（共 4 处） |
| 97 | `grants` | data/labs/ch01_labs.json:122<br>data/labs/ch02_labs.json:58<br>data/labs/ch03_labs.json:41<br>（共 20 处） | src/core/chapter_runtime.gd:66<br>（共 2 处） |
| 98 | `groups` | data/labs/ch04_labs.json:148 | src/core/ch03_checks.gd:166<br>（共 3 处） |
| 99 | `hazard` | data/labs/ch01_labs.json:142 | src/core/signal_lab_model.gd:37<br>（共 3 处） |
| 100 | `hidden` | data/items/items.json:91 | src/ui/screens/lab_craft.gd:97 |
| 101 | `high_addr` | data/labs/ch04_labs.json:150 | src/core/ch04_checks.gd:340<br>（共 2 处） |
| 102 | `hint` | data/labs/ch01_labs.json:23<br>data/labs/ch02_labs.json:40<br>data/labs/ch03_labs.json:27<br>（共 20 处） | src/ui/screens/lab_binary.gd:66<br>（共 7 处） |
| 103 | `hold_required` | data/labs/ch03_labs.json:142 | src/core/ch03_checks.gd:352 |
| 104 | `id` | data/chapters/ch01_levels.json:3<br>data/chapters/ch02_levels.json:3<br>data/chapters/ch03_levels.json:3<br>（共 38 处） | src/autoload/data_db.gd:70<br>（共 248 处） |
| 105 | `illegal_opcodes` | data/labs/ch04_labs.json:113 | src/core/ch04_checks.gd:242 |
| 106 | `input_ids` | data/labs/ch01_labs.json:114<br>data/labs/ch02_labs.json:101 | src/core/ch02_checks.gd:417<br>（共 10 处） |
| 107 | `inputs` | data/economy/recipes.json:12<br>data/labs/ch01_labs.json:82<br>data/labs/ch04_labs.json:36 | src/autoload/data_db.gd:157<br>（共 37 处） |
| 108 | `instances` | data/labs/ch03_labs.json:67 | src/core/ch03_checks.gd:159<br>（共 3 处） |
| 109 | `inverters` | data/labs/ch03_labs.json:136 | src/core/ch03_checks.gd:272<br>（共 2 处） |
| 110 | `isa` | data/labs/ch05_labs.json:75 | src/core/ch05_checks.gd:231 |
| 111 | `items` | data/items/items.json:4<br>data/questions/ch01_exercises.json:7<br>data/questions/ch02_exercises.json:7<br>（共 6 处） | src/autoload/data_db.gd:211<br>（共 6 处） |
| 112 | `key_items` | data/economy/recipes.json:15 | src/autoload/data_db.gd:158<br>（共 3 处） |
| 113 | `keys` | data/labs/ch09_labs.json:108<br>data/labs/ch10_labs.json:108<br>data/labs/ch11_labs.json:108<br>（共 12 处） | src/core/net_lab_kit.gd:74 |
| 114 | `kind` | data/items/items.json:5<br>data/labs/ch01_labs.json:26<br>data/labs/ch02_labs.json:43<br>（共 22 处） | src/autoload/knowledge.gd:13<br>（共 123 处） |
| 115 | `knowledge` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/chapter_flow.gd:47<br>（共 21 处） |
| 116 | `knowledge_cards` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/chapter_flow.gd:53<br>（共 5 处） |
| 117 | `lab` | data/chapters/ch01_levels.json:21<br>data/chapters/ch02_levels.json:37<br>data/chapters/ch03_levels.json:20<br>（共 12 处） | src/core/chapter_runtime.gd:154<br>（共 19 处） |
| 118 | `label` | data/labs/ch01_labs.json:47 | src/core/circuit_graph.gd:17<br>（共 28 处） |
| 119 | `labs` | data/chapters/ch01_levels.json:12<br>data/chapters/ch02_levels.json:29<br>data/chapters/ch03_levels.json:13<br>（共 28 处） | src/core/ch02_checks.gd:62<br>（共 13 处） |
| 120 | `layer` | data/items/items.json:5 | src/core/ch08_checks.gd:77<br>（共 36 处） |
| 121 | `layers` | data/labs/ch08_labs.json:30 | src/core/ch08_checks.gd:62<br>（共 7 处） |
| 122 | `legacy` | data/items/items.json:91<br>data/skilltree.json:176 | src/ui/screens/shop_screen.gd:354<br>（共 2 处） |
| 123 | `legal_opcodes` | data/labs/ch04_labs.json:117 | src/core/ch04_checks.gd:276 |
| 124 | `level` | data/labs/ch03_labs.json:21<br>data/labs/ch04_labs.json:23<br>data/labs/ch05_labs.json:21<br>（共 19 处） | src/ui/main.gd:536<br>（共 5 处） |
| 125 | `levels` | data/labs/ch04_labs.json:36 | src/core/ch04_checks.gd:134<br>（共 4 处） |
| 126 | `limits` | data/sim/delays.json:25 | src/sim/sim_delays.gd:41 |
| 127 | `line` | data/labs/ch11_labs.json:117 | src/core/ch04_checks.gd:388<br>（共 5 处） |
| 128 | `low_addr` | data/labs/ch04_labs.json:150 | src/core/ch04_checks.gd:338<br>（共 2 处） |
| 129 | `max` | data/labs/ch01_labs.json:21<br>data/labs/ch02_labs.json:136 | src/core/ch02_checks.gd:352<br>（共 15 处） |
| 130 | `max_delay` | data/labs/ch01_labs.json:125<br>data/labs/ch02_labs.json:130 | src/core/ch02_checks.gd:352<br>（共 2 处） |
| 131 | `max_gates` | data/labs/ch01_labs.json:112<br>data/labs/ch02_labs.json:74 | src/core/ch02_checks.gd:286<br>（共 12 处） |
| 132 | `max_id_ua` | data/labs/ch02_labs.json:44 | src/core/ch02_checks.gd:173<br>（共 3 处） |
| 133 | `max_int_ticks` | data/labs/ch06_labs.json:71 | src/core/ch06_checks.gd:126<br>（共 2 处） |
| 134 | `max_ron_ohm` | data/labs/ch02_labs.json:46 | src/core/ch02_checks.gd:178<br>（共 3 处） |
| 135 | `max_ticks` | data/labs/ch05_labs.json:32 | src/core/ch05_checks.gd:101<br>（共 3 处） |
| 136 | `milestone` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/chapter_flow.gd:50<br>（共 9 处） |
| 137 | `min_frames` | data/labs/ch08_labs.json:105 | src/core/ch08_checks.gd:236 |
| 138 | `min_width` | data/labs/ch01_labs.json:142 | src/core/lab_checks.gd:242<br>（共 2 处） |
| 139 | `misconception` | data/labs/ch01_labs.json:24<br>data/labs/ch02_labs.json:41<br>data/labs/ch03_labs.json:28<br>（共 20 处） | src/ui/screens/lab_base.gd:541<br>（共 3 处） |
| 140 | `name` | data/economy/recipes.json:7<br>data/items/items.json:5<br>data/labs/ch01_labs.json:82<br>（共 4 处） | src/core/catalog.gd:46<br>（共 23 处） |
| 141 | `next_chapter` | data/chapters/ch01_levels.json:11<br>data/chapters/ch02_levels.json:12<br>data/chapters/ch03_levels.json:12<br>（共 8 处） | src/core/chapter_registry.gd:82<br>（共 2 处） |
| 142 | `nodes` | data/skilltree.json:9 | src/core/circuit_graph.gd:211<br>（共 3 处） |
| 143 | `note` | data/questions/ch01_exercises.json:6<br>data/questions/ch02_exercises.json:6<br>data/questions/ch03_exercises.json:6<br>（共 7 处） | src/ui/widgets/section_reader.gd:82 |
| 144 | `number` | data/chapters/ch01_levels.json:4<br>data/chapters/ch02_levels.json:4<br>data/chapters/ch03_levels.json:4<br>（共 8 处） | src/core/chapter_registry.gd:77<br>（共 10 处） |
| 145 | `objective` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/chapter_flow.gd:16<br>（共 9 处） |
| 146 | `objectives` | data/chapters/ch01_levels.json:20<br>data/chapters/ch02_levels.json:36<br>data/chapters/ch03_levels.json:19<br>（共 8 处） | src/core/chapter_runtime.gd:15<br>（共 9 处） |
| 147 | `offset_ratio` | data/labs/ch07_labs.json:114 | src/core/ch07_checks.gd:206<br>（共 4 处） |
| 148 | `opcode_ports` | data/labs/ch04_labs.json:71 | src/core/ch04_checks.gd:192<br>（共 4 处） |
| 149 | `operands` | data/labs/ch04_labs.json:68 | src/core/ch04_checks.gd:146 |
| 150 | `ops` | data/economy/recipes.json:11<br>data/labs/ch04_labs.json:67 | src/core/ch04_checks.gd:145<br>（共 3 处） |
| 151 | `options` | data/questions/ch02_exercises.json:41<br>data/questions/ch03_exercises.json:18<br>data/questions/ch04_exercises.json:238<br>（共 4 处） | src/core/question_bank.gd:13<br>（共 5 处） |
| 152 | `order` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 12 处） | src/ui/screens/lab_base.gd:225<br>（共 7 处） |
| 153 | `output` | data/economy/recipes.json:8 | src/autoload/data_db.gd:160<br>（共 6 处） |
| 154 | `output_qty` | data/economy/recipes.json:9 | src/core/economy_core.gd:102 |
| 155 | `outputs` | data/labs/ch01_labs.json:178 | src/autoload/data_db.gd:159<br>（共 23 处） |
| 156 | `p1` | data/labs/ch03_labs.json:18<br>data/labs/ch04_labs.json:20<br>data/labs/ch05_labs.json:18<br>（共 18 处） | src/core/signal_lab_model.gd:42<br>（共 4 处） |
| 157 | `pages` | data/sim/macros.json:26 | src/sim/sim_macro.gd:45<br>（共 2 处） |
| 158 | `palette` | data/labs/ch01_labs.json:114<br>data/labs/ch02_labs.json:98 | src/ui/screens/lab_ch02.gd:268<br>（共 5 处） |
| 159 | `panel` | data/labs/ch11_labs.json:719 | src/ui/main.gd:104<br>（共 25 处） |
| 160 | `part` | data/labs/ch03_labs.json:67 | src/core/ch03_checks.gd:153<br>（共 2 处） |
| 161 | `pending_reason` | data/labs/ch02_labs.json:81<br>data/labs/ch04_labs.json:73<br>data/labs/ch06_labs.json:184<br>（共 17 处） | src/core/ch02_checks.gd:90<br>（共 8 处） |
| 162 | `ports` | data/labs/ch04_labs.json:34 | src/core/ch04_checks.gd:114<br>（共 5 处） |
| 163 | `pos` | data/skilltree.json:10 | src/core/circuit_graph.gd:17<br>（共 21 处） |
| 164 | `power_model` | data/labs/ch02_labs.json:154 | src/ui/screens/lab_ch02.gd:31<br>（共 4 处） |
| 165 | `prereq` | data/skilltree.json:10 | src/core/knowledge_graph.gd:41 |
| 166 | `presets` | data/labs/ch01_labs.json:22<br>data/labs/ch02_labs.json:34 | src/ui/screens/lab_level.gd:65 |
| 167 | `qty` | data/items/items.json:9 | src/core/knowledge_graph.gd:142<br>（共 4 处） |
| 168 | `quiz` | data/labs/ch01_labs.json:50<br>data/labs/ch02_labs.json:50<br>data/labs/ch03_labs.json:24<br>（共 19 处） | src/core/ch02_checks.gd:98<br>（共 34 处） |
| 169 | `rail` | data/labs/ch02_labs.json:72 | src/core/ch02_checks.gd:458 |
| 170 | `random_count` | data/labs/ch03_labs.json:69 | src/core/ch03_checks.gd:167 |
| 171 | `ratio` | data/labs/ch07_labs.json:154 | src/core/ch02_checks.gd:393<br>（共 5 处） |
| 172 | `ratio_tolerance` | data/labs/ch07_labs.json:114 | src/core/ch07_checks.gd:215<br>（共 2 处） |
| 173 | `recipe` | data/items/items.json:5 | src/core/catalog.gd:77<br>（共 4 处） |
| 174 | `recipes` | data/economy/recipes.json:4 | src/core/catalog.gd:30 |
| 175 | `ref` | data/labs/ch02_labs.json:135 | src/core/ch02_checks.gd:308<br>（共 5 处） |
| 176 | `relay` | data/sim/delays.json:45 | src/sim/sim_delays.gd:44 |
| 177 | `required` | data/labs/ch01_labs.json:26<br>data/labs/ch02_labs.json:44<br>data/labs/ch03_labs.json:30<br>（共 20 处） | src/core/ch02_checks.gd:88<br>（共 18 处） |
| 178 | `requirement` | data/chapters/ch02_levels.json:33 | src/core/chapter_runtime.gd:98 |
| 179 | `requires` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 9 处） | src/autoload/data_db.gd:226<br>（共 4 处） |
| 180 | `requires_skill` | data/economy/recipes.json:16 | src/autoload/data_db.gd:172<br>（共 4 处） |
| 181 | `reward` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/chapter_flow.gd:33<br>（共 4 处） |
| 182 | `rows` | data/labs/ch01_labs.json:82<br>data/labs/ch02_labs.json:78<br>data/labs/ch04_labs.json:32 | src/core/black_box.gd:74<br>（共 19 处） |
| 183 | `rubric` | data/questions/ch01_exercises.json:19<br>data/questions/ch02_exercises.json:23<br>data/questions/ch03_exercises.json:56<br>（共 5 处） | src/core/question_bank.gd:74 |
| 184 | `sections` | data/labs/ch01_labs.json:9<br>data/labs/ch02_labs.json:12<br>data/labs/ch03_labs.json:11<br>（共 20 处） | src/ui/teaching.gd:76<br>（共 2 处） |
| 185 | `seed` | data/labs/ch01_labs.json:190 | src/core/deterministic_rng.gd:30<br>（共 5 处） |
| 186 | `sell` | data/economy/prices.json:45 | src/core/catalog.gd:26 |
| 187 | `setup_required` | data/labs/ch03_labs.json:142 | src/core/ch03_checks.gd:351 |
| 188 | `signals` | data/labs/ch04_labs.json:114 | src/core/ch04_checks.gd:244<br>（共 2 处） |
| 189 | `skill_node` | data/chapters/ch01_levels.json:13<br>data/chapters/ch02_levels.json:30<br>data/chapters/ch03_levels.json:14<br>（共 8 处） | src/autoload/chapter_flow.gd:56<br>（共 7 处） |
| 190 | `skill_nodes` | data/chapters/ch01_levels.json:15<br>data/chapters/ch02_levels.json:33 | src/autoload/chapter_flow.gd:55<br>（共 4 处） |
| 191 | `slots` | data/labs/ch02_labs.json:162 | src/core/ch02_checks.gd:403<br>（共 4 处） |
| 192 | `solutions` | data/questions/ch01_exercises.json:14<br>data/questions/ch02_exercises.json:18<br>data/questions/ch03_exercises.json:42<br>（共 5 处） | src/core/question_bank.gd:71 |
| 193 | `stage` | data/labs/ch09_labs.json:154<br>data/labs/ch10_labs.json:159<br>data/labs/ch11_labs.json:378<br>（共 12 处） | src/core/net_lab_kit.gd:424<br>（共 2 处） |
| 194 | `stage_signals` | data/labs/ch05_labs.json:34 | src/core/waveform_align.gd:21 |
| 195 | `stages` | data/labs/ch03_labs.json:73 | src/core/ch03_checks.gd:210<br>（共 24 处） |
| 196 | `start_gold` | data/chapters/ch01_levels.json:8<br>data/chapters/ch02_levels.json:9<br>data/chapters/ch03_levels.json:9<br>（共 8 处） | src/core/chapter_runtime.gd:111<br>（共 2 处） |
| 197 | `start_items` | data/chapters/ch01_levels.json:9<br>data/chapters/ch02_levels.json:10<br>data/chapters/ch03_levels.json:10<br>（共 8 处） | src/core/chapter_runtime.gd:114 |
| 198 | `states` | data/labs/ch02_labs.json:80<br>data/labs/ch03_labs.json:138<br>data/labs/ch08_labs.json:68<br>（共 4 处） | src/core/ch02_checks.gd:466<br>（共 9 处） |
| 199 | `status` | data/labs/ch02_labs.json:81<br>data/labs/ch04_labs.json:73<br>data/labs/ch06_labs.json:175<br>（共 17 处） | src/core/ch02_checks.gd:70<br>（共 5 处） |
| 200 | `stem` | data/questions/ch01_exercises.json:13<br>data/questions/ch02_exercises.json:17<br>data/questions/ch03_exercises.json:17<br>（共 5 处） | src/core/question_bank.gd:66 |
| 201 | `steps` | data/tutorial.json:3 | src/autoload/data_db.gd:236<br>（共 5 处） |
| 202 | `subtitle` | data/chapters/ch01_levels.json:6<br>data/chapters/ch02_levels.json:6<br>data/chapters/ch03_levels.json:6<br>（共 8 处） | src/core/chapter_runtime.gd:38<br>（共 3 处） |
| 203 | `sum` | data/labs/ch03_labs.json:71 | src/core/black_box.gd:120<br>（共 29 处） |
| 204 | `target` | data/labs/ch01_labs.json:65<br>data/labs/ch02_labs.json:101 | src/core/black_box.gd:94<br>（共 19 处） |
| 205 | `targets` | data/labs/ch01_labs.json:46<br>data/labs/ch02_labs.json:162 | src/core/ch02_checks.gd:405<br>（共 5 处） |
| 206 | `tasks` | data/labs/ch01_labs.json:113<br>data/labs/ch02_labs.json:100 | src/core/lab_checks.gd:140<br>（共 6 处） |
| 207 | `text` | data/tutorial.json:7 | src/core/ch06_checks.gd:109<br>（共 12 处） |
| 208 | `ticks` | data/labs/ch03_labs.json:138 | src/core/ch03_checks.gd:284<br>（共 15 处） |
| 209 | `title` | data/chapters/ch01_levels.json:5<br>data/chapters/ch02_levels.json:5<br>data/chapters/ch03_levels.json:5<br>（共 31 处） | src/autoload/chapter_flow.gd:63<br>（共 81 处） |
| 210 | `toggles` | data/labs/ch01_labs.json:143 | src/core/lab_checks.gd:245<br>（共 9 处） |
| 211 | `tol` | data/labs/ch02_labs.json:160<br>data/questions/ch01_exercises.json:150<br>data/questions/ch05_exercises.json:451 | src/core/ch02_checks.gd:380<br>（共 8 处） |
| 212 | `tolerance` | data/labs/ch06_labs.json:106<br>data/labs/ch07_labs.json:36 | src/core/ch06_checks.gd:208<br>（共 5 处） |
| 213 | `topology` | data/labs/ch02_labs.json:71 | src/core/ch02_checks.gd:506 |
| 214 | `tree` | data/skilltree.json:10 | src/core/knowledge_graph.gd:38<br>（共 2 处） |
| 215 | `trigger` | data/tutorial.json:8 | src/autoload/data_db.gd:238<br>（共 2 处） |
| 216 | `type` | data/questions/ch01_exercises.json:12<br>data/questions/ch02_exercises.json:16<br>data/questions/ch03_exercises.json:16<br>（共 6 处） | src/autoload/data_db.gd:249<br>（共 3 处） |
| 217 | `unique_key` | data/labs/ch09_labs.json:113<br>data/labs/ch12_labs.json:108 | src/core/net_lab_kit.gd:86 |
| 218 | `v` | data/labs/ch01_labs.json:26 | src/core/ch04_checks.gd:397<br>（共 10 处） |
| 219 | `v_high_min` | data/labs/ch02_labs.json:72 | src/core/ch02_checks.gd:462<br>（共 3 处） |
| 220 | `v_low_max` | data/labs/ch02_labs.json:72 | src/core/ch02_checks.gd:463<br>（共 3 处） |
| 221 | `value` | data/labs/ch01_labs.json:47 | src/core/bit_math.gd:28<br>（共 32 处） |
| 222 | `vdd` | data/labs/ch02_labs.json:27 | src/core/ch02_checks.gd:459<br>（共 3 处） |
| 223 | `vds` | data/labs/ch02_labs.json:20 | src/core/ch02_checks.gd:149<br>（共 6 处） |
| 224 | `vectors` | data/labs/ch07_labs.json:78 | src/core/ch02_checks.gd:347<br>（共 4 处） |
| 225 | `version` | data/chapters/ch01_levels.json:2<br>data/chapters/ch02_levels.json:2<br>data/chapters/ch03_levels.json:2<br>（共 41 处） | src/autoload/data_db.gd:56<br>（共 17 处） |
| 226 | `vgs` | data/labs/ch02_labs.json:20 | src/core/ch02_checks.gd:148<br>（共 6 处） |
| 227 | `voltage` | data/labs/ch01_labs.json:21 | src/core/voltage_model.gd:15<br>（共 3 处） |
| 228 | `waveform` | data/labs/ch05_labs.json:36 | src/core/ch05_checks.gd:196<br>（共 2 处） |
| 229 | `width` | data/labs/ch03_labs.json:140 | src/core/ch03_checks.gd:320<br>（共 16 处） |
| 230 | `xp_award` | data/skilltree.json:16 | src/core/chapter_runtime.gd:234<br>（共 4 处） |
| 231 | `xp_cost` | data/skilltree.json:182 | src/core/knowledge_graph.gd:55<br>（共 3 处） |
## 附录 C　`src/**` 零引用 `const`（19 条）

口径：`const` 声明在**全部 `src/**/*.gd`（含自身文件）**中都无第二次出现。共 375 条声明 → 356 活 / 19 死。

| # | 常量 | 定义 | 说明 |
|---|---|---|---|
| 1 | `MAX_SETTLE` | `src/core/black_box.gd:8` | 黑盒收敛上限，疑似被参数/局部量取代 |
| 2 | `TAGS` | `src/core/gate_result.gd:47` | 标签总表；实际消费走 `TAG_MAP`（`:81`） |
| 3 | `ALLOWED_CODES` | `src/core/lab_gate_kit.gd:13` | 允许码清单，无引用 |
| 4 | `KIND_FULL_ADDER` | `src/sim/sim_module.gd:13` | 模块 kind 常量，声明后未接线 |
| 5 | `KIND_RIPPLE` | `src/sim/sim_module.gd:14` | 同上 |
| 6 | `KIND_MUX2` | `src/sim/sim_module.gd:15` | 同上 |
| 7 | `KIND_MUX4` | `src/sim/sim_module.gd:16` | 同上 |
| 8 | `KIND_DECODER3` | `src/sim/sim_module.gd:17` | 同上 |
| 9 | `KIND_COMPARATOR4` | `src/sim/sim_module.gd:18` | 同上 |
| 10 | `PANEL_3` | `src/ui/ui_theme.gd:29` | 主题色板留白 |
| 11 | `F_CAPTION` | `src/ui/ui_theme.gd:37` | 字号留白 |
| 12 | `F_TITLE` | `src/ui/ui_theme.gd:44` | 字号留白 |
| 13 | `S1` | `src/ui/ui_theme.gd:47` | 间距留白 |
| 14 | `S4` | `src/ui/ui_theme.gd:50` | 间距留白 |
| 15 | `S5` | `src/ui/ui_theme.gd:51` | 间距留白 |
| 16 | `S6` | `src/ui/ui_theme.gd:52` | 间距留白 |
| 17 | `CONTROL_LG` | `src/ui/ui_theme.gd:54` | 控件尺寸留白 |
| 18 | `HUB_RACK_COUNT` | `src/ui/screens/laboratory_screen.gd:60` | 布局常量，实际用 `RACK_SLOT` |
| 19 | `CAT_COUNT` | `src/ui/screens/lab_craft.gd:20` | 布局常量，分类数由数据决定 |

`JUDGEMENT_KINDS`（`src/sim/sim_circuit.gd:211-221`）不在此表：它在 `record_judgement`（`:223-232`）内部被消费；其中 `static_current` 一项见 §2。

## 附录 B　`GateResult` 失败码逐条（28 条）

| 码 | 常量 | `src` 引用（除 `gate_result.gd`） | 首个调用点 | 判定 |
|---|---|---|---|---|
| 1 | `E_MISSING_GRAPH` | 7 | src/core/black_box.gd:25（1 处） | 活 |
| 2 | `E_BUILD` | 14 | src/core/black_box.gd:32（7 处） | 活 |
| 3 | `E_UNCONNECTED` | 37 | src/core/black_box.gd:28（1 处） | 活 |
| 4 | `E_UNKNOWN_KIND` | 5 | src/core/lab_checks.gd:51（5 处） | 活 |
| 5 | `E_UNKNOWN_TARGET` | 11 | src/core/black_box.gd:93（1 处） | 活 |
| 6 | `E_TRUTH_ROW` | 27 | src/core/black_box.gd:66（3 处） | 活 |
| 7 | `E_TABLE_CELL` | 32 | src/core/ch04_checks.gd:235（3 处） | 活 |
| 8 | `E_DELAY_EXCEED` | 11 | src/core/ch02_checks.gd:359（1 处） | 活 |
| 9 | `E_DELAY_MISMATCH` | 16 | src/core/ch03_checks.gd:245（1 处） | 活 |
| 10 | `E_OUTPUT_MISMATCH` | 100 | src/core/ch04_checks.gd:269（2 处） | 活 |
| 11 | `E_STRUCTURE_SAME` | 1 | src/core/lab_checks.gd:204（1 处） | 活 |
| 12 | `E_ENCAPSULATION` | 5 | src/core/ch03_checks.gd:135（2 处） | 活 |
| 13 | `E_COVERAGE` | 34 | src/core/ch05_checks.gd:293（1 处） | 活 |
| 14 | `E_QUIZ` | 4 | src/core/ch02_checks.gd:230（1 处） | 活 |
| 15 | `E_TARGET_UNREACHED` | 3 | src/core/ch02_checks.gd:431（1 处） | 活 |
| 16 | `E_GLITCH` | 2 | src/core/lab_checks.gd:244（2 处） | 活 |
| 17 | `E_X_ROW` | 5 | src/core/ch02_checks.gd:273（1 处） | 活 |
| 18 | `E_REGION` | 7 | src/core/ch02_checks.gd:163（7 处） | 活 |
| 19 | `E_STATIC_CURRENT` | 0 | — | 死 |
| 20 | `E_RAIL_MARGIN` | 2 | src/core/ch02_checks.gd:482（2 处） | 活 |
| 21 | `E_EQUIV` | 1 | src/core/ch02_checks.gd:343（1 处） | 活 |
| 22 | `E_AREA` | 4 | src/core/ch02_checks.gd:302（4 处） | 活 |
| 23 | `E_POWER_CALC` | 1 | src/core/ch02_checks.gd:383（1 处） | 活 |
| 24 | `E_POWER_RATIO` | 1 | src/core/ch02_checks.gd:395（1 处） | 活 |
| 25 | `E_PENDING` | 2 | src/core/ch02_checks.gd:92（1 处） | 活 |
| 26 | `E_HOLD_TICKS` | 3 | src/core/ch03_checks.gd:274（3 处） | 活 |
| 27 | `E_TIMING_MARGIN` | 4 | src/core/ch03_checks.gd:254（2 处） | 活 |
| 99 | `E_GENERIC` | 12 | src/core/ch02_checks.gd:121（1 处） | 活 |
<!-- REGISTRY:BEGIN -->
## 附录 D　字段路径登记（守卫比对用，勿手改）

口径：`文件 :: 路径`，含 `id` 的对象归一成 `*`，数组元素归一成 `[]`。
守卫（`tests/test_field_registry.gd`）逐条比对；数据里新增未登记路径即判红。

- data/chapters/ch01_levels.json :: *.complete_reward
- data/chapters/ch01_levels.json :: *.id
- data/chapters/ch01_levels.json :: *.labs
- data/chapters/ch01_levels.json :: *.labs[].data_key
- data/chapters/ch01_levels.json :: *.labs[].gate_ids
- data/chapters/ch01_levels.json :: *.labs[].id
- data/chapters/ch01_levels.json :: *.labs[].knowledge
- data/chapters/ch01_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch01_levels.json :: *.labs[].milestone
- data/chapters/ch01_levels.json :: *.labs[].objective
- data/chapters/ch01_levels.json :: *.labs[].order
- data/chapters/ch01_levels.json :: *.labs[].requires
- data/chapters/ch01_levels.json :: *.labs[].reward
- data/chapters/ch01_levels.json :: *.labs[].segs
- data/chapters/ch01_levels.json :: *.labs[].skill_node
- data/chapters/ch01_levels.json :: *.labs[].skill_nodes
- data/chapters/ch01_levels.json :: *.labs[].subtitle
- data/chapters/ch01_levels.json :: *.labs[].title
- data/chapters/ch01_levels.json :: *.next_chapter
- data/chapters/ch01_levels.json :: *.number
- data/chapters/ch01_levels.json :: *.objectives
- data/chapters/ch01_levels.json :: *.objectives[].id
- data/chapters/ch01_levels.json :: *.objectives[].knowledge
- data/chapters/ch01_levels.json :: *.objectives[].lab
- data/chapters/ch01_levels.json :: *.objectives[].title
- data/chapters/ch01_levels.json :: *.source
- data/chapters/ch01_levels.json :: *.start_gold
- data/chapters/ch01_levels.json :: *.start_items
- data/chapters/ch01_levels.json :: *.subtitle
- data/chapters/ch01_levels.json :: *.title
- data/chapters/ch01_levels.json :: *.version
- data/chapters/ch02_levels.json :: *.complete_reward
- data/chapters/ch02_levels.json :: *.economy
- data/chapters/ch02_levels.json :: *.id
- data/chapters/ch02_levels.json :: *.labs
- data/chapters/ch02_levels.json :: *.labs[].content_status
- data/chapters/ch02_levels.json :: *.labs[].data_key
- data/chapters/ch02_levels.json :: *.labs[].deferred_reason
- data/chapters/ch02_levels.json :: *.labs[].gate_ids
- data/chapters/ch02_levels.json :: *.labs[].id
- data/chapters/ch02_levels.json :: *.labs[].knowledge
- data/chapters/ch02_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch02_levels.json :: *.labs[].milestone
- data/chapters/ch02_levels.json :: *.labs[].objective
- data/chapters/ch02_levels.json :: *.labs[].order
- data/chapters/ch02_levels.json :: *.labs[].requirement
- data/chapters/ch02_levels.json :: *.labs[].requires
- data/chapters/ch02_levels.json :: *.labs[].reward
- data/chapters/ch02_levels.json :: *.labs[].segs
- data/chapters/ch02_levels.json :: *.labs[].skill_node
- data/chapters/ch02_levels.json :: *.labs[].skill_nodes
- data/chapters/ch02_levels.json :: *.labs[].subtitle
- data/chapters/ch02_levels.json :: *.labs[].title
- data/chapters/ch02_levels.json :: *.next_chapter
- data/chapters/ch02_levels.json :: *.number
- data/chapters/ch02_levels.json :: *.objectives
- data/chapters/ch02_levels.json :: *.objectives[].id
- data/chapters/ch02_levels.json :: *.objectives[].knowledge
- data/chapters/ch02_levels.json :: *.objectives[].lab
- data/chapters/ch02_levels.json :: *.objectives[].title
- data/chapters/ch02_levels.json :: *.source
- data/chapters/ch02_levels.json :: *.start_gold
- data/chapters/ch02_levels.json :: *.start_gold_mode
- data/chapters/ch02_levels.json :: *.start_items
- data/chapters/ch02_levels.json :: *.subtitle
- data/chapters/ch02_levels.json :: *.title
- data/chapters/ch02_levels.json :: *.version
- data/chapters/ch03_levels.json :: *.complete_reward
- data/chapters/ch03_levels.json :: *.id
- data/chapters/ch03_levels.json :: *.labs
- data/chapters/ch03_levels.json :: *.labs[].data_key
- data/chapters/ch03_levels.json :: *.labs[].gate_ids
- data/chapters/ch03_levels.json :: *.labs[].id
- data/chapters/ch03_levels.json :: *.labs[].knowledge
- data/chapters/ch03_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch03_levels.json :: *.labs[].milestone
- data/chapters/ch03_levels.json :: *.labs[].objective
- data/chapters/ch03_levels.json :: *.labs[].order
- data/chapters/ch03_levels.json :: *.labs[].requires
- data/chapters/ch03_levels.json :: *.labs[].reward
- data/chapters/ch03_levels.json :: *.labs[].segs
- data/chapters/ch03_levels.json :: *.labs[].skill_node
- data/chapters/ch03_levels.json :: *.labs[].subtitle
- data/chapters/ch03_levels.json :: *.labs[].title
- data/chapters/ch03_levels.json :: *.next_chapter
- data/chapters/ch03_levels.json :: *.number
- data/chapters/ch03_levels.json :: *.objectives
- data/chapters/ch03_levels.json :: *.objectives[].id
- data/chapters/ch03_levels.json :: *.objectives[].knowledge
- data/chapters/ch03_levels.json :: *.objectives[].lab
- data/chapters/ch03_levels.json :: *.objectives[].title
- data/chapters/ch03_levels.json :: *.source
- data/chapters/ch03_levels.json :: *.start_gold
- data/chapters/ch03_levels.json :: *.start_gold_mode
- data/chapters/ch03_levels.json :: *.start_items
- data/chapters/ch03_levels.json :: *.subtitle
- data/chapters/ch03_levels.json :: *.title
- data/chapters/ch03_levels.json :: *.version
- data/chapters/ch04_levels.json :: *.complete_reward
- data/chapters/ch04_levels.json :: *.id
- data/chapters/ch04_levels.json :: *.labs
- data/chapters/ch04_levels.json :: *.labs[].data_key
- data/chapters/ch04_levels.json :: *.labs[].gate_ids
- data/chapters/ch04_levels.json :: *.labs[].id
- data/chapters/ch04_levels.json :: *.labs[].knowledge
- data/chapters/ch04_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch04_levels.json :: *.labs[].milestone
- data/chapters/ch04_levels.json :: *.labs[].objective
- data/chapters/ch04_levels.json :: *.labs[].order
- data/chapters/ch04_levels.json :: *.labs[].requires
- data/chapters/ch04_levels.json :: *.labs[].reward
- data/chapters/ch04_levels.json :: *.labs[].segs
- data/chapters/ch04_levels.json :: *.labs[].skill_node
- data/chapters/ch04_levels.json :: *.labs[].subtitle
- data/chapters/ch04_levels.json :: *.labs[].title
- data/chapters/ch04_levels.json :: *.next_chapter
- data/chapters/ch04_levels.json :: *.number
- data/chapters/ch04_levels.json :: *.objectives
- data/chapters/ch04_levels.json :: *.objectives[].id
- data/chapters/ch04_levels.json :: *.objectives[].knowledge
- data/chapters/ch04_levels.json :: *.objectives[].lab
- data/chapters/ch04_levels.json :: *.objectives[].title
- data/chapters/ch04_levels.json :: *.source
- data/chapters/ch04_levels.json :: *.start_gold
- data/chapters/ch04_levels.json :: *.start_gold_mode
- data/chapters/ch04_levels.json :: *.start_items
- data/chapters/ch04_levels.json :: *.subtitle
- data/chapters/ch04_levels.json :: *.title
- data/chapters/ch04_levels.json :: *.version
- data/chapters/ch05_levels.json :: *.complete_reward
- data/chapters/ch05_levels.json :: *.id
- data/chapters/ch05_levels.json :: *.labs
- data/chapters/ch05_levels.json :: *.labs[].data_key
- data/chapters/ch05_levels.json :: *.labs[].gate_ids
- data/chapters/ch05_levels.json :: *.labs[].id
- data/chapters/ch05_levels.json :: *.labs[].knowledge
- data/chapters/ch05_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch05_levels.json :: *.labs[].milestone
- data/chapters/ch05_levels.json :: *.labs[].objective
- data/chapters/ch05_levels.json :: *.labs[].order
- data/chapters/ch05_levels.json :: *.labs[].requires
- data/chapters/ch05_levels.json :: *.labs[].reward
- data/chapters/ch05_levels.json :: *.labs[].segs
- data/chapters/ch05_levels.json :: *.labs[].skill_node
- data/chapters/ch05_levels.json :: *.labs[].subtitle
- data/chapters/ch05_levels.json :: *.labs[].title
- data/chapters/ch05_levels.json :: *.next_chapter
- data/chapters/ch05_levels.json :: *.number
- data/chapters/ch05_levels.json :: *.objectives
- data/chapters/ch05_levels.json :: *.objectives[].id
- data/chapters/ch05_levels.json :: *.objectives[].knowledge
- data/chapters/ch05_levels.json :: *.objectives[].lab
- data/chapters/ch05_levels.json :: *.objectives[].title
- data/chapters/ch05_levels.json :: *.source
- data/chapters/ch05_levels.json :: *.start_gold
- data/chapters/ch05_levels.json :: *.start_gold_mode
- data/chapters/ch05_levels.json :: *.start_items
- data/chapters/ch05_levels.json :: *.subtitle
- data/chapters/ch05_levels.json :: *.title
- data/chapters/ch05_levels.json :: *.version
- data/chapters/ch06_levels.json :: *.complete_reward
- data/chapters/ch06_levels.json :: *.id
- data/chapters/ch06_levels.json :: *.labs
- data/chapters/ch06_levels.json :: *.labs[].data_key
- data/chapters/ch06_levels.json :: *.labs[].gate_ids
- data/chapters/ch06_levels.json :: *.labs[].id
- data/chapters/ch06_levels.json :: *.labs[].knowledge
- data/chapters/ch06_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch06_levels.json :: *.labs[].milestone
- data/chapters/ch06_levels.json :: *.labs[].objective
- data/chapters/ch06_levels.json :: *.labs[].order
- data/chapters/ch06_levels.json :: *.labs[].requires
- data/chapters/ch06_levels.json :: *.labs[].reward
- data/chapters/ch06_levels.json :: *.labs[].segs
- data/chapters/ch06_levels.json :: *.labs[].skill_node
- data/chapters/ch06_levels.json :: *.labs[].subtitle
- data/chapters/ch06_levels.json :: *.labs[].title
- data/chapters/ch06_levels.json :: *.next_chapter
- data/chapters/ch06_levels.json :: *.number
- data/chapters/ch06_levels.json :: *.objectives
- data/chapters/ch06_levels.json :: *.objectives[].id
- data/chapters/ch06_levels.json :: *.objectives[].knowledge
- data/chapters/ch06_levels.json :: *.objectives[].lab
- data/chapters/ch06_levels.json :: *.objectives[].title
- data/chapters/ch06_levels.json :: *.source
- data/chapters/ch06_levels.json :: *.start_gold
- data/chapters/ch06_levels.json :: *.start_gold_mode
- data/chapters/ch06_levels.json :: *.start_items
- data/chapters/ch06_levels.json :: *.subtitle
- data/chapters/ch06_levels.json :: *.title
- data/chapters/ch06_levels.json :: *.version
- data/chapters/ch07_levels.json :: *.complete_reward
- data/chapters/ch07_levels.json :: *.id
- data/chapters/ch07_levels.json :: *.labs
- data/chapters/ch07_levels.json :: *.labs[].data_key
- data/chapters/ch07_levels.json :: *.labs[].gate_ids
- data/chapters/ch07_levels.json :: *.labs[].id
- data/chapters/ch07_levels.json :: *.labs[].knowledge
- data/chapters/ch07_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch07_levels.json :: *.labs[].milestone
- data/chapters/ch07_levels.json :: *.labs[].objective
- data/chapters/ch07_levels.json :: *.labs[].order
- data/chapters/ch07_levels.json :: *.labs[].requires
- data/chapters/ch07_levels.json :: *.labs[].reward
- data/chapters/ch07_levels.json :: *.labs[].segs
- data/chapters/ch07_levels.json :: *.labs[].skill_node
- data/chapters/ch07_levels.json :: *.labs[].subtitle
- data/chapters/ch07_levels.json :: *.labs[].title
- data/chapters/ch07_levels.json :: *.next_chapter
- data/chapters/ch07_levels.json :: *.number
- data/chapters/ch07_levels.json :: *.objectives
- data/chapters/ch07_levels.json :: *.objectives[].id
- data/chapters/ch07_levels.json :: *.objectives[].knowledge
- data/chapters/ch07_levels.json :: *.objectives[].lab
- data/chapters/ch07_levels.json :: *.objectives[].title
- data/chapters/ch07_levels.json :: *.source
- data/chapters/ch07_levels.json :: *.start_gold
- data/chapters/ch07_levels.json :: *.start_gold_mode
- data/chapters/ch07_levels.json :: *.start_items
- data/chapters/ch07_levels.json :: *.subtitle
- data/chapters/ch07_levels.json :: *.title
- data/chapters/ch07_levels.json :: *.version
- data/chapters/ch08_levels.json :: *.complete_reward
- data/chapters/ch08_levels.json :: *.id
- data/chapters/ch08_levels.json :: *.labs
- data/chapters/ch08_levels.json :: *.labs[].data_key
- data/chapters/ch08_levels.json :: *.labs[].gate_ids
- data/chapters/ch08_levels.json :: *.labs[].id
- data/chapters/ch08_levels.json :: *.labs[].knowledge
- data/chapters/ch08_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch08_levels.json :: *.labs[].milestone
- data/chapters/ch08_levels.json :: *.labs[].objective
- data/chapters/ch08_levels.json :: *.labs[].order
- data/chapters/ch08_levels.json :: *.labs[].requires
- data/chapters/ch08_levels.json :: *.labs[].reward
- data/chapters/ch08_levels.json :: *.labs[].segs
- data/chapters/ch08_levels.json :: *.labs[].skill_node
- data/chapters/ch08_levels.json :: *.labs[].subtitle
- data/chapters/ch08_levels.json :: *.labs[].title
- data/chapters/ch08_levels.json :: *.next_chapter
- data/chapters/ch08_levels.json :: *.number
- data/chapters/ch08_levels.json :: *.objectives
- data/chapters/ch08_levels.json :: *.objectives[].id
- data/chapters/ch08_levels.json :: *.objectives[].knowledge
- data/chapters/ch08_levels.json :: *.objectives[].lab
- data/chapters/ch08_levels.json :: *.objectives[].title
- data/chapters/ch08_levels.json :: *.source
- data/chapters/ch08_levels.json :: *.start_gold
- data/chapters/ch08_levels.json :: *.start_gold_mode
- data/chapters/ch08_levels.json :: *.start_items
- data/chapters/ch08_levels.json :: *.subtitle
- data/chapters/ch08_levels.json :: *.title
- data/chapters/ch08_levels.json :: *.version
- data/chapters/ch09_levels.json :: *.complete_reward
- data/chapters/ch09_levels.json :: *.id
- data/chapters/ch09_levels.json :: *.labs
- data/chapters/ch09_levels.json :: *.labs[].data_key
- data/chapters/ch09_levels.json :: *.labs[].gate_ids
- data/chapters/ch09_levels.json :: *.labs[].id
- data/chapters/ch09_levels.json :: *.labs[].knowledge
- data/chapters/ch09_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch09_levels.json :: *.labs[].milestone
- data/chapters/ch09_levels.json :: *.labs[].objective
- data/chapters/ch09_levels.json :: *.labs[].order
- data/chapters/ch09_levels.json :: *.labs[].requires
- data/chapters/ch09_levels.json :: *.labs[].reward
- data/chapters/ch09_levels.json :: *.labs[].segs
- data/chapters/ch09_levels.json :: *.labs[].skill_node
- data/chapters/ch09_levels.json :: *.labs[].subtitle
- data/chapters/ch09_levels.json :: *.labs[].title
- data/chapters/ch09_levels.json :: *.next_chapter
- data/chapters/ch09_levels.json :: *.number
- data/chapters/ch09_levels.json :: *.objectives
- data/chapters/ch09_levels.json :: *.objectives[].id
- data/chapters/ch09_levels.json :: *.objectives[].knowledge
- data/chapters/ch09_levels.json :: *.objectives[].lab
- data/chapters/ch09_levels.json :: *.objectives[].title
- data/chapters/ch09_levels.json :: *.source
- data/chapters/ch09_levels.json :: *.start_gold
- data/chapters/ch09_levels.json :: *.start_gold_mode
- data/chapters/ch09_levels.json :: *.start_items
- data/chapters/ch09_levels.json :: *.subtitle
- data/chapters/ch09_levels.json :: *.title
- data/chapters/ch09_levels.json :: *.version
- data/chapters/ch10_levels.json :: *.complete_reward
- data/chapters/ch10_levels.json :: *.id
- data/chapters/ch10_levels.json :: *.labs
- data/chapters/ch10_levels.json :: *.labs[].data_key
- data/chapters/ch10_levels.json :: *.labs[].gate_ids
- data/chapters/ch10_levels.json :: *.labs[].id
- data/chapters/ch10_levels.json :: *.labs[].knowledge
- data/chapters/ch10_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch10_levels.json :: *.labs[].milestone
- data/chapters/ch10_levels.json :: *.labs[].objective
- data/chapters/ch10_levels.json :: *.labs[].order
- data/chapters/ch10_levels.json :: *.labs[].requires
- data/chapters/ch10_levels.json :: *.labs[].reward
- data/chapters/ch10_levels.json :: *.labs[].segs
- data/chapters/ch10_levels.json :: *.labs[].skill_node
- data/chapters/ch10_levels.json :: *.labs[].subtitle
- data/chapters/ch10_levels.json :: *.labs[].title
- data/chapters/ch10_levels.json :: *.next_chapter
- data/chapters/ch10_levels.json :: *.number
- data/chapters/ch10_levels.json :: *.objectives
- data/chapters/ch10_levels.json :: *.objectives[].id
- data/chapters/ch10_levels.json :: *.objectives[].knowledge
- data/chapters/ch10_levels.json :: *.objectives[].lab
- data/chapters/ch10_levels.json :: *.objectives[].title
- data/chapters/ch10_levels.json :: *.source
- data/chapters/ch10_levels.json :: *.start_gold
- data/chapters/ch10_levels.json :: *.start_gold_mode
- data/chapters/ch10_levels.json :: *.start_items
- data/chapters/ch10_levels.json :: *.subtitle
- data/chapters/ch10_levels.json :: *.title
- data/chapters/ch10_levels.json :: *.version
- data/chapters/ch11_levels.json :: *.complete_reward
- data/chapters/ch11_levels.json :: *.id
- data/chapters/ch11_levels.json :: *.labs
- data/chapters/ch11_levels.json :: *.labs[].data_key
- data/chapters/ch11_levels.json :: *.labs[].gate_ids
- data/chapters/ch11_levels.json :: *.labs[].id
- data/chapters/ch11_levels.json :: *.labs[].knowledge
- data/chapters/ch11_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch11_levels.json :: *.labs[].milestone
- data/chapters/ch11_levels.json :: *.labs[].objective
- data/chapters/ch11_levels.json :: *.labs[].order
- data/chapters/ch11_levels.json :: *.labs[].requires
- data/chapters/ch11_levels.json :: *.labs[].reward
- data/chapters/ch11_levels.json :: *.labs[].segs
- data/chapters/ch11_levels.json :: *.labs[].skill_node
- data/chapters/ch11_levels.json :: *.labs[].subtitle
- data/chapters/ch11_levels.json :: *.labs[].title
- data/chapters/ch11_levels.json :: *.next_chapter
- data/chapters/ch11_levels.json :: *.number
- data/chapters/ch11_levels.json :: *.objectives
- data/chapters/ch11_levels.json :: *.objectives[].id
- data/chapters/ch11_levels.json :: *.objectives[].knowledge
- data/chapters/ch11_levels.json :: *.objectives[].lab
- data/chapters/ch11_levels.json :: *.objectives[].title
- data/chapters/ch11_levels.json :: *.source
- data/chapters/ch11_levels.json :: *.start_gold
- data/chapters/ch11_levels.json :: *.start_gold_mode
- data/chapters/ch11_levels.json :: *.start_items
- data/chapters/ch11_levels.json :: *.subtitle
- data/chapters/ch11_levels.json :: *.title
- data/chapters/ch11_levels.json :: *.version
- data/chapters/ch12_levels.json :: *.complete_reward
- data/chapters/ch12_levels.json :: *.id
- data/chapters/ch12_levels.json :: *.labs
- data/chapters/ch12_levels.json :: *.labs[].data_key
- data/chapters/ch12_levels.json :: *.labs[].gate_ids
- data/chapters/ch12_levels.json :: *.labs[].id
- data/chapters/ch12_levels.json :: *.labs[].knowledge
- data/chapters/ch12_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch12_levels.json :: *.labs[].milestone
- data/chapters/ch12_levels.json :: *.labs[].objective
- data/chapters/ch12_levels.json :: *.labs[].order
- data/chapters/ch12_levels.json :: *.labs[].requires
- data/chapters/ch12_levels.json :: *.labs[].reward
- data/chapters/ch12_levels.json :: *.labs[].segs
- data/chapters/ch12_levels.json :: *.labs[].skill_node
- data/chapters/ch12_levels.json :: *.labs[].subtitle
- data/chapters/ch12_levels.json :: *.labs[].title
- data/chapters/ch12_levels.json :: *.next_chapter
- data/chapters/ch12_levels.json :: *.number
- data/chapters/ch12_levels.json :: *.objectives
- data/chapters/ch12_levels.json :: *.objectives[].id
- data/chapters/ch12_levels.json :: *.objectives[].knowledge
- data/chapters/ch12_levels.json :: *.objectives[].lab
- data/chapters/ch12_levels.json :: *.objectives[].title
- data/chapters/ch12_levels.json :: *.source
- data/chapters/ch12_levels.json :: *.start_gold
- data/chapters/ch12_levels.json :: *.start_gold_mode
- data/chapters/ch12_levels.json :: *.start_items
- data/chapters/ch12_levels.json :: *.subtitle
- data/chapters/ch12_levels.json :: *.title
- data/chapters/ch12_levels.json :: *.version
- data/chapters/ch13_levels.json :: *.complete_reward
- data/chapters/ch13_levels.json :: *.id
- data/chapters/ch13_levels.json :: *.labs
- data/chapters/ch13_levels.json :: *.labs[].data_key
- data/chapters/ch13_levels.json :: *.labs[].gate_ids
- data/chapters/ch13_levels.json :: *.labs[].id
- data/chapters/ch13_levels.json :: *.labs[].knowledge
- data/chapters/ch13_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch13_levels.json :: *.labs[].milestone
- data/chapters/ch13_levels.json :: *.labs[].objective
- data/chapters/ch13_levels.json :: *.labs[].order
- data/chapters/ch13_levels.json :: *.labs[].requires
- data/chapters/ch13_levels.json :: *.labs[].reward
- data/chapters/ch13_levels.json :: *.labs[].segs
- data/chapters/ch13_levels.json :: *.labs[].skill_node
- data/chapters/ch13_levels.json :: *.labs[].subtitle
- data/chapters/ch13_levels.json :: *.labs[].title
- data/chapters/ch13_levels.json :: *.next_chapter
- data/chapters/ch13_levels.json :: *.number
- data/chapters/ch13_levels.json :: *.objectives
- data/chapters/ch13_levels.json :: *.objectives[].id
- data/chapters/ch13_levels.json :: *.objectives[].knowledge
- data/chapters/ch13_levels.json :: *.objectives[].lab
- data/chapters/ch13_levels.json :: *.objectives[].title
- data/chapters/ch13_levels.json :: *.source
- data/chapters/ch13_levels.json :: *.start_gold
- data/chapters/ch13_levels.json :: *.start_gold_mode
- data/chapters/ch13_levels.json :: *.start_items
- data/chapters/ch13_levels.json :: *.subtitle
- data/chapters/ch13_levels.json :: *.title
- data/chapters/ch13_levels.json :: *.version
- data/chapters/ch14_levels.json :: *.complete_reward
- data/chapters/ch14_levels.json :: *.id
- data/chapters/ch14_levels.json :: *.labs
- data/chapters/ch14_levels.json :: *.labs[].data_key
- data/chapters/ch14_levels.json :: *.labs[].gate_ids
- data/chapters/ch14_levels.json :: *.labs[].id
- data/chapters/ch14_levels.json :: *.labs[].knowledge
- data/chapters/ch14_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch14_levels.json :: *.labs[].milestone
- data/chapters/ch14_levels.json :: *.labs[].objective
- data/chapters/ch14_levels.json :: *.labs[].order
- data/chapters/ch14_levels.json :: *.labs[].requires
- data/chapters/ch14_levels.json :: *.labs[].reward
- data/chapters/ch14_levels.json :: *.labs[].segs
- data/chapters/ch14_levels.json :: *.labs[].skill_node
- data/chapters/ch14_levels.json :: *.labs[].subtitle
- data/chapters/ch14_levels.json :: *.labs[].title
- data/chapters/ch14_levels.json :: *.next_chapter
- data/chapters/ch14_levels.json :: *.number
- data/chapters/ch14_levels.json :: *.objectives
- data/chapters/ch14_levels.json :: *.objectives[].id
- data/chapters/ch14_levels.json :: *.objectives[].knowledge
- data/chapters/ch14_levels.json :: *.objectives[].lab
- data/chapters/ch14_levels.json :: *.objectives[].title
- data/chapters/ch14_levels.json :: *.source
- data/chapters/ch14_levels.json :: *.start_gold
- data/chapters/ch14_levels.json :: *.start_gold_mode
- data/chapters/ch14_levels.json :: *.start_items
- data/chapters/ch14_levels.json :: *.subtitle
- data/chapters/ch14_levels.json :: *.title
- data/chapters/ch14_levels.json :: *.version
- data/chapters/ch15_levels.json :: *.complete_reward
- data/chapters/ch15_levels.json :: *.id
- data/chapters/ch15_levels.json :: *.labs
- data/chapters/ch15_levels.json :: *.labs[].data_key
- data/chapters/ch15_levels.json :: *.labs[].gate_ids
- data/chapters/ch15_levels.json :: *.labs[].id
- data/chapters/ch15_levels.json :: *.labs[].knowledge
- data/chapters/ch15_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch15_levels.json :: *.labs[].milestone
- data/chapters/ch15_levels.json :: *.labs[].objective
- data/chapters/ch15_levels.json :: *.labs[].order
- data/chapters/ch15_levels.json :: *.labs[].requires
- data/chapters/ch15_levels.json :: *.labs[].reward
- data/chapters/ch15_levels.json :: *.labs[].segs
- data/chapters/ch15_levels.json :: *.labs[].skill_node
- data/chapters/ch15_levels.json :: *.labs[].subtitle
- data/chapters/ch15_levels.json :: *.labs[].title
- data/chapters/ch15_levels.json :: *.next_chapter
- data/chapters/ch15_levels.json :: *.number
- data/chapters/ch15_levels.json :: *.objectives
- data/chapters/ch15_levels.json :: *.objectives[].id
- data/chapters/ch15_levels.json :: *.objectives[].knowledge
- data/chapters/ch15_levels.json :: *.objectives[].lab
- data/chapters/ch15_levels.json :: *.objectives[].title
- data/chapters/ch15_levels.json :: *.source
- data/chapters/ch15_levels.json :: *.start_gold
- data/chapters/ch15_levels.json :: *.start_gold_mode
- data/chapters/ch15_levels.json :: *.start_items
- data/chapters/ch15_levels.json :: *.subtitle
- data/chapters/ch15_levels.json :: *.title
- data/chapters/ch15_levels.json :: *.version
- data/chapters/ch16_levels.json :: *.complete_reward
- data/chapters/ch16_levels.json :: *.id
- data/chapters/ch16_levels.json :: *.labs
- data/chapters/ch16_levels.json :: *.labs[].data_key
- data/chapters/ch16_levels.json :: *.labs[].gate_ids
- data/chapters/ch16_levels.json :: *.labs[].id
- data/chapters/ch16_levels.json :: *.labs[].knowledge
- data/chapters/ch16_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch16_levels.json :: *.labs[].milestone
- data/chapters/ch16_levels.json :: *.labs[].objective
- data/chapters/ch16_levels.json :: *.labs[].order
- data/chapters/ch16_levels.json :: *.labs[].requires
- data/chapters/ch16_levels.json :: *.labs[].reward
- data/chapters/ch16_levels.json :: *.labs[].segs
- data/chapters/ch16_levels.json :: *.labs[].skill_node
- data/chapters/ch16_levels.json :: *.labs[].subtitle
- data/chapters/ch16_levels.json :: *.labs[].title
- data/chapters/ch16_levels.json :: *.next_chapter
- data/chapters/ch16_levels.json :: *.number
- data/chapters/ch16_levels.json :: *.objectives
- data/chapters/ch16_levels.json :: *.objectives[].id
- data/chapters/ch16_levels.json :: *.objectives[].knowledge
- data/chapters/ch16_levels.json :: *.objectives[].lab
- data/chapters/ch16_levels.json :: *.objectives[].title
- data/chapters/ch16_levels.json :: *.source
- data/chapters/ch16_levels.json :: *.start_gold
- data/chapters/ch16_levels.json :: *.start_gold_mode
- data/chapters/ch16_levels.json :: *.start_items
- data/chapters/ch16_levels.json :: *.subtitle
- data/chapters/ch16_levels.json :: *.title
- data/chapters/ch16_levels.json :: *.version
- data/chapters/ch17_levels.json :: *.complete_reward
- data/chapters/ch17_levels.json :: *.id
- data/chapters/ch17_levels.json :: *.labs
- data/chapters/ch17_levels.json :: *.labs[].data_key
- data/chapters/ch17_levels.json :: *.labs[].gate_ids
- data/chapters/ch17_levels.json :: *.labs[].id
- data/chapters/ch17_levels.json :: *.labs[].knowledge
- data/chapters/ch17_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch17_levels.json :: *.labs[].milestone
- data/chapters/ch17_levels.json :: *.labs[].objective
- data/chapters/ch17_levels.json :: *.labs[].order
- data/chapters/ch17_levels.json :: *.labs[].requires
- data/chapters/ch17_levels.json :: *.labs[].reward
- data/chapters/ch17_levels.json :: *.labs[].segs
- data/chapters/ch17_levels.json :: *.labs[].skill_node
- data/chapters/ch17_levels.json :: *.labs[].subtitle
- data/chapters/ch17_levels.json :: *.labs[].title
- data/chapters/ch17_levels.json :: *.next_chapter
- data/chapters/ch17_levels.json :: *.number
- data/chapters/ch17_levels.json :: *.objectives
- data/chapters/ch17_levels.json :: *.objectives[].id
- data/chapters/ch17_levels.json :: *.objectives[].knowledge
- data/chapters/ch17_levels.json :: *.objectives[].lab
- data/chapters/ch17_levels.json :: *.objectives[].title
- data/chapters/ch17_levels.json :: *.source
- data/chapters/ch17_levels.json :: *.start_gold
- data/chapters/ch17_levels.json :: *.start_gold_mode
- data/chapters/ch17_levels.json :: *.start_items
- data/chapters/ch17_levels.json :: *.subtitle
- data/chapters/ch17_levels.json :: *.title
- data/chapters/ch17_levels.json :: *.version
- data/chapters/ch18_levels.json :: *.complete_reward
- data/chapters/ch18_levels.json :: *.id
- data/chapters/ch18_levels.json :: *.labs
- data/chapters/ch18_levels.json :: *.labs[].data_key
- data/chapters/ch18_levels.json :: *.labs[].gate_ids
- data/chapters/ch18_levels.json :: *.labs[].id
- data/chapters/ch18_levels.json :: *.labs[].knowledge
- data/chapters/ch18_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch18_levels.json :: *.labs[].milestone
- data/chapters/ch18_levels.json :: *.labs[].objective
- data/chapters/ch18_levels.json :: *.labs[].order
- data/chapters/ch18_levels.json :: *.labs[].requires
- data/chapters/ch18_levels.json :: *.labs[].reward
- data/chapters/ch18_levels.json :: *.labs[].segs
- data/chapters/ch18_levels.json :: *.labs[].skill_node
- data/chapters/ch18_levels.json :: *.labs[].subtitle
- data/chapters/ch18_levels.json :: *.labs[].title
- data/chapters/ch18_levels.json :: *.next_chapter
- data/chapters/ch18_levels.json :: *.number
- data/chapters/ch18_levels.json :: *.objectives
- data/chapters/ch18_levels.json :: *.objectives[].id
- data/chapters/ch18_levels.json :: *.objectives[].knowledge
- data/chapters/ch18_levels.json :: *.objectives[].lab
- data/chapters/ch18_levels.json :: *.objectives[].title
- data/chapters/ch18_levels.json :: *.source
- data/chapters/ch18_levels.json :: *.start_gold
- data/chapters/ch18_levels.json :: *.start_gold_mode
- data/chapters/ch18_levels.json :: *.start_items
- data/chapters/ch18_levels.json :: *.subtitle
- data/chapters/ch18_levels.json :: *.title
- data/chapters/ch18_levels.json :: *.version
- data/chapters/ch19_levels.json :: *.complete_reward
- data/chapters/ch19_levels.json :: *.id
- data/chapters/ch19_levels.json :: *.labs
- data/chapters/ch19_levels.json :: *.labs[].data_key
- data/chapters/ch19_levels.json :: *.labs[].gate_ids
- data/chapters/ch19_levels.json :: *.labs[].id
- data/chapters/ch19_levels.json :: *.labs[].knowledge
- data/chapters/ch19_levels.json :: *.labs[].knowledge_cards
- data/chapters/ch19_levels.json :: *.labs[].milestone
- data/chapters/ch19_levels.json :: *.labs[].objective
- data/chapters/ch19_levels.json :: *.labs[].order
- data/chapters/ch19_levels.json :: *.labs[].requires
- data/chapters/ch19_levels.json :: *.labs[].reward
- data/chapters/ch19_levels.json :: *.labs[].segs
- data/chapters/ch19_levels.json :: *.labs[].skill_node
- data/chapters/ch19_levels.json :: *.labs[].subtitle
- data/chapters/ch19_levels.json :: *.labs[].title
- data/chapters/ch19_levels.json :: *.next_chapter
- data/chapters/ch19_levels.json :: *.number
- data/chapters/ch19_levels.json :: *.objectives
- data/chapters/ch19_levels.json :: *.objectives[].id
- data/chapters/ch19_levels.json :: *.objectives[].knowledge
- data/chapters/ch19_levels.json :: *.objectives[].lab
- data/chapters/ch19_levels.json :: *.objectives[].title
- data/chapters/ch19_levels.json :: *.source
- data/chapters/ch19_levels.json :: *.start_gold
- data/chapters/ch19_levels.json :: *.start_gold_mode
- data/chapters/ch19_levels.json :: *.start_items
- data/chapters/ch19_levels.json :: *.subtitle
- data/chapters/ch19_levels.json :: *.title
- data/chapters/ch19_levels.json :: *.version
- data/economy/prices.json :: buy
- data/economy/prices.json :: currency
- data/economy/prices.json :: sell
- data/economy/prices.json :: sell_ratio
- data/economy/prices.json :: source
- data/economy/prices.json :: version
- data/economy/recipes.json :: recipes
- data/economy/recipes.json :: recipes[].cash
- data/economy/recipes.json :: recipes[].id
- data/economy/recipes.json :: recipes[].inputs
- data/economy/recipes.json :: recipes[].key_items
- data/economy/recipes.json :: recipes[].name
- data/economy/recipes.json :: recipes[].ops
- data/economy/recipes.json :: recipes[].output
- data/economy/recipes.json :: recipes[].output_qty
- data/economy/recipes.json :: recipes[].requires_skill
- data/economy/recipes.json :: recipes[].source_recipe
- data/economy/recipes.json :: source
- data/economy/recipes.json :: version
- data/items/items.json :: generated_from
- data/items/items.json :: items
- data/items/items.json :: items[].acquire
- data/items/items.json :: items[].blueprint
- data/items/items.json :: items[].bound_first
- data/items/items.json :: items[].craft_cost
- data/items/items.json :: items[].craft_ops
- data/items/items.json :: items[].derived
- data/items/items.json :: items[].desc
- data/items/items.json :: items[].hidden
- data/items/items.json :: items[].id
- data/items/items.json :: items[].kind
- data/items/items.json :: items[].layer
- data/items/items.json :: items[].legacy
- data/items/items.json :: items[].name
- data/items/items.json :: items[].price
- data/items/items.json :: items[].recipe
- data/items/items.json :: items[].recipe[].id
- data/items/items.json :: items[].recipe[].qty
- data/items/items.json :: items[].recipe_consume
- data/items/items.json :: items[].reusable
- data/items/items.json :: items[].tags
- data/items/items.json :: items[].unlock_chapter
- data/items/items.json :: items[].uses
- data/items/items.json :: version
- data/labs/ch01_labs.json :: labs
- data/labs/ch01_labs.json :: labs.*.bit_count
- data/labs/ch01_labs.json :: labs.*.body
- data/labs/ch01_labs.json :: labs.*.chain
- data/labs/ch01_labs.json :: labs.*.coverage_max
- data/labs/ch01_labs.json :: labs.*.demorgan
- data/labs/ch01_labs.json :: labs.*.encapsulation
- data/labs/ch01_labs.json :: labs.*.fix
- data/labs/ch01_labs.json :: labs.*.gate_cases
- data/labs/ch01_labs.json :: labs.*.gate_cases[].count
- data/labs/ch01_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch01_labs.json :: labs.*.gate_cases[].expected
- data/labs/ch01_labs.json :: labs.*.gate_cases[].gate
- data/labs/ch01_labs.json :: labs.*.gate_cases[].id
- data/labs/ch01_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch01_labs.json :: labs.*.gate_cases[].max
- data/labs/ch01_labs.json :: labs.*.gate_cases[].max_delay
- data/labs/ch01_labs.json :: labs.*.gate_cases[].min_width
- data/labs/ch01_labs.json :: labs.*.gate_cases[].required
- data/labs/ch01_labs.json :: labs.*.gate_cases[].seed
- data/labs/ch01_labs.json :: labs.*.gate_cases[].target
- data/labs/ch01_labs.json :: labs.*.gate_cases[].title
- data/labs/ch01_labs.json :: labs.*.gate_cases[].toggles
- data/labs/ch01_labs.json :: labs.*.gate_cases[].v
- data/labs/ch01_labs.json :: labs.*.gates
- data/labs/ch01_labs.json :: labs.*.gates[].expected
- data/labs/ch01_labs.json :: labs.*.gates[].id
- data/labs/ch01_labs.json :: labs.*.gates[].inputs
- data/labs/ch01_labs.json :: labs.*.gates[].name
- data/labs/ch01_labs.json :: labs.*.gates[].rows
- data/labs/ch01_labs.json :: labs.*.grants
- data/labs/ch01_labs.json :: labs.*.hazard
- data/labs/ch01_labs.json :: labs.*.hint
- data/labs/ch01_labs.json :: labs.*.id
- data/labs/ch01_labs.json :: labs.*.inputs
- data/labs/ch01_labs.json :: labs.*.inputs[].id
- data/labs/ch01_labs.json :: labs.*.inputs[].label
- data/labs/ch01_labs.json :: labs.*.max_delay
- data/labs/ch01_labs.json :: labs.*.max_gates
- data/labs/ch01_labs.json :: labs.*.misconception
- data/labs/ch01_labs.json :: labs.*.outputs
- data/labs/ch01_labs.json :: labs.*.outputs[].expect
- data/labs/ch01_labs.json :: labs.*.outputs[].id
- data/labs/ch01_labs.json :: labs.*.outputs[].label
- data/labs/ch01_labs.json :: labs.*.palette
- data/labs/ch01_labs.json :: labs.*.presets
- data/labs/ch01_labs.json :: labs.*.quiz
- data/labs/ch01_labs.json :: labs.*.random_cases
- data/labs/ch01_labs.json :: labs.*.rules
- data/labs/ch01_labs.json :: labs.*.sections
- data/labs/ch01_labs.json :: labs.*.targets
- data/labs/ch01_labs.json :: labs.*.targets[].hint
- data/labs/ch01_labs.json :: labs.*.targets[].id
- data/labs/ch01_labs.json :: labs.*.targets[].label
- data/labs/ch01_labs.json :: labs.*.targets[].value
- data/labs/ch01_labs.json :: labs.*.tasks
- data/labs/ch01_labs.json :: labs.*.tasks[].id
- data/labs/ch01_labs.json :: labs.*.tasks[].input_ids
- data/labs/ch01_labs.json :: labs.*.tasks[].palette
- data/labs/ch01_labs.json :: labs.*.tasks[].require_second
- data/labs/ch01_labs.json :: labs.*.tasks[].target
- data/labs/ch01_labs.json :: labs.*.tasks[].title
- data/labs/ch01_labs.json :: labs.*.title
- data/labs/ch01_labs.json :: labs.*.voltage
- data/labs/ch01_labs.json :: source
- data/labs/ch01_labs.json :: version
- data/labs/ch02_labs.json :: labs
- data/labs/ch02_labs.json :: labs.*.board
- data/labs/ch02_labs.json :: labs.*.body
- data/labs/ch02_labs.json :: labs.*.device
- data/labs/ch02_labs.json :: labs.*.gate_cases
- data/labs/ch02_labs.json :: labs.*.gate_cases[].alpha
- data/labs/ch02_labs.json :: labs.*.gate_cases[].c_f
- data/labs/ch02_labs.json :: labs.*.gate_cases[].cadence_tol
- data/labs/ch02_labs.json :: labs.*.gate_cases[].equal_id_tol
- data/labs/ch02_labs.json :: labs.*.gate_cases[].equal_id_vds
- data/labs/ch02_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch02_labs.json :: labs.*.gate_cases[].expect_mw
- data/labs/ch02_labs.json :: labs.*.gate_cases[].expect_ratio
- data/labs/ch02_labs.json :: labs.*.gate_cases[].expect_region
- data/labs/ch02_labs.json :: labs.*.gate_cases[].expected
- data/labs/ch02_labs.json :: labs.*.gate_cases[].f_from
- data/labs/ch02_labs.json :: labs.*.gate_cases[].f_hz
- data/labs/ch02_labs.json :: labs.*.gate_cases[].f_to
- data/labs/ch02_labs.json :: labs.*.gate_cases[].id
- data/labs/ch02_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch02_labs.json :: labs.*.gate_cases[].max
- data/labs/ch02_labs.json :: labs.*.gate_cases[].max_gates
- data/labs/ch02_labs.json :: labs.*.gate_cases[].max_id_ua
- data/labs/ch02_labs.json :: labs.*.gate_cases[].max_ron_ohm
- data/labs/ch02_labs.json :: labs.*.gate_cases[].max_ua
- data/labs/ch02_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch02_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch02_labs.json :: labs.*.gate_cases[].ref
- data/labs/ch02_labs.json :: labs.*.gate_cases[].required
- data/labs/ch02_labs.json :: labs.*.gate_cases[].rows
- data/labs/ch02_labs.json :: labs.*.gate_cases[].slots
- data/labs/ch02_labs.json :: labs.*.gate_cases[].states
- data/labs/ch02_labs.json :: labs.*.gate_cases[].status
- data/labs/ch02_labs.json :: labs.*.gate_cases[].target
- data/labs/ch02_labs.json :: labs.*.gate_cases[].targets
- data/labs/ch02_labs.json :: labs.*.gate_cases[].title
- data/labs/ch02_labs.json :: labs.*.gate_cases[].tol
- data/labs/ch02_labs.json :: labs.*.gate_cases[].v_high_min
- data/labs/ch02_labs.json :: labs.*.gate_cases[].v_low_max
- data/labs/ch02_labs.json :: labs.*.gate_cases[].vdd
- data/labs/ch02_labs.json :: labs.*.gate_cases[].vds
- data/labs/ch02_labs.json :: labs.*.gate_cases[].vgs
- data/labs/ch02_labs.json :: labs.*.grants
- data/labs/ch02_labs.json :: labs.*.hint
- data/labs/ch02_labs.json :: labs.*.id
- data/labs/ch02_labs.json :: labs.*.max_delay
- data/labs/ch02_labs.json :: labs.*.max_gates
- data/labs/ch02_labs.json :: labs.*.measure_conditions
- data/labs/ch02_labs.json :: labs.*.misconception
- data/labs/ch02_labs.json :: labs.*.palette
- data/labs/ch02_labs.json :: labs.*.power_model
- data/labs/ch02_labs.json :: labs.*.presets
- data/labs/ch02_labs.json :: labs.*.rail
- data/labs/ch02_labs.json :: labs.*.reference
- data/labs/ch02_labs.json :: labs.*.region_model
- data/labs/ch02_labs.json :: labs.*.sections
- data/labs/ch02_labs.json :: labs.*.static_current_max_ua
- data/labs/ch02_labs.json :: labs.*.tasks
- data/labs/ch02_labs.json :: labs.*.tasks[].id
- data/labs/ch02_labs.json :: labs.*.tasks[].input_ids
- data/labs/ch02_labs.json :: labs.*.tasks[].palette
- data/labs/ch02_labs.json :: labs.*.tasks[].target
- data/labs/ch02_labs.json :: labs.*.tasks[].title
- data/labs/ch02_labs.json :: labs.*.title
- data/labs/ch02_labs.json :: labs.*.topology
- data/labs/ch02_labs.json :: pending_kinds
- data/labs/ch02_labs.json :: source
- data/labs/ch02_labs.json :: version
- data/labs/ch03_labs.json :: labs
- data/labs/ch03_labs.json :: labs.*.body
- data/labs/ch03_labs.json :: labs.*.gate_cases
- data/labs/ch03_labs.json :: labs.*.gate_cases[].a
- data/labs/ch03_labs.json :: labs.*.gate_cases[].b
- data/labs/ch03_labs.json :: labs.*.gate_cases[].boundary
- data/labs/ch03_labs.json :: labs.*.gate_cases[].c8
- data/labs/ch03_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch03_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch03_labs.json :: labs.*.gate_cases[].expect_mode
- data/labs/ch03_labs.json :: labs.*.gate_cases[].expect_sum
- data/labs/ch03_labs.json :: labs.*.gate_cases[].extra_stages
- data/labs/ch03_labs.json :: labs.*.gate_cases[].hold_required
- data/labs/ch03_labs.json :: labs.*.gate_cases[].id
- data/labs/ch03_labs.json :: labs.*.gate_cases[].instances
- data/labs/ch03_labs.json :: labs.*.gate_cases[].inverters
- data/labs/ch03_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch03_labs.json :: labs.*.gate_cases[].part
- data/labs/ch03_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch03_labs.json :: labs.*.gate_cases[].random_count
- data/labs/ch03_labs.json :: labs.*.gate_cases[].required
- data/labs/ch03_labs.json :: labs.*.gate_cases[].setup_required
- data/labs/ch03_labs.json :: labs.*.gate_cases[].stages
- data/labs/ch03_labs.json :: labs.*.gate_cases[].states
- data/labs/ch03_labs.json :: labs.*.gate_cases[].sum
- data/labs/ch03_labs.json :: labs.*.gate_cases[].ticks
- data/labs/ch03_labs.json :: labs.*.gate_cases[].title
- data/labs/ch03_labs.json :: labs.*.gate_cases[].width
- data/labs/ch03_labs.json :: labs.*.grants
- data/labs/ch03_labs.json :: labs.*.hint
- data/labs/ch03_labs.json :: labs.*.id
- data/labs/ch03_labs.json :: labs.*.misconception
- data/labs/ch03_labs.json :: labs.*.p1
- data/labs/ch03_labs.json :: labs.*.p1_gates
- data/labs/ch03_labs.json :: labs.*.practice
- data/labs/ch03_labs.json :: labs.*.practice[].codes
- data/labs/ch03_labs.json :: labs.*.practice[].gates
- data/labs/ch03_labs.json :: labs.*.practice[].id
- data/labs/ch03_labs.json :: labs.*.practice[].judge
- data/labs/ch03_labs.json :: labs.*.practice[].level
- data/labs/ch03_labs.json :: labs.*.practice[].produce
- data/labs/ch03_labs.json :: labs.*.sections
- data/labs/ch03_labs.json :: labs.*.title
- data/labs/ch03_labs.json :: pending_kinds
- data/labs/ch03_labs.json :: source
- data/labs/ch03_labs.json :: source_note
- data/labs/ch03_labs.json :: version
- data/labs/ch04_labs.json :: labs
- data/labs/ch04_labs.json :: labs.*.body
- data/labs/ch04_labs.json :: labs.*.gate_cases
- data/labs/ch04_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch04_labs.json :: labs.*.gate_cases[].devices
- data/labs/ch04_labs.json :: labs.*.gate_cases[].drivers
- data/labs/ch04_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch04_labs.json :: labs.*.gate_cases[].groups
- data/labs/ch04_labs.json :: labs.*.gate_cases[].high_addr
- data/labs/ch04_labs.json :: labs.*.gate_cases[].id
- data/labs/ch04_labs.json :: labs.*.gate_cases[].illegal_opcodes
- data/labs/ch04_labs.json :: labs.*.gate_cases[].inputs
- data/labs/ch04_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch04_labs.json :: labs.*.gate_cases[].legal_opcodes
- data/labs/ch04_labs.json :: labs.*.gate_cases[].levels
- data/labs/ch04_labs.json :: labs.*.gate_cases[].low_addr
- data/labs/ch04_labs.json :: labs.*.gate_cases[].opcode_ports
- data/labs/ch04_labs.json :: labs.*.gate_cases[].operands
- data/labs/ch04_labs.json :: labs.*.gate_cases[].ops
- data/labs/ch04_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch04_labs.json :: labs.*.gate_cases[].ports
- data/labs/ch04_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch04_labs.json :: labs.*.gate_cases[].required
- data/labs/ch04_labs.json :: labs.*.gate_cases[].rows
- data/labs/ch04_labs.json :: labs.*.gate_cases[].signals
- data/labs/ch04_labs.json :: labs.*.gate_cases[].status
- data/labs/ch04_labs.json :: labs.*.gate_cases[].title
- data/labs/ch04_labs.json :: labs.*.grants
- data/labs/ch04_labs.json :: labs.*.hint
- data/labs/ch04_labs.json :: labs.*.id
- data/labs/ch04_labs.json :: labs.*.misconception
- data/labs/ch04_labs.json :: labs.*.p1
- data/labs/ch04_labs.json :: labs.*.p1_gates
- data/labs/ch04_labs.json :: labs.*.practice
- data/labs/ch04_labs.json :: labs.*.practice[].codes
- data/labs/ch04_labs.json :: labs.*.practice[].gates
- data/labs/ch04_labs.json :: labs.*.practice[].id
- data/labs/ch04_labs.json :: labs.*.practice[].judge
- data/labs/ch04_labs.json :: labs.*.practice[].level
- data/labs/ch04_labs.json :: labs.*.practice[].produce
- data/labs/ch04_labs.json :: labs.*.sections
- data/labs/ch04_labs.json :: labs.*.title
- data/labs/ch04_labs.json :: pending_kinds
- data/labs/ch04_labs.json :: source
- data/labs/ch04_labs.json :: source_note
- data/labs/ch04_labs.json :: version
- data/labs/ch05_labs.json :: labs
- data/labs/ch05_labs.json :: labs.*.body
- data/labs/ch05_labs.json :: labs.*.datapath
- data/labs/ch05_labs.json :: labs.*.gate_cases
- data/labs/ch05_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch05_labs.json :: labs.*.gate_cases[].contract
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect_final
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect_jumps
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect_lines
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect_opcodes
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect_out
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect_regs
- data/labs/ch05_labs.json :: labs.*.gate_cases[].expect_ticks
- data/labs/ch05_labs.json :: labs.*.gate_cases[].final_signal
- data/labs/ch05_labs.json :: labs.*.gate_cases[].id
- data/labs/ch05_labs.json :: labs.*.gate_cases[].isa
- data/labs/ch05_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch05_labs.json :: labs.*.gate_cases[].max_ticks
- data/labs/ch05_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch05_labs.json :: labs.*.gate_cases[].required
- data/labs/ch05_labs.json :: labs.*.gate_cases[].stage_signals
- data/labs/ch05_labs.json :: labs.*.gate_cases[].title
- data/labs/ch05_labs.json :: labs.*.gate_cases[].waveform
- data/labs/ch05_labs.json :: labs.*.gate_cases[].waveform_note
- data/labs/ch05_labs.json :: labs.*.grants
- data/labs/ch05_labs.json :: labs.*.grants_note
- data/labs/ch05_labs.json :: labs.*.hint
- data/labs/ch05_labs.json :: labs.*.id
- data/labs/ch05_labs.json :: labs.*.isa
- data/labs/ch05_labs.json :: labs.*.misconception
- data/labs/ch05_labs.json :: labs.*.p1
- data/labs/ch05_labs.json :: labs.*.p1_gates
- data/labs/ch05_labs.json :: labs.*.practice
- data/labs/ch05_labs.json :: labs.*.practice[].codes
- data/labs/ch05_labs.json :: labs.*.practice[].gates
- data/labs/ch05_labs.json :: labs.*.practice[].id
- data/labs/ch05_labs.json :: labs.*.practice[].judge
- data/labs/ch05_labs.json :: labs.*.practice[].level
- data/labs/ch05_labs.json :: labs.*.practice[].level_note
- data/labs/ch05_labs.json :: labs.*.practice[].produce
- data/labs/ch05_labs.json :: labs.*.sections
- data/labs/ch05_labs.json :: labs.*.timing
- data/labs/ch05_labs.json :: labs.*.title
- data/labs/ch05_labs.json :: pending_kinds
- data/labs/ch05_labs.json :: source
- data/labs/ch05_labs.json :: source_note
- data/labs/ch05_labs.json :: version
- data/labs/ch06_labs.json :: labs
- data/labs/ch06_labs.json :: labs.*.body
- data/labs/ch06_labs.json :: labs.*.gate_cases
- data/labs/ch06_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_bytes
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_chars
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_freqs
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_hi
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_keycode
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_lo
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_prefix
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_pressed
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_ratio
- data/labs/ch06_labs.json :: labs.*.gate_cases[].expect_text
- data/labs/ch06_labs.json :: labs.*.gate_cases[].id
- data/labs/ch06_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch06_labs.json :: labs.*.gate_cases[].max_int_ticks
- data/labs/ch06_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch06_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch06_labs.json :: labs.*.gate_cases[].required
- data/labs/ch06_labs.json :: labs.*.gate_cases[].status
- data/labs/ch06_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch06_labs.json :: labs.*.gate_cases[].title
- data/labs/ch06_labs.json :: labs.*.gate_cases[].tolerance
- data/labs/ch06_labs.json :: labs.*.grants
- data/labs/ch06_labs.json :: labs.*.grants_note
- data/labs/ch06_labs.json :: labs.*.hint
- data/labs/ch06_labs.json :: labs.*.id
- data/labs/ch06_labs.json :: labs.*.keyboard
- data/labs/ch06_labs.json :: labs.*.misconception
- data/labs/ch06_labs.json :: labs.*.p1
- data/labs/ch06_labs.json :: labs.*.p1_gates
- data/labs/ch06_labs.json :: labs.*.practice
- data/labs/ch06_labs.json :: labs.*.practice[].codes
- data/labs/ch06_labs.json :: labs.*.practice[].gates
- data/labs/ch06_labs.json :: labs.*.practice[].id
- data/labs/ch06_labs.json :: labs.*.practice[].judge
- data/labs/ch06_labs.json :: labs.*.practice[].level
- data/labs/ch06_labs.json :: labs.*.practice[].produce
- data/labs/ch06_labs.json :: labs.*.sections
- data/labs/ch06_labs.json :: labs.*.thresholds
- data/labs/ch06_labs.json :: labs.*.title
- data/labs/ch06_labs.json :: pending_kinds
- data/labs/ch06_labs.json :: source
- data/labs/ch06_labs.json :: source_note
- data/labs/ch06_labs.json :: version
- data/labs/ch07_labs.json :: labs
- data/labs/ch07_labs.json :: labs.*.body
- data/labs/ch07_labs.json :: labs.*.gate_cases
- data/labs/ch07_labs.json :: labs.*.gate_cases[].byte
- data/labs/ch07_labs.json :: labs.*.gate_cases[].byte_a
- data/labs/ch07_labs.json :: labs.*.gate_cases[].byte_b
- data/labs/ch07_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch07_labs.json :: labs.*.gate_cases[].expect_accum_bits
- data/labs/ch07_labs.json :: labs.*.gate_cases[].expect_bit_us
- data/labs/ch07_labs.json :: labs.*.gate_cases[].expect_half_us
- data/labs/ch07_labs.json :: labs.*.gate_cases[].expect_offset_us
- data/labs/ch07_labs.json :: labs.*.gate_cases[].fields
- data/labs/ch07_labs.json :: labs.*.gate_cases[].flip_bit
- data/labs/ch07_labs.json :: labs.*.gate_cases[].flip_nibble
- data/labs/ch07_labs.json :: labs.*.gate_cases[].id
- data/labs/ch07_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch07_labs.json :: labs.*.gate_cases[].offset_ratio
- data/labs/ch07_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch07_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch07_labs.json :: labs.*.gate_cases[].ratio
- data/labs/ch07_labs.json :: labs.*.gate_cases[].ratio_tolerance
- data/labs/ch07_labs.json :: labs.*.gate_cases[].required
- data/labs/ch07_labs.json :: labs.*.gate_cases[].status
- data/labs/ch07_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch07_labs.json :: labs.*.gate_cases[].title
- data/labs/ch07_labs.json :: labs.*.gate_cases[].tolerance
- data/labs/ch07_labs.json :: labs.*.gate_cases[].vectors
- data/labs/ch07_labs.json :: labs.*.gate_cases[].vectors[].data
- data/labs/ch07_labs.json :: labs.*.gate_cases[].vectors[].id
- data/labs/ch07_labs.json :: labs.*.grants
- data/labs/ch07_labs.json :: labs.*.grants_note
- data/labs/ch07_labs.json :: labs.*.hint
- data/labs/ch07_labs.json :: labs.*.id
- data/labs/ch07_labs.json :: labs.*.misconception
- data/labs/ch07_labs.json :: labs.*.p1
- data/labs/ch07_labs.json :: labs.*.p1_gates
- data/labs/ch07_labs.json :: labs.*.practice
- data/labs/ch07_labs.json :: labs.*.practice[].codes
- data/labs/ch07_labs.json :: labs.*.practice[].gates
- data/labs/ch07_labs.json :: labs.*.practice[].id
- data/labs/ch07_labs.json :: labs.*.practice[].judge
- data/labs/ch07_labs.json :: labs.*.practice[].level
- data/labs/ch07_labs.json :: labs.*.practice[].produce
- data/labs/ch07_labs.json :: labs.*.sections
- data/labs/ch07_labs.json :: labs.*.title
- data/labs/ch07_labs.json :: pending_kinds
- data/labs/ch07_labs.json :: source
- data/labs/ch07_labs.json :: source_note
- data/labs/ch07_labs.json :: version
- data/labs/ch08_labs.json :: labs
- data/labs/ch08_labs.json :: labs.*.body
- data/labs/ch08_labs.json :: labs.*.gate_cases
- data/labs/ch08_labs.json :: labs.*.gate_cases[].actions
- data/labs/ch08_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch08_labs.json :: labs.*.gate_cases[].events
- data/labs/ch08_labs.json :: labs.*.gate_cases[].expected_path
- data/labs/ch08_labs.json :: labs.*.gate_cases[].id
- data/labs/ch08_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch08_labs.json :: labs.*.gate_cases[].layers
- data/labs/ch08_labs.json :: labs.*.gate_cases[].min_frames
- data/labs/ch08_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch08_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch08_labs.json :: labs.*.gate_cases[].required
- data/labs/ch08_labs.json :: labs.*.gate_cases[].states
- data/labs/ch08_labs.json :: labs.*.gate_cases[].status
- data/labs/ch08_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch08_labs.json :: labs.*.gate_cases[].title
- data/labs/ch08_labs.json :: labs.*.grants
- data/labs/ch08_labs.json :: labs.*.grants_note
- data/labs/ch08_labs.json :: labs.*.hint
- data/labs/ch08_labs.json :: labs.*.id
- data/labs/ch08_labs.json :: labs.*.misconception
- data/labs/ch08_labs.json :: labs.*.p1
- data/labs/ch08_labs.json :: labs.*.p1_gates
- data/labs/ch08_labs.json :: labs.*.practice
- data/labs/ch08_labs.json :: labs.*.practice[].codes
- data/labs/ch08_labs.json :: labs.*.practice[].gates
- data/labs/ch08_labs.json :: labs.*.practice[].id
- data/labs/ch08_labs.json :: labs.*.practice[].judge
- data/labs/ch08_labs.json :: labs.*.practice[].level
- data/labs/ch08_labs.json :: labs.*.practice[].produce
- data/labs/ch08_labs.json :: labs.*.sections
- data/labs/ch08_labs.json :: labs.*.title
- data/labs/ch08_labs.json :: pending_kinds
- data/labs/ch08_labs.json :: source
- data/labs/ch08_labs.json :: source_note
- data/labs/ch08_labs.json :: version
- data/labs/ch09_labs.json :: labs
- data/labs/ch09_labs.json :: labs.*.body
- data/labs/ch09_labs.json :: labs.*.gate_cases
- data/labs/ch09_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch09_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch09_labs.json :: labs.*.gate_cases[].expect_cases
- data/labs/ch09_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch09_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch09_labs.json :: labs.*.gate_cases[].id
- data/labs/ch09_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch09_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch09_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch09_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch09_labs.json :: labs.*.gate_cases[].required
- data/labs/ch09_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch09_labs.json :: labs.*.gate_cases[].status
- data/labs/ch09_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch09_labs.json :: labs.*.gate_cases[].title
- data/labs/ch09_labs.json :: labs.*.gate_cases[].unique_key
- data/labs/ch09_labs.json :: labs.*.grants
- data/labs/ch09_labs.json :: labs.*.hint
- data/labs/ch09_labs.json :: labs.*.id
- data/labs/ch09_labs.json :: labs.*.misconception
- data/labs/ch09_labs.json :: labs.*.p1
- data/labs/ch09_labs.json :: labs.*.p1_gates
- data/labs/ch09_labs.json :: labs.*.practice
- data/labs/ch09_labs.json :: labs.*.practice[].codes
- data/labs/ch09_labs.json :: labs.*.practice[].gates
- data/labs/ch09_labs.json :: labs.*.practice[].id
- data/labs/ch09_labs.json :: labs.*.practice[].judge
- data/labs/ch09_labs.json :: labs.*.practice[].level
- data/labs/ch09_labs.json :: labs.*.practice[].produce
- data/labs/ch09_labs.json :: labs.*.sections
- data/labs/ch09_labs.json :: labs.*.title
- data/labs/ch09_labs.json :: pending_kinds
- data/labs/ch09_labs.json :: source
- data/labs/ch09_labs.json :: source_note
- data/labs/ch09_labs.json :: version
- data/labs/ch10_labs.json :: labs
- data/labs/ch10_labs.json :: labs.*.body
- data/labs/ch10_labs.json :: labs.*.gate_cases
- data/labs/ch10_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch10_labs.json :: labs.*.gate_cases[].events
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect_bytes
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect_cases
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect_repeatable
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect_state_after_drop
- data/labs/ch10_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch10_labs.json :: labs.*.gate_cases[].id
- data/labs/ch10_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch10_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch10_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch10_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch10_labs.json :: labs.*.gate_cases[].required
- data/labs/ch10_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch10_labs.json :: labs.*.gate_cases[].states
- data/labs/ch10_labs.json :: labs.*.gate_cases[].status
- data/labs/ch10_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch10_labs.json :: labs.*.gate_cases[].title
- data/labs/ch10_labs.json :: labs.*.grants
- data/labs/ch10_labs.json :: labs.*.hint
- data/labs/ch10_labs.json :: labs.*.id
- data/labs/ch10_labs.json :: labs.*.misconception
- data/labs/ch10_labs.json :: labs.*.p1
- data/labs/ch10_labs.json :: labs.*.p1_gates
- data/labs/ch10_labs.json :: labs.*.practice
- data/labs/ch10_labs.json :: labs.*.practice[].codes
- data/labs/ch10_labs.json :: labs.*.practice[].gates
- data/labs/ch10_labs.json :: labs.*.practice[].id
- data/labs/ch10_labs.json :: labs.*.practice[].judge
- data/labs/ch10_labs.json :: labs.*.practice[].level
- data/labs/ch10_labs.json :: labs.*.practice[].produce
- data/labs/ch10_labs.json :: labs.*.sections
- data/labs/ch10_labs.json :: labs.*.title
- data/labs/ch10_labs.json :: pending_kinds
- data/labs/ch10_labs.json :: source
- data/labs/ch10_labs.json :: source_note
- data/labs/ch10_labs.json :: version
- data/labs/ch11_labs.json :: labs
- data/labs/ch11_labs.json :: labs.*.body
- data/labs/ch11_labs.json :: labs.*.gate_cases
- data/labs/ch11_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_rows[].fixed
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_rows[].id
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_rows[].line
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_rows[].panel
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_rows[].value_before
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_rows[].value_expected
- data/labs/ch11_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch11_labs.json :: labs.*.gate_cases[].id
- data/labs/ch11_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch11_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch11_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch11_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch11_labs.json :: labs.*.gate_cases[].required
- data/labs/ch11_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch11_labs.json :: labs.*.gate_cases[].status
- data/labs/ch11_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch11_labs.json :: labs.*.gate_cases[].title
- data/labs/ch11_labs.json :: labs.*.grants
- data/labs/ch11_labs.json :: labs.*.hint
- data/labs/ch11_labs.json :: labs.*.id
- data/labs/ch11_labs.json :: labs.*.misconception
- data/labs/ch11_labs.json :: labs.*.p1
- data/labs/ch11_labs.json :: labs.*.p1_gates
- data/labs/ch11_labs.json :: labs.*.practice
- data/labs/ch11_labs.json :: labs.*.practice[].codes
- data/labs/ch11_labs.json :: labs.*.practice[].gates
- data/labs/ch11_labs.json :: labs.*.practice[].id
- data/labs/ch11_labs.json :: labs.*.practice[].judge
- data/labs/ch11_labs.json :: labs.*.practice[].level
- data/labs/ch11_labs.json :: labs.*.practice[].produce
- data/labs/ch11_labs.json :: labs.*.sections
- data/labs/ch11_labs.json :: labs.*.title
- data/labs/ch11_labs.json :: pending_kinds
- data/labs/ch11_labs.json :: source
- data/labs/ch11_labs.json :: source_note
- data/labs/ch11_labs.json :: version
- data/labs/ch12_labs.json :: labs
- data/labs/ch12_labs.json :: labs.*.body
- data/labs/ch12_labs.json :: labs.*.gate_cases
- data/labs/ch12_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch12_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch12_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch12_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch12_labs.json :: labs.*.gate_cases[].id
- data/labs/ch12_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch12_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch12_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch12_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch12_labs.json :: labs.*.gate_cases[].required
- data/labs/ch12_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch12_labs.json :: labs.*.gate_cases[].status
- data/labs/ch12_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch12_labs.json :: labs.*.gate_cases[].title
- data/labs/ch12_labs.json :: labs.*.gate_cases[].unique_key
- data/labs/ch12_labs.json :: labs.*.grants
- data/labs/ch12_labs.json :: labs.*.hint
- data/labs/ch12_labs.json :: labs.*.id
- data/labs/ch12_labs.json :: labs.*.misconception
- data/labs/ch12_labs.json :: labs.*.p1
- data/labs/ch12_labs.json :: labs.*.p1_gates
- data/labs/ch12_labs.json :: labs.*.practice
- data/labs/ch12_labs.json :: labs.*.practice[].codes
- data/labs/ch12_labs.json :: labs.*.practice[].gates
- data/labs/ch12_labs.json :: labs.*.practice[].id
- data/labs/ch12_labs.json :: labs.*.practice[].judge
- data/labs/ch12_labs.json :: labs.*.practice[].level
- data/labs/ch12_labs.json :: labs.*.practice[].produce
- data/labs/ch12_labs.json :: labs.*.sections
- data/labs/ch12_labs.json :: labs.*.title
- data/labs/ch12_labs.json :: pending_kinds
- data/labs/ch12_labs.json :: source
- data/labs/ch12_labs.json :: source_note
- data/labs/ch12_labs.json :: version
- data/labs/ch13_labs.json :: labs
- data/labs/ch13_labs.json :: labs.*.body
- data/labs/ch13_labs.json :: labs.*.gate_cases
- data/labs/ch13_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch13_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch13_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch13_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch13_labs.json :: labs.*.gate_cases[].graph
- data/labs/ch13_labs.json :: labs.*.gate_cases[].id
- data/labs/ch13_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch13_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch13_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch13_labs.json :: labs.*.gate_cases[].required
- data/labs/ch13_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch13_labs.json :: labs.*.gate_cases[].title
- data/labs/ch13_labs.json :: labs.*.grants
- data/labs/ch13_labs.json :: labs.*.hint
- data/labs/ch13_labs.json :: labs.*.id
- data/labs/ch13_labs.json :: labs.*.misconception
- data/labs/ch13_labs.json :: labs.*.p1
- data/labs/ch13_labs.json :: labs.*.p1_gates
- data/labs/ch13_labs.json :: labs.*.practice
- data/labs/ch13_labs.json :: labs.*.practice[].codes
- data/labs/ch13_labs.json :: labs.*.practice[].gates
- data/labs/ch13_labs.json :: labs.*.practice[].id
- data/labs/ch13_labs.json :: labs.*.practice[].judge
- data/labs/ch13_labs.json :: labs.*.practice[].level
- data/labs/ch13_labs.json :: labs.*.practice[].produce
- data/labs/ch13_labs.json :: labs.*.program
- data/labs/ch13_labs.json :: labs.*.sections
- data/labs/ch13_labs.json :: labs.*.source_lines
- data/labs/ch13_labs.json :: labs.*.title
- data/labs/ch13_labs.json :: pending_kinds
- data/labs/ch13_labs.json :: source
- data/labs/ch13_labs.json :: source_note
- data/labs/ch13_labs.json :: version
- data/labs/ch14_labs.json :: labs
- data/labs/ch14_labs.json :: labs.*.body
- data/labs/ch14_labs.json :: labs.*.case_sources
- data/labs/ch14_labs.json :: labs.*.gate_cases
- data/labs/ch14_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch14_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch14_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch14_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch14_labs.json :: labs.*.gate_cases[].id
- data/labs/ch14_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch14_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch14_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch14_labs.json :: labs.*.gate_cases[].required
- data/labs/ch14_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch14_labs.json :: labs.*.gate_cases[].title
- data/labs/ch14_labs.json :: labs.*.grants
- data/labs/ch14_labs.json :: labs.*.hint
- data/labs/ch14_labs.json :: labs.*.id
- data/labs/ch14_labs.json :: labs.*.misconception
- data/labs/ch14_labs.json :: labs.*.p1
- data/labs/ch14_labs.json :: labs.*.p1_gates
- data/labs/ch14_labs.json :: labs.*.practice
- data/labs/ch14_labs.json :: labs.*.practice[].codes
- data/labs/ch14_labs.json :: labs.*.practice[].gates
- data/labs/ch14_labs.json :: labs.*.practice[].id
- data/labs/ch14_labs.json :: labs.*.practice[].judge
- data/labs/ch14_labs.json :: labs.*.practice[].level
- data/labs/ch14_labs.json :: labs.*.practice[].produce
- data/labs/ch14_labs.json :: labs.*.sections
- data/labs/ch14_labs.json :: labs.*.title
- data/labs/ch14_labs.json :: pending_kinds
- data/labs/ch14_labs.json :: source
- data/labs/ch14_labs.json :: source_note
- data/labs/ch14_labs.json :: version
- data/labs/ch15_labs.json :: labs
- data/labs/ch15_labs.json :: labs.*.body
- data/labs/ch15_labs.json :: labs.*.case_sources
- data/labs/ch15_labs.json :: labs.*.case_sources.symbols.programs[].declares
- data/labs/ch15_labs.json :: labs.*.case_sources.symbols.programs[].id
- data/labs/ch15_labs.json :: labs.*.capture
- data/labs/ch15_labs.json :: labs.*.gate_cases
- data/labs/ch15_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch15_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch15_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch15_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch15_labs.json :: labs.*.gate_cases[].id
- data/labs/ch15_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch15_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch15_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch15_labs.json :: labs.*.gate_cases[].required
- data/labs/ch15_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch15_labs.json :: labs.*.gate_cases[].title
- data/labs/ch15_labs.json :: labs.*.grants
- data/labs/ch15_labs.json :: labs.*.hint
- data/labs/ch15_labs.json :: labs.*.id
- data/labs/ch15_labs.json :: labs.*.misconception
- data/labs/ch15_labs.json :: labs.*.p1
- data/labs/ch15_labs.json :: labs.*.p1_gates
- data/labs/ch15_labs.json :: labs.*.practice
- data/labs/ch15_labs.json :: labs.*.practice[].codes
- data/labs/ch15_labs.json :: labs.*.practice[].gates
- data/labs/ch15_labs.json :: labs.*.practice[].id
- data/labs/ch15_labs.json :: labs.*.practice[].judge
- data/labs/ch15_labs.json :: labs.*.practice[].level
- data/labs/ch15_labs.json :: labs.*.practice[].produce
- data/labs/ch15_labs.json :: labs.*.sections
- data/labs/ch15_labs.json :: labs.*.socket_calls
- data/labs/ch15_labs.json :: labs.*.title
- data/labs/ch15_labs.json :: pending_kinds
- data/labs/ch15_labs.json :: source
- data/labs/ch15_labs.json :: source_note
- data/labs/ch15_labs.json :: version
- data/labs/ch16_labs.json :: labs
- data/labs/ch16_labs.json :: labs.*.body
- data/labs/ch16_labs.json :: labs.*.case_sources
- data/labs/ch16_labs.json :: labs.*.gate_cases
- data/labs/ch16_labs.json :: labs.*.gate_cases[].*.gap
- data/labs/ch16_labs.json :: labs.*.gate_cases[].*.got
- data/labs/ch16_labs.json :: labs.*.gate_cases[].*.id
- data/labs/ch16_labs.json :: labs.*.gate_cases[].*.latency
- data/labs/ch16_labs.json :: labs.*.gate_cases[].*.sent
- data/labs/ch16_labs.json :: labs.*.gate_cases[].*.seq
- data/labs/ch16_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch16_labs.json :: labs.*.gate_cases[].delay
- data/labs/ch16_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch16_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch16_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch16_labs.json :: labs.*.gate_cases[].id
- data/labs/ch16_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch16_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch16_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch16_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch16_labs.json :: labs.*.gate_cases[].required
- data/labs/ch16_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch16_labs.json :: labs.*.gate_cases[].status
- data/labs/ch16_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch16_labs.json :: labs.*.gate_cases[].timing
- data/labs/ch16_labs.json :: labs.*.gate_cases[].title
- data/labs/ch16_labs.json :: labs.*.grants
- data/labs/ch16_labs.json :: labs.*.hint
- data/labs/ch16_labs.json :: labs.*.id
- data/labs/ch16_labs.json :: labs.*.misconception
- data/labs/ch16_labs.json :: labs.*.p1
- data/labs/ch16_labs.json :: labs.*.p1_gates
- data/labs/ch16_labs.json :: labs.*.practice
- data/labs/ch16_labs.json :: labs.*.practice[].codes
- data/labs/ch16_labs.json :: labs.*.practice[].gates
- data/labs/ch16_labs.json :: labs.*.practice[].id
- data/labs/ch16_labs.json :: labs.*.practice[].judge
- data/labs/ch16_labs.json :: labs.*.practice[].level
- data/labs/ch16_labs.json :: labs.*.practice[].produce
- data/labs/ch16_labs.json :: labs.*.sections
- data/labs/ch16_labs.json :: labs.*.title
- data/labs/ch16_labs.json :: pending_kinds
- data/labs/ch16_labs.json :: source
- data/labs/ch16_labs.json :: source_note
- data/labs/ch16_labs.json :: version
- data/labs/ch17_labs.json :: labs
- data/labs/ch17_labs.json :: labs.*.body
- data/labs/ch17_labs.json :: labs.*.gate_cases
- data/labs/ch17_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch17_labs.json :: labs.*.gate_cases[].delay
- data/labs/ch17_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch17_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch17_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch17_labs.json :: labs.*.gate_cases[].id
- data/labs/ch17_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch17_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch17_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch17_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch17_labs.json :: labs.*.gate_cases[].required
- data/labs/ch17_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch17_labs.json :: labs.*.gate_cases[].status
- data/labs/ch17_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch17_labs.json :: labs.*.gate_cases[].title
- data/labs/ch17_labs.json :: labs.*.grants
- data/labs/ch17_labs.json :: labs.*.hint
- data/labs/ch17_labs.json :: labs.*.id
- data/labs/ch17_labs.json :: labs.*.misconception
- data/labs/ch17_labs.json :: labs.*.p1
- data/labs/ch17_labs.json :: labs.*.p1_gates
- data/labs/ch17_labs.json :: labs.*.practice
- data/labs/ch17_labs.json :: labs.*.practice[].codes
- data/labs/ch17_labs.json :: labs.*.practice[].gates
- data/labs/ch17_labs.json :: labs.*.practice[].id
- data/labs/ch17_labs.json :: labs.*.practice[].judge
- data/labs/ch17_labs.json :: labs.*.practice[].level
- data/labs/ch17_labs.json :: labs.*.practice[].produce
- data/labs/ch17_labs.json :: labs.*.sections
- data/labs/ch17_labs.json :: labs.*.title
- data/labs/ch17_labs.json :: pending_kinds
- data/labs/ch17_labs.json :: source
- data/labs/ch17_labs.json :: source_note
- data/labs/ch17_labs.json :: version
- data/labs/ch18_labs.json :: labs
- data/labs/ch18_labs.json :: labs.*.body
- data/labs/ch18_labs.json :: labs.*.gate_cases
- data/labs/ch18_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch18_labs.json :: labs.*.gate_cases[].delay
- data/labs/ch18_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch18_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch18_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch18_labs.json :: labs.*.gate_cases[].id
- data/labs/ch18_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch18_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch18_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch18_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch18_labs.json :: labs.*.gate_cases[].required
- data/labs/ch18_labs.json :: labs.*.gate_cases[].script
- data/labs/ch18_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch18_labs.json :: labs.*.gate_cases[].status
- data/labs/ch18_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch18_labs.json :: labs.*.gate_cases[].title
- data/labs/ch18_labs.json :: labs.*.grants
- data/labs/ch18_labs.json :: labs.*.hint
- data/labs/ch18_labs.json :: labs.*.id
- data/labs/ch18_labs.json :: labs.*.misconception
- data/labs/ch18_labs.json :: labs.*.p1
- data/labs/ch18_labs.json :: labs.*.p1_gates
- data/labs/ch18_labs.json :: labs.*.practice
- data/labs/ch18_labs.json :: labs.*.practice[].codes
- data/labs/ch18_labs.json :: labs.*.practice[].gates
- data/labs/ch18_labs.json :: labs.*.practice[].id
- data/labs/ch18_labs.json :: labs.*.practice[].judge
- data/labs/ch18_labs.json :: labs.*.practice[].level
- data/labs/ch18_labs.json :: labs.*.practice[].produce
- data/labs/ch18_labs.json :: labs.*.sections
- data/labs/ch18_labs.json :: labs.*.title
- data/labs/ch18_labs.json :: pending_kinds
- data/labs/ch18_labs.json :: source
- data/labs/ch18_labs.json :: source_note
- data/labs/ch18_labs.json :: version
- data/labs/ch19_labs.json :: labs
- data/labs/ch19_labs.json :: labs.*.body
- data/labs/ch19_labs.json :: labs.*.gate_cases
- data/labs/ch19_labs.json :: labs.*.gate_cases[].codes
- data/labs/ch19_labs.json :: labs.*.gate_cases[].delay
- data/labs/ch19_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/ch19_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/ch19_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/ch19_labs.json :: labs.*.gate_cases[].id
- data/labs/ch19_labs.json :: labs.*.gate_cases[].keys
- data/labs/ch19_labs.json :: labs.*.gate_cases[].kind
- data/labs/ch19_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/ch19_labs.json :: labs.*.gate_cases[].quiz
- data/labs/ch19_labs.json :: labs.*.gate_cases[].required
- data/labs/ch19_labs.json :: labs.*.gate_cases[].sampling
- data/labs/ch19_labs.json :: labs.*.gate_cases[].stage
- data/labs/ch19_labs.json :: labs.*.gate_cases[].status
- data/labs/ch19_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/ch19_labs.json :: labs.*.gate_cases[].title
- data/labs/ch19_labs.json :: labs.*.grants
- data/labs/ch19_labs.json :: labs.*.hint
- data/labs/ch19_labs.json :: labs.*.id
- data/labs/ch19_labs.json :: labs.*.misconception
- data/labs/ch19_labs.json :: labs.*.p1
- data/labs/ch19_labs.json :: labs.*.p1_gates
- data/labs/ch19_labs.json :: labs.*.practice
- data/labs/ch19_labs.json :: labs.*.practice[].codes
- data/labs/ch19_labs.json :: labs.*.practice[].gates
- data/labs/ch19_labs.json :: labs.*.practice[].id
- data/labs/ch19_labs.json :: labs.*.practice[].judge
- data/labs/ch19_labs.json :: labs.*.practice[].level
- data/labs/ch19_labs.json :: labs.*.practice[].produce
- data/labs/ch19_labs.json :: labs.*.sections
- data/labs/ch19_labs.json :: labs.*.title
- data/labs/ch19_labs.json :: pending_kinds
- data/labs/ch19_labs.json :: source
- data/labs/ch19_labs.json :: source_note
- data/labs/ch19_labs.json :: version
- data/labs/final_labs.json :: labs
- data/labs/final_labs.json :: labs.*.body
- data/labs/final_labs.json :: labs.*.gate_cases
- data/labs/final_labs.json :: labs.*.gate_cases[].codes
- data/labs/final_labs.json :: labs.*.gate_cases[].delay
- data/labs/final_labs.json :: labs.*.gate_cases[].expect_meta
- data/labs/final_labs.json :: labs.*.gate_cases[].expect_rows
- data/labs/final_labs.json :: labs.*.gate_cases[].expect_values
- data/labs/final_labs.json :: labs.*.gate_cases[].id
- data/labs/final_labs.json :: labs.*.gate_cases[].keys
- data/labs/final_labs.json :: labs.*.gate_cases[].kind
- data/labs/final_labs.json :: labs.*.gate_cases[].pending_reason
- data/labs/final_labs.json :: labs.*.gate_cases[].required
- data/labs/final_labs.json :: labs.*.gate_cases[].stage
- data/labs/final_labs.json :: labs.*.gate_cases[].status
- data/labs/final_labs.json :: labs.*.gate_cases[].thresholds
- data/labs/final_labs.json :: labs.*.gate_cases[].title
- data/labs/final_labs.json :: labs.*.grants
- data/labs/final_labs.json :: labs.*.hint
- data/labs/final_labs.json :: labs.*.id
- data/labs/final_labs.json :: labs.*.misconception
- data/labs/final_labs.json :: labs.*.p1
- data/labs/final_labs.json :: labs.*.p1_gates
- data/labs/final_labs.json :: labs.*.practice
- data/labs/final_labs.json :: labs.*.practice[].codes
- data/labs/final_labs.json :: labs.*.practice[].gates
- data/labs/final_labs.json :: labs.*.practice[].id
- data/labs/final_labs.json :: labs.*.practice[].judge
- data/labs/final_labs.json :: labs.*.practice[].level
- data/labs/final_labs.json :: labs.*.practice[].produce
- data/labs/final_labs.json :: labs.*.sections
- data/labs/final_labs.json :: labs.*.title
- data/labs/final_labs.json :: pending_kinds
- data/labs/final_labs.json :: source
- data/labs/final_labs.json :: source_note
- data/labs/final_labs.json :: version
- data/manifest.json :: files
- data/manifest.json :: version
- data/questions/ch01_exercises.json :: bank
- data/questions/ch01_exercises.json :: chapter
- data/questions/ch01_exercises.json :: format
- data/questions/ch01_exercises.json :: items
- data/questions/ch01_exercises.json :: items[].answer_value
- data/questions/ch01_exercises.json :: items[].common_errors
- data/questions/ch01_exercises.json :: items[].hints
- data/questions/ch01_exercises.json :: items[].id
- data/questions/ch01_exercises.json :: items[].rubric
- data/questions/ch01_exercises.json :: items[].section
- data/questions/ch01_exercises.json :: items[].solutions
- data/questions/ch01_exercises.json :: items[].stem
- data/questions/ch01_exercises.json :: items[].task_ids
- data/questions/ch01_exercises.json :: items[].tol
- data/questions/ch01_exercises.json :: items[].type
- data/questions/ch01_exercises.json :: note
- data/questions/ch01_exercises.json :: version
- data/questions/ch02_exercises.json :: bank
- data/questions/ch02_exercises.json :: chapter
- data/questions/ch02_exercises.json :: format
- data/questions/ch02_exercises.json :: items
- data/questions/ch02_exercises.json :: items[].answer
- data/questions/ch02_exercises.json :: items[].common_errors
- data/questions/ch02_exercises.json :: items[].concept
- data/questions/ch02_exercises.json :: items[].distractor_notes
- data/questions/ch02_exercises.json :: items[].gate
- data/questions/ch02_exercises.json :: items[].hints
- data/questions/ch02_exercises.json :: items[].id
- data/questions/ch02_exercises.json :: items[].lab
- data/questions/ch02_exercises.json :: items[].options
- data/questions/ch02_exercises.json :: items[].order
- data/questions/ch02_exercises.json :: items[].rubric
- data/questions/ch02_exercises.json :: items[].section
- data/questions/ch02_exercises.json :: items[].solutions
- data/questions/ch02_exercises.json :: items[].source_excerpt
- data/questions/ch02_exercises.json :: items[].stem
- data/questions/ch02_exercises.json :: items[].type
- data/questions/ch02_exercises.json :: note
- data/questions/ch02_exercises.json :: version
- data/questions/ch03_exercises.json :: bank
- data/questions/ch03_exercises.json :: chapter
- data/questions/ch03_exercises.json :: format
- data/questions/ch03_exercises.json :: items
- data/questions/ch03_exercises.json :: items[].answer
- data/questions/ch03_exercises.json :: items[].common_errors
- data/questions/ch03_exercises.json :: items[].concept
- data/questions/ch03_exercises.json :: items[].distractor_notes
- data/questions/ch03_exercises.json :: items[].gate
- data/questions/ch03_exercises.json :: items[].hints
- data/questions/ch03_exercises.json :: items[].id
- data/questions/ch03_exercises.json :: items[].lab
- data/questions/ch03_exercises.json :: items[].options
- data/questions/ch03_exercises.json :: items[].order
- data/questions/ch03_exercises.json :: items[].rubric
- data/questions/ch03_exercises.json :: items[].section
- data/questions/ch03_exercises.json :: items[].solutions
- data/questions/ch03_exercises.json :: items[].source_excerpt
- data/questions/ch03_exercises.json :: items[].stem
- data/questions/ch03_exercises.json :: items[].type
- data/questions/ch03_exercises.json :: note
- data/questions/ch03_exercises.json :: version
- data/questions/ch04_exercises.json :: bank
- data/questions/ch04_exercises.json :: chapter
- data/questions/ch04_exercises.json :: format
- data/questions/ch04_exercises.json :: items
- data/questions/ch04_exercises.json :: items[].answer
- data/questions/ch04_exercises.json :: items[].common_errors
- data/questions/ch04_exercises.json :: items[].concept
- data/questions/ch04_exercises.json :: items[].distractor_notes
- data/questions/ch04_exercises.json :: items[].gate
- data/questions/ch04_exercises.json :: items[].hints
- data/questions/ch04_exercises.json :: items[].id
- data/questions/ch04_exercises.json :: items[].lab
- data/questions/ch04_exercises.json :: items[].options
- data/questions/ch04_exercises.json :: items[].order
- data/questions/ch04_exercises.json :: items[].rubric
- data/questions/ch04_exercises.json :: items[].section
- data/questions/ch04_exercises.json :: items[].solutions
- data/questions/ch04_exercises.json :: items[].source_excerpt
- data/questions/ch04_exercises.json :: items[].stem
- data/questions/ch04_exercises.json :: items[].type
- data/questions/ch04_exercises.json :: note
- data/questions/ch04_exercises.json :: version
- data/questions/ch05_exercises.json :: bank
- data/questions/ch05_exercises.json :: chapter
- data/questions/ch05_exercises.json :: format
- data/questions/ch05_exercises.json :: items
- data/questions/ch05_exercises.json :: items[].answer
- data/questions/ch05_exercises.json :: items[].answer_value
- data/questions/ch05_exercises.json :: items[].common_errors
- data/questions/ch05_exercises.json :: items[].concept
- data/questions/ch05_exercises.json :: items[].distractor_notes
- data/questions/ch05_exercises.json :: items[].gate
- data/questions/ch05_exercises.json :: items[].hints
- data/questions/ch05_exercises.json :: items[].id
- data/questions/ch05_exercises.json :: items[].lab
- data/questions/ch05_exercises.json :: items[].options
- data/questions/ch05_exercises.json :: items[].order
- data/questions/ch05_exercises.json :: items[].rubric
- data/questions/ch05_exercises.json :: items[].section
- data/questions/ch05_exercises.json :: items[].solutions
- data/questions/ch05_exercises.json :: items[].source_excerpt
- data/questions/ch05_exercises.json :: items[].stem
- data/questions/ch05_exercises.json :: items[].tol
- data/questions/ch05_exercises.json :: items[].type
- data/questions/ch05_exercises.json :: note
- data/questions/ch05_exercises.json :: version
- data/sim/delays.json :: bench_note
- data/sim/delays.json :: dff
- data/sim/delays.json :: frame
- data/sim/delays.json :: gate_delay
- data/sim/delays.json :: l3
- data/sim/delays.json :: limits
- data/sim/delays.json :: note
- data/sim/delays.json :: relay
- data/sim/delays.json :: source
- data/sim/delays.json :: version
- data/sim/macros.json :: cells
- data/sim/macros.json :: format
- data/sim/macros.json :: note
- data/sim/macros.json :: pages
- data/sim/macros.json :: pages.alu4[].cells
- data/sim/macros.json :: pages.alu4[].gates
- data/sim/macros.json :: pages.alu4[].group
- data/sim/macros.json :: pages.alu4[].id
- data/sim/macros.json :: pages.alu4[].title
- data/sim/macros.json :: pages.comparator4[].cells
- data/sim/macros.json :: pages.comparator4[].gates
- data/sim/macros.json :: pages.comparator4[].group
- data/sim/macros.json :: pages.comparator4[].id
- data/sim/macros.json :: pages.comparator4[].title
- data/sim/macros.json :: pages.decoder3[].cells
- data/sim/macros.json :: pages.decoder3[].gates
- data/sim/macros.json :: pages.decoder3[].group
- data/sim/macros.json :: pages.decoder3[].id
- data/sim/macros.json :: pages.decoder3[].title
- data/sim/macros.json :: source
- data/sim/macros.json :: version
- data/skilltree.json :: nodes
- data/skilltree.json :: nodes[].auto
- data/skilltree.json :: nodes[].desc
- data/skilltree.json :: nodes[].effects
- data/skilltree.json :: nodes[].gold_award
- data/skilltree.json :: nodes[].id
- data/skilltree.json :: nodes[].kind
- data/skilltree.json :: nodes[].legacy
- data/skilltree.json :: nodes[].level
- data/skilltree.json :: nodes[].pos
- data/skilltree.json :: nodes[].prereq
- data/skilltree.json :: nodes[].requires
- data/skilltree.json :: nodes[].requires.all[].id
- data/skilltree.json :: nodes[].requires.all[].type
- data/skilltree.json :: nodes[].title
- data/skilltree.json :: nodes[].tree
- data/skilltree.json :: nodes[].xp_award
- data/skilltree.json :: nodes[].xp_cost
- data/skilltree.json :: source
- data/skilltree.json :: trees
- data/skilltree.json :: trees[].desc
- data/skilltree.json :: trees[].id
- data/skilltree.json :: trees[].name
- data/skilltree.json :: version
- data/tutorial.json :: steps
- data/tutorial.json :: steps[].id
- data/tutorial.json :: steps[].text
- data/tutorial.json :: steps[].title
- data/tutorial.json :: steps[].trigger
- data/tutorial.json :: version
<!-- REGISTRY:END -->
