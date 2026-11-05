# 接口扩展提案（字段级）

状态：**部分批准并已实施（2026-11-05）**。用户批了 §2.1（13.1 源码行映射）、§2.3（14.1 tokens/AST 序列导出）、§2.5（15.2 句柄编号映射），本轮另按指令实施 §2.6（16.3 逐请求时延）。§2.1/§2.3/§2.6 已落成真判据；§2.5 只到接口形成，`T15.2-1` 仍 pending（缺真实抓包数据源）。另新增第 11 项 §2.11（14.2 类型标签导出，来自 CH14 §2 的扩接口诉求），**已实施并转正** `T14.2-1`（CH14 进分母 11→12、pending 1→0；全书实测 pending 由 19 降到 17，见 `docs/PROGRESS.md` §10.2）。其余各项**仍未批准、未实施**，不得报成已实现。

## 0. 背景与口径

- 来源：CH13–CH19 与终章降级清单里「课文要求玩家能指认，但数据侧只有布尔位/汇总数」的项。
- 目标：把「能指认」变成「有字段可逐条核对」，而不是再加一个 `true/false`。
- 逐项写：章节/gate、课文原话、现在缺什么、要哪些字段（JSON 形状）、由哪一侧实现、影响面、估时。
- 所有字段名均为**提案命名**，未与仿真核心对齐；批准前不得作为数据 schema 使用。
- 估时按「单人、含单测与文档」计，单位**人日**，不含 UI 重做。

## 1. 总表

| # | 章节 / gate | 诉求 | 主责侧 | 估时 |
|---|---|---|---|---|
| 1 | 13.1 / `T13.1-1` | 源码行 ↔ 字节码可追溯 | 仿真核心 | 4 |
| 2 | 13.2 / `T13.2-1` | 对象图节点与边可端点核对 | 仿真核心 | 6 |
| 3 | 14.1 / `T14.1-1` | tokens / ast 序列逐段导出 | 仿真核心 | 6 |
| 4 | 15.1 / `T15.1-1` | 符号签名（类型/顺序）可逐符号比 | 仿真核心 + 数据 | 4 |
| 5 | 15.2 / `T15.2-1` | 句柄编号与帧/调用同一编号 | 仿真核心 | 5 |
| 6 | 16.3 / `T16.3-1` | 压测逐请求时延可逐条核（已实施） | 仿真核心 | 3 |
| 7 | 17.1 / `T17.1-1` | 消息四字段位宽与超长拒绝可逐字段核 | 数据 + 仿真核心 | 5 |
| 8 | 18.4 / `T18.4-1` | 证书开关与剧本结果可指认 | 数据 + 仿真核心 | 6 |
| 9 | 19.3 / `T19.3-1` | 采样链路五段 I/O 与原始码值 | 仿真核心 + UI | 8 |
| 10 | F1 / `F1-1` | 本机真实字节与两次输出 | 仿真核心 + UI | 6 |
| 11 | 14.2 / `T14.2-1` | 逐值类型标签与类型错误可逐行核（新增项，已实施） | 仿真核心 | 2 |

合计 **42 人日**（第 1–10 项的原始估算，不随实施进度改动）。第 6 项已实施、第 11 项为 CH14 §2 扩接口诉求的补录（估 2 人日，不计入上列合计）。

## 2. 逐项规格

### 2.1 13.1 源码行映射（`T13.1-1`）

- **课文原话**：「需技术侧扩接口：源码↔字节码行映射（`{source_line, bytecode_pc[]}`） / 最小替代：要求每条字节码记来源行号，人工走查行号覆盖；对不上即红。」
- **现在缺什么**：单步只有 `stack_before/after` 与 `opcode`，没有来源行；「行号覆盖」只能人工走查，判据无法自动红。
- **要的字段**：

```json
{
  "line_map": [{"pc": 3, "src_line": 7}, {"pc": 4, "src_line": 7}],
  "lines_covered": [5, 6, 7],
  "unmapped_pc": []
}
```

- **实现侧**：编译/汇编阶段记录 pc→行，运行时随单步快照一起导出（仿真核心）。
- **影响面**：`net_lab_kit` 的 `table` 可继续用；新增字段落在单步产物的 `meta`，不新增 kind。13.1 A 第①条从人工走查转机判。
- **估时**：4 人日。

### 2.2 13.2 对象图节点边（`T13.2-1`）

- **课文原话**：「需技术侧扩接口：对象图判据（`{obj_addr, fields[{name, offset}], refs[]}` + 父子/接口边） / 最小替代：导出对象清单与引用列表，逐对象核对起始地址与字段偏移，再比对边端点地址。」
- **现在缺什么**：只有「对象数/引用数」两个计数与一个布尔位；父子边、接口边都不可见，端点对不上也判不出。
- **要的字段**：

```json
{
  "nodes": [
    {"obj_addr": "0x20", "type": "Child", "fields": [{"name": "hp", "offset": 2}]}
  ],
  "edges": [
    {"kind": "parent", "from": "0x20", "to": "0x10", "field": "parent"},
    {"kind": "iface", "from": "0x20", "to": "0x18", "field": "iface_ptr"}
  ],
  "orphans": []
}
```

- **实现侧**：堆快照导出（仿真核心）；边由运行时引用扫描生成。
- **影响面**：13.2 A 的「逐对象/逐边」从布尔位转机判；`table` 需新增 `nodes`/`edges` 形状的读取约定（仍属 table）。
- **估时**：6 人日。

### 2.3 14.1 tokens / ast 序列（`T14.1-1`）

- **课文原话**：「需技术侧扩接口：三段产物判据（`{tokens[], ast, value}` + 逐段导出） / 最小替代：要求每段都能单独导出并与源码比对，任一段缺失即红。」
- **现在缺什么**：只有「三段都出现过」布尔位与最终值；token 序列、AST 形状无法逐段比对。
- **要的字段**：

```json
{
  "tokens": [{"i": 0, "kind": "num", "text": "2", "line": 1}],
  "ast": {"kind": "add", "children": [{"kind": "num", "value": 2}, {"kind": "num", "value": 3}]},
  "value": 5,
  "stages_exported": ["tokens", "ast", "value"]
}
```

- **实现侧**：词法/语法分析器逐段导出（仿真核心）；数据侧只存期望序列。
- **影响面**：14.1 A 的「每段可单独导出」转机判；14.1 C 的列表用例仍走 `derived_number`。
- **估时**：6 人日。

### 2.4 15.1 签名类型与顺序（`T15.1-1`）

- **课文原话**：「需技术侧扩接口：符号表与链接结果判据（`{symbols, call_sites, lib_ref}`） / 最小替代：要求两个程序的可执行产物都引用同一库符号，改库后两程序输出同步变化；任一程序内联复制即红。」
- **现在缺什么**：只有「引用同一库」布尔位；符号的参数类型、返回类型、声明顺序都没有，签名不符也能过。
- **要的字段**：

```json
{
  "symbols": [
    {"name": "str_len", "params": ["char*"], "ret": "i32", "order": 0, "from": "lib"},
    {"name": "main", "params": [], "ret": "i32", "order": 1, "from": "app"}
  ],
  "call_sites": [{"pc": 12, "symbol": "str_len", "argc": 1}],
  "lib_ref": "libnet.so"
}
```

- **实现侧**：符号表导出与调用点登记（仿真核心）；期望签名由数据侧题库给（数据）。
- **影响面**：15.1 A 从「能跑」转「签名逐符号对上」；与 15.3 的 ABI 判据共用同一符号表。
- **估时**：4 人日。

### 2.5 15.2 句柄编号映射（`T15.2-1`）

- **课文原话**：「需技术侧扩接口：socket→栈映射判据（`{fd, calls[], frames[]}`） / 最小替代：抓包面板须能列出本次 send/recv 的帧，且与协议栈日志同一编号；无帧即红。」
- **现在缺什么**：只有「抓到帧」布尔位；fd、调用序号、帧编号三者互相对不上，也看不出哪一帧属于哪个句柄。
- **要的字段**：

```json
{
  "handles": [{"fd": 3, "socket_id": "s1", "calls": [{"n": 1, "op": "send"}]}],
  "frames": [{"frame_id": 7, "fd": 3, "call_n": 1, "dir": "out"}],
  "unmatched_frames": []
}
```

- **实现侧**：协议栈与抓包面板共用一个自增编号（仿真核心）；UI 只读展示。
- **影响面**：15.2 A 的「同一编号」转机判；抓包面板需显示 fd 与 call_n。
- **估时**：5 人日。

### 2.6 16.3 时延逐条（`T16.3-1`，已实施 2026-11-05）

- **课文原话**：「需技术侧扩接口：压测逐请求判据（`{req_id, sent_at, got_at, ok, status}` + 汇总） / 最小替代：服务端须有与压测器对得上的 8 条请求日志，逐条比对结果与时延；日志不足 8 条即红。」
- **原缺失**：有 `rows` 逐条与 `delay` 上限（越限已能发 9），但 `sent_at/got_at` 是单值时延，无法复算排队与处理分段；`req_id` 与客户端请求号未绑定。
- **已落成的字段形状**（`src/core/load_probe.gd` 产出，`data/labs/ch16_labs.json` 的 `T16.3-1` 声明）：

```json
{
  "rows": [
    {"req_id": 1, "client_seq": 1, "sent_at": 0, "got_at": 15,
     "latency": 15, "ok": true, "status": 200}
  ],
  "meta": {"real_requests": true, "all_ok": true,
           "latency_logged": true, "events_logged": true},
  "summary": {"avg_latency": 13, "throughput": 16}
}
```

- **时间戳来源**：`LoadProbe.run(plan)` 用事件队列推进时钟——每个请求产生「发送事件」与「到达事件」两枚事件，`sent_at` / `got_at` 一律取 `clock.now`，`latency` 只由 `got_at − sent_at` 现算。8 并发时 8 枚发送事件都在 t=0（真实并发），到达时刻由「服务耗时 10 + 抖动」逐条决定，故完成次序与编号无关。
- **判据（读取点）**：`src/core/net_lab_kit.gd` `_table` 的 `timing` 块（`id/seq/sent/got/latency/gap`）逐行校验——`req_id==client_seq==i+1`（否则 7）、`sent_at == i*gap`（否则 9）、`got_at > sent_at`（否则 9）、`latency == got_at − sent_at 且 >0`（否则 9）；随后 `delay.max=30` 越限发 9；最后逐格对 `expect_rows`。**下游真读**：`tests/test_ch16.gd` 的 `_good` 把 `LoadProbe.run` 的 `summary` 直接喂给 `T16.3-3` 的 `values`（均值 13、吞吐 16 由同一批逐条记录算出，不再手填）。
- **能红的证据**（本轮实测，`tests/test_ch16.gd` 负例组）：

```
RED-PROBE CH16 T16.3-1 第 1 行时延改成固定 12(与 got−sent=15 不符) -> code=9
RED-PROBE CH16 T16.3-1 第 1 行 got_at 抄成 sent_at -> code=9
RED-PROBE CH16 T16.3-1 第 1/2 行 req_id 绑错请求 -> code=7
RED-PROBE CH16 T16.3-1 第 1/2 行 client_seq 绑错请求 -> code=7
```

- **未落地的部分**：提案里的 `queue_ms` / `handle_ms` 四段拆分未实现——当前仿真只有「服务耗时 + 抖动」，没有可复算的排队段，故不写进 schema，不拿常数冒充。
- **影响面**：`table` kind 不改、失败码不发新的；`T16.3-1` 原为 ready，进分母与 pending 数不变（CH16 仍 15 进分母、1 pending）。
- **估时**：3 人日（原估）。

### 2.7 17.1 消息字段（`T17.1-1`，当前 pending）

- **课文原话**：「需技术侧扩接口：消息字段与超长拒绝判据（`{type, len, payload, ts, rejected_reason}`） / 最小替代：只认四字段可解析、超长被拒且原因可读。」
- **现在缺什么**：数据侧定了「头 6 B + 上限 256 B」，但没有逐字段位宽、时间戳精度、拒绝原因枚举；pending 就卡在这。
- **要的字段**：

```json
{
  "field_width": {"type": 1, "len": 2, "ts": 3},
  "limits": {"max_payload": 256, "ts_resolution_ms": 1},
  "messages": [
    {"type": 1, "len": 6, "payload_hex": "68692c20", "ts": 1001, "accepted": true, "reason": ""},
    {"type": 1, "len": 300, "payload_hex": "", "ts": 1002, "accepted": false, "reason": "len"}
  ],
  "reason_enum": ["len", "type", "ts"]
}
```

- **实现侧**：位宽与拒绝枚举由数据侧定稿；序列化/解析与拒绝路径由仿真核心实现。
- **影响面**：T17.1-1 解除 pending；17.1 C 的 6 B 头与 256 B 上限不变。
- **估时**：5 人日。

### 2.8 18.4 剧本开关（`T18.4-1`）

- **课文原话**：「需技术侧扩接口：剧本开关判据（`{phase, cert_verify, intercepted, rejected, reason}`） / 最小替代：两遍剧本必须给出相反的拦截/拒绝结果，且拒绝原因可读。」
- **现在缺什么**：`intercepted/rejected` 是布尔，开关本身是否真的接到验证逻辑无法指认；拒绝原因只有一个字符串。
- **要的字段**：

```json
{
  "phase": "verify_on",
  "cert_verify": true,
  "chain": [{"node": "leaf", "sig_ok": false, "reason": "untrusted_root"}],
  "intercepted": false,
  "rejected": true,
  "reason": "untrusted_root",
  "handshake_ms": 40
}
```

- **实现侧**：剧本开关直连验证器（仿真核心）；证书链结果由 18.3 的导出复用。
- **影响面**：18.4 A 的「开关是否真接」转机判；同时给 18.3 提供逐级原因。
- **估时**：6 人日。

### 2.9 19.3 采样链路（`T19.3-1`）

- **课文原话**：「需技术侧扩接口：采样链路判据（`{stage, in, out, raw_v, code, sample_ms, stored}` 逐段） / 最小替代：五段都要有输入输出与入库记录。」
- **现在缺什么**：`in/out` 是文本单元格，`raw_v` 与 ADC 码没有分开；量化误差只能靠固定期望值，无法指认原始电压。
- **要的字段**：

```json
{
  "stages": [
    {"stage": "sensor", "raw_v": 0.5, "code": null, "stored": false, "sample_ms": 20},
    {"stage": "adc", "raw_v": 0.5, "code": 64, "stored": false, "sample_ms": 20},
    {"stage": "server", "raw_v": 0.5, "code": 64, "stored": true, "sample_ms": 20}
  ],
  "lsb_v": 0.0078125,
  "error_lsb": 0
}
```

- **实现侧**：采样与量化在设备侧导出 raw_v/code（仿真核心）；UI 只画链路与码值。
- **影响面**：T19.3-1 的「误差 ≤1 LSB」转机判；19.2 的功耗预算可复用同一导出格式。
- **估时**：8 人日。

### 2.10 F1 出网（`F1-1`，当前 pending）

- **课文原话**：「需技术侧扩接口：出网判据（`{local_bytes[], before, after, port}`） / 最小替代：本机终端必须真的收到两行，且改输入后第二行随之变化。」
- **现在缺什么**：只有两行文本与一个时延；端口、本机字节、两次运行的独立性不可指认，固定文案也能过。
- **要的字段**：

```json
{
  "port": 7777,
  "runs": [
    {"input": "hi, human", "local_bytes": ["68 69 2c 20 68 75 6d 61 6e"], "deliver_ms": 20},
    {"input": "hello, world", "local_bytes": ["68 65 6c 6c 6f ..."], "deliver_ms": 25}
  ],
  "bridge": {"kind": "world_port", "wired": true}
}
```

- **实现侧**：World Port 桥接与字节抓取在仿真核心；终端显示在 UI。
- **影响面**：F1-1 解除 pending；终章 F2/F3 复用同一「真实字节」产出口径。
- **估时**：6 人日。

### 2.11 14.2 类型标签导出（`T14.2-1`，已实施 2026-11-05）

- **课文原话**：「需技术侧扩接口：标签判据（每个值的 `{type_tag, value}` + 运算前检查结果） / 最小替代：同一变量先存 1 再存 `"hi"`、再算 `1+"hi"`，标签必须跟着值变；运算前的检查结果要能看到两边类型，不能只给一个报错布尔位。」
- **实现方式**：`src/core/mini_interp.gd::run_typed(src)` 复用 `lex/parse/eval`，扩出 `parse_program`（按 `;` 切语句、`ident=expr` 记赋值）与带标签求值。逐值标签按 **AST 路径**绑定（根为 `root`，子节点为 `root/0`、`root/1`），子先父后按求值顺序导出。
- **导出字段（下游真读）**：

```json
{
  "tags": [
    {"stmt": 1, "node": "root",   "type_tag": "INT",  "value": "1"},
    {"stmt": 2, "node": "root",   "type_tag": "STR",  "value": "hi"},
    {"stmt": 3, "node": "root/0", "type_tag": "INT",  "value": "1"},
    {"stmt": 3, "node": "root/1", "type_tag": "STR",  "value": "hi"},
    {"stmt": 3, "node": "root",   "type_tag": "ERROR","value": "TYPE_MISMATCH"},
    {"stmt": 4, "node": "root",   "type_tag": "STR",  "value": "hi"}
  ],
  "errors": [{"stmt": 3, "node": "root", "code": "TYPE_MISMATCH", "left": "INT", "right": "STR"}],
  "meta": {"tag_follows_value": true, "error_names_both": true, "program_alive": true}
}
```

- **判据**：`table`（不新增 kind、不新增失败码）；`T14.2-1` 由 pending 转正，`keys = stmt/node/type_tag/value`，`expect_rows` 为上面 6 行。行数不符 → 13，单元格不符 → 7，`meta` 判据不符 → 10，未交 rows → 3。
- **能红证据（实测原文）**：
  - 漏一行（删 stmt4 标签）→ `E_COVERAGE(13)`
  - 多一行（复制 stmt1 标签）→ `E_COVERAGE(13)`
  - 标签绑错节点（`root/0` 改挂 `root/1`）→ `E_TABLE_CELL(7)`
- **影响面**：CH14 进分母 11→12、pending 1→0；全书 pending 实测由 19 降到 **17**（另有 CH13 同步转正 −1；CH05 的 `required=false` quiz 与 CH02 整节 deferred 不算进分母）；`test_ch14` 检查数 59→65，全量读数 `7354/7354`、`7356 checks`。`T14.2-2`（skip 层）与 `T14.2-3/-4`（4 位标签复算、quiz）口径不变。
- **估时**：2 人日（实际单会话内完成）。

## 3. 批准门槛（提案用）

1. 先批**字段形状**，不批具体数值；数值仍由数据侧定并挂 pending。
2. 任一项落地必须同时给：单测（越限/缺失各一例）、一条 `RED-PROBE ... -> code=N` 实测原文、对应章降级清单同步删除该条。
3. 未落地前，降级清单里的「最小替代」继续生效，**不得**用本文件字段冒充已实现。
4. 本提案不新增失败码，也不新增 kind；需要新 kind 时另写提案。

## 4. 与既有判据的关系

- 已落地的 `table`（含 `delay:{key,max}` 与 `timing`）能承接 2.1/2.2/2.6/2.7/2.8/2.9 的行级比对形状；2.3/2.5 需要嵌套结构，仍在 `table` 内以「一行一对象」表达，不改 kind。2.6 的 `sent_at/got_at` 取自仿真事件时钟，`timing` 只做自洽校验，不引入新失败码。
- 2.4 的签名顺序与 15.3 的 ABI 判据共用符号表；批 2.4 前不得先改 15.3。
- 2.10 与 17.1/17.3 共用「真实字节」口径；批 2.10 前 F1 仍按最小替代判。
- 2.11（14.2 标签导出）已落地，与 2.3（14.1 tokens/AST）共用同一份 `mini_interp`：14.1 走纯数值 `eval`，14.2 走 `run_typed` 的带标签求值；两套口径互不影响。

——
本文件由 CH13–CH19 + 终章落地批次整理；2026-11-05 补录并实施 §2.11，同日按指令实施 §2.6（16.3 逐请求时延）。
