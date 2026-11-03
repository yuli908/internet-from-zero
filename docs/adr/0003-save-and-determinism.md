# ADR 0003 · 存档与确定性

- 状态：已接受（Accepted）；前向迁移框架部分为"未完成"
- 日期：2026-11-04
- 关联：[0002 原生边界](0002-native-boundary.md)、[0005 仿真契约](0005-simulation-contract.md)、`docs/simulation/02_determinism.md`

## 1. 背景

本作把"确定性"当作产品承诺的一部分：**相同起始状态 + 相同操作序列 ⇒ 相同结果**。
玩家会反复试错、反复验收；若同一电路两次验收结论不同，"教学"就变成了玄学。
同时存档必须抗崩溃：断电/强杀/磁盘写失败都不能让玩家丢掉 20 分钟的进度。

两条需求互相牵制：存档要"停在可复现的点"，仿真要"能在任意时刻被保存而不改变未来轨迹"。

## 2. 决策

### 2.1 存档信封 v2（`src/core/save_codec.gd`）

```
{
  "fmt": "internet-from-zero.save",
  "version": 2,
  "algo": "sha256",
  "checksum": "<sha256(payload_str)>",
  "payload": "<JSON string>"
}
```

- **信封 + payload 字符串双层**：信封是纯文本常量与校验和，payload 是可演进的业务状态。
- `payload` 内也带 `version`，与信封版本一致；读取时取 payload 的 `version` 判定迁移。
- 校验和覆盖的是 `payload` 原文（`JSON.stringify(p, "", true)`，键序稳定），任何改动都会被发现。
- 只允许整数/字符串/布尔/数组/对象；**禁止浮点进入仿真状态**（`stats.play_seconds` 是唯一例外，属统计而非仿真）。
  - 假设：`play_seconds` 不参与任何判定，因此允许 float；若将来参与判定，需改为整数毫秒。

### 2.2 原子写：tmp → 回读校验 → `.bak` → rename（`src/core/save_store.gd`）

写入顺序固定（每一步失败都可安全中止）：

1. 写 `slot_1.json.tmp`；
2. **回读** tmp 并与内存文本逐字节比对（防"写成功但内容被截断"）；
3. 若已有 `slot_1.json`，先把旧内容写进 `slot_1.bak`；
4. 删旧主文件 → `rename(tmp → slot_1.json)`；rename 失败则退化为直接写主文件并删除 tmp。

读取顺序：主文件 → 解码失败则回退 `.bak`（结果带 `used_backup=true` 与 `primary_error`）→ 两者皆坏则报错。
测试覆盖（`tests/test_save.gd`）：校验和篡改检测（错误文本含"校验和"）、损坏 JSON 拒绝、二次保存生成 `.bak`、主文件损坏后从 `.bak` 恢复且 `used_backup=true`、删除槽位、空槽位读取失败。

### 2.3 确定性：整数 tick + `(tick, seq)` 全序（`src/sim/sim_engine.gd`）

- 时间只有整数 tick；`seq` 在入队时单线程自增；堆比较先 `t` 后 `seq`。
- **禁止**遍历 `Dictionary` / `Array` 决定行为（`SimCircuit.build_graph` 遍历节点时按插入序，输出前对线网键**排序**）。
- 单 tick 事件数超 `limits.max_events_per_tick`（当前 20000）→ 显式失败（`SimLimitExceeded` 语义），**不静默丢事件**；
- `run_until` / `run_events` 另有"事件数异常膨胀"上限（`max_events_per_tick * 64`），用于捕获组合环/零延迟自激。
- 帧只是**输入**：每帧最多 4 tick（`SimDelays.ticks_per_frame()`），预算超了只减少本帧 tick 数（降速），事件堆不变 ⇒ 轨迹不变。测试断言"1 tick/帧 与 4 tick/帧 跑同样输入，线网快照完全一致"。

### 2.4 快照/恢复：只在静止点，且恢复不触发监听者（`src/sim/sim_circuit.gd`）

- `snapshot()` 在事件队列非空时**拒绝**（`{ok:false, error:"队列非空…"}`）；格式 `ifz-circuit/1`：
  `{format, tick, wires（键排序）, digest, canonical}`，`digest = SHA-256(canonical JSON)`。
- `restore()` 要求 `format == "ifz-circuit/1"` 且队列为空；**直接写线网字段**（`prev / bits / last_change`），
  **不经过 `_write()`、不调用 listener**。原因：若走正常写入路径，会立刻产生新事件，破坏"恢复后队列为空"的静止前提，
  恢复出的未来轨迹就会与原轨迹分叉（`test_sim.gd` 断言：`snapshot → restore → snapshot` 的 digest 必须相同）。
- 存档只存 `CircuitGraph.to_dict()`（人类可读拓扑）+ 结果 flags（`labstate:<lab>`、`gate:<id>`、`lab:<id>`），
  **不存仿真堆**：堆里的闭包不可序列化，且跨版本恢复会破坏语义。
- `digest` 只用于"同一实现内比对"和回归；跨语言（Python oracle）比对用**真值向量**（ADR 0005），不比对 digest。

### 2.5 版本迁移现状（重要）

- **已实现**：信封 v2 + **v1→v2 迁移**。`SaveCodec.decode()` 遇到 legacy payload（`version=1`，`player` 嵌套结构）会自动
  调用 `_migrate_v1_to_v2()` 拍平字段并补默认值，返回 `migrated_from=1`；`SaveStore.load_slot()` 把 `migrated_from` 透出。
  `tests/test_save.gd` 有断言（`migrated from v1 == 1`、默认 `labs_completed` 为空、`rng_seed` 默认 1）。
- **已实现**：存档版本**高于**当前（v3+）时**明确拒绝**，错误文本含"高于"，而不是尝试迁移。
- **未实现（缺口）**：v2 之后的**前向迁移框架**。当前迁移是 `match version` 手写分支，没有"注册式迁移器 + 迁移链校验"；
  新增版本必须改 `SaveCodec` 源码并手写 `_migrate_vN_to_vN1`，且没有"迁移后 digest/字段完整性"的契约测试。
  - 风险：版本一多，`match` 分支会退化为不可测的意大利面；迁移漏字段只在真实老档上暴露。
  - 待办（需人工）：注册表化 + 每条迁移一份 fixture（老档样本进 `tests/data/`）+ 迁移链长度与推进版本号断言（现有 `guard > 16` 与"必须推进版本号"检查可复用）。

## 3. 后果

- 玩家侧：写档失败不会毁掉上一份好档；主文件坏了自动回退；老档（v1）能读。
- 开发侧：任何改字段的提交都必须回答三个问题——"老档还能读吗？迁移写了吗？fixture 加了吗？"
- 确定性侧：只要不把"帧号/真实时钟/浮点"塞进状态，跨帧率与跨存档的轨迹都一致。

## 4. 备选方案与否决理由

| 方案 | 否决理由 |
|---|---|
| **`Resource` + `.tres`/`.res`** | 反序列化会执行构造与 setter，攻击面与不确定性都在；Godot 资源路径与 UID 会把存档绑死在工程结构上；版本迁移难 |
| **纯 JSON，无信封/无校验** | 半截文件与手工篡改无法区分；回退策略无从谈起 |
| **SQLite / 外部数据库** | 单机单档不需要事务数据库；引入原生依赖与跨平台打包负担；与"原子写 + .bak"已能满足的可靠性目标重复 |
| **二进制定长存档** | 字段演进成本高、不可人读、调试成本高；大场景才需要（07 §6.2 可选），当前规模不需要 |
| **每次改动都 bump 到新格式、老档作废** | 教育产品玩家会长期不玩再回来；作废旧档等于丢进度，不可接受（02 §8.3 的 major 规则只允许"改延迟常量/排序规则"时作废） |
| **全量事件日志重放（不存快照）** | 回放长、启动慢；且玩家"手动点击"的输入序列无法完整记录（UI 采集点太散），M1 不做回放 |

## 5. 复审触发条件

1. 引入 L3 时序状态（DFF/时钟相位）进存档 → 需要新格式与迁移（ADR 0005 的 L3 契约）。
2. 存档体积 > 512 KB 或读档 > 50 ms → 考虑 07 §6.2 的二进制格式。
3. 出现第二个迁移档（v2→v3）→ 必须先完成注册式迁移框架。
