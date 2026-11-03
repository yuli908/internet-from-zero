# M1 验收清单

> 逐条可判定；不能自动验证的明确标「需人工」。

## A. 工程可启动
- [ ] A1 `--editor --quit` 导入检查无 `Parse Error` / `ERROR:`。
- [ ] A2 启动日志出现 `IFZ_BOOT data_ok=true files=8 chapter=ch01`。
- [ ] A3 `artifacts/shots/` 下 11 张截图存在、非空、无 `SCRIPT ERROR`。

## B. 数据驱动
- [ ] B1 `data/manifest.json` 列出 8 个数据文件、version=2。
- [ ] B2 物品 85 项（77 正式 + 7 旧别名 + scrap），价格/配方引用的物品全部存在。
- [ ] B3 技能/知识树 36 节点（里程碑 7 / 知识卡 19 / 技能 10）。
- [ ] B4 第一章 6 实验、24 条 gate、每节 4 条且与 `gate_ids` 一致。
- [ ] B5 代码中无硬编码物品价格/章节数值（价格与奖励均从 JSON 读取）。

## C. 判定与知识树/存档
- [ ] C1 `LabChecks` 6 节判定齐备，24 条 gate 正确解全过、错误解失败。
- [ ] C2 门级/半加器采用行为黑盒验收，XOR 两种结构都通过且 signature 不同。
- [ ] C3 gate 结果写入 `gate:<id>` flags 并落存档。
- [ ] C4 解锁写入知识树（KnowledgeGraph 四态、CH01 链式解锁）。
- [ ] C5 存档往返：v2 信封 + v1→v2 迁移 + 篡改检测 + `.bak` 回退。

## D. 与参考模型一致
- [ ] D1 `tests/data/ref_vectors.json` 来自 `docs/simulation/ref`，含 30 门向量 + 9 半加器向量。
- [ ] D2 `test_sim` 逐条比对全部通过，延迟表与 ref 数值一致。
- [ ] D3 三值（含 X）随机向量固定种子（seed=1，8 组），结果锁定。

## E. 性能与范围边界
- [ ] E1 GDScript 门级上限 ≤200 门/200 DFF 已写入延迟与校验配置。
- [ ] E2 `SimEngine` 出现单 tick 超限时显式失败，不静默丢事件。
- [ ] E3 M1 未实现 CPU/网络/加密相关功能（保持范围克制）。
- [ ] E4 `native/` 只有脚手架，未编译；标注**需人工**。

## F. 文档与提交
- [ ] F1 `README.md` 有运行命令、目录结构、M1 状态。
- [ ] F2 `docs/adr/0001..0005` 齐备，含备选方案与否决理由；0005 含 L0–L7 契约映射。
- [ ] F3 `docs/PROGRESS.md` 有偏差表（原规格/实际实现/原因）与「已完成/未完成/下一步」。
- [ ] F4 `scripts/*.ps1` 可用；`selfcheck.ps1` 本地跑通。
- [ ] F5 `git log` 至少有 data / sim+checks / UI / tests / docs 五次提交，且每次提交后工程可启动（导入检查已在提交前跑）。
