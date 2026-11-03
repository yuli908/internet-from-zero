class_name LabChecks
extends RefCounted

## 第一章 6 节 gate 用例的纯逻辑判定（不依赖 autoload / 场景树）。
## 输入来自 data/labs/ch01_labs.json；UI 只负责采集与展示，测试可直接调用。

static func voltage(cfg: Dictionary) -> GateReport:
	return VoltageModel.cases(cfg)

static func binary(cfg: Dictionary, visited: Dictionary, achieved: Dictionary, quiz_answer: int) -> GateReport:
	var rep := GateReport.new()
	var ci := 0
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", "T1.2-%d" % (ci + 1)))
		ci += 1
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"coverage":
				var top := int(c.get("max", 15))
				var missing := []
				for v in range(0, top + 1):
					if not bool(visited.get(str(v), visited.get(v, false))):
						missing.append(str(v))
				var ok := missing.is_empty()
				rep.add(cid, str(c.get("title", "")), ok, "已覆盖 %d/%d 个值" % [top + 1 - missing.size(), top + 1], required)
			"target":
				var tid := str(c.get("target", ""))
				var tgt := _target(cfg, tid)
				var want := int(tgt.get("value", -1))
				var ok := bool(achieved.get(tid, false))
				rep.add(cid, str(c.get("title", "")), ok, "目标值 %d，已达成=%s" % [want, str(ok)], required)
			"quiz":
				var q: Dictionary = cfg.get("quiz", {})
				var ok := quiz_answer == int(q.get("answer", -1))
				rep.add(cid, str(c.get("title", "")), ok, "选择 %d，正确答案 %d" % [quiz_answer, int(q.get("answer", -1))], required)
			_:
				rep.add(cid, str(c.get("title", "")), false, "未知判定类型 %s" % kind, required)
	return rep

static func boolean(cfg: Dictionary, filled: Dictionary) -> GateReport:
	var rep := GateReport.new()
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"table":
				var gid := str(c.get("gate", ""))
				var gate := _gate_cfg(cfg, gid)
				var expected: Array = gate.get("expected", [])
				var got: Array = filled.get(gid, [])
				var ok := got.size() == expected.size()
				var detail := "%d/%d 行正确" % [mini(got.size(), expected.size()), expected.size()]
				for i in expected.size():
					if i >= got.size() or str(got[i]) != str(int(expected[i])):
						ok = false
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, detail, required)
			"demorgan":
				var rows: Array = cfg.get("demorgan", {}).get("rows", [])
				var got: Array = filled.get("demorgan", [])
				var ok := got.size() == rows.size()
				for i in rows.size():
					var pair: Array = rows[i]
					var a := str(int(pair[0]))
					var b := str(int(pair[1]))
					var left := SimValue.not3(SimValue.bin3("and", a, b))
					var right := SimValue.bin3("or", SimValue.not3(a), SimValue.not3(b))
					if left != right:
						ok = false
					if i >= got.size() or str(got[i]) != left:
						ok = false
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, "填表 %d/%d，等价成立=%s" % [got.size(), rows.size(), str(ok)], required)
			_:
				rep.add(str(c.get("id", "")), str(c.get("title", "")), false, "未知判定类型 %s" % kind, required)
	return rep

static func gate(cfg: Dictionary, graphs: Dictionary, checkpoints: Dictionary) -> GateReport:
	var rep := GateReport.new()
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"basic":
				var parts := []
				var ok := true
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
					parts.append("%s:%d/%d" % [target, int(res.get("passed", 0)), int(res.get("total", 0))])
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, " ".join(PackedStringArray(parts)), required)
			"xor":
				var task := _task_by_target(cfg, "xor")
				var g: CircuitGraph = graphs.get(str(task.get("id", "t_xor")), null)
				var res := _check_task(g, task)
				var delay := measure_delay(g, task.get("input_ids", ["a", "b"]))
				var limit := int(c.get("max_delay", 12))
				var ok := bool(res.get("ok", false)) and delay >= 0 and delay <= limit
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, "行 %d/%d，延迟 %d tick（上限 %d）" % [int(res.get("passed", 0)), int(res.get("total", 0)), delay, limit], required)
			"encapsulation":
				var ok := bool(checkpoints.get("encapsulated", false))
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, "封装标记=%s" % str(ok), required)
			"second":
				var first: CircuitGraph = graphs.get("t_xor", null)
				var second: CircuitGraph = graphs.get("t_xor_2", null)
				var ok := false
				var detail := "第二结构缺失"
				if first != null and second != null:
					var res := _check_task(second, _task_by_target(cfg, "xor"))
					var diff := BlackBox.signature(first) != BlackBox.signature(second)
					ok = bool(res.get("ok", false)) and diff
					detail = "行 %d/%d，结构不同=%s" % [int(res.get("passed", 0)), int(res.get("total", 0)), str(diff)]
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, detail, required)
			_:
				rep.add(str(c.get("id", "")), str(c.get("title", "")), false, "未知判定类型 %s" % kind, required)
	return rep

static func signal_cases(cfg: Dictionary, measured_delay: int, glitch_width: int, fix_clean: bool, quiz_answer: int) -> GateReport:
	var rep := GateReport.new()
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"delay":
				var want := int(c.get("expected", 9))
				var ok := measured_delay == want
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, "测得 %d tick，期望 %d" % [measured_delay, want], required)
			"glitch":
				var min_w := int(c.get("min_width", 1))
				var ok := glitch_width >= min_w
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, "测得毛刺宽度 %d tick（下限 %d）" % [glitch_width, min_w], required)
			"fix":
				var toggles := int(c.get("toggles", 20))
				rep.add(str(c.get("id", "")), str(c.get("title", "")), fix_clean, "翻转 %d 次，毛刺=%s" % [toggles, "无" if fix_clean else "有"], required)
			"quiz":
				var q: Dictionary = cfg.get("quiz", {})
				var ok := quiz_answer == int(q.get("answer", -1))
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, "选择 %d，正确答案 %d" % [quiz_answer, int(q.get("answer", -1))], required)
			_:
				rep.add(str(c.get("id", "")), str(c.get("title", "")), false, "未知判定类型 %s" % kind, required)
	return rep

static func half_adder(cfg: Dictionary, graph: CircuitGraph, encapsulated: bool) -> GateReport:
	var rep := GateReport.new()
	var inputs := ["a", "b"]
	var outputs := ["sum", "carry"]
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var kind := str(c.get("kind", ""))
		var required := bool(c.get("required", true))
		match kind:
			"truth":
				var res := BlackBox.check_outputs(graph, inputs, outputs, BlackBox.half_adder_rows())
				rep.add(str(c.get("id", "")), str(c.get("title", "")), bool(res.get("ok", false)), "%d/%d 行" % [int(res.get("passed", 0)), int(res.get("total", 0))], required)
			"delay":
				var delay := measure_delay(graph, inputs)
				var limit := int(c.get("max", 12))
				var ok := delay >= 0 and delay <= limit
				rep.add(str(c.get("id", "")), str(c.get("title", "")), ok, "稳定时间 %d tick（上限 %d）" % [delay, limit], required)
			"encapsulation":
				rep.add(str(c.get("id", "")), str(c.get("title", "")), encapsulated, "封装标记=%s" % str(encapsulated), required)
			"random_x":
				var count := int(c.get("count", 8))
				var seed := int(c.get("seed", 1))
				var rng := DeterministicRng.new(seed)
				var tri := ["0", "1", "X"]
				var bad := 0
				var rows := []
				for i in count:
					var a := str(tri[rng.next_int(0, 2)])
					var b := str(tri[rng.next_int(0, 2)])
					var got := BlackBox.tri_eval(graph, {"a": a, "b": b})
					var want := BlackBox.half_adder_tri(a, b)
					var ok_row := bool(got.get("ok", false))
					if ok_row:
						var vals: Dictionary = got.get("values", {})
						if str(vals.get("sum", "")) != str(want["sum"]) or str(vals.get("carry", "")) != str(want["carry"]):
							ok_row = false
					if not ok_row:
						bad += 1
					rows.append({"a": a, "b": b, "ok": ok_row})
				rep.add(str(c.get("id", "")), str(c.get("title", "")), bad == 0, "含 X 随机 %d 组，失败 %d" % [count, bad], required)
			_:
				rep.add(str(c.get("id", "")), str(c.get("title", "")), false, "未知判定类型 %s" % kind, required)
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
		return {"ok": false, "passed": 0, "total": 0, "issues": ["电路缺失"]}
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
