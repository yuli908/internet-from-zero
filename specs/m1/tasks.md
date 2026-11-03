# M1 任务清单（按执行顺序）

> 完成定义：代码可运行 + 自动测试通过 + 截图/日志证据 + 一次 git 提交。
> 未跑通不标记完成；无法自动验证的标「需人工」。

## T1. 仓库与基线核查
- [x] 检查 `git status`、`.gitignore`、`README` 是否存在；若未初始化：`git init` + 基线提交。
- [x] 建立 `artifacts/shots/` 与 `backups/` 忽略规则。
- 验证：`git log --oneline` 至少 1 条；`git status` 干净或仅预期改动。

## T2. 数据索引修正与校验
- [x] `Catalog.recipe_ids()`、`Catalog.recipe_for_output()`。
- [x] `shop_screen.gd` 配方 output 兼容与层级排序修正。
- [x] `DataDB.validate()` 无错误（启动日志 `data_ok=true`）。
- 验证：headless 加载数据脚本打印 0 errors。

## T3. 纯逻辑判定层
- [x] 新增 `src/core/voltage_model.gd`。
- [x] 新增 `src/core/lab_checks.gd`（voltage/binary/boolean/gate/signal/half_adder）。
- [x] 修正 `BlackBox`（check_outputs/depth/signature）。
- 验证：`tests/test_lab_checks.gd` 覆盖 24 条 case id 的通过/失败路径。

## T4. UI 基础控件
- [x] 重写 `level_gauge.gd`（0.8/2.0 双阈值）。
- [x] 新增 `bit_switches.gd`、`waveform.gd`。
- [x] 新增 `circuit_editor.gd`（点击式；门/端口/连线/删除/评估/快照）。
- 验证：`gate` 与 `half_adder` 实验页能构建电路并 `evaluate()`。

## T5. 工作台与技能树页（启动阻断项）
- [x] `workbench_screen.gd`（6 实验、锁定原因、嵌入实验、solved→ChapterFlow）。
- [x] `skill_screen.gd`（三树、四态、解锁、详情）。
- [x] `LabBase.save_state/load_state/pass_report`。
- 验证：`--shot-screen=workbench` 与 `--shot-screen=skills` 成功出图，无缺失脚本。

## T6. 六个实验页
- [x] `lab_level.gd` 重写（T1.1-1..4）。
- [x] `lab_binary.gd`（T1.2-1..4）。
- [x] `lab_boolean.gd`（T1.3-1..4）。
- [x] `lab_gate.gd`（T1.4-1..4，多解、延迟、封装、第二结构）。
- [x] `lab_signal.gd`（T1.5-1..4）。
- [x] `lab_half_adder.gd`（T1.6-1..4）。
- 验证：每页 `--shot-lab=<id>` 出图；手动流程「操作 → 验收 → 知识树完成 → 存档」需人工走查（**需人工**，尚未由人点击验证）。

## T7. 测试更新与新增
- [x] 更新 `test_data/test_chapter/test_economy/test_knowledge/test_save/test_tutorial`。
- [x] 新增 `test_sim.gd`、`test_black_box.gd`、`test_lab_checks.gd`（原计划的 `test_gate_cases.gd` 合并进 `test_lab_checks.gd`，24 条 gate 全在同一套件内验证）。
- [x] `tools/gen_ref_vectors.py` + `tests/data/ref_vectors.json`（从 sim ref 导出）。
- [x] `run_tests.gd` 注册新套件。
- 验证：`run_tests.gd` 输出 `ALL PASS`，含「sim 与参考向量一致」。

## T8. 启动冒烟与截图
- [x] `--editor --quit` 生成类缓存。
- [x] 启动日志检查：`IFZ_BOOT data_ok=true`、无 `Parse Error`、无资源缺失。
- [x] 截图：workbench + 6 labs + shop + skills + archive + diagnostics。
- 验证：所有截图文件存在且非空；日志无 `ERROR:`。

## T9. 文档与脚本
- [ ] `README.md`。
- [ ] `docs/adr/0001..0005`。
- [ ] `docs/PROGRESS.md`（偏差表、完成度、下一步）。
- [ ] `scripts/run_game.ps1`、`run_tests.ps1`、`selfcheck.ps1`、`backup.ps1`。
- [ ] `.github/workflows/ci.yml`（标注需人工项）。
- [ ] `native/` 脚手架（不编译，ADR 说明）。
- 验证：`scripts/run_tests.ps1` 本地执行通过。

## T10. 提交与报告
- [x] 按子系统提交：data / sim+checks / UI / tests / docs+scripts（docs+scripts 待 T9 完成）。
- [ ] 最终报告：已完成、未完成、偏差、下一步、运行命令、截图路径、测试摘要。
- 验证：`git log --oneline` 至少 5 条新提交；报告与实况一致。
