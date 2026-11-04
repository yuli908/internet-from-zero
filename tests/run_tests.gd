extends SceneTree

## headless 测试入口：
##   godot --headless --path . -s res://tests/run_tests.gd
## 返回码 0 = 全通过，1 = 有失败。
##
## 防线：每个 suite 声明「应有的 check 数」。实际执行数少于声明数即判该 suite 失败——
## 运行时错误会让 suite 中途中止、后续 check 永不执行，而失败数仍为 0，光看失败数对「测试被删/被跳过」完全失明。

const SUITES := [
	"res://tests/test_bit_math.gd",
	"res://tests/test_logic_gates.gd",
	"res://tests/test_circuit.gd",
	"res://tests/test_economy.gd",
	"res://tests/test_knowledge.gd",
	"res://tests/test_chapter.gd",
	"res://tests/test_tutorial.gd",
	"res://tests/test_save.gd",
	"res://tests/test_data.gd",
	"res://tests/test_sim.gd",
	"res://tests/test_l2.gd",
	"res://tests/test_black_box.gd",
	"res://tests/test_lab_checks.gd",
	"res://tests/test_l3.gd",
	"res://tests/test_l3_vectors.gd",
	"res://tests/test_l2_vectors.gd",
	"res://tests/test_trace.gd",
	"res://tests/test_rewards.gd",
	"res://tests/test_macro.gd",
	"res://tests/test_ch02_kinds.gd",
	"res://tests/test_questions.gd",
	"res://tests/test_difficulty.gd",
	"res://tests/test_gate_result.gd",
	"res://tests/test_ch01_grants.gd",
	"res://tests/test_ch02.gd",
	"res://tests/test_denominator.gd",
	"res://tests/test_ch02_denominator_ui.gd",
	"res://tests/test_lab_bench_ui.gd",
	"res://tests/test_teaching.gd",
	"res://tests/test_ch01_sections.gd",
	"res://tests/test_ch01_sections_ui.gd",
	"res://tests/test_ch02_body.gd",
	"res://tests/test_ch02_sections.gd",
]

# TODO(迁移中)：期望数正逐个下沉到套件自己的 `const EXPECT`；已迁 13 个，其余仍在本表。
# 全部迁完后本表删除，总数改为运行时求和。
# 声明的 check 数（2026-11-04 实测，总数 3226）。少一项即该 suite 判红。
const SUITE_EXPECT := {
	"test_l2": 430,
	"test_black_box": 18,
	"test_lab_checks": 49,
	"test_l3": 100,
	"test_l3_vectors": 4,
	"test_l2_vectors": 36,
	"test_trace": 34,
	"test_rewards": 28,
	"test_macro": 69,
	"test_ch02_kinds": 49,
	"test_questions": 37,
	"test_difficulty": 24,
	"test_gate_result": 305,
	"test_ch01_grants": 43,
	"test_ch02": 100,
	"test_denominator": 46,
	"test_ch02_denominator_ui": 37,
	"test_lab_bench_ui": 36,
	"test_teaching": 46,
	"test_ch01_sections_ui": 256,
}

const ABORT_PROBE := "res://tests/_abort_probe.gd"
const EXPECT_PROBES := "res://tests/_expect_probes.gd"
const EXPECT_DROPS := "res://tests/expect_drops.txt"

func _initialize() -> void:
	print("=== Internet From Zero :: test runner ===")
	var ctx := TestContext.new()
	var executed := 0
	var declared := 0

	for path in SUITES:
		var name: String = str(path).get_file().get_basename()
		var res := load(path)
		if res == null:
			print("SUITE %s load_failed" % name)
			ctx.check("suite load %s" % path, false, "无法加载测试脚本")
			continue
		var consts: Dictionary = res.get_script_constant_map()
		# 期望数优先读套件自己声明的 EXPECT；未迁移的套件回退到本文件旧表。
		var expect: int = int(consts.get("EXPECT", SUITE_EXPECT.get(name, -1)))
		if expect > 0:
			declared += expect
		var inst: RefCounted = res.new()
		ctx.begin(name)
		print("-- ", path.get_file(), " expected=", expect)
		var before: int = ctx.checks
		inst.run(ctx)
		var actual: int = ctx.checks - before
		executed += actual
		print("SUITE %s expected=%d actual=%d" % [name, expect, actual])
		var v: Dictionary = TestContext.verdict(expect, actual)
		if not bool(v["ok"]):
			ctx.check("[guard] %s 执行数达标" % name, false,
				"实际 %d / 声明 %d：有 %d 项 check 未执行（中途中止或声明过期）" % [actual, expect, expect - actual])
		_verify_groups(ctx, name, consts, expect)
		_verify_drop(ctx, name, consts, path, expect)

	print("SUITE_TOTAL expected=%d actual=%d" % [declared, executed])
	var vt: Dictionary = TestContext.verdict(declared, executed)
	if not bool(vt["ok"]):
		ctx.check("[guard] 全量 check 数达标", false,
			"实际 %d / 声明 %d" % [executed, declared])

	# 自测：故意中断的探针必须被判红，否则这道防线本身没被验证过。
	var probe_red := _abort_probe_is_red()
	ctx.check("[guard] 自测：故意中断的 suite 被判红", probe_red,
		"探针未判红，检查总数下限机制失效")
	# 防线自检探针（_expect_probes.gd）必须存在：删掉它就绕过了三道防线的自检。
	ctx.check("[guard] 防线自检探针存在", FileAccess.file_exists(EXPECT_PROBES),
		"缺 %s：分组/下降防线无自检（应有 PROBE 1/2/3 RED 标记）" % EXPECT_PROBES)

	var ok: bool = ctx.report()
	print("=== %s ===" % ("ALL PASS" if ok else "FAILED"))
	quit(0 if ok else 1)

# 用与正式 suite 完全相同的路径跑一次探针（故意抛运行时错误中断），返回「是否判红」。
func _abort_probe_is_red() -> bool:
	var res := load(ABORT_PROBE)
	if res == null:
		print("GUARD_SELFTEST load_failed")
		return false
	var declared_probe: int = int(res.get_script_constant_map().get("DECLARED", 0))
	var ctx := TestContext.new()
	ctx.begin("guard_probe")
	var inst: RefCounted = res.new()
	var before: int = ctx.checks
	inst.run(ctx)
	var actual: int = ctx.checks - before
	var v: Dictionary = TestContext.verdict(declared_probe, actual)
	print("GUARD_SELFTEST declared=%d actual=%d red=%s (探针中途中止属预期)" % [declared_probe, actual, str(not bool(v["ok"]))])
	return declared_probe > 0 and actual < declared_probe and not bool(v["ok"])

## 逐组比对：组和=EXPECT、每组实际计数=声明、组说明有效、单组不过半、无未声明组。
func _verify_groups(ctx: TestContext, name: String, consts: Dictionary, expect: int) -> void:
	ctx.begin_group("")  # guard 自身不得计入上一套件最后一组的计数
	var groups: Dictionary = consts.get("EXPECT_GROUPS", {})
	if groups.is_empty():
		return
	var descs: Dictionary = consts.get("GROUP_DESCRIPTIONS", {})
	var sum := 0
	for g in groups:
		sum += int(groups[g])
	if sum != expect:
		ctx.check("[guard] %s 分组之和=EXPECT" % name, false, "组和 %d / EXPECT %d" % [sum, expect])
	var banned := ["", "无", "调整", "优化", "清理", "重构", "misc", "other", "rest", "general"]
	for g in groups:
		var want := int(groups[g])
		var got := int(ctx.group_counts.get(g, 0))
		if got != want:
			ctx.check("[guard] %s 组 %s 计数" % [name, str(g)], false,
				"实际 %d / 声明 %d（漏断言，或该组 label 前缀未生效）" % [got, want])
		var d := str(descs.get(g, "")).strip_edges()
		if d in banned:
			ctx.check("[guard] %s 组 %s 说明" % [name, str(g)], false, "说明缺失或空话：%s" % d)
		if float(want) > float(expect) / 2.0:
			ctx.check("[guard] %s 组 %s 不过半" % [name, str(g)], false,
				"%d > 总数 %d 的一半" % [want, expect])
	for g in ctx.group_counts:
		if not groups.has(g):
			ctx.check("[guard] %s 未声明组 %s" % [name, str(g)], false,
				"实际 %d 条" % int(ctx.group_counts[g]))

## 期望数下降检查：>10% 必须命中 expect_drops.txt 白名单行（并每次打印该行）；≤10% 必须有非空话理由。
func _verify_drop(ctx: TestContext, name: String, consts: Dictionary, path: String, expect: int) -> void:
	ctx.begin_group("")  # guard 自身不得计入上一套件最后一组的计数
	if expect <= 0:
		return
	var prev := _expect_in_head(path)
	if prev <= 0:
		print("EXPECT_BASELINE %s [skip] no baseline" % name)
		return
	if expect >= prev:
		return
	var drop := 1.0 - float(expect) / float(prev)
	if drop > 0.10:
		var row := _find_drop_row(name + ".gd", prev, expect)
		if row.is_empty():
			ctx.check("[guard] %s 大降需白名单" % name, false,
				"EXPECT %d→%d（降 %.1f%% > 10%%）需人工复核：expect_drops.txt 无匹配行" % [prev, expect, drop * 100.0])
		else:
			print("EXPECT_DROP ", row)
		return
	var why := str(consts.get("EXPECT_RATIONALE", "")).strip_edges()
	var banned := ["", "无", "调整", "优化", "清理", "重构"]
	if why in banned:
		ctx.check("[guard] %s 下降需写明删哪一条" % name, false,
			"EXPECT %d→%d（%.1f%%）理由缺失或空话" % [prev, expect, drop * 100.0])

## 基线取已提交的 HEAD：先读套件文件的 const EXPECT；迁移期文件里还没有，回退 HEAD 的 SUITE_EXPECT。
func _expect_in_head(path: String) -> int:
	var rel := str(path).replace("res://", "")
	var txt := _git_show("HEAD:" + rel)
	if not txt.is_empty():
		var re := RegEx.new()
		re.compile("const\\s+EXPECT\\s*(?::\\s*int\\s*)?(:?=)\\s*(\\d+)")
		var m := re.search(txt)
		if m != null:
			return int(m.get_string(2))
	var key := str(path).get_file().get_basename()
	var rt := _git_show("HEAD:tests/run_tests.gd")
	if rt.is_empty():
		return -1
	var row := RegEx.new()
	row.compile("\"%s\"\\s*:\\s*(\\d+)" % key)
	var r := row.search(rt)
	return int(r.get_string(1)) if r != null else -1

func _git_show(spec: String) -> String:
	var out := []
	var root := ProjectSettings.globalize_path("res://").replace("\\", "/").trim_suffix("/")
	var rc := OS.execute("git", ["-C", root, "show", spec], out)
	if rc != 0 or out.size() == 0:
		return ""
	return str(out[0])

## 白名单行格式：<套件文件> <旧值> <新值> <删掉哪一组/几条+理由> <批准人> <日期>
func _find_drop_row(file: String, prev: int, expect: int) -> String:
	var f := FileAccess.open(EXPECT_DROPS, FileAccess.READ)
	if f == null:
		return ""
	var head := "%s %d %d " % [file, prev, expect]
	while not f.eof_reached():
		var ln := f.get_line().strip_edges()
		if ln.is_empty() or ln.begins_with("#"):
			continue
		if not ln.begins_with(head) or not ln.contains("approved-by-"):
			continue
		var rest := ln.substr(head.length()).strip_edges()
		if rest.length() >= 8:
			return ln
	return ""
