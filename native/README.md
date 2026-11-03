# native/ —— GDExtension 脚手架（M1 未编译）

> 状态：**未编译、未验证、未接入 `project.godot`**。
> M1 的门级仿真全部由 GDScript 实现（`src/sim/`），在 ≤200 门预算内够用。
> 本目录存在的意义是：当实测超预算时，能立刻开始下沉，而不是从零搭环境。决策与阈值见
> [`docs/adr/0002-native-boundary.md`](../docs/adr/0002-native-boundary.md)。

## 1. 文件

| 文件 | 作用 |
|---|---|
| `CMakeLists.txt` | `ifz_selftest`（纯 C++ 自检）/ `ifz_native`（可选 GDExtension 动态库） |
| `src/ifz_native.cpp` | 三值 Kleene 求值 + `(tick, seq)` 事件堆 + 延迟表镜像 + `IfzSim`（仅在 `IFZ_WITH_GODOT_CPP` 下编译） |
| `ifz_native.gdextension` | 描述文件，指向 `res://native/bin/ifz_native.dll`；**未在 `project.godot` 中启用** |
| `.gdignore` | 让 Godot 忽略整个 `native/`。否则编辑器会扫描 `.gdextension` 并尝试加载不存在的 dll，启动日志出现 3 行 `ERROR: GDExtension dynamic library not found`（实测：不带 `.gdignore` 的干净副本 5 处 ERROR，带则 0 处） |

> 注意：`.gdignore` 是"未构建状态"的开关。构建出 dll 后必须删除它，否则扩展永远不会被加载。
> 若某台机器在加入本目录前已有 `.godot` 缓存，首次运行可能仍残留一次 GDExtension 报错，
> 再跑一次 `godot --headless --editor --quit` 或让编辑器重建扫描缓存后即消失（不是代码问题）。

## 2. 构建（核心自检，不依赖 Godot）

```powershell
cmake -S native -B native/build -DIFZ_BUILD_EXTENSION=OFF
cmake --build native/build --config Release
ctest --test-dir native/build --output-on-failure
```

期望输出：`ifz_native selftest: PASS (0 failures)`。

> 已验证（2026-11-04）：MinGW g++ 15.1.0 + CMake，`ctest` 1/1 Passed。
> **MSVC 未验证**（本机无 `cl.exe`）；GDExtension 动态库未构建。

自检覆盖：

- 12 条 Kleene 向量（含 `X AND 0 = 0`、`X OR 1 = 1`、`xor(X,0)=X`）；
- 延迟表抽查（`not=1 / nand=2 / and=3 / xor=4 / xnor=5`）；
- 事件堆：`(tick, seq)` 升序、推进后队列清空、`now()` 正确。

## 3. 构建 GDExtension（需 godot-cpp）

前提：`godot-cpp` 分支与 Godot 4.4.1 对齐（ABI 不匹配会直接加载失败）。

```powershell
cmake -S native -B native/build-ext -G "Visual Studio 17 2022" -A x64 `
      -DIFZ_BUILD_EXTENSION=ON -DGODOT_CPP_DIR=D:\tools\godot-cpp
cmake --build native/build-ext --config Release
```

产物应落在 `native/bin/ifz_native.dll`。

**接入前必须完成**（否则不要打开 `ifz_native.gdextension`）：

1. 与 GDScript 同向量：用 `tests/data/ref_vectors.json` 的 30 条门向量 + 9 条半加器向量跑 C++，逐条一致。
2. 语义等价：`(tick, seq)` 顺序、延迟表、三值传播必须与 `SimCircuit` 相同；不一致视为 C++ 实现错误。
3. 只允许一条引擎路径：接原生时 UI 与存档必须统一切到 `IfzSim`，禁止两套引擎并存判定。
4. 体积与启动：确认 dll 能被导入、无缺失 CRT。

## 4. 与文档契约的对应

| 契约 | 本目录位置 | 备注 |
|---|---|---|
| `docs/simulation/02` `(tick, seq)` 全序 | `ifz::Event` / `EventLess` | 同 tick 按 `seq` 先入先出 |
| `docs/simulation/03` 延迟表 | `ifz::gate_delay` | **镜像**；唯一来源仍是 `data/sim/delays.json`，CI 应比对 |
| `docs/simulation/04` 三值 | `ifz::Trit` + `kleene_*` | `Trit` 用 `uint8_t`，禁止 `bool` 混用 |
| `docs/simulation/07` §3 边界铁律 | `IfzSim` | 只做类型转换，算法全在 `ifz::` |
| `docs/simulation/07` §5 错误码 | 预留 `IFZ_ERR_*` | 当前仅 `not_implemented_code()` 占位 6 |

## 5. 已知缺口（需人工）

- 未实现：`setup_level / probe_many / trace_since / snapshot / restore / digest`，以及 `budget_us` 帧预算。
- 未实现：单 tick 事件上限之外的"降速不丢事件"（GDScript 侧有，C++ 侧未写）。
- 未实现：延迟常量 JSON ↔ 头文件 ↔ 文档的自动比对（人工核对）。
- 未验证：MSVC + CMake + godot-cpp 的实际构建（本机未安装/未尝试）。
- 未做：Rust(`gdext`) 备选方案的可行性验证（ADR 0002 §4 保留该方案）。
