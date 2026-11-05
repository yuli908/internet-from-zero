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
| `rules` | `data/labs/ch01_labs.json:16-20`（全库唯一 1 处） | 读取 `src/ui/teaching.gd:17`、`:106`；UI 调用 `src/ui/screens/lab_base.gd:322` | **半死** | 读取路径在，但**实际不可达**：`fallback_note`（`teaching.gd:116-117`）在 `has_sections` 为真时返回 `""`；该 lab 有 5 段 sections（`ch01_labs.json:9-15`）→ 产品 UI 永不渲染。仅测试读：`tests/test_teaching.gd:42-46`、`tests/test_ch01_sections_ui.gd:259,268` |
| `gate.body` | **不存在**：`data/**` 无任何 `gate_cases[].body`；`body` 只在 lab 级（82 个 lab，如 `ch02_labs.json:11,63,90,119,146`） | lab 级 `body` 由 `src/ui/screens/lab_ch02.gd:133,190,305` 直接渲染（`Ui.wrap`），另有探针 `lab_base.gd:537-538` | **lab.body = 活**；`gate.body` 无定义 | 用户点名的 `gate.body` 在数据中不存在，不需要处置；lab 级 `body` 是活字段，**不能删** |

另发现的**同口径旧归因残留**（本轮按指定范围未改，供下一轮裁决）：

- `data/labs/ch02_labs.json:5` `pending_kinds.static_current` 仍写"L1 仿真层只输出逻辑值，无稳态电流模型"；
- `src/core/ch02_checks.gd:15` `PENDING_REASONS` 同句；
- `specs/m5/failure_contract.md:244` §9.5.2 仍把前置条件写成"需要 L1 仿真层具备实测平均电流的能力"。

三处都是被本轮否掉的"需要器件级建模"归因。改它们会动到 `PENDING_REASONS`（玩家可见文案，受 `tests/test_chapter.gd` 内部术语断言约束）与契约文档，因此**未擅自动手**。

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

**② `task_ids`（42 处，`data/questions/ch01_exercises.json:11`）被判"死"**
`src`/`tests`/`scripts` 全部零命中。可能是给题库路由/统计工具预留的字段，也可能只是迁移残留。
不确定原因：题库目前只在 `tests/test_qbank_*.gd` 里被整体读取并断言，外部工具（未纳入扫描的 `tools/` 若存在）可能按题 id 关联。

**③ `items[].acquire / unlock_chapter`（各 86 处，`data/items/items.json:5`）被判"死"**
字面量零命中，但 `Catalog.from_data` 把整条 item dict 原样存进 `c.items`（`src/core/catalog.gd:21`），后续任何 `catalog.item(id).get(<变量>)` 都无法静态排除。
不确定原因：这是"整对象透传"的固有盲区；要确认只能靠运行时插桩或人工通读 `shop_screen.gd` / `main.gd` 的全部取字段点。

## 5. 本轮不删的说明

- 用户明确要求"不许直接删任何东西"，本文件只出清单与建议。
- `static_current_max_ua`、`max_ua` 等字段与"第二章转正"绑定：转正时 `STATIC_CURRENT` 实现会第一次真正读 `max_ua`。**先别删**，否则转正要重新补数据。
- `rules` 与 lab 级 `body` 是教学内容，价值在文案不在读取点；删了等于删课程。
- 19 条零引用 `const` 里，多数是 UI 布局常量（`ui_theme.gd` 的 `S1/S4/S5/S6`、`shop_screen.gd` 的颜色/坐标），属于"设计留白"，不宜批量清。

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
| 27 | `task_ids` | data/questions/ch01_exercises.json:11 | 42 | 无 |
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
