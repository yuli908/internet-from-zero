extends RefCounted

## M4-G3/G4：8 种 CH02 判定 kind 的白名单、固定 payload 键、机械映射与帧粒度摘要一致。
## 口径：`docs/design/11` §3 的判定 kind 全大写；`build_area` 是语法糖，不产生 trace。

const CASES := {
	"mosfet_region": {"kind": "MOSFET_REGION",
		"payload": {"region": "cutoff", "vgs": 0.0, "vds": 1.0, "id_ua": 0.0}},
	"x_propagation": {"kind": "X_PROPAGATION", "payload": {"expect": "0", "got": "X"}},
	"static_current": {"kind": "STATIC_CURRENT", "payload": {"ua": 1.5, "states": 2}},
	"rail_margin": {"kind": "RAIL_MARGIN", "payload": {"v_high": 3.3, "v_low": 0.0}},
	"equiv": {"kind": "EQUIV", "payload": {"ref": "ref/l2", "vectors": 8, "mismatch": 0}},
	"area_max": {"kind": "AREA_MAX", "payload": {"gates": 11, "max": 80}},
	"power_calc": {"kind": "POWER_CALC", "payload": {"mw": 1.0, "expect_mw": 1.0, "tol": 0.1}},
	"power_ratio": {"kind": "POWER_RATIO", "payload": {"ratio": 2.0, "expect_ratio": 2.0, "tol": 0.01}},
}

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 49
const EXPECT_GROUPS := {
	"kind_whitelist": 1, "kind_mapping": 19, "write_all": 14,
	"reject": 9, "framing": 4, "no_eval_effect": 2,
}
const GROUP_DESCRIPTIONS := {
	"kind_whitelist": "trace kind 白名单条数为 15",
	"kind_mapping": "8 个判定 kind 与 trace kind 逐项映射、白名单含每个 kind、build_area 被排除且不产生 trace",
	"write_all": "8 个判定 kind 都能写入、落库 8 条无拒绝、字段仍为 5、首末 kind 与互异性",
	"reject": "未开 trace / 未知 kind / build_area / 缺固定键 / 类型不符各类拒绝与拒绝计数",
	"framing": "含 CH02 kind 的事件流在 1 tick/帧 与 4 tick/帧 下 digest、事件数、拒绝数与逐条事件一致",
	"no_eval_effect": "写 trace 与不写 trace 的同构电路末态与状态摘要相同",
}

func run(ctx: TestContext) -> void:
	ctx.begin_group("kind_whitelist")
	ctx.eq("M4-G3 CH02 kind 白名单条数", TraceSink.KINDS.size(), 15)
	_test_mapping(ctx)
	_test_write_all(ctx)
	_test_reject(ctx)
	_test_framing_digest(ctx)
	_test_no_effect_on_eval(ctx)

func _test_mapping(ctx: TestContext) -> void:
	## M4-G4：8 个判定 kind ↔ trace kind 逐项断言（8/8，build_area 显式排除）。
	ctx.begin_group("kind_mapping")
	var n := 0
	for raw_key in CASES:
		var key := str(raw_key)
		var want := str((CASES[key] as Dictionary)["kind"])
		ctx.eq("M4-G4 映射 %s → %s" % [key, want],
			str(SimCircuit.JUDGEMENT_KINDS.get(key, "")), want)
		ctx.check("M4-G4 trace 白名单含 %s" % want, TraceSink.KINDS.has(want))
		n += 1
	ctx.eq("M4-G4 映射条数", n, 8)
	ctx.check("M4-G4 build_area 不计入 8 种", not SimCircuit.JUDGEMENT_KINDS.has("build_area"))
	ctx.check("M4-G4 build_area 不产生 trace",
		not TraceSink.KINDS.has("BUILD_AREA"))

func _test_write_all(ctx: TestContext) -> void:
	ctx.begin_group("write_all")
	var c := SimCircuit.new("ch02_write")
	c.enable_trace(4096)
	var t := 0
	for raw_key in CASES:
		var key := str(raw_key)
		var case: Dictionary = CASES[key]
		var ok := c.record_judgement(key, "ch02:%s" % key, case["payload"], t)
		ctx.check("M4-G3 可写入 %s" % key, ok, str(c.sink.last_error))
		t += 1
	var s: TraceSink = c.sink
	ctx.eq("M4-G3 8 种 kind 全部落库", s.size(), 8)
	ctx.eq("M4-G3 无拒绝", s.rejected, 0)
	var shape_ok := true
	var kinds := {}
	for i in s.size():
		var e: Dictionary = s.entry(i)
		if e.size() != 5:
			shape_ok = false
		kinds[str(e["kind"])] = true
	ctx.check("M4-G3 每条仍恰好 5 字段", shape_ok)
	ctx.eq("M4-G3 8 种 kind 互异", kinds.size(), 8)
	ctx.eq("M4-G3 first kind", str(s.entry(0)["kind"]), "MOSFET_REGION")
	ctx.eq("M4-G3 last kind", str(s.entry(7)["kind"]), "POWER_RATIO")

func _test_reject(ctx: TestContext) -> void:
	ctx.begin_group("reject")
	var c := SimCircuit.new("ch02_reject")
	ctx.check("M4-G3 trace 未开启时拒绝写入", not c.record_judgement("equiv", "alu", CASES["equiv"]["payload"]))
	c.enable_trace(64)
	ctx.check("M4-G3 未知判定 kind 被拒", not c.record_judgement("bogus", "x", {}))
	ctx.check("M4-G3 build_area 被拒", not c.record_judgement("build_area", "x", {"gates": 3}))
	ctx.eq("M4-G3 未知 kind 不落 sink（拒绝计数 0）", c.sink.rejected, 0)
	ctx.check("M4-G3 payload 缺固定键被拒",
		not c.record_judgement("mosfet_region", "m", {"vgs": 0.0, "vds": 1.0, "id_ua": 0.0}))
	ctx.check("M4-G3 payload 类型不符被拒",
		not c.record_judgement("equiv", "e", {"ref": "r", "vectors": "8", "mismatch": 0}))
	ctx.eq("M4-G3 拒绝计数（缺键/类型 2 次）", c.sink.rejected, 2)
	ctx.eq("M4-G3 拒绝后仍为空", c.sink.size(), 0)
	ctx.check("M4-G3 补全键后可写入",
		c.record_judgement("equiv", "e", {"ref": "r", "vectors": 8, "mismatch": 0}))

func _test_framing_digest(ctx: TestContext) -> void:
	## 含 CH02 kind 的事件流在 1 tick/帧 与 4 tick/帧 下 digest 必须相同（G3 硬门槛）。
	ctx.begin_group("framing")
	var one := _mk("ch02_one")
	for t in range(1, 41):
		one.run_until(t)
	var four := _mk("ch02_four")
	for t in range(4, 41, 4):
		four.run_until(t)
	ctx.eq("M4-G3 1 vs 4 tick/帧 digest 一致", one.trace_digest(), four.trace_digest())
	ctx.eq("M4-G3 1 vs 4 tick/帧 事件数一致", one.sink.size(), four.sink.size())
	ctx.eq("M4-G3 1 vs 4 tick/帧 拒绝数一致", one.sink.rejected, four.sink.rejected)
	var same := true
	for i in mini(one.sink.size(), four.sink.size()):
		if str(one.sink.entry(i)) != str(four.sink.entry(i)):
			same = false
			break
	ctx.check("M4-G3 两条事件逐条相同", same)

func _test_no_effect_on_eval(ctx: TestContext) -> void:
	## 只读观测：写 trace 与不写 trace 的两个同构电路，末态必须相同。
	ctx.begin_group("no_eval_effect")
	var plain := _mk("ch02_plain", false)
	plain.run_until(40)
	var traced := _mk("ch02_traced", true)
	traced.run_until(40)
	ctx.eq("M4-G3 trace 不影响求值（y）", plain.probe("y"), traced.probe("y"))
	ctx.eq("M4-G3 trace 不影响末态摘要",
		plain.state_digest(), traced.state_digest())

func _mk(c_name: String, trace_on: bool = true) -> SimCircuit:
	var c := SimCircuit.new(c_name)
	c.add_wire("a", SimValue.ZERO)
	c.add_gate("y", "not", ["a"])
	if trace_on:
		c.enable_trace(4096)
	c.set_input("a", SimValue.ONE, 2)
	c.set_input("a", SimValue.ZERO, 9)
	c.set_input("a", SimValue.ONE, 18)
	c.eng.schedule(12, Callable(c, "record_judgement"),
		["equiv", "alu4", {"ref": "ref/l2", "vectors": 8, "mismatch": 0}])
	c.eng.schedule(21, Callable(c, "record_judgement"),
		["area_max", "alu4", {"gates": 166, "max": 80}])
	return c
