extends SceneTree

## headless 测试入口：
##   godot --headless --path . -s res://tests/run_tests.gd
## 返回码 0 = 全通过，1 = 有失败。

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
]

func _initialize() -> void:
	print("=== Internet From Zero :: test runner ===")
	var ctx := TestContext.new()
	for path in SUITES:
		var res := load(path)
		if res == null:
			ctx.check("suite load %s" % path, false, "无法加载测试脚本")
			continue
		var inst: RefCounted = res.new()
		ctx.begin(path.get_file().get_basename())
		print("-- ", path.get_file())
		inst.run(ctx)
	var ok: bool = ctx.report()
	print("=== %s ===" % ("ALL PASS" if ok else "FAILED"))
	quit(0 if ok else 1)
