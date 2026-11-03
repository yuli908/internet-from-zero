extends RefCounted

## 第一章 6 节、24 条 gate 用例：驱动 LabChecks 纯判定层。
## 每种 lab 都验证「正确解全过」与「错误解失败」两条路径。

const LAB_IDS := ["level", "binary", "boolean", "gate", "signal", "half_adder"]

func run(ctx: TestContext) -> void:
	var labs: Dictionary = TestUtil.labs_doc().get("labs", {})
	ctx.eq("lab count", labs.size(), 6)
	for lid in LAB_IDS:
		ctx.check("lab cfg %s" % lid, labs.has(lid))
	var total := 0
	for lid in LAB_IDS:
		if not labs.has(lid):
			continue
		var raw: Dictionary = labs[lid]
		total += (raw.get("gate_cases", []) as Array).size()
		ctx.eq("gate cases %s" % lid, (raw.get("gate_cases", []) as Array).size(), 4)
	ctx.eq("total gate cases", total, 24)

	_voltage(ctx, labs.get("level", {}))
	_binary(ctx, labs.get("binary", {}))
	_boolean(ctx, labs.get("boolean", {}))
	_gate(ctx, labs.get("gate", {}))
	_signal(ctx, labs.get("signal", {}))
	_half_adder(ctx, labs.get("half_adder", {}))

func _voltage(ctx: TestContext, cfg: Dictionary) -> void:
	var rep := LabChecks.voltage(cfg)
	ctx.check("voltage 4 cases", rep.cases.size() == 4, str(rep.cases.size()))
	ctx.check("voltage all pass", rep.all_required_passed(), rep.summary())
	for i in rep.cases.size():
		ctx.check("voltage %s" % str(rep.cases[i].get("id", "")), bool(rep.cases[i].get("ok", false)))
	# 错误期望值必须被识别为失败
	var bad := cfg.duplicate(true)
	var cases: Array = bad.get("gate_cases", [])
	for i in cases.size():
		if str((cases[i] as Dictionary).get("id", "")) == "T1.1-4":
			(cases[i] as Dictionary)["expect"] = "0"
	var bad_rep := LabChecks.voltage(bad)
	ctx.check("voltage wrong expect fails", not bad_rep.all_required_passed(), bad_rep.summary())
	ctx.check("voltage boundary 0.8 is 0", VoltageModel.judge(0.8, 0.8, 2.0) == SimValue.ZERO)
	ctx.check("voltage boundary 2.0 is 1", VoltageModel.judge(2.0, 0.8, 2.0) == SimValue.ONE)

func _binary(ctx: TestContext, cfg: Dictionary) -> void:
	var visited := {}
	for v in range(0, 16):
		visited[str(v)] = true
	var achieved := {"t137": true, "t2f": true}
	var quiz := 1
	var rep := LabChecks.binary(cfg, visited, achieved, quiz)
	ctx.check("binary 4 cases", rep.cases.size() == 4, str(rep.cases.size()))
	ctx.check("binary all pass", rep.all_required_passed(), rep.summary())
	# 缺一个值 → 覆盖用例失败
	var miss := visited.duplicate()
	miss.erase("7")
	var r2 := LabChecks.binary(cfg, miss, achieved, quiz)
	ctx.check("binary missing coverage fails", not r2.all_required_passed(), r2.summary())
	# 未达成目标 → 目标用例失败
	var r3 := LabChecks.binary(cfg, visited, {"t137": true}, quiz)
	ctx.check("binary missing target fails", not r3.all_required_passed(), r3.summary())
	# 答错 → quiz 用例失败
	var r4 := LabChecks.binary(cfg, visited, achieved, 0)
	ctx.check("binary wrong quiz fails", not r4.all_required_passed(), r4.summary())

func _boolean(ctx: TestContext, cfg: Dictionary) -> void:
	var filled := {
		"and": ["0", "0", "0", "1"],
		"or": ["0", "1", "1", "1"],
		"not": ["1", "0"],
		"demorgan": ["1", "1", "1", "0"],
	}
	var rep := LabChecks.boolean(cfg, filled)
	ctx.check("boolean 4 cases", rep.cases.size() == 4, str(rep.cases.size()))
	ctx.check("boolean all pass", rep.all_required_passed(), rep.summary())
	var bad := filled.duplicate(true)
	bad["and"] = ["0", "0", "1", "1"]
	var r2 := LabChecks.boolean(cfg, bad)
	ctx.check("boolean wrong AND fails", not r2.all_required_passed(), r2.summary())
	var bad2 := filled.duplicate(true)
	bad2["demorgan"] = ["1", "0", "0", "1"]
	var r3 := LabChecks.boolean(cfg, bad2)
	ctx.check("boolean wrong demorgan fails", not r3.all_required_passed(), r3.summary())

func _gate(ctx: TestContext, cfg: Dictionary) -> void:
	var graphs := {
		"t_and": _and_graph(),
		"t_or": _or_graph(),
		"t_not": _not_graph(),
		"t_xor": _xor_graph_a(),
		"t_xor_2": _xor_graph_b(),
	}
	var rep := LabChecks.gate(cfg, graphs, {"encapsulated": true})
	ctx.check("gate 4 cases", rep.cases.size() == 4, str(rep.cases.size()))
	ctx.check("gate all pass", rep.all_required_passed(), rep.summary())
	# 少一个第二结构 → T1.4-4 失败
	var partial := graphs.duplicate()
	partial.erase("t_xor_2")
	var r2 := LabChecks.gate(cfg, partial, {"encapsulated": true})
	ctx.check("gate missing second fails", not r2.all_required_passed(), r2.summary())
	# 未封装 → T1.4-3 失败
	var r3 := LabChecks.gate(cfg, graphs, {"encapsulated": false})
	ctx.check("gate no encapsulation fails", not r3.all_required_passed(), r3.summary())
	# XOR 用错结构 → T1.4-2 失败
	var wrong := graphs.duplicate()
	wrong["t_xor"] = _xor_bad_graph()
	var r4 := LabChecks.gate(cfg, wrong, {"encapsulated": true})
	ctx.check("gate wrong xor fails", not r4.all_required_passed(), r4.summary())
	# 延迟必须可测且在上限内
	ctx.check("xor delay > 0", LabChecks.measure_delay(_xor_graph_a(), ["a", "b"]) > 0)
	ctx.check("xor delay <= 12", LabChecks.measure_delay(_xor_graph_a(), ["a", "b"]) <= 12)

func _signal(ctx: TestContext, cfg: Dictionary) -> void:
	var rep := LabChecks.signal_cases(cfg, 9, 2, true, 1)
	ctx.check("signal 4 cases", rep.cases.size() == 4, str(rep.cases.size()))
	ctx.check("signal all pass", rep.all_required_passed(), rep.summary())
	var r2 := LabChecks.signal_cases(cfg, 6, 2, true, 1)
	ctx.check("signal wrong delay fails", not r2.all_required_passed(), r2.summary())
	var r3 := LabChecks.signal_cases(cfg, 9, 0, true, 1)
	ctx.check("signal no glitch fails", not r3.all_required_passed(), r3.summary())
	var r4 := LabChecks.signal_cases(cfg, 9, 2, false, 1)
	ctx.check("signal unfixed fails", not r4.all_required_passed(), r4.summary())

func _half_adder(ctx: TestContext, cfg: Dictionary) -> void:
	var graph := _half_adder_graph()
	var rep := LabChecks.half_adder(cfg, graph, true)
	ctx.check("half_adder 4 cases", rep.cases.size() == 4, str(rep.cases.size()))
	ctx.check("half_adder all pass", rep.all_required_passed(), rep.summary())
	var r2 := LabChecks.half_adder(cfg, graph, false)
	ctx.check("half_adder no encapsulation fails", not r2.all_required_passed(), r2.summary())
	var wrong := _half_adder_wrong_carry()
	var r3 := LabChecks.half_adder(cfg, wrong, true)
	ctx.check("half_adder wrong carry fails", not r3.all_required_passed(), r3.summary())
	ctx.check("half_adder delay <= 12", LabChecks.measure_delay(graph, ["a", "b"]) <= 12)

# --- 电路构造 ---

func _base_graph() -> CircuitGraph:
	return CircuitGraph.new()

func _and_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _or_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("or"), "OR", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _not_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_gate("g1", LogicGates.from_string("not"), "NOT", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _xor_bad_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _xor_graph_a() -> CircuitGraph:
	## (a ∧ ¬b) ∨ (¬a ∧ b)
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("na", LogicGates.from_string("not"), "NOT", Vector2(90, -20))
	g.add_gate("nb", LogicGates.from_string("not"), "NOT", Vector2(90, 80))
	g.add_gate("p1", LogicGates.from_string("and"), "AND", Vector2(200, 0))
	g.add_gate("p2", LogicGates.from_string("and"), "AND", Vector2(200, 100))
	g.add_gate("o1", LogicGates.from_string("or"), "OR", Vector2(320, 40))
	g.link("a", "na", 0)
	g.link("b", "nb", 0)
	g.link("a", "p1", 0)
	g.link("nb", "p1", 1)
	g.link("na", "p2", 0)
	g.link("b", "p2", 1)
	g.link("p1", "o1", 0)
	g.link("p2", "o1", 1)
	g.add_output("out", "OUT", Vector2(440, 40))
	g.link("o1", "out", 0)
	return g

func _xor_graph_b() -> CircuitGraph:
	## (a ∨ b) ∧ ¬(a ∧ b)
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("n1", LogicGates.from_string("and"), "AND", Vector2(90, 10))
	g.add_gate("n2", LogicGates.from_string("not"), "NOT", Vector2(200, 10))
	g.add_gate("o1", LogicGates.from_string("or"), "OR", Vector2(90, 100))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(320, 40))
	g.link("a", "n1", 0)
	g.link("b", "n1", 1)
	g.link("n1", "n2", 0)
	g.link("a", "o1", 0)
	g.link("b", "o1", 1)
	g.link("o1", "g1", 0)
	g.link("n2", "g1", 1)
	g.add_output("out", "OUT", Vector2(440, 40))
	g.link("g1", "out", 0)
	return g

func _half_adder_graph() -> CircuitGraph:
	## SUM = a ⊕ b（复用 xor_b 结构），CARRY = a ∧ b
	var g := _xor_graph_b()
	g.add_gate("g_carry", LogicGates.from_string("and"), "AND", Vector2(320, 140))
	g.link("a", "g_carry", 0)
	g.link("b", "g_carry", 1)
	g.add_output("sum", "SUM", Vector2(440, 40))
	g.link("g1", "sum", 0)
	g.add_output("carry", "CARRY", Vector2(440, 140))
	g.link("g_carry", "carry", 0)
	return g

func _half_adder_wrong_carry() -> CircuitGraph:
	## CARRY 错接成 OR
	var g := _xor_graph_b()
	g.add_gate("g_carry", LogicGates.from_string("or"), "OR", Vector2(320, 140))
	g.link("a", "g_carry", 0)
	g.link("b", "g_carry", 1)
	g.add_output("sum", "SUM", Vector2(440, 40))
	g.link("g1", "sum", 0)
	g.add_output("carry", "CARRY", Vector2(440, 140))
	g.link("g_carry", "carry", 0)
	return g
