extends RefCounted

## M3-G8：L3 时序层参考向量逐条比对（tests/data/l3_vectors.json）。
## 覆盖 4 类器件（dff/register/counter/shift）+ 复位 + setup/hold 两类违例。
## 每条期望比对三件事：tick 处的 Q 值（MSB 在前）、最后一条 L3 观测事件的 kind、亚稳态 reason。

const VEC_PATH := "res://tests/data/l3_vectors.json"

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 4
const EXPECT_GROUPS := {"loadable": 0, "vectors": 2, "compare": 2}
const GROUP_DESCRIPTIONS := {
	"loadable": "向量文件可读、JSON 可解析：仅在文件缺失或解析失败时才执行的兜底检查",
	"vectors": "格式标记为 ifz-l3-vectors/1、用例数 ≥24",
	"compare": "期望条数恰为 51、51 条逐条比对全过",
}

func run(ctx: TestContext) -> void:
	var f := FileAccess.open(VEC_PATH, FileAccess.READ)
	ctx.begin_group("loadable")
	if f == null:
		ctx.check("L3 向量文件存在", false, VEC_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		ctx.check("L3 向量可解析", false, str(parsed))
		return
	var doc: Dictionary = parsed
	ctx.begin_group("vectors")
	ctx.eq("L3 向量格式", str(doc.get("format", "")), "ifz-l3-vectors/1")
	var cases: Array = doc.get("cases", [])
	ctx.check("L3 向量用例 ≥ 24", cases.size() >= 24, "cases=%d" % cases.size())
	var rows := 0
	var passed := 0
	for i in cases.size():
		var c: Dictionary = cases[i]
		var res := _run_case(c)
		var exps: Array = c.get("expects", [])
		rows += exps.size()
		passed += int(res["passed"])
		for msg in (res["fails"] as Array):
			ctx.check("L3 向量 %s：%s" % [str(c.get("name", i)), str(msg)], false)
	ctx.begin_group("compare")
	ctx.eq("L3 向量期望条数", rows, 51)
	ctx.check("L3 向量逐条通过 %d/%d" % [passed, rows], passed == rows)

func _run_case(c: Dictionary) -> Dictionary:
	var kind := str(c.get("kind", ""))
	var width := int(c.get("width", 1))
	var sim := SimCircuit.new("l3vec_%s" % str(c.get("name", "case")))
	sim.add_wire("clk", SimValue.ZERO)
	var q: Array = []
	match kind:
		"dff":
			sim.add_wire("d", SimValue.ZERO)
			var rst := ""
			if bool(c.get("reset", false)):
				sim.add_wire("rst", SimValue.ZERO)
				rst = "rst"
			sim.add_dff("q", "d", "clk", -1, rst)
			q = ["q"]
		"register":
			sim.add_wire("rst", SimValue.ZERO)
			var en := ""
			if bool(c.get("en", false)):
				sim.add_wire("en", SimValue.ZERO)
				en = "en"
			var r := SimSequential.create_register(sim, "r", width, "clk",
				"rst" if bool(c.get("reset", false)) else "", en)
			if not bool(r.get("ok", false)):
				return {"passed": 0, "fails": ["构建失败：%s" % str(r.get("error", ""))]}
			q = r["q"]
		"counter":
			sim.add_wire("rst", SimValue.ZERO)
			var en2 := ""
			var load := ""
			var srcs: Array = []
			if bool(c.get("en", false)):
				sim.add_wire("en", SimValue.ZERO)
				en2 = "en"
			if bool(c.get("load", false)):
				sim.add_wire("load", SimValue.ZERO)
				load = "load"
				for wname in (c.get("load_srcs", []) as Array):
					sim.add_wire(str(wname), SimValue.ZERO)
					srcs.append(str(wname))
			var r2 := SimSequential.create_counter(sim, "cnt", width, "clk",
				"rst" if bool(c.get("reset", false)) else "", en2, load, srcs)
			if not bool(r2.get("ok", false)):
				return {"passed": 0, "fails": ["构建失败：%s" % str(r2.get("error", ""))]}
			q = r2["q"]
		"shift":
			sim.add_wire("din", SimValue.ZERO)
			sim.add_wire("rst", SimValue.ZERO)
			var en3 := ""
			if bool(c.get("en", false)):
				sim.add_wire("en", SimValue.ZERO)
				en3 = "en"
			var r3 := SimSequential.create_shift_register(sim, "s", width, "din", "clk",
				"rst" if bool(c.get("reset", false)) else "", en3)
			if not bool(r3.get("ok", false)):
				return {"passed": 0, "fails": ["构建失败：%s" % str(r3.get("error", ""))]}
			q = r3["q"]
		_:
			return {"passed": 0, "fails": ["未知器件 %s" % kind]}

	sim.settle()   # 清掉建门时的初始求值，后续 set_input 的 delay 才与绝对 tick 对齐
	for ev in (c.get("events", []) as Array):
		var t := int(ev[0])
		sim.set_input(str(ev[1]), str(ev[2]), maxi(0, t - sim.now()))
	if c.has("clock"):
		var clk: Dictionary = c["clock"]
		SimSequential.drive_clock(sim, "clk", int(clk.get("period", 0)),
			int(clk.get("cycles", 0)), -1, int(clk.get("start", 0)))
	var sink := sim.enable_trace(4096)

	var subject := str(q[0])
	var passed := 0
	var fails: Array = []
	for exp in (c.get("expects", []) as Array):
		var e: Dictionary = exp
		var t := int(e["t"])
		sim.run_until(t)
		var got := _read(sim, q)
		var want := str(e["value"])
		if want == "X*":
			if not got.contains(SimValue.X):
				fails.append("t=%d 期望至少一位 X，实得 %s" % [t, got])
			else:
				passed += 1
		elif got == want:
			passed += 1
		else:
			fails.append("t=%d 期望 %s 实得 %s" % [t, want, got])
		var want_kind := str(e.get("kind", ""))
		var got_kind := _last_kind(sink, subject, t)
		if got_kind != want_kind:
			fails.append("t=%d kind 期望 %s 实得 %s" % [t, want_kind, got_kind])
		if e.has("meta"):
			var want_meta := str(e["meta"])
			if want_meta == "" and not sim.metastable.is_empty():
				fails.append("t=%d 期望无亚稳态，实得 %s" % [t, str(sim.metastable)])
			elif want_meta == "any" and sim.metastable.is_empty():
				fails.append("t=%d 期望出现亚稳态，实得空" % t)
			elif want_meta not in ["", "any"] and not _has_reason(sim, want_meta):
				fails.append("t=%d 期望亚稳态 reason=%s，实得 %s" % [t, want_meta, str(sim.metastable)])
	if sink.rejected > 0:
		fails.append("TraceSink 拒绝 %d 条：%s" % [sink.rejected, sink.last_error])
	return {"passed": passed, "fails": fails}

func _read(sim: SimCircuit, q: Array) -> String:
	var bits := ""
	for i in range(q.size() - 1, -1, -1):
		bits += sim.probe(str(q[i]))
	return bits

func _last_kind(sink: TraceSink, subject: String, t: int) -> String:
	var entries := sink.entries()
	for i in range(entries.size() - 1, -1, -1):
		var e: Dictionary = entries[i]
		if int(e["tick"]) > t:
			continue
		if str(e["subject"]) != subject:
			continue
		if str(e["kind"]) in ["EDGE", "SAMPLE", "METASTABLE"]:
			return str(e["kind"])
	return ""

func _has_reason(sim: SimCircuit, reason: String) -> bool:
	for m in sim.metastable:
		if str((m as Dictionary).get("reason", "")) == reason:
			return true
	return false
