# M1 验收清单

> 逐条可判定；不能自动验证的明确标「需人工」。

## A. 工程可启动
- [x] A1 `--editor --quit` 导入检查无 `Parse Error` / `ERROR:`（`artifacts/logs/import.log` 为空结果）。
- [x] A2 启动日志出现 `IFZ_BOOT data_ok=true files=8 chapter=ch01`（`artifacts/logs/shot_workbench.log:4`）。
- [x] A3 `artifacts/shots/` 下 11 张截图存在、非空、日志无 `SCRIPT ERROR`。

## B. 数据驱动
- [x] B1 `data/manifest.json` 列出 8 个数据文件、version=2（`tests/test_data.gd`）。
- [x] B2 物品 86 项（77 正式 + 7 旧别名 + gold 货币 + scrap 材料），价格/配方引用的物品全部存在（`tests/test_data/test_economy.gd`）。
- [x] B3 技能/知识树 36 节点（里程碑 7 / 知识卡 19 / 技能 10）（`tests/test_data.gd`）。
- [x] B4 第一章 6 实验、24 条 gate、每节 4 条且与 `gate_ids` 一致（`tests/test_data.gd`）。
- [x] B5 价格与奖励均从 JSON 读取（`Catalog.buy_price/sell_price`、`ch01_levels.json` 的 `reward`）。

## C. 判定与知识树/存档
- [x] C1 `LabChecks` 6 节判定齐备，24 条 gate 正确解全过、错误解失败（`tests/test_lab_checks.gd`）。
- [x] C2 门级/半加器采用行为黑盒验收，XOR 两种结构都通过且 signature 不同（`tests/test_black_box.gd`）。
- [x] C3 gate 结果写入 `gate:<id>` flags 并落存档（`LabBase.pass_report`/`mark_gate` + `save_state`；代码路径已核对，真实点击需人工）。
- [x] C4 解锁写入知识树（`tests/test_knowledge.gd`：四态、CH01 链式解锁、奖励数值）。
- [x] C5 存档往返：v2 信封 + v1→v2 迁移 + 篡改检测 + `.bak` 回退（`tests/test_save.gd`）。

## D. 与参考模型一致
- [x] D1 `tests/data/ref_vectors.json` 来自 `docs/simulation/ref`，含 30 门向量 + 9 半加器向量（`tools/gen_ref_vectors.py`）。
- [x] D2 `test_sim` 逐条比对全部通过，延迟表与 ref 数值一致。
- [x] D3 三值（含 X）随机向量固定种子（seed=1，8 组），结果锁定（`tests/test_lab_checks.gd` 半加器 random_x）。

## E. 性能与范围边界
- [x] E1 GDScript 门级上限 ≤200 门/200 DFF 已写入数据与校验（`data/labs/ch01_labs.json` 的 `max_gates`）。
- [x] E2 `SimEngine` 单 tick 超限显式失败，不静默丢事件（`tests/test_sim.gd`）。
- [x] E3 M1 未实现 CPU/网络/加密功能（`src/` 无 L2+ 实现，仅 ADR 0005 占位）。
- [x] E4 `native/` 只有脚手架，未编译；`docs/PROGRESS.md` 标**未完成/需人工**。

## F. 文档与提交
- [x] F1 `README.md` 有运行命令、目录结构、M1 状态。
- [x] F2 `docs/adr/0001..0005` 齐备，含备选方案与否决理由；0005 含 L0–L7 契约映射。
- [x] F3 `docs/PROGRESS.md` 有偏差表（原规格/实际实现/原因）与「已完成/未完成/下一步」。
- [x] F4 `scripts/*.ps1` 可用；`selfcheck.ps1` 本地跑通（导入 PASS / 测试 PASS / 冒烟 PASS）。
- [x] F5 `git log` 有 data / sim+checks / UI / tests / docs 五次提交；每次提交前均跑过导入检查。

## G. 仍需人工（不计入通过）
- [ ] G1 6 节真实点击走查（操作 → 验收 → 知识树 completed → 重启读档）。
- [ ] G2 性能基准关（64/256/1024 门，5 ms/帧实测）。
- [ ] G3 GDExtension 动态库构建与接入。
- [ ] G4 真实 GitHub Actions 跑通。
