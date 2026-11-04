class_name LabChecks
extends RefCounted

## 第一章 6 节 gate 用例的纯逻辑判定（不依赖 autoload / 场景树）。
## 输入来自 data/labs/ch01_labs.json；UI 只负责采集与展示，测试可直接调用。
## M5：每个用例都带结构化失败回传（`GateResult`）；`tracker` 可选，用于 attempt 计数。

static func voltage(cfg: Dictionary, tracker: GateAttemptTracker = null) -> GateReport:
	return VoltageModel.cases(cfg, tracker)

static func binary(cfg: Dictionary, visited: Dictionary, achieved: Dictionary, quiz_answer: int,
		tracker: GateAttemptTracker = null) -> GateReport:
	var rep := GateReport.new()
	var ci := 0
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", "T1.2-%d" % (ci + 1)))
		ci += 1
		var kind := str(c.get("kind", ""))
		var title := str(c.get("title", ""))
		var required := bool(c.get("required", true))
		match kind:
			"coverage":
				var top := int(c.get("max", 15))
				var missing := []
				for v in range(0, top + 1):
					if not bool(visited.get(str(v), visited.get(v, false))):
						missing.append(str(v))
				var ok := missing.is_empty()
				_emit(rep, tracker, GateResult.E_COVERAGE, cid, title, ok,
					{"missing": missing}, {"missing": []}, {"missing": missing},
					"已覆盖 %d/%d 个值" % [top + 1 - missing.size(), top + 1], required)
			"target":
				var tid := str(c.get("target", ""))
				var tgt := _target(cfg, tid)
				var want := int(tgt.get("value", -1))
				var ok := bool(achieved.get(tid, false))
				_emit(rep, tracker, GateResult.E_TARGET_UNREACHED, cid, title, ok,
					{"target": tid}, want, ok,
					"目标值 %d，已达成=%s" % [want, str(ok)], required)
			"quiz":
				var q: Dictionary = cfg.get("quiz", {})
				var answer := int(q.get("answer", -1))
				var ok := quiz_answer == answer
				_emit(rep, tracker, GateResult.E_QUIZ, cid, title, ok,
					{"chosen": quiz_answer}, answer, quiz_answer,
					"选择 %d，正确答案 %d" % [quiz_answer, answer], required)
			_:
				_emit(rep, tracker, GateResult.E_UNKNOWN_KIND, cid, title, false,
					{"kind": kind}, "已知 gate kind", kind,
					"未知判定类型 %s" % kind, required)
	return rep

static func boolean(cfg: Dictionary, filled: Dictionary, tracker: GateAttemptTracker = null) -> GateReport:
	var rep := GateReport.new()
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		var title := str(c.get("title", ""))
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"table":
				var gid := str(c.get("gate", ""))
				var gate := _gate_cfg(cfg, gid)
				var expected: Array = gate.get("expected", [])
				var got: Array = filled.get(gid, [])
				var ok := got.size() == expected.size()
				var bad_row := -1
				var exp_cell: Variant = null
				var got_cell: Variant = null
				var correct := 0
				for i in expected.size():
					if i < got.size() and str(got[i]) == str(int(expected[i])):
						correct += 1
					else:
						ok = false
						if bad_row < 0:
							bad_row = i
							exp_cell = int(expected[i])
							got_cell = "(缺)" if i >= got.size() else str(got[i])
				_emit(rep, tracker, GateResult.E_TABLE_CELL, cid, title, ok,
					{"gate": gid, "row": bad_row}, exp_cell, got_cell,
					"%d/%d 行正确" % [correct, expected.size()], required)
			"demorgan":
				var rows: Array = cfg.get("demorgan", {}).get("rows", [])
				var got: Array = filled.get("demorgan", [])
				var ok := got.size() == rows.size()
				var bad_row := -1
				var exp_cell: Variant = null
				var got_cell: Variant = null
				var correct := 0
				for i in rows.size():
					var pair: Array = rows[i]
					var a := str(int(pair[0]))
					var b := str(int(pair[1]))
					var left := SimValue.not3(SimValue.bin3("and", a, b))
					var right := SimValue.bin3("or", SimValue.not3(a), SimValue.not3(b))
					var eq := left == right
					if eq and i < got.size() and str(got[i]) == left:
						correct += 1
					else:
						ok = false
						if bad_row < 0:
							bad_row = i
							exp_cell = left
							got_cell = "(缺)" if i >= got.size() else str(got[i])
				_emit(rep, tracker, GateResult.E_TABLE_CELL, cid, title, ok,
					{"gate": "demorgan", "row": bad_row}, exp_cell, got_cell,
					"正确 %d/%d，等价成立=%s" % [correct, rows.size(), str(ok)], required)
			_:
				_emit(rep, tracker, GateResult.E_UNKNOWN_KIND, cid, title, false,
					{"kind": kind}, "已知 gate kind", kind,
					"未知判定类型 %s" % kind, required)
	return rep

static func gate(cfg: Dictionary, graphs: Dictionary, checkpoints: Dictionary,
		tracker: GateAttemptTracker = null) -> GateReport:
	var rep := GateReport.new()
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		var title := str(c.get("title", ""))
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"basic":
				var parts := []
				var ok := true
				var first_code := GateResult.OK
				var first_input: Variant = null
				var first_expected: Variant = null
				var first_actual: Variant = null
				for raw_task in cfg.get("tasks", []):
					var task: Dictionary = raw_task
					var target := str(task.get("target", ""))
					if target == "xor":
						continue
					var tid := str(task.get("id", ""))
					var g: CircuitGraph = graphs.get(tid, null)
					var res := _check_task(g, task)
					if not bool(res.get("ok", false)):
						ok = false
						if first_code == GateResult.OK:
							first_code = int(res.get("code", GateResult.E_GENERIC))
							var f: Dictionary = res.get("failure", {})
							first_input = f.get("input", {"task": tid})
							first_expected = f.get("expected", null)
							first_actual = f.get("actual", null)
					parts.append("%s:%d/%d" % [target, int(res.get("passed", 0)), int(res.get("total", 0))])
				_emit(rep, tracker, first_code, cid, title, ok,
					first_input, first_expected, first_actual,
					" ".join(PackedStringArray(parts)), required)
			"xor":
				var task := _task_by_target(cfg, "xor")
				var g: CircuitGraph = graphs.get(str(task.get("id", "t_xor")), null)
				var res := _check_task(g, task)
				var delay := measure_delay(g, task.get("input_ids", ["a", "b"]))
				var limit := int(c.get("max_delay", 12))
				var rows_ok := bool(res.get("ok", false))
				var delay_ok := delay >= 0 and delay <= limit
				var ok := rows_ok and delay_ok
				var code := GateResult.OK
				var input: Variant = null
				var expected: Variant = null
				var actual: Variant = null
				if not rows_ok:
					code = int(res.get("code", GateResult.E_TRUTH_ROW))
					var f: Dictionary = res.get("failure", {})
					input = f.get("input", {"task": task.get("id", "t_xor")})
					expected = f.get("expected", null)
					actual = f.get("actual", null)
				elif not delay_ok:
					code = GateResult.E_BUILD if delay < 0 else GateResult.E_DELAY_EXCEED
					input = {"inputs": task.get("input_ids", ["a", "b"])}
					expected = limit
					actual = delay
				_emit(rep, tracker, code, cid, title, ok, input, expected, actual,
					"行 %d/%d，延迟 %d tick（上限 %d）" % [int(res.get("passed", 0)), int(res.get("total", 0)), delay, limit], required)
			"encapsulation":
				var ok := bool(checkpoints.get("encapsulated", false))
				_emit(rep, tracker, GateResult.E_ENCAPSULATION, cid, title, ok,
					{"checkpoint": "encapsulated"}, true, ok,
					"封装标记=%s" % str(ok), required)
			"second":
				var first: CircuitGraph = graphs.get("t_xor", null)
				var second: CircuitGraph = graphs.get("t_xor_2", null)
				var ok := false
				var detail := "第二结构缺失"
				var code := GateResult.E_MISSING_GRAPH
				var input: Variant = {"graph": "t_xor_2"}
				var expected: Variant = "第二份结构"
				var actual: Variant = null
				if first != null and second != null:
					var res := _check_task(second, _task_by_target(cfg, "xor"))
					var diff := BlackBox.signature(first) != BlackBox.signature(second)
					ok = bool(res.get("ok", false)) and diff
					code = GateResult.E_STRUCTURE_SAME if not diff else int(res.get("code", GateResult.E_TRUTH_ROW))
					if bool(res.get("ok", false)) and not diff:
						input = {"first": "t_xor", "second": "t_xor_2"}
						expected = "不同结构"
						actual = "相同结构"
					elif not bool(res.get("ok", false)):
						var f: Dictionary = res.get("failure", {})
						input = f.get("input", {"task": "t_xor_2"})
						expected = f.get("expected", null)
						actual = f.get("actual", null)
					detail = "行 %d/%d，结构不同=%s" % [int(res.get("passed", 0)), int(res.get("total", 0)), str(diff)]
				_emit(rep, tracker, code, cid, title, ok, input, expected, actual, detail, required)
			_:
				_emit(rep, tracker, GateResult.E_UNKNOWN_KIND, cid, title, false,
					{"kind": kind}, "已知 gate kind", kind,
					"未知判定类型 %s" % kind, required)
	return rep

static func signal_cases(cfg: Dictionary, measured_delay: int, glitch_width: int, fix_clean: bool, quiz_answer: int,
		tracker: GateAttemptTracker = null) -> GateReport:
	var rep := GateReport.new()
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		var title := str(c.get("title", ""))
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"delay":
				var want := int(c.get("expected", 9))
				var ok := measured_delay == want
				var code := GateResult.E_BUILD if measured_delay < 0 else GateResult.E_DELAY_MISMATCH
				_emit(rep, tracker, code, cid, title, ok,
					{"inputs": ["a", "b"]}, want, measured_delay,
					"测得 %d tick，期望 %d" % [measured_delay, want], required)
			"glitch":
				var min_w := int(c.get("min_width", 1))
				var ok := glitch_width >= min_w
				_emit(rep, tracker, GateResult.E_GLITCH, cid, title, ok,
					{"toggles": int(c.get("toggles", 20))}, min_w, glitch_width,
					"测得毛刺宽度 %d tick（下限 %d）" % [glitch_width, min_w], required)
			"fix":
				var toggles := int(c.get("toggles", 20))
				_emit(rep, tracker, GateResult.E_GLITCH, cid, title, fix_clean,
					{"toggles": toggles}, true, fix_clean,
					"翻转 %d 次，毛刺=%s" % [toggles, "无" if fix_clean else "有"], required)
			"quiz":
				var q: Dictionary = cfg.get("quiz", {})
				var answer := int(q.get("answer", -1))
				var ok := quiz_answer == answer
				_emit(rep, tracker, GateResult.E_QUIZ, cid, title, ok,
					{"chosen": quiz_answer}, answer, quiz_answer,
					"选择 %d，正确答案 %d" % [quiz_answer, answer], required)
			_:
				_emit(rep, tracker, GateResult.E_UNKNOWN_KIND, cid, title, false,
					{"kind": kind}, "已知 gate kind", kind,
					"未知判定类型 %s" % kind, required)
	return rep

static func half_adder(cfg: Dictionary, graph: CircuitGraph, encapsulated: bool,
		tracker: GateAttemptTracker = null) -> GateReport:
	var rep := GateReport.new()
	var inputs := ["a", "b"]
	var outputs := ["sum", "carry"]
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		var title := str(c.get("title", ""))
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"truth":
				var res := BlackBox.check_outputs(graph, inputs, outputs, BlackBox.half_adder_rows())
				var f: Dictionary = res.get("failure", {})
				_emit(rep, tracker, int(res.get("code", GateResult.E_TRUTH_ROW)), cid, title,
					bool(res.get("ok", false)), f.get("input", null), f.get("expected", null), f.get("actual", null),
					"%d/%d 行" % [int(res.get("passed", 0)), int(res.get("total", 0))], required)
			"delay":
				var delay := measure_delay(graph, inputs)
				var limit := int(c.get("max", 12))
				var ok := delay >= 0 and delay <= limit
				var code := GateResult.E_BUILD if delay < 0 else GateResult.E_DELAY_EXCEED
				_emit(rep, tracker, code, cid, title, ok,
					{"inputs": inputs}, limit, delay,
					"稳定时间 %d tick（上限 %d）" % [delay, limit], required)
			"encapsulation":
				_emit(rep, tracker, GateResult.E_ENCAPSULATION, cid, title, encapsulated,
					{"checkpoint": "encapsulated"}, true, encapsulated,
					"封装标记=%s" % str(encapsulated), required)
			"random_x":
				var count := int(c.get("count", 8))
				var seed := int(c.get("seed", 1))
				var rng := DeterministicRng.new(seed)
				var tri := ["0", "1", "X"]
				var bad := 0
				var first_input: Variant = null
				var first_expected: Variant = null
				var first_actual: Variant = null
				var first_code := GateResult.E_X_ROW
				for i in count:
					var a := str(tri[rng.next_int(0, 2)])
					var b := str(tri[rng.next_int(0, 2)])
					var got := BlackBox.tri_eval(graph, {"a": a, "b": b})
					var want := BlackBox.half_adder_tri(a, b)
					var ok_row := bool(got.get("ok", false))
					var actual: Variant = got.get("values", {})
					if ok_row:
						var vals: Dictionary = got.get("values", {})
						if str(vals.get("sum", "")) != str(want["sum"]) or str(vals.get("carry", "")) != str(want["carry"]):
							ok_row = false
					if not ok_row:
						bad += 1
						if first_input == null:
							first_input = {"a": a, "b": b}
							first_expected = want
							first_actual = actual
							first_code = int(got.get("code", GateResult.E_X_ROW)) if not bool(got.get("ok", false)) else GateResult.E_X_ROW
				_emit(rep, tracker, first_code, cid, title, bad == 0,
					first_input, first_expected, first_actual,
					"含 X 随机 %d 组，失败 %d" % [count, bad], required)
			_:
				_emit(rep, tracker, GateResult.E_UNKNOWN_KIND, cid, title, false,
					{"kind": kind}, "已知 gate kind", kind,
					"未知判定类型 %s" % kind, required)
	return rep

static func measure_delay(graph: CircuitGraph, input_ids: Array) -> int:
	## 用 L1 仿真测最坏稳定时间（tick）。失败返回 -1。
	if graph == null:
		return -1
	var built := SimCircuit.build_graph(graph, -1)
	if not bool(built.get("ok", false)):
		return -1
	var sim: SimCircuit = built["sim"]
	var outputs: Array = built.get("outputs", [])
	var patterns := _patterns(input_ids.size())
	var worst := 0
	var prev: Array = []
	for p in patterns:
		if not prev.is_empty():
			var t0 := sim.now()
			for i in input_ids.size():
				sim.set_input(str(input_ids[i]), str(p[i]))
			var d := sim.measure_settle(outputs, t0)
			if d < 0:
				return -1
			worst = maxi(worst, d)
		else:
			for i in input_ids.size():
				sim.set_input(str(input_ids[i]), str(p[i]))
			var rr := sim.settle()
			if not bool(rr.get("ok", false)):
				return -1
		prev = p
	return worst

static func _emit(rep: GateReport, tracker: GateAttemptTracker, code: int, cid: String, title: String,
		ok: bool, input: Variant, expected: Variant, actual: Variant, detail: String, required: bool) -> void:
	## 统一出口：失败 code 原样保留（未知 code 由 `GateResult` 兜底成 `E_GENERIC`）。
	var attempt := tracker.record(cid, ok) if tracker != null else 0
	var use_code := GateResult.OK if ok else code
	rep.add_case(use_code, cid, title, input, expected, actual, [], detail, required, attempt)

static func _patterns(n: int) -> Array:
	if n <= 0:
		return [[]]
	var out := [[]]
	for _i in n:
		var next := []
		for row in out:
			for b in ["0", "1"]:
				var nr: Array = (row as Array).duplicate()
				nr.append(b)
				next.append(nr)
		out = next
	return out

static func _check_task(graph: CircuitGraph, task: Dictionary) -> Dictionary:
	if graph == null:
		return {"ok": false, "passed": 0, "total": 0, "issues": ["电路缺失"],
			"code": GateResult.E_MISSING_GRAPH,
			"failure": GateResult.make(GateResult.E_MISSING_GRAPH, "", {"task": task.get("id", "")}, "电路存在", null)}
	var target := str(task.get("target", ""))
	var inputs: Array = task.get("input_ids", ["a", "b"])
	return BlackBox.check_target(graph, target, inputs, ["out"])

static func _task_by_target(cfg: Dictionary, target: String) -> Dictionary:
	for raw in cfg.get("tasks", []):
		var t: Dictionary = raw
		if str(t.get("target", "")) == target:
			return t
	return {}

static func _gate_cfg(cfg: Dictionary, gid: String) -> Dictionary:
	for raw in cfg.get("gates", []):
		var g: Dictionary = raw
		if str(g.get("id", "")) == gid:
			return g
	return {}

static func _target(cfg: Dictionary, tid: String) -> Dictionary:
	for raw in cfg.get("targets", []):
		var t: Dictionary = raw
		if str(t.get("id", "")) == tid:
			return t
	return {}
