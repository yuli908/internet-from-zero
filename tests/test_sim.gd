extends RefCounted

## L0b/L1：三值真值、确定性 tick、延迟、快照、与参考实现同向量一致。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 76
const EXPECT_GROUPS := {
	"loadable": 1, "trinary_and_or_xor": 27, "trinary_not": 3, "half_adder_vectors": 18,
	"gate_delay_vectors": 8, "engine_schedule": 3, "relay_chain": 3,
	"snapshot_restore": 6, "tick_equivalence": 2, "pulse_glitch": 2, "equalizer": 3,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "参考向量文件可读且非空",
	"trinary_and_or_xor": "and/or/xor 的 9 行三值真值向量逐条一致",
	"trinary_not": "not 的 3 行三值真值向量逐条一致",
	"half_adder_vectors": "半加器 9 行向量的 sum/carry 与 xor/and 一致",
	"gate_delay_vectors": "各门延迟向量与 SimDelays 一致",
	"engine_schedule": "调度器按 tick 顺序执行且 now 停在最后 tick",
	"relay_chain": "三级反相器收敛、总延迟 9 tick、输出翻转",
	"snapshot_restore": "快照可取、可恢复、恢复后 digest/tick 与摘要长度",
	"tick_equivalence": "一步 vs 四步推进得到相同导线状态与 xor 输出",
	"pulse_glitch": "C 下降沿脉冲可生成且宽度 ≥1",
	"equalizer": "均衡器修正成功、无残留毛刺事件",
}

func run(ctx: TestContext) -> void:
	var ref := _ref()
	ctx.begin_group("loadable")
	ctx.check("ref vectors loaded", not ref.is_empty())

	var gates: Dictionary = ref.get("gates", {})
	for kind in ["and", "or", "xor"]:
		for raw in gates.get(kind, []):
			var row: Array = raw
			var got := SimValue.bin3(str(kind), str(row[0]), str(row[1]))
			ctx.begin_group("trinary_and_or_xor")
			ctx.eq("ref %s(%s,%s)" % [kind, str(row[0]), str(row[1])], got, str(row[2]))
	var not_rows: Array = gates.get("not", [])
	for raw in not_rows:
		var row: Array = raw
		ctx.begin_group("trinary_not")
		ctx.eq("ref not(%s)" % str(row[0]), SimValue.not3(str(row[0])), str(row[1]))

	var ha: Array = ref.get("half_adder", [])
	for raw in ha:
		var row: Array = raw
		ctx.begin_group("half_adder_vectors")
		ctx.eq("ref HA(%s,%s) sum" % [str(row[0]), str(row[1])], SimValue.bin3("xor", str(row[0]), str(row[1])), str(row[2]))
		ctx.eq("ref HA(%s,%s) carry" % [str(row[0]), str(row[1])], SimValue.bin3("and", str(row[0]), str(row[1])), str(row[3]))

	var delays: Dictionary = ref.get("gate_delay", {})
	for kind in delays.keys():
		ctx.begin_group("gate_delay_vectors")
		ctx.eq("ref delay %s" % str(kind), SimDelays.delay(str(kind)), int(delays[kind]))

	var eng := SimEngine.new()
	var order := []
	var a := func(): order.append("a")
	var b := func(): order.append("b")
	var c := func(): order.append("c")
	eng.schedule(2, a)
	eng.schedule(1, b)
	eng.schedule(1, c)
	var r := eng.run_until(3)
	ctx.begin_group("engine_schedule")
	ctx.check("engine ok", bool(r.get("ok", false)), str(r.get("error", "")))
	ctx.eq("engine order", order, ["b", "c", "a"])
	ctx.eq("engine now", eng.now, 2)

	var sim := SimCircuit.new("chain")
	sim.add_wire("a", "0")
	sim.add_gate("n1", "not", ["a"], 3)
	sim.add_gate("n2", "not", ["n1"], 3)
	sim.add_gate("n3", "not", ["n2"], 3)
	var settle := sim.settle()
	ctx.begin_group("relay_chain")
	ctx.check("chain settles", bool(settle.get("ok", false)))
	var t0 := sim.now()
	sim.set_input("a", "1")
	ctx.eq("3-stage relay delay", sim.measure_settle(["n3"], t0), 9)
	ctx.eq("chain output", sim.probe("n3"), "0")

	var snap := sim.snapshot()
	ctx.begin_group("snapshot_restore")
	ctx.check("snapshot ok", bool(snap.get("ok", false)), str(snap.get("error", "")))
	var digest := str(snap.get("digest", ""))
	sim.set_input("a", "0")
	sim.settle()
	var restore := sim.restore(snap)
	ctx.check("restore ok", bool(restore.get("ok", false)), str(restore.get("error", "")))
	var snap2 := sim.snapshot()
	ctx.check("resnapshot ok", bool(snap2.get("ok", false)))
	ctx.eq("restore digest", str(snap2.get("digest", "")), digest)
	ctx.eq("restore tick", int(sim.now()), int(snap.get("tick", -1)))
	ctx.check("digest nonempty", digest.length() == 64)

	var g1 := _xor_graph()
	var sim1: SimCircuit = SimCircuit.build_graph(g1, -1)["sim"]
	var sim2: SimCircuit = SimCircuit.build_graph(g1, -1)["sim"]
	for s in [sim1, sim2]:
		s.set_input("a", "0")
		s.set_input("b", "0")
		s.settle()
		s.set_input("a", "1")
		s.set_input("b", "1")
	for i in 40:
		var rr1: Dictionary = sim1.run(1)
		if not bool(rr1.get("ok", false)):
			break
	for i in 10:
		var rr2: Dictionary = sim2.run(4)
		if not bool(rr2.get("ok", false)):
			break
	sim1.settle()
	sim2.settle()
	var wires1: Dictionary = sim1.snapshot().get("wires", {})
	var wires2: Dictionary = sim2.snapshot().get("wires", {})
	ctx.begin_group("tick_equivalence")
	ctx.eq("1 tick vs 4 tick wires", JSON.stringify(wires1), JSON.stringify(wires2))
	ctx.eq("xor output after 1,1", sim1.probe("__out_out"), "0")

	var glitch := SignalLabModel.pulse_after_c_fall(4, 3)
	ctx.begin_group("pulse_glitch")
	ctx.check("glitch ok", bool(glitch.get("ok", false)), str(glitch.get("error", "")))
	ctx.check("glitch width >= 1", int(glitch.get("width", 0)) >= 1)
	var fixed := SignalLabModel.run_fixed("equalize", 20)
	ctx.begin_group("equalizer")
	ctx.check("fix ok", bool(fixed.get("ok", false)))
	ctx.check("fix clean", bool(fixed.get("clean", false)))
	ctx.eq("fix glitches", int(fixed.get("glitch_events", -1)), 0)

func _ref() -> Dictionary:
	var text := FileAccess.get_file_as_string("res://tests/data/ref_vectors.json")
	var parsed: Variant = JSON.parse_string(text)
	return parsed if parsed is Dictionary else {}

func _xor_graph() -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("xor"), "XOR", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g
