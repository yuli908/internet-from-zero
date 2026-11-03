# ADR 0002 · 原生边界：何时必须 GDExtension

- 状态：已接受（约束）/ 实现待启用（`native/` 脚手架未编译）
- 日期：2026-11-04
- 关联：[0001 引擎架构](0001-engine-architecture.md)、[0005 仿真契约](0005-simulation-contract.md)、`docs/simulation/06_performance.md`、`docs/simulation/07_api_contract.md`、`docs/simulation/09_feasibility_risks.md`

## 1. 背景

M1 的门级仿真用纯 GDScript（`src/sim/*`）落地，语义已与 Python 参考实现逐向量对齐。
但 `docs/simulation/06` 的器件上限是**估算**：GDScript ≈ 200 门 / 200 DFF、GDExtension ≈ 10,000 门 / 8000 DFF
（前提 60 FPS、5 ms/帧、4 tick/帧）。估算不是承诺，必须被工程内基准关校准。

因此要先写死"什么情况下**必须**离开 GDScript"，避免两种失控：
一是过早下沉原生（工期与 CI 复杂度前置投入）；二是拖到卡顿才动手（玩家已经看到掉帧）。

## 2. 决策

### 2.1 必须（MUST）使用 GDExtension 的判据

满足任一条即必须下沉原生，且必须先有基准数据支撑：

| 判据 | 阈值 | 依据 |
|---|---|---|
| 单场景门数 | `> 200 门` 或 `> 200 DFF` | `data/sim/delays.json` 的 `limits.gdscript_gates/gdscript_dff`；`require_gdextension_above = 200` |
| 单 tick 事件量 | 最坏全翻转场景下，5 ms 预算内跑不完 4 tick | `docs/simulation/06` §2.3（"最坏全翻转"验法） |
| 时序仿真 | 需要 ≥ 1000 DFF 或同一 tick 内大量边沿（寄存器堆、计数器阵列） | L3 事件密度：每边沿 ≈ 4 事件 |
| 位宽向量化 | 8/16/32 位位串逐位运算成为热区（ALU、总线、CRC） | 脚本位运算慢一个数量级（07 §2） |
| 帧内序列化 | 大网表 snapshot + SHA-256 出现在帧内 | 07 §2：快照序列化必须原生或后台线程 |
| 路由/图算法 | 256 节点 Dijkstra / 距离矢量每帧重算 | 07 §2：脚本单次 1–3 ms |

反之，**不得**为以下内容引入原生：探针/波形绘制、关卡流程、文案、音效、JSON 解析（07 §2 已规定）。

### 2.2 边界形状（与 `docs/simulation/07` 对齐）

1. 纯 C++ 层 `ifz::SimEngine` **不 include 任何 Godot 头文件**，可独立编译与单测（07 §3 铁律 2、§9）。
2. Godot 侧只做类型转换：`IfzSim`（`RefCounted`）暴露 `setup_level / step_ticks / probe / probe_many / trace_since / snapshot / restore / digest`。
3. 每帧只跨边界一次：一次 `step_ticks` + 一次批量 `probe_many`；禁止逐线网跨语言调用。
4. 错误用返回码（0–18，见 07 §5），不跨边界抛 C++ 异常。
5. 延迟常量**只有一份来源**：`data/sim/delays.json`；头文件/编译期常量由它生成，CI 比对"文档表格 == JSON == 头文件"。

### 2.3 本仓库的落地形态

- `native/CMakeLists.txt`：`ifz_core`（纯 C++ 静态库）+ 可选 `ifz_native`（GDExtension，需 `godot-cpp`）。
- `native/src/ifz_native.cpp`：`ifz::Trit`、`ifz::Bits`、`(tick, seq)` 堆骨架、Kleene 门求值、延迟表、`IfzSim` 的 GDCLASS 壳（仅在 `IFZ_WITH_GODOT_CPP` 下编译）。
- `native/ifz_native.gdextension`：`entry_symbol = ifz_library_init`，Windows x86_64 指向 `res://native/bin/ifz_native.dll`。
- **M1 状态：仅脚手架，未编译、未验证、未接入 `project.godot`**。GDScript 版本在 ≤200 门预算内是当前唯一实现。

## 3. 后果

- 现在：无原生依赖、CI 简单、调试单栈；缺点是性能上限未知。
- 未来：语义层（GDScript）与性能层（C++）必须**同向量等价**；`tests/data/ref_vectors.json` 可直接复用为跨实现 golden。
- 双实现并存期间，判定**只允许**走一条路径（`SimCircuit` 或 `IfzSim`），避免"UI 看到的和存档记录的不是同一个引擎"。

## 4. 备选方案与否决/保留理由

| 方案 | 结论 | 理由 |
|---|---|---|
| **C++20 + godot-cpp（当前脚手架）** | 采用 | 与 07 的接口草案同语言、同数据结构（`Trit=uint8_t`、整数 NetId）；可直接复用 07 §9 的独立编译验收片段 |
| **Rust + gdext（godot-rust）** | **保留**（不改当前脚手架） | 优点：内存安全、`enum Trit` 表达力、cargo 测试与 fuzz 方便、无 UB 风险。否决为"当前实现"的理由：需要额外 Rust 工具链与 `gdext` 版本与 Godot 4.4.1 精确对齐；07 的 API/头文件草案是 C++ 形状，双语种并行会长期双维护；团队未验证 Rust 在本仓库的构建链。触发切换的条件：C++ 侧出现内存安全类缺陷，或需要使用 Rust 生态的 fuzz/并发工具 |
| **GDScript + 多线程** | 否决 | 确定性要求单线程事件循环（02 §2、07 §7 铁律 1）；线程化只会引入顺序不确定性 |
| **GDExtension + 计算着色器 / GPU** | 否决 | 门级事件是稀疏分支密集负载，GPU 不适合；且结果回读破坏确定性时延 |
| **外部进程（Python/C++ 伴生）做门级仿真** | 否决 | 每 tick 进程间通信成本远超收益；且崩溃隔离可留给 L7 沙箱（ADR 0004），不用于主仿真 |
| **旧 GDNative（3.x）** | 否决 | Godot 4 已移除；见 ADR 0001 |

## 5. 待办（需人工）

1. 建立基准关：固定 64/256/1024 门 × 全翻转场景，测"事件/毫秒"与"帧内 tick 数"，写入 `artifacts/logs/bench.log`。
2. 用实测数据回填 `docs/simulation/06` 的估算（只读文档，需与该文档负责人确认后再改）。
3. 若实测 < 200 门即超预算，下调 `limits.gdscript_gates` 并在 `docs/PROGRESS.md` 记偏差。
4. 原生路径落地前，先在 CI 跑 `ifz_core` 的独立测试（07 §9），再谈接入 Godot。
