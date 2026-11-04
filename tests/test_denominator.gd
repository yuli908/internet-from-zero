extends RefCounted

## M5 · 分母口径：`content_status` 非 ready 的 gate 不进分母 / 不进进度条。
## 旧逻辑（分母 = 全部 gate）会把永远 pending 的项算进去，玩家永远停在 3/4。

const Ch02ChecksScript := preload("res://src/core/ch02_checks.gd")

func run(ctx: TestContext) -> void:
	var labs: Dictionary = TestUtil.read_json("res://data/labs/ch02_labs.json").get("labs", {})
	ctx.check("ch02_labs 可读", not labs.is_empty())
	var inverter: Dictionary = labs.get("inverter", {})
	var replace: Dictionary = labs.get("replace", {})

	# ---- 4 → 3：inverter / replace 各有一项永远 pending ----
	var inv: Dictionary = Ch02ChecksScript.deferred_gates(inverter)
	ctx.eq("inverter gate 总数 4", int(inv["total"]), 4)
	ctx.eq("inverter 进分母 3", int(inv["counted"]), 3)
	ctx.eq("inverter 延后数 1", int(inv["deferred"]), 1)
	ctx.eq("inverter 延后 id", inv["ids"], ["T2.2-3"])
	var rep_lab: Dictionary = Ch02ChecksScript.deferred_gates(replace)
	ctx.eq("replace gate 总数 4", int(rep_lab["total"]), 4)
	ctx.eq("replace 进分母 3", int(rep_lab["counted"]), 3)
	ctx.eq("replace 延后 id", rep_lab["ids"], ["T2.4-4"])

	# ---- 没有 pending 的节不许被误剔：4 / 4 ----
	for id in ["transistor", "nand", "power"]:
		var r: Dictionary = Ch02ChecksScript.deferred_gates(labs.get(id, {}))
		ctx.eq("%s gate 总数 4" % id, int(r["total"]), 4)
		ctx.eq("%s 进分母 4" % id, int(r["counted"]), 4)
		ctx.eq("%s 延后 0" % id, int(r["deferred"]), 0)

	# ---- ready 后自动回到分母（同一份数据，只在内存里改） ----
	var ready: Dictionary = inverter.duplicate(true)
	for raw in (ready["gate_cases"] as Array):
		if str((raw as Dictionary).get("id", "")) == "T2.2-3":
			raw["content_status"] = "ready"
	var rdy: Dictionary = Ch02ChecksScript.deferred_gates(ready)
	ctx.eq("ready 后进分母 4", int(rdy["counted"]), 4)
	ctx.eq("ready 后延后 0", int(rdy["deferred"]), 0)
	ctx.check("ready 后无 section_deferred", not bool(rdy["section_deferred"]))

	# ---- 整节 deferred：整节不进分母（沿用既有裁决，不按 gate 逐个丢） ----
	var ch2 := ChapterRuntime.from_doc(TestUtil.read_json("res://data/chapters/ch02_levels.json"))
	var sec := str(ch2.content_status("replace"))
	ctx.eq("replace 整节状态取自数据", sec, "deferred")
	var d_sec: Dictionary = Ch02ChecksScript.deferred_gates(replace, sec)
	ctx.eq("整节 deferred 进分母 0", int(d_sec["counted"]), 0)
	ctx.eq("整节 deferred 延后 4", int(d_sec["deferred"]), 4)
	ctx.check("整节 deferred 标记为真", bool(d_sec["section_deferred"]))
	ctx.check("ready 节整节标记为假", not bool(inv["section_deferred"]))

	# ---- E_PENDING(25) 不进提示阶梯 ----
	ctx.eq("25 为纯 R（只进日志）", GateResult.tags_for(GateResult.E_PENDING), ["R"])

	# ---- 正向对照：旧逻辑 3/4，新逻辑 3/3 ----
	var i_res: Dictionary = Ch02ChecksScript.run("inverter", inverter, {"graph": _not_graph()})
	var i_rep: GateReport = i_res["report"]
	var passed := 0
	for c in i_rep.cases:
		if bool((c as Dictionary).get("ok", false)):
			passed += 1
	ctx.eq("inverter 实过 3 项", passed, 3)
	ctx.eq("旧逻辑分母 4", i_rep.cases.size(), 4)
	ctx.check("旧逻辑显示 3/4（差项永远补不上）", passed == 3 and i_rep.cases.size() == 4)
	ctx.check("新逻辑 3/3 全绿", passed == int(inv["counted"]))
	ctx.eq("新逻辑分母 3", int(inv["counted"]), 3)

	# ---- 附 1：id_sat_ua 兜底默认必须与数据一致（旧值 1000 会让线性 4 mA 被判成超饱和） ----
	var dev: Dictionary = (labs.get("transistor", {}) as Dictionary).get("device", {})
	ctx.eq("数据 id_sat_ua 为 5000", int(dev.get("id_sat_ua", -1)), 5000)
	ctx.eq("缺省兜底等于数据值", Ch02ChecksScript.id_ua_of(3.3, 3.0, {}), float(dev.get("id_sat_ua", -1)))
	ctx.check("线性 4 mA 不再大于饱和电流", Ch02ChecksScript.id_ua_of(3.3, 0.2, {})
		< Ch02ChecksScript.id_ua_of(3.3, 3.0, {}))

	# ---- 附 2：build_area 槽位分支按真实顶层器件占用，而不是 target 个数 ----
	var p_cfg: Dictionary = labs.get("power", {})
	var p_answers := {"power_mw": 0.05445, "ratio": 0.5, "T2.5-4": 1}
	var p_graphs := {"not": _g1("not"), "and": _g2("and"), "or": _g2("or"), "xor": _g2("xor")}
	var p_ok: Dictionary = Ch02ChecksScript.run("power", p_cfg, {"answers": p_answers, "graphs": p_graphs})
	ctx.check("现成门占 4 槽全过", bool((p_ok["report"] as GateReport).all_required_passed()))
	var p_tight := {"not": _g1("not"), "and": _g2("and"), "or": _g2("or"), "xor": _nand_xor()}
	var p_slot: Dictionary = Ch02ChecksScript.run("power", p_cfg, {"answers": p_answers, "graphs": p_tight})
	var p_rep: GateReport = p_slot["report"]
	ctx.check("4 目标 ≤4 槽但实占 7 槽 → 红", not p_rep.all_required_passed())
	ctx.check("槽位分支落 E_AREA", GateResult.E_AREA in p_rep.failure_codes())
	var p_detail := ""
	for c in p_rep.cases:
		if str((c as Dictionary).get("id", "")) == "T2.5-3":
			p_detail = str((c as Dictionary).get("detail", ""))
	ctx.check("拒绝理由写明 7>4 槽", p_detail.contains("槽位 7>4"))

func _g1(gate: String) -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_gate("g1", LogicGates.from_string(gate))
	g.link("a", "g1", 0)
	g.add_output("out")
	g.link("g1", "out", 0)
	return g

func _g2(gate: String) -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_input("b")
	g.add_gate("g1", LogicGates.from_string(gate))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out")
	g.link("g1", "out", 0)
	return g

func _nand_xor() -> CircuitGraph:
	## 用 4 个顶层 NAND 拼 XOR：展开 4 门，但占 4 个物理槽位。
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_input("b")
	g.add_gate("n1", LogicGates.Type.NAND)
	g.link("a", "n1", 0)
	g.link("b", "n1", 1)
	g.add_gate("n2", LogicGates.Type.NAND)
	g.link("a", "n2", 0)
	g.link("n1", "n2", 1)
	g.add_gate("n3", LogicGates.Type.NAND)
	g.link("b", "n3", 0)
	g.link("n1", "n3", 1)
	g.add_gate("n4", LogicGates.Type.NAND)
	g.link("n2", "n4", 0)
	g.link("n3", "n4", 1)
	g.add_output("out")
	g.link("n4", "out", 0)
	return g

func _not_graph() -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_gate("g1", LogicGates.Type.NOT)
	g.link("a", "g1", 0)
	g.add_output("out")
	g.link("g1", "out", 0)
	return g
