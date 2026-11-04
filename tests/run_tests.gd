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
	"res://tests/test_teaching.gd",
	"res://tests/test_ch01_sections.gd",
	"res://tests/test_ch01_sections_ui.gd",
	"res://tests/test_ch02_body.gd",
]

# TODO(下一轮，待 UI/数据两会话空闲后再做)：把各套件期望数从本文件挪到各自测试文件的
# `const EXPECT := N`，总数改为运行时对已注册套件求和。这样每个会话只碰自己的文件，
# 不再出现“提交前临时把别人的数字置回 HEAD、提交后再恢复”的风险。
# 声明的 check 数（2026-11-04 实测，总数 2993）。少一项即该 suite 判红。
const SUITE_EXPECT := {
	"test_bit_math": 27,
	"test_logic_gates": 24,
	"test_circuit": 33,
	"test_economy": 42,
	"test_knowledge": 32,
	"test_chapter": 61,
	"test_tutorial": 12,
	"test_save": 120,
	"test_data": 615,
	"test_sim": 76,
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
	"test_teaching": 46,
	"test_ch01_sections": 260,
	"test_ch01_sections_ui": 250,
	"test_ch02_body": 23,
}

const ABORT_PROBE := "res://tests/_abort_probe.gd"

func _initialize() -> void:
	print("=== Internet From Zero :: test runner ===")
	var ctx := TestContext.new()
	var executed := 0
	var declared := 0

	for path in SUITES:
		var name: String = str(path).get_file().get_basename()
		var expect: int = int(SUITE_EXPECT.get(name, -1))
		if expect > 0:
			declared += expect
		var res := load(path)
		if res == null:
			print("SUITE %s expected=%d actual=0" % [name, expect])
			ctx.check("suite load %s" % path, false, "无法加载测试脚本")
			continue
		var inst: RefCounted = res.new()
		ctx.begin(name)
		print("-- ", path.get_file())
		var before: int = ctx.checks
		inst.run(ctx)
		var actual: int = ctx.checks - before
		executed += actual
		print("SUITE %s expected=%d actual=%d" % [name, expect, actual])
		var v: Dictionary = TestContext.verdict(expect, actual)
		if not bool(v["ok"]):
			ctx.check("[guard] %s 执行数达标" % name, false,
				"实际 %d / 声明 %d：有 %d 项 check 未执行（中途中止或声明过期）" % [actual, expect, expect - actual])

	print("SUITE_TOTAL expected=%d actual=%d" % [declared, executed])
	var vt: Dictionary = TestContext.verdict(declared, executed)
	if not bool(vt["ok"]):
		ctx.check("[guard] 全量 check 数达标", false,
			"实际 %d / 声明 %d" % [executed, declared])

	# 自测：故意中断的探针必须被判红，否则这道防线本身没被验证过。
	var probe_red := _abort_probe_is_red()
	ctx.check("[guard] 自测：故意中断的 suite 被判红", probe_red,
		"探针未判红，检查总数下限机制失效")

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
