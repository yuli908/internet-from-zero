# 07 接口契约（实现方 API 草案）

本文档给主工程技术负责人的**边界约定**。目标是把"必须原生"的部分与"可以脚本"的部分切干净,
并让存档/回放成为**格式**而不是"另写一套代码"。

## 1. 模块划分

| 模块 | 语言 | 职责 | 不允许做 |
|---|---|---|---|
| `ifz_sim`(GDExtension) | C++20 | 事件引擎、三值求值、器件、路由、TCP 定时器、快照/摘要 | 直接碰 `Node`/`SceneTree`/`Resource` |
| `ifz_view` | GDScript | 探针面板、示波器、抓包器、时序图、教学脚本 | 自己算门延迟/路由 |
| `ifz_level` | GDScript + JSON | 关卡数据(拓扑/器件表/初始状态/文案) | 硬编码延迟常量 |
| `ifz_bridge` | C++ + 宿主进程 | L7 真实主机桥接(本地 socket) | 解析游戏内协议 |

**只有一份延迟常量**:`delays.json` 由 `ifz_sim` 的编译期常量生成,
CI 校验"文档表格 == JSON == 头文件"。禁止三处各写一套。

## 2. 原生/脚本的划分(硬规则)

| 内容 | 必须原生 | 可 GDScript | 原因 |
|---|---|---|---|
| 事件队列与调度 | ✅ | ❌ | 每次 `push/pop` 都要 O(log n);脚本层做会成为瓶颈 |
| 三值逐位运算 | ✅ | ❌ | 位串向量化;脚本位运算慢一个数量级 |
| 器件(门/FA/ALU/寄存器/存储器) | ✅ | ❌ | 每 tick 被调用上万次 |
| 路由(Dijkstra / DV) | ✅ | ❌ | 256 节点 O(V²) 单次 1–3 ms(脚本) |
| TCP 定时器与重传 | ✅ | ⚠️ 可 | 事件量低;但必须与网络同一时钟,建议原生 |
| 快照序列化 + SHA-256 | ✅ | ❌ | 帧内做会卡顿;必须放原生(或后台线程) |
| 探针/波形绘制 | ❌ | ✅ | 只在可见时执行 |
| 教学脚本/关卡流程 | ❌ | ✅ | 频繁改,不该编译 |
| 音效/动画/文案 | ❌ | ✅ | 与仿真无关 |
| 关卡 JSON 解析 | ⚠️ | ✅ | 解析一次;校验必须调原生 |

> 判据:**每帧被调用 > 1000 次的逻辑,或影响确定性的逻辑 → 原生**。

## 3. GDExtension 边界(给 Godot 侧的最小面)

```cpp
// ifz/godot/ifz_sim.hpp  (草案,非最终实现)
namespace ifz {

class IfzSim : public godot::RefCounted {
    GDCLASS(IfzSim, RefCounted)

public:
    // 关卡装配:一次性。返回 ifz-sim/1 风格的结果字典 {ok, code, msg}
    godot::Dictionary setup_level(const godot::Dictionary& level);
    void reset(uint64_t world_seed);

    // 推进:最多 ticks 个 tick,最多 budget_us 微秒。允许"跑不完"。
    // 返回实际推进到的 tick;确定性不因 budget 改变。
    int64_t step_ticks(int64_t ticks, int64_t budget_us);

    // 观测:只读、无副作用
    godot::String probe(const godot::String& wire) const;
    godot::Array   probe_many(const godot::PackedStringArray& wires) const;
    godot::Dictionary trace_since(int64_t tick, int64_t max_events) const;

    // 存档/回放
    godot::Dictionary snapshot() const;                 // 队列非空 → {ok:false, code:IFZ_E_BUSY}
    godot::Dictionary restore(const godot::Dictionary& snap);
    godot::String     digest() const;

    // 回放:输入日志由 view 侧提供,原生按 (tick, seq) 应用
    godot::Dictionary replay_begin(const godot::Dictionary& replay_header);
    godot::Dictionary replay_apply(const godot::Dictionary& input_event);

    // 配置:冒险档位、是否记录 trace、是否分块
    godot::Dictionary configure(const godot::Dictionary& cfg);

private:
    ifz::SimEngine engine_;   // 纯 C++,无 Godot 类型
};
} // namespace ifz
```

**边界铁律**:

1. `IfzSim` 只做**类型转换 + 调用**,不含算法;算法在纯 C++ 的 `ifz::SimEngine` 里,
   可以被独立单测(不启动 Godot)。
2. 纯 C++ 层**不得** include Godot 头文件。理由:可跨引擎复用、可跑 CI、可被 fuzz。
3. 任何返回给 GDScript 的值都是**值语义**(`Dictionary`/`Array`/`String`),不暴露裸指针。
4. 每帧只跨边界**一次**(一次 `step_ticks` + 一次批量 `probe_many`),
   禁止在循环里逐线网调用(跨语言调用开销会吃掉预算)。

## 4. 数据结构(与参考实现同构)

```cpp
// ifz/types.hpp
using Tick = int64_t;
using Seq  = uint64_t;

enum class Trit : uint8_t { Zero = 0, One = 1, Unknown = 2 };

// 位串:小位宽用掩码,大位宽用 trit 数组。位序 bit0 = LSB。
struct Bits {
    uint32_t width;
    uint64_t value;      // width<=32 时有效
    uint64_t known;      // 1=确定, 0=X; value 与 known 同时用
    std::vector<uint8_t> ext;  // width>32
    Trit at(uint32_t i) const;
};

struct Event { Tick when; Seq seq; HandlerId handler; ArgId args; };

struct GateDesc   { GateKind kind; uint32_t width; int16_t delay; NetId out; NetId in[8]; uint8_t n_in; };
struct DffDesc    { uint8_t setup, hold, clk_to_q; NetId d, clk, rst, q; };
struct RouteEntry { uint32_t dst_ip; uint32_t next_hop_ip; uint16_t metric; uint8_t source; };

struct Packet {
    uint32_t src_ip, dst_ip; uint8_t ttl, proto, flags;
    uint32_t seq, ack; std::vector<uint8_t> payload;
};

struct Snapshot {
    std::string format;    // "ifz-sim/1"
    std::string engine_version;
    Tick tick; uint64_t world_seed;
    std::vector<std::pair<NetId, Bits>> wires;   // 按 NetId 排序
    std::vector<std::pair<RegId, int64_t>> regs;
    std::vector<std::pair<uint32_t, uint8_t>> memory;
    std::vector<TimerDesc> timers;   // handler_id + args,无闭包
    Seq next_seq;
    std::string digest;              // "sha256:..."
};
```

- `Trit` 用 `uint8_t`,不用 `bool` —— 需要三值,二值化会丢掉 X。
- `Bits` 的双表示是为了省内存:教学场景 1–8 位占绝大多数。
- 所有 id 都是**整数索引**(`NetId = uint32_t`),不是字符串;字符串只出现在
  `probe()` 的边界转换层。理由:字符串哈希会引入不稳定顺序与额外开销。

## 5. 错误码(固定,不可复用编号)

| 码 | 名称 | 触发 | 严重度 | 玩家可见 |
|---|---|---|---|---|
| 0 | `IFZ_OK` | — | — | — |
| 1 | `IFZ_E_BUSY` | 队列非空时存档 | 可恢复 | "请等电路稳定后再存档" |
| 2 | `IFZ_E_WIDTH` | 位宽不匹配 | 构建期致命 | 关卡加载失败 |
| 3 | `IFZ_E_KIND` | 未知门/器件 | 构建期致命 | 同上 |
| 4 | `IFZ_E_LIMIT` | 单 tick 事件超限 | 运行期致命 | "电路自激/存在环" |
| 5 | `IFZ_E_VERSION` | 存档 major 版本不符 | 致命 | "存档不兼容" |
| 6 | `IFZ_E_STATE` | 状态机非法迁移 | 致命(开发期 bug) | 不应出现 |
| 7 | `IFZ_E_NO_ROUTE` | 无路由表项 | 网络可恢复 | 抓包器标红 |
| 8 | `IFZ_E_TTL` | TTL 归零 | 可恢复 | 标红 |
| 9 | `IFZ_E_CRC` | FCS 校验失败 | 可恢复 | 标红 |
| 10 | `IFZ_E_LOSS` | 链路丢包 | 可恢复 | 标黄 |
| 11 | `IFZ_E_NO_ACK` | 从设备无响应超时 | 可恢复 | 标黄 |
| 12 | `IFZ_E_BUS_CONTENTION` | 多主设备同时驱动 | 可恢复 | 总线变 X + 提示 |
| 13 | `IFZ_E_ADDR` | 读越界/未初始化 | 可恢复 | `DOUT=X` |
| 14 | `IFZ_E_X_WRITE` | 写入含 X | 可恢复 | 拒绝写入 |
| 15 | `IFZ_E_ROM_WRITE` | 写 ROM | 可恢复 | 拒绝 |
| 16 | `IFZ_E_X_ADDR` | 地址含 X | 可恢复 | `DOUT=X` |
| 17 | `IFZ_E_FRAMING` | UART 停止位错 | 可恢复 | 标红 |
| 18 | `IFZ_W_METASTABLE` | 建立/保持违例（**警告**,非错误） | 警告 | 高亮 + 波形说明 |

- `METASTABLE` 是**警告**而不是错误:它不终止仿真,只是把 Q 置 X。
  把它当错误会让"时钟太快"这一课直接崩掉,玩家学不到东西。
- 错误码不复用:删掉的码永久保留空号,避免存档里的数字含义漂移。

## 6. 序列化

### 6.1 文本格式(默认,`.ifzsnap.json`)

- **canonical JSON**:键按字典序、无空格、无浮点、`\n` 分隔。
  `digest` = 去掉 `digest` 字段后的规范化串的 SHA-256。
- 只允许:整数、字符串、布尔、数组、对象。**禁止浮点与 NaN**。
- 版本字段:顶层 `format: "ifz-sim/1"` + `engine_version: "x.y.z"`。

### 6.2 二进制格式(可选,`.ifzsnap.bin`)

- 用途:大场景(10k 线网)读档 < 5 ms。
- 结构:`magic "IFZS" + u32 version + u32 flags + 段表(offset,len,type)`,
  段 = wires / regs / memory / timers / digest。
- 字节序固定 **little-endian**;跨平台读档必须显式转换。
- 两种格式必须能双向转换,并有等价性测试(读文本 → 写二进制 → 读回 → 逐字段比)。

### 6.3 回放(`.ifzreplay.jsonl`)

见 02 第 8.2 节。补充两条:

- 每行**必须**是 JSON 对象,单行 ≤ 4 KB(避免解析器大对象分配)。
- 文件末尾的 `checkpoint` 是**必须**的:没有它就无法证明"这段回放真的跑到了"。

## 7. 线程模型(确定性优先)

```
[主线程]  Godot 渲染/UI/输入
   │  ① 提交输入事件(带 tick)          ▲ ④ 读取不可变快照
   ▼                                   │
[仿真线程]  单线程事件循环 ──────────────┘
   │  ② step_ticks(k, budget)
   ▼
  ③ 发布 Snapshot(POD,双缓冲)
```

铁律:

1. **仿真永远单线程**。多线程事件队列无法保证 `(tick, seq)` 全序(02 第 2 节)。
2. 仿真线程**不得**调用任何 Godot API、不得 `emit_signal`、不得访问 `Node`。
   跨线程通信只允许"双缓冲 POD + 原子交换指针"。
3. 主线程只读**发布后的**快照;不能读仿真中状态(会撕裂)。
4. 输入事件必须带 **tick**,不能带"帧号"。同一 tick 的多个输入按提交顺序(seq)。
5. 存档必须由主线程发起 → 仿真线程在"静止点"生成 → 主线程写盘。
   存档期间仿真**暂停**(否则 digest 不可复现)。

## 8. 版本与兼容

| 变更 | 动作 | 存档 |
|---|---|---|
| UI/文案 | patch +1 | 全兼容 |
| 新器件/新字段(有默认) | minor +1 | 旧档可读;新档旧版不可读 |
| **改任何延迟常量 / 排序规则 / tick 语义** | **major +1** | 旧档作废 |
| 改 JSON 键名 | major +1 | 同上 |

- 载入时:`format` 不匹配 → `IFZ_E_VERSION`;**禁止"尽力解析"**。
- 任何 major 变更必须重录 08 的 golden 哈希,并在 `verify_report.md` 里留新记录。

## 9. 交付验收接口(给技术负责人)

原生模块必须能**脱离 Godot 独立运行**下面这段(CI 用):

```cpp
ifz::SimEngine e(/*max_events_per_tick=*/20000);
auto cir = ifz::build_full_adder(e);
cir.set_inputs(1,1,0);
e.settle();
assert(cir.probe("s") == Trit::One);
assert(cir.probe("cout") == Trit::One);
```

要求:

1. 不链接 Godot 也能编译(纯 C++ 目标 + `add_library(ifz_core STATIC)`)。
2. 同一段代码在引擎内与 CI 内产生**相同 digest**。
3. 头文件里的延迟常量与 `delays.json`、03 的表格三处一致(CI 脚本比对)。
4. 公开 API 全部**无异常跨边界**:错误用返回码,不用 C++ 异常
   (GDExtension 边界上抛异常是未定义行为)。
