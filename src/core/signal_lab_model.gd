class_name SignalLabModel
extends RefCounted

## 第一章 1.5 节信号/延迟/竞争实验的确定性模型。
## 复用 L1 事件仿真；继电器教学延迟 3 tick/级（data/sim/delays.json 的 relay 段）。

const RELAY := 3

static func build_not_chain(stages: int, delay_per_stage: int = RELAY) -> Dictionary:
	var sim := SimCircuit.new("not_chain")
	sim.add_wire("in", SimValue.ZERO)
	var prev := "in"
	for i in range(stages):
		var out := "n%d" % i
		sim.add_gate(out, "not", [prev], delay_per_stage)
		prev = out
	sim.settle()
	return {"ok": true, "sim": sim, "out": prev, "stages": stages}

static func measure_chain(stages: int = 3, delay_per_stage: int = RELAY) -> Dictionary:
	var built := build_not_chain(stages, delay_per_stage)
	var sim: SimCircuit = built["sim"]
	var out := str(built["out"])
	var t0 := sim.now()
	sim.set_input("in", SimValue.ONE)
	var delay := sim.measure_settle([out], t0)
	return {
		"ok": delay >= 0,
		"delay": delay,
		"per_stage": float(delay) / float(maxi(1, stages)),
		"stages": stages,
		"out": sim.probe(out),
	}

static func build_hazard(extra_skew: int = 0, delay_per_gate: int = RELAY) -> Dictionary:
	## F = A·C + B·C'，A=B=1；给第二条路径加 extra_skew 的缓冲延迟。
	var sim := SimCircuit.new("hazard")
	sim.add_wire("A", SimValue.ONE)
	sim.add_wire("B", SimValue.ONE)
	sim.add_wire("C", SimValue.ONE)
	sim.add_gate("nC", "not", ["C"], delay_per_gate)
	sim.add_gate("p1", "and", ["A", "C"], delay_per_gate)
	sim.add_gate("p2", "and", ["B", "nC"], delay_per_gate)
	var src := "p2"
	if extra_skew > 0:
		sim.add_gate("skew", "buf", ["p2"], extra_skew)
		src = "skew"
	sim.add_gate("F", "or", ["p1", src], delay_per_gate)
	sim.watch_glitch("F")
	sim.settle()
	return {"ok": true, "sim": sim, "out": "F"}

static func pulse_after_c_fall(extra_skew: int = 4, delay_per_gate: int = RELAY) -> Dictionary:
	var built := build_hazard(extra_skew, delay_per_gate)
	var sim: SimCircuit = built["sim"]
	var t0 := sim.now()
	sim.set_input("C", SimValue.ZERO)
	var rr := sim.settle()
	if not bool(rr.get("ok", false)):
		return {"ok": false, "error": str(rr.get("error", "")), "changes": [], "width": 0}
	var changes := []
	for h in sim.history:
		var ev: Dictionary = h
		if str(ev.get("wire", "")) == "F" and int(ev.get("t", 0)) >= t0:
			changes.append({"t": int(ev["t"]) - t0, "v": str(ev["new"])})
	var width := 0
	for i in range(1, changes.size()):
		var prev: Dictionary = changes[i - 1]
		var cur: Dictionary = changes[i]
		if str(prev["v"]) == "0" and str(cur["v"]) == "1":
			width = int(cur["t"]) - int(prev["t"])
	var final := sim.probe("F")
	return {
		"ok": true,
		"changes": changes,
		"width": width,
		"final": final,
		"glitch_visible": width >= 1,
		"filtered": changes.is_empty(),
	}

static func run_fixed(mode: String, toggles: int = 20) -> Dictionary:
	## 修复方案 equalize：在 C 的直连路径上补一级缓冲，使 C 与 C′ 同时到达 OR。
	## 这就是"用结构消除冒险"：不是换更快的门，而是平衡路径延迟。
	## 其它 mode 目前回落到 equalize（后续章节再引入同步采样/施密特触发）。
	var sim := SimCircuit.new("hazard_fixed")
	sim.add_wire("A", SimValue.ONE)
	sim.add_wire("B", SimValue.ONE)
	sim.add_wire("C", SimValue.ONE)
	sim.add_gate("bufC", "buf", ["C"], RELAY)
	sim.add_gate("nC", "not", ["C"], RELAY)
	sim.add_gate("p1", "and", ["A", "bufC"], RELAY)
	sim.add_gate("p2", "and", ["B", "nC"], RELAY)
	sim.add_gate("F", "or", ["p1", "p2"], RELAY)
	sim.settle()
	var seen := 0
	var dips := 0
	for i in range(toggles):
		var t0 := sim.now()
		sim.set_input("C", SimValue.ONE if (i % 2 == 0) else SimValue.ZERO)
		var rr := sim.settle()
		if not bool(rr.get("ok", false)):
			return {"ok": false, "error": str(rr.get("error", "")), "toggles": 0}
		dips += _dips_since(sim, "F", t0)
		seen += 1
	return {
		"ok": true,
		"toggles": seen,
		"glitch_events": dips,
		"clean": dips == 0,
		"mode": "equalize",
		"final": sim.probe("F"),
	}

static func _dips_since(sim: SimCircuit, wire_name: String, from_tick: int) -> int:
	## 统计窗口内"输出变 0 并持续 ≥1 tick 后回到 1"的次数（真正的毛刺）。
	var changes := []
	for h in sim.history:
		var ev: Dictionary = h
		if str(ev.get("wire", "")) == wire_name and int(ev.get("t", 0)) >= from_tick:
			changes.append({"t": int(ev["t"]), "v": str(ev["new"])})
	var n := 0
	for i in range(1, changes.size()):
		var prev: Dictionary = changes[i - 1]
		var cur: Dictionary = changes[i]
		if str(prev["v"]) == "0" and str(cur["v"]) == "1" and int(cur["t"]) - int(prev["t"]) >= 1:
			n += 1
	return n
