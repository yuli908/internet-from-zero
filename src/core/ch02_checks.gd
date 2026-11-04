class_name Ch02Checks
extends RefCounted

## CH02（物理层）五节 gate 判定入口。
## 唯一出口沿用 `GateReport` / `GateResult`（`specs/m5/failure_contract.md`），
## 不返回自定义判定结构；额外只回传 `pending`（仿真层尚未支持的用例清单）。
##
## 已落地 kind：mosfet_region / quiz / truth / x_propagation / target / equiv /
##              delay / area_max / power_calc / power_ratio / build_area / rail_margin
## pending kind：static_current（需 L1 稳态电流模型）
##
## 黑盒语义复用 `BlackBox` + `LabChecks`，不复制真值表或仿真器。

const PENDING_REASONS := {
	"static_current": "L1 仿真层只输出逻辑值，没有稳态电流模型（规格要求 50 tick 平均 Idd）",
}

static func run(_lab_id: String, cfg: Dictionary, inputs: Dictionary = {}, tracker: GateAttemptTracker = null) -> Dictionary:
	var rep := GateReport.new()
	var pending := []
	var graph: CircuitGraph = inputs.get("graph", null)
	var graphs: Dictionary = inputs.get("graphs", {})
	var answers: Dictionary = inputs.get("answers", {})
	var sim: SimCircuit = inputs.get("sim", null)
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		var title := str(c.get("title", ""))
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		if PENDING_REASONS.has(kind):
			var reason := str(c.get("pending_reason", PENDING_REASONS[kind]))
			pending.append({"id": cid, "kind": kind, "title": title, "reason": reason})
			rep.add_case(GateResult.E_PENDING, cid, title, {"kind": kind}, "仿真层支持", "pending",
				[], "pending：" + reason, false, 0)
			continue
		match kind:
			"mosfet_region":
				_judge_region(rep, tracker, sim, cfg, c, cid, title, required, answers)
			"quiz":
				_judge_quiz(rep, tracker, cfg, c, cid, title, required, answers)
			"truth":
				_judge_truth(rep, tracker, cfg, c, cid, title, required, graph, graphs)
			"x_propagation":
				_judge_xprop(rep, tracker, cfg, c, cid, title, required, graph, sim)
			"target":
				_judge_target(rep, tracker, cfg, c, cid, title, required, graph, graphs)
			"equiv":
				_judge_equiv(rep, tracker, c, cid, title, required, graph, sim)
			"delay":
				_judge_delay(rep, tracker, cfg, c, cid, title, required, graph)
			"area_max":
				_judge_area(rep, tracker, c, cid, title, required, graph, sim)
			"power_calc":
				_judge_power_calc(rep, tracker, c, cid, title, required, answers, sim)
			"power_ratio":
				_judge_power_ratio(rep, tracker, c, cid, title, required, answers, sim)
			"build_area":
				_judge_build_area(rep, tracker, c, cid, title, required, graphs)
			"rail_margin":
				_judge_rail(rep, tracker, cfg, c, cid, title, required, graph, sim)
			_:
				rep.add_case(GateResult.E_GENERIC, cid, title, {"kind": kind}, "已知判定 kind",
					kind, [], "未知判定 kind：%s" % kind, required, 0)
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

# ---------------------------------------------------------------- MOS 离散模型

static func region_of(vgs: float, vds: float, dev: Dictionary) -> String:
	## 教学离散档位：只区分截止 / 线性 / 饱和，不做 SPICE 级求解。
	var vth := float(dev.get("vth", 0.9))
	if vgs < vth:
		return "cutoff"
	if vds < (vgs - vth):
		return "linear"
	return "saturation"

static func id_ua_of(vgs: float, vds: float, dev: Dictionary) -> float:
	var region := region_of(vgs, vds, dev)
	if region == "cutoff":
		return float(dev.get("id_off_ua", 0.001))
	if region == "linear":
		var ron := float(dev.get("ron_ohm", 50.0))
		return vds / ron * 1e6
	return float(dev.get("id_sat_ua", 1000.0))

static func _judge_region(rep: GateReport, tracker: GateAttemptTracker, sim: SimCircuit,
		cfg: Dictionary, c: Dictionary, cid: String, title: String, required: bool, answers: Dictionary) -> void:
	var dev: Dictionary = c.get("device", cfg.get("device", {}))
	var vgs := float(c.get("vgs", 3.3))
	var vds := float(c.get("vds", 0.0))
	var region := region_of(vgs, vds, dev)
	var id_ua := id_ua_of(vgs, vds, dev)
	var given := _region_answer(answers, cid)
	var ok := true
	var code := GateResult.OK
	var expected := {}
	var actual := {"region": region, "id_ua": id_ua, "answer": given}
	var detail := "区域=%s，Id=%.4f µA" % [region, id_ua]
	var want_region := str(c.get("expect_region", ""))
	if not want_region.is_empty():
		expected["region"] = want_region
		if region != want_region:
			ok = false
			code = GateResult.E_REGION
	# 玩家必须提交区域判断：这一步是练习本身，不能靠模型自证放行。
	if given.is_empty():
		ok = false
		code = GateResult.E_REGION
		detail += "，未提交区域判断"
	elif given != region:
		ok = false
		code = GateResult.E_REGION
		detail += "，判读=%s（正确 %s）" % [given, region]
	if c.has("max_id_ua"):
		expected["max_id_ua"] = float(c["max_id_ua"])
		if id_ua > float(c["max_id_ua"]):
			ok = false
			code = GateResult.E_REGION
	if c.has("max_ron_ohm"):
		var ron := vds * 1e6 / maxf(id_ua, 1e-9)
		expected["max_ron_ohm"] = float(c["max_ron_ohm"])
		actual["ron_ohm"] = ron
		detail += "，Ron=%.2f Ω" % ron
		if ron > float(c["max_ron_ohm"]):
			ok = false
			code = GateResult.E_REGION
	var tol := float(c.get("cadence_tol", -1.0))
	if tol > 0.0:
		var id2 := id_ua_of(vgs, vds * 1.1, dev)
		var drift := 0.0 if absf(id_ua) < 1e-12 else absf(id2 - id_ua) / absf(id_ua)
		expected["cadence_tol"] = tol
		actual["drift"] = drift
		detail += "，随 Vds 漂移 %.1f%%" % (drift * 100.0)
		if drift > tol:
			ok = false
			code = GateResult.E_REGION
	# 多点封顶：同一 Vgs 下，列出的多个 Vds 必须给出同一个 Id（默认容差 0）。
	if c.has("equal_id_vds"):
		var probes: Array = c["equal_id_vds"]
		var vals := []
		for raw_v in probes:
			vals.append(id_ua_of(vgs, float(raw_v), dev))
		var spread := 0.0
		if not vals.is_empty():
			var lo: float = vals[0]
			var hi: float = vals[0]
			for v in vals:
				lo = minf(lo, float(v))
				hi = maxf(hi, float(v))
			spread = hi - lo
		var id_tol := float(c.get("equal_id_tol", 0.0))
		expected["equal_id_vds"] = probes
		expected["equal_id_tol"] = id_tol
		actual["equal_id_ua"] = vals
		detail += "，Vds %s 下 Id=%s µA" % [str(probes), str(vals)]
		if spread > id_tol:
			ok = false
			code = GateResult.E_REGION
	LabChecks._emit(rep, tracker, code, cid, title, ok, {"vgs": vgs, "vds": vds, "device": dev},
		expected, actual, detail, required)
	_trace(sim, "mosfet_region", cid, {"region": region, "vgs": vgs, "vds": vds, "id_ua": id_ua, "answer": given})

# ---------------------------------------------------------------- 逐 kind 判定

static func _judge_quiz(rep: GateReport, tracker: GateAttemptTracker, cfg: Dictionary, c: Dictionary,
		cid: String, title: String, required: bool, answers: Dictionary) -> void:
	var quiz: Dictionary = c.get("quiz", cfg.get("quiz", {}))
	var want := int(quiz.get("answer", -1))
	var got := _answer(answers, cid)
	var ok := want >= 0 and got == want
	LabChecks._emit(rep, tracker, GateResult.E_QUIZ, cid, title, ok, {"answer": got}, want, got,
		"作答 %d，期望 %d" % [got, want], required)

static func _judge_truth(rep: GateReport, tracker: GateAttemptTracker, cfg: Dictionary, c: Dictionary,
		cid: String, title: String, required: bool, graph: CircuitGraph, graphs: Dictionary) -> void:
	var g: CircuitGraph = graph
	if g == null:
		# 多任务实验（如 2.3）没有单一 graph，按任务 A 的真值表取图。
		g = graphs.get("t_nand", null)
		if g == null and graphs.size() == 1:
			g = graphs.values()[0]
	var rows: Array = c.get("rows", [])
	var bits: Array = c.get("expected", [])
	var ids := _input_ids(cfg, rows)
	var expected := []
	var n := mini(rows.size(), bits.size())
	for i in n:
		var ins := {}
		var row: Array = rows[i]
		for j in row.size():
			ins[str(ids[j])] = "1" if int(row[j]) == 1 else "0"
		expected.append({"inputs": ins, "outputs": {"out": "1" if int(bits[i]) == 1 else "0"}})
	var res := BlackBox.check_outputs(g, ids, ["out"], expected)
	var f: Dictionary = res.get("failure", {})
	var code := int(res.get("code", GateResult.E_TRUTH_ROW)) if not bool(res.get("ok", false)) else GateResult.OK
	LabChecks._emit(rep, tracker, code, cid, title, bool(res.get("ok", false)),
		f.get("input", {"rows": rows.size()}), f.get("expected", "真值表"), f.get("actual", null),
		"行 %d/%d" % [int(res.get("passed", 0)), int(res.get("total", 0))], required)

static func _judge_xprop(rep: GateReport, tracker: GateAttemptTracker, cfg: Dictionary, c: Dictionary,
		cid: String, title: String, required: bool, graph: CircuitGraph, sim: SimCircuit) -> void:
	var ids := _input_ids(cfg, [])
	var vals := {}
	for id in ids:
		vals[str(id)] = "X"
	var want := str(c.get("expect", "X"))
	var res := BlackBox.tri_eval(graph, vals)
	var got := str((res.get("values", {}) as Dictionary).get("out", "?"))
	var ok := bool(res.get("ok", false)) and got == want
	var code := GateResult.OK
	if not bool(res.get("ok", false)):
		code = GateResult.E_BUILD
	elif not ok:
		code = GateResult.E_X_ROW
	LabChecks._emit(rep, tracker, code, cid, title, ok, vals, want, got,
		"X 输入输出 %s（期望 %s）" % [got, want], required)
	_trace(sim, "x_propagation", cid, {"expect": want, "got": got})

static func _judge_target(rep: GateReport, tracker: GateAttemptTracker, cfg: Dictionary, c: Dictionary,
		cid: String, title: String, required: bool, graph: CircuitGraph, graphs: Dictionary) -> void:
	var task := LabChecks._task_by_target(cfg, str(c.get("target", "")))
	var g: CircuitGraph = graph
	if g == null:
		g = graphs.get(str(task.get("id", "")), null)
	var res := LabChecks._check_task(g, task)
	var count := BlackBox.gate_count(g) if g != null else -1
	var limit := int(c.get("max_gates", 99999))
	var rows_ok := bool(res.get("ok", false))
	var ok := rows_ok and count >= 0 and count <= limit
	var code := GateResult.OK
	var input: Variant = {"target": str(task.get("target", ""))}
	var expected: Variant = {"max_gates": limit}
	var actual: Variant = {"gates": count}
	if not rows_ok:
		var f: Dictionary = res.get("failure", {})
		code = int(res.get("code", GateResult.E_TRUTH_ROW))
		input = f.get("input", input)
		expected = f.get("expected", expected)
		actual = f.get("actual", actual)
	elif count < 0:
		code = GateResult.E_MISSING_GRAPH
	elif count > limit:
		code = GateResult.E_AREA
	LabChecks._emit(rep, tracker, code, cid, title, ok, input, expected, actual,
		"行 %d/%d，门数 %d（上限 %d）" % [int(res.get("passed", 0)), int(res.get("total", 0)), count, limit], required)

static func _judge_equiv(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		cid: String, title: String, required: bool, graph: CircuitGraph, sim: SimCircuit) -> void:
	var ref := str(c.get("ref", "xor"))
	var type := LogicGates.from_string(ref)
	if type < 0:
		rep.add_case(GateResult.E_UNKNOWN_TARGET, cid, title, {"ref": ref}, "已知参考函数", ref,
			[], "未知参考函数：%s" % ref, required, 0)
		return
	var arity := LogicGates.arity(type)
	var total := 0
	var bad := 0
	var first: Dictionary = {}
	var build_err := ""
	var b_values := ["0"] if arity == 1 else ["0", "1", "X"]
	for a in ["0", "1", "X"]:
		for b in b_values:
			var vals := {"a": a}
			if arity == 2:
				vals["b"] = b
			var res := BlackBox.tri_eval(graph, vals)
			if not bool(res.get("ok", false)):
				build_err = str(res.get("error", "构建失败"))
				break
			var got := str((res.get("values", {}) as Dictionary).get("out", "?"))
			var want := SimValue.gate(ref, [a, b] if arity == 2 else [a])
			total += 1
			if got != want:
				bad += 1
				if first.is_empty():
					first = {"a": a, "b": b, "expected": want, "actual": got}
		if not build_err.is_empty():
			break
	var ok := build_err.is_empty() and bad == 0 and total > 0
	var code := GateResult.OK
	if not build_err.is_empty():
		code = GateResult.E_BUILD
	elif not ok:
		code = GateResult.E_EQUIV
	var detail := ("向量 %d/%d 通过" % [total - bad, total]) if build_err.is_empty() else ("仿真失败：%s" % build_err)
	LabChecks._emit(rep, tracker, code, cid, title, ok, first if not first.is_empty() else {"ref": ref},
		"与 %s 等价" % ref, first if not first.is_empty() else null, detail, required)
	_trace(sim, "equiv", cid, {"ref": ref, "vectors": total, "mismatch": bad})

static func _judge_delay(rep: GateReport, tracker: GateAttemptTracker, cfg: Dictionary, c: Dictionary,
		cid: String, title: String, required: bool, graph: CircuitGraph) -> void:
	var ids := _input_ids(cfg, [])
	var limit := int(c.get("max", c.get("max_delay", 8)))
	var d := LabChecks.measure_delay(graph, ids)
	var ok := d >= 0 and d <= limit
	var code := GateResult.OK
	if d < 0:
		code = GateResult.E_BUILD
	elif not ok:
		code = GateResult.E_DELAY_EXCEED
	LabChecks._emit(rep, tracker, code, cid, title, ok, {"inputs": ids}, limit, d,
		"稳定时间 %d tick（上限 %d）" % [d, limit], required)

static func _judge_area(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		cid: String, title: String, required: bool, graph: CircuitGraph, sim: SimCircuit) -> void:
	var limit := int(c.get("max_gates", c.get("max", 5)))
	var count := BlackBox.gate_count(graph) if graph != null else -1
	var ok := count >= 0 and count <= limit
	var code := GateResult.OK
	if count < 0:
		code = GateResult.E_MISSING_GRAPH
	elif not ok:
		code = GateResult.E_AREA
	LabChecks._emit(rep, tracker, code, cid, title, ok, {"graph": "submitted"}, limit, count,
		"门数 %d（上限 %d）" % [count, limit], required)
	_trace(sim, "area_max", cid, {"gates": count, "max": limit})

static func _judge_power_calc(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		cid: String, title: String, required: bool, answers: Dictionary, sim: SimCircuit) -> void:
	var want := float(c.get("expect_mw", power_mw(c.get("formula", {}))))
	var tol := float(c.get("tol", 0.05))
	var got := float(answers.get(cid, answers.get("power_mw", -1.0)))
	var ok := absf(got - want) <= tol * absf(want)
	var code := GateResult.OK if ok else GateResult.E_POWER_CALC
	LabChecks._emit(rep, tracker, code, cid, title, ok, c.get("formula", {}),
		"%.4f mW ±%.0f%%" % [want, tol * 100.0], "%.4f mW" % got,
		"作答 %.4f mW，期望 %.4f mW" % [got, want], required)
	_trace(sim, "power_calc", cid, {"mw": got, "expect_mw": want, "tol": tol})

static func _judge_power_ratio(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		cid: String, title: String, required: bool, answers: Dictionary, sim: SimCircuit) -> void:
	var want := float(c.get("expect_ratio", 0.5))
	var tol := float(c.get("tol", 0.02))
	var got := float(answers.get(cid, answers.get("ratio", -1.0)))
	var ok := absf(got - want) <= tol
	var code := GateResult.OK if ok else GateResult.E_POWER_RATIO
	LabChecks._emit(rep, tracker, code, cid, title, ok, {"baseline": "全部门反转"},
		"%.3f ±%.3f" % [want, tol], "%.3f" % got,
		"作答 %.3f，期望 %.3f ±%.3f" % [got, want, tol], required)
	_trace(sim, "power_ratio", cid, {"ratio": got, "expect_ratio": want, "tol": tol})

static func _judge_build_area(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		cid: String, title: String, required: bool, graphs: Dictionary) -> void:
	var slots := int(c.get("slots", 4))
	var budget := int(c.get("max_total_gates", -1))
	var targets: Array = c.get("targets", [])
	var ok := targets.size() <= slots
	var lines := []
	var code := GateResult.OK
	if targets.size() > slots:
		code = GateResult.E_AREA
	var total_gates := 0
	for raw in targets:
		var t: Dictionary = {}
		if raw is Dictionary:
			t = raw
		else:
			var name := str(raw)
			t = {"id": name, "target": name, "input_ids": ["a"] if name == "not" else ["a", "b"]}
		var tid := str(t.get("id", ""))
		var g: CircuitGraph = graphs.get(tid, null)
		var res := BlackBox.check_target(g, str(t.get("target", "")), t.get("input_ids", ["a", "b"]), ["out"])
		var used := BlackBox.gate_count(g) if g != null else 0
		total_gates += used
		if bool(res.get("ok", false)):
			lines.append("%s ✓(%d门)" % [tid, used])
		else:
			lines.append("%s ✗" % tid)
			ok = false
			if code == GateResult.OK:
				code = int(res.get("code", GateResult.E_TARGET_UNREACHED))
	if budget >= 0 and total_gates > budget:
		ok = false
		code = GateResult.E_AREA
		lines.append("总门数 %d>%d" % [total_gates, budget])
	LabChecks._emit(rep, tracker, code, cid, title, ok, {"slots": slots, "max_total_gates": budget},
		"%d/%d 槽，总门数 ≤%d" % [targets.size(), slots, budget], lines,
		"%s（%d 槽 / %d 目标 / %d 门）" % [", ".join(lines), slots, targets.size(), total_gates], required)

static func _judge_rail(rep: GateReport, tracker: GateAttemptTracker, cfg: Dictionary,
		c: Dictionary, cid: String, title: String, required: bool,
		graph: CircuitGraph, sim: SimCircuit) -> void:
	## 逻辑值 → 电平反查：先用黑盒求各稳态的逻辑输出，再按上/下拉导通电阻与负载
	## 分压反算该逻辑值对应的实际电压，比对轨到轨门限。纯离散算术，不依赖模拟求解器。
	var rail: Dictionary = c.get("rail", cfg.get("rail", {}))
	var vdd := float(rail.get("vdd", 3.3))
	var ron := float(rail.get("ron_ohm", 50.0))
	var load := float(rail.get("load_ohm", 2000.0))
	var hi_min := float(c.get("v_high_min", rail.get("v_high_min", 3.2)))
	var lo_max := float(c.get("v_low_max", rail.get("v_low_max", 0.1)))
	var v_high := vdd * load / (load + ron)
	var v_low := vdd * ron / (load + ron)
	var states: Array = c.get("states", [])
	var ids := _input_ids(cfg, states)
	var ok := graph != null
	var code := GateResult.OK if ok else GateResult.E_MISSING_GRAPH
	var probed := []
	for row in states:
		var vals := {}
		for j in (row as Array).size():
			vals[str(ids[j])] = "1" if int(row[j]) == 1 else "0"
		var res: Dictionary = BlackBox.tri_eval(graph, vals) if graph != null else {}
		var out := str((res.get("values", {}) as Dictionary).get("out", "?")) if bool(res.get("ok", false)) else "?"
		probed.append({"inputs": row, "out": out})
		if not ok:
			continue
		if out == "1" and v_high < hi_min:
			ok = false
			code = GateResult.E_RAIL_MARGIN
		elif out == "0" and v_low > lo_max:
			ok = false
			code = GateResult.E_RAIL_MARGIN
		elif out != "0" and out != "1":
			ok = false
			code = GateResult.E_BUILD
	LabChecks._emit(rep, tracker, code, cid, title, ok, {"v_high_min": hi_min, "v_low_max": lo_max},
		"V_high ≥ %.3f V，V_low ≤ %.3f V" % [hi_min, lo_max],
		{"v_high": v_high, "v_low": v_low, "states": probed},
		"%d 稳态：V_high=%.3f V，V_low=%.3f V" % [states.size(), v_high, v_low], required)
	_trace(sim, "rail_margin", cid, {"v_high": v_high, "v_low": v_low})

# ---------------------------------------------------------------- 工具

static func power_mw(formula: Dictionary) -> float:
	## P = α · C · V² · f，单位换算到 mW。
	var alpha := float(formula.get("alpha", 0.5))
	var c_f := float(formula.get("c_f", 1e-11))
	var vdd := float(formula.get("vdd", 3.3))
	var f_hz := float(formula.get("f_hz", 1e6))
	return alpha * c_f * vdd * vdd * f_hz * 1e3

static func _input_ids(cfg: Dictionary, rows: Array) -> Array:
	var topo: Dictionary = cfg.get("topology", {})
	var decl: Variant = topo.get("inputs", null)
	if decl is Array and not (decl as Array).is_empty():
		return (decl as Array).duplicate()
	if not rows.is_empty() and (rows[0] as Array).size() == 1:
		return ["a"]
	return ["a", "b"]

static func _region_answer(answers: Dictionary, cid: String) -> String:
	if answers.has(cid) and typeof(answers[cid]) == TYPE_STRING:
		return str(answers[cid]).strip_edges().to_lower()
	var fallback: Variant = answers.get("region", "")
	return str(fallback).strip_edges().to_lower() if typeof(fallback) == TYPE_STRING else ""

static func _answer(answers: Dictionary, cid: String) -> int:
	if answers.has(cid):
		return int(answers[cid])
	if answers.has("default"):
		return int(answers["default"])
	return -1

static func _trace(sim: SimCircuit, kind: String, cid: String, payload: Dictionary) -> void:
	if sim == null:
		return
	sim.record_judgement(kind, cid, payload)
