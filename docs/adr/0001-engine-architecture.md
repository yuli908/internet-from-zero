# ADR 0001 · 引擎架构：Godot 4.4.1 + GDScript 主导

- 状态：已接受（Accepted）
- 日期：2026-11-04
- 决策者：技术负责人
- 关联：[0002 原生边界](0002-native-boundary.md)、[0003 存档与确定性](0003-save-and-determinism.md)、[0005 仿真契约](0005-simulation-contract.md)、`docs/design/03`、`docs/simulation/01`

## 1. 背景

本作是**二维教育模拟**而不是 3D 游戏：画面由文字、几何图形、开关、导线、波形构成；
核心负载是"大量小控件 + 每帧少量 tick 的确定性仿真 + 频繁读写的 JSON 数据"。

硬性需求：

1. Windows 单机，可离线，无联网依赖（联网功能明确不做）。
2. 启动即可玩，无需外部文档；存档必须能在崩溃后回退（见 ADR 0003）。
3. 教学内容高频改动（文案、gate 用例、价格、关卡数据），**不能每次改文案都重新编译**。
4. 仿真必须整数 tick 可复现；性能预算 5 ms/帧、4 tick/帧、≤200 门（GDScript 估算值，见 `docs/simulation/06`）。
5. 未来若门数/时序规模超出脚本能力，要能**渐进下沉**到原生，而不是整体重写。

## 2. 决策

采用 **Godot 4.4.1（GL Compatibility）+ GDScript 主导**：

| 层 | 落地 | 理由 |
|---|---|---|
| 数据 | `data/*.json`（manifest 8 文件，版本 2） | 内容迭代不触发编译；`DataDB.validate()` 在启动期做结构与引用校验 |
| 壳层 | 8 个 autoload（EventBus / DataDB / GameState / SaveManager / Knowledge / ChapterFlow / Economy / Tutorial） | 单一职责、事件解耦；UI 不互相调用 |
| 纯逻辑 | `src/core`、`src/sim`：`RefCounted` + `class_name`，**不引用任何 autoload** | 可 headless 直测（`godot -s res://tests/run_tests.gd`）；将来可整体下沉原生 |
| 仿真 | `SimValue`（三值 Kleene）、`SimEngine`（`(tick, seq)` 最小堆）、`SimCircuit`（线网/延迟/毛刺/快照）、`SimDelays`（唯一延迟来源） | 语义对齐 Python 参考实现；纯整数 tick |
| 界面 | 纯 Control 节点 + `UiTheme` / `Ui` 构造器 + `SystemFont`（Microsoft YaHei UI），无外部图片 | 2D UI 成本最低；字体与色板统一，1080p 基准 |
| 渲染 | `gl_compatibility`，1440×900 视口（截图用 1600×900） | 老显卡/虚拟机可跑；教育场景不需要高级渲染特性 |

明确不做：3D、粒子、物理引擎、TileMap、自定义着色器美术管线。

## 3. 后果

正面：

- 编辑器与场景/控件能力成熟，纯代码构造 UI（`main.gd` 一行行 build）即可交付，无需美术资源。
- GDScript 与 JSON 天然亲和，内容团队改数据即可验证（`DataDB.validate()` + 测试）。
- 逻辑层与引擎层解耦后，测试不需要主场景、不需要渲染，CI 可 headless 跑全量（902 项）。
- GDExtension 是**渐进**路径：先脚本跑通语义，再按实测把热区下沉（ADR 0002）。

负面/代价：

- GDScript 单事件成本高（估算 3–8 µs，`docs/simulation/06`）：上限 200 门 / 200 DFF 属**估算**，尚未实测；超标策略是"降速不丢事件"。
- GDScript 无编译期类型检查，只能靠测试兜底；曾出现"运行时才 `load()` 的脚本不进 `--editor --quit` 编译"的漏检（见 `docs/PROGRESS.md` 偏差 10）。
- 4.x 的 `.uid` 文件与导入缓存在仓库中出现，需要 `.gitignore` 纪律。

## 4. 备选方案与否决理由

| 方案 | 否决理由 |
|---|---|
| **Unity 6** | 授权与计费条款对教育/小团队不可控；2D UI（uGUI/UI Toolkit）搭建同等界面的成本高于 Godot Control；包体与启动时间更重；纯 C# 逻辑层同样要面对"内容改动即重编译" |
| **自研 C++ 引擎** | 窗口、输入、字体与文本排版、控件、布局、撤销/重做、截图全部要自己写，属于把 80% 工期花在与教学无关的基础设施上；本作不需要自研渲染 |
| **Electron / Web（TS + Canvas/DOM）** | DOM 布局简单，但确定性 tick 与大批量位运算不如本地；高频控件重排与 60 FPS 的稳定帧预算难保证；桌面文件与进程能力（未来 L7 桥接、沙箱）要额外搭桥；存档/原子写要绕 Node 层 |
| **Godot 3.x** | 已停止主线维护；`SystemFont`、`Control` 主题与 GDExtension（4.x 才有）均缺失，未来下沉原生没有官方路径 |
| **Godot 4 + C#（.NET 版）** | 需要 .NET SDK 与 Mono 运行时，分发包更大；团队 GDScript 熟练度更高；C# 与 GDScript 混用会增加边界与调试成本，收益（性能）在本里程碑规模内不明显 |
| **纯 Python（pygame 等）** | 参考实现是 Python，但用它当游戏宿主会在 UI 与分发上踩坑；且"参考实现"与"产品实现"应当语言隔离，避免同源 bug（见 ADR 0005 的 oracle 策略） |

## 5. 复审触发条件

出现以下任一情况，应重开本 ADR：

1. 实测 200 门场景在目标机器上持续超 5 ms/帧（→ 触发 ADR 0002 的 GDExtension 落地）。
2. 需要 3D 或大量美术资源（→ 评估换引擎）。
3. 需要多人协作/联机（当前明确不做）。
4. Godot 主线版本跨越到 4.5+ 且 GDExtension ABI 不兼容（→ 评估升级与 golden 重录）。
