extends RefCounted

## M5 · CH02 数据落地与判定：20 条 gate，每节正确解全过 + 错误解失败。

const Ch02ChecksScript := preload("res://src/core/ch02_checks.gd")

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 100
const EXPECT_GROUPS := {
	"loadable": 2, "doc_shape": 4, "gate_cases_per_lab": 25, "gate_totals": 3,
	"economy": 8, "manifest": 3, "transistor_correct": 8, "transistor_quiz": 2,
	"transistor_region": 12, "inverter": 9, "nand": 2, "replace": 5,
	"power": 13, "trace": 4,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch02_levels / ch02_labs 两个数据文件可读",
	"doc_shape": "章节 version=2、id=ch02、5 节、5 目标",
	"gate_cases_per_lab": "每节 4 条 gate、gate_ids 与用例一一对应、奖励物品存在",
	"gate_totals": "20 条 gate、2 条 pending 且清单为 T2.2-3/T2.4-4",
	"economy": "CH01 结余区间、CH02 收支与章末结余、起始金币模式与开局物品",
	"manifest": "manifest 登记 10 个文件且含 ch02 两个新文件",
	"transistor_correct": "2.1 正确解全过、四测点、Vds=6.0 仍饱和且 Id 封顶 5000µA",
	"transistor_quiz": "2.1 错误选择题失败并命中 E_QUIZ",
	"transistor_region": "2.1 三区域判对/判错/未作答/期望区域不符均按 E_REGION 处理",
	"inverter": "2.2 正确解 required 全过、pending 不计入、轨到轨合法与越界、错误解落真值表",
	"nand": "2.3 全 NAND 正确解全过、换掉 t_or 后失败",
	"replace": "2.4 正确解 required 全过、pending 1 不计入、错误解落 E_EQUIV",
	"power": "2.5 功耗/面积/槽位三类判据：正确解过、错比、塞不下、槽位不足、展开门数口径",
	"trace": "四个判定 kind 写入统一 trace，pending 不写假 trace",
}

func run(ctx: TestContext) -> void:
	var lv := TestUtil.read_json("res://data/chapters/ch02_levels.json")
	var labs := TestUtil.read_json("res://data/labs/ch02_labs.json")
	var db := TestUtil.data_db()
	var cat: Catalog = db.catalog

	ctx.begin_group("loadable")
	ctx.check("ch02_levels 可读", not lv.is_empty())
	ctx.check("ch02_labs 可读", not labs.is_empty())
	ctx.begin_group("doc_shape")
	ctx.eq("ch02 version", int(lv.get("version", 0)), 2)
	ctx.eq("ch02 id", str(lv.get("id", "")), "ch02")
	ctx.eq("ch02 5 节", (lv.get("labs", []) as Array).size(), 5)
	ctx.eq("ch02 5 目标", (lv.get("objectives", []) as Array).size(), 5)

	# ---- 20 条 gate：每节 4 条且 gate_ids 与用例一一对应 ----
	var cases_total := 0
	var gate_ids_seen := {}
	var pending_ids := []
	for raw_lab in lv.get("labs", []):
		var lab: Dictionary = raw_lab
		var lid := str(lab.get("id", ""))
		var key := str(lab.get("data_key", ""))
		var seg: Dictionary = (labs.get("labs", {}) as Dictionary).get(key, {})
		ctx.begin_group("gate_cases_per_lab")
		ctx.check("ch02 段存在 %s" % key, not seg.is_empty())
		var cases: Array = seg.get("gate_cases", [])
		ctx.eq("%s gate 数" % lid, cases.size(), 4)
		ctx.eq("%s gate_ids 数" % lid, (lab.get("gate_ids", []) as Array).size(), 4)
		for raw in cases:
			var c: Dictionary = raw
			gate_ids_seen[str(c.get("id", ""))] = true
			cases_total += 1
			if str(c.get("status", "")) == "pending":
				pending_ids.append(str(c.get("id", "")))
		ctx.check("%s 的 gate_ids 全部有定义" % lid,
			_contains_all((lab.get("gate_ids", []) as Array), gate_ids_seen))
		ctx.eq("%s 奖励物品存在" % lid, _missing_item(seg.get("grants", {}), cat), "")
	ctx.begin_group("gate_totals")
	ctx.eq("ch02 gate 总数", cases_total, 20)
	ctx.eq("ch02 pending 数", pending_ids.size(), 2)
	ctx.eq("ch02 pending 清单", pending_ids, ["T2.2-3", "T2.4-4"])

	# ---- 经济口径纠偏（12 §5）：不是 252 / 不是 88 ----
	var eco: Dictionary = lv.get("economy", {})
	ctx.begin_group("economy")
	ctx.eq("CH01 结余下限", int(eco.get("ch01_surplus_range", [0, 0])[0]), 277)
	ctx.eq("CH01 结余上限", int(eco.get("ch01_surplus_range", [0, 0])[1]), 337)
	ctx.eq("CH02 必需支出", int(eco.get("required_spend", 0)), 70)
	ctx.eq("CH02 收入", int(eco.get("chapter_income", 0)), 175)
	ctx.eq("CH02 章末结余下限", int(eco.get("end_balance_range", [0, 0])[0]), 382)
	ctx.eq("CH02 章末结余上限", int(eco.get("end_balance_range", [0, 0])[1]), 442)
	ctx.eq("CH02 起始金币模式", str(lv.get("start_gold_mode", "")), "carry")
	ctx.eq("开局物品存在", _missing_item({"items": lv.get("start_items", {})}, cat), "")

	# ---- manifest 登记：8 → 10 ----
	var files: Array = TestUtil.read_json("res://data/manifest.json").get("files", [])
	ctx.begin_group("manifest")
	ctx.eq("manifest 10 文件", files.size(), 10)
	ctx.check("manifest 含 ch02_levels", "res://data/chapters/ch02_levels.json" in files)
	ctx.check("manifest 含 ch02_labs", "res://data/labs/ch02_labs.json" in files)

	# ---- 2.1 正确解 / 错误解（区域判断由玩家提交，模型只给真值）----
	var t_cfg: Dictionary = labs["labs"]["transistor"]
	var t_answers := {"T2.1-1": "cutoff", "T2.1-2": "linear", "T2.1-3": "saturation", "T2.1-4": 1}
	var t_ok: Dictionary = Ch02ChecksScript.run("transistor", t_cfg, {"answers": t_answers})
	ctx.begin_group("transistor_correct")
	ctx.check("2.1 正确解全过", bool((t_ok["report"] as GateReport).all_required_passed()))
	ctx.eq("2.1 pending 0", (t_ok["pending"] as Array).size(), 0)
	# 第四个测点：Vgs=3.3、Vds=6.0 仍在饱和，Id 与 Vds=3.0 完全相等（容差 0）
	var dev: Dictionary = t_cfg["device"]
	ctx.eq("2.1 四个测点", (t_cfg.get("measure_conditions", []) as Array).size(), 4)
	ctx.eq("2.1 第四测点 Vds", float((t_cfg["measure_conditions"][3] as Dictionary).get("vds", -1)), 6.0)
	ctx.eq("2.1 Vds 6.0 仍饱和", Ch02ChecksScript.region_of(3.3, 6.0, dev), "saturation")
	ctx.eq("2.1 Vds 3.0/6.0 的 Id 相等（容差 0）",
		Ch02ChecksScript.id_ua_of(3.3, 3.0, dev), Ch02ChecksScript.id_ua_of(3.3, 6.0, dev))
	ctx.eq("2.1 封顶值 5000 µA", Ch02ChecksScript.id_ua_of(3.3, 6.0, dev), 5000.0)
	ctx.eq("2.1 T2.1-3 声明多点封顶", t_cfg["gate_cases"][2].get("equal_id_vds", []), [3.0, 6.0])
	var t_bad_quiz := t_answers.duplicate()
	t_bad_quiz["T2.1-4"] = 0
	var t_bad: Dictionary = Ch02ChecksScript.run("transistor", t_cfg, {"answers": t_bad_quiz})
	ctx.begin_group("transistor_quiz")
	ctx.check("2.1 错误选择题失败", not bool((t_bad["report"] as GateReport).all_required_passed()))
	ctx.check("2.1 错误选择题命中 quiz code",
		GateResult.E_QUIZ in (t_bad["report"] as GateReport).failure_codes())
	# 四种组合：三个区域各一条正确 + 各一条错误 + 未作答
	for combo in [["T2.1-1", "cutoff"], ["T2.1-2", "linear"], ["T2.1-3", "saturation"]]:
		var only := t_answers.duplicate()
		only[combo[0]] = combo[1]
		ctx.begin_group("transistor_region")
		ctx.check("2.1 %s 判对通过" % combo[1],
			bool((Ch02ChecksScript.run("transistor", t_cfg, {"answers": only})["report"] as GateReport).all_required_passed()))
		var wrong_by := {"cutoff": "linear", "linear": "saturation", "saturation": "cutoff"}
		var only_bad := t_answers.duplicate()
		only_bad[combo[0]] = wrong_by[combo[1]]
		var r_combo: Dictionary = Ch02ChecksScript.run("transistor", t_cfg, {"answers": only_bad})
		ctx.check("2.1 %s 判错失败" % combo[1],
			not bool((r_combo["report"] as GateReport).all_required_passed()))
		ctx.check("2.1 %s 判错落 E_REGION" % combo[1],
			GateResult.E_REGION in (r_combo["report"] as GateReport).failure_codes())
	var t_no_answer := t_answers.duplicate()
	t_no_answer.erase("T2.1-2")
	var t_none: Dictionary = Ch02ChecksScript.run("transistor", t_cfg, {"answers": t_no_answer})
	ctx.check("2.1 未作答区域失败", not bool((t_none["report"] as GateReport).all_required_passed()))
	# 期望区域与模型不符：判定必须失败而不是放行
	var t_fake: Dictionary = t_cfg.duplicate(true)
	t_fake["gate_cases"][0]["expect_region"] = "linear"
	var t_fake_res: Dictionary = Ch02ChecksScript.run("transistor", t_fake, {"answers": t_answers})
	ctx.check("2.1 区域期望不符失败", not bool((t_fake_res["report"] as GateReport).all_required_passed()))
	ctx.eq("2.1 错误 code", (t_fake_res["report"] as GateReport).failure_codes(), [GateResult.E_REGION])

	# ---- 2.2 反相器 ----
	var i_cfg: Dictionary = labs["labs"]["inverter"]
	var i_ok: Dictionary = Ch02ChecksScript.run("inverter", i_cfg, {"graph": _g1("not")})
	var i_rep: GateReport = i_ok["report"]
	ctx.begin_group("inverter")
	ctx.check("2.2 正确解 required 全过", i_rep.all_required_passed())
	ctx.eq("2.2 pending 1", (i_ok["pending"] as Array).size(), 1)
	ctx.check("2.2 pending 不计入 required", _pending_not_required(i_rep))
	# rail_margin 已落地：合法电平通过
	ctx.check("2.2 轨到轨合法电平通过", _code_of(i_rep, "T2.2-4") == "OK")
	ctx.check("2.2 轨到轨未落失败 code", not (GateResult.E_RAIL_MARGIN in i_rep.failure_codes()))
	# rail_margin 越界：导通电阻过大 → 高电平被拉低、低电平被抬升
	var i_bad_rail_cfg: Dictionary = i_cfg.duplicate(true)
	i_bad_rail_cfg["rail"]["ron_ohm"] = 1000
	var i_rail: Dictionary = Ch02ChecksScript.run("inverter", i_bad_rail_cfg, {"graph": _g1("not")})
	ctx.check("2.2 轨到轨越界失败", not bool((i_rail["report"] as GateReport).all_required_passed()))
	ctx.check("2.2 轨到轨越界落 E_RAIL_MARGIN",
		GateResult.E_RAIL_MARGIN in (i_rail["report"] as GateReport).failure_codes())
	var i_bad: Dictionary = Ch02ChecksScript.run("inverter", i_cfg, {"graph": _g1("buf")})
	ctx.check("2.2 错误解失败", not bool((i_bad["report"] as GateReport).all_required_passed()))
	ctx.check("2.2 错误解命中真值表 code",
		GateResult.E_TRUTH_ROW in (i_bad["report"] as GateReport).failure_codes())

	# ---- 2.3 万能门：只用 NAND ----
	var n_cfg: Dictionary = labs["labs"]["nand"]
	var n_graphs := {
		"t_nand": _g2("nand"),
		"t_not": _nand_not(),
		"t_and": _nand_and(),
		"t_or": _nand_or(),
	}
	var n_ok: Dictionary = Ch02ChecksScript.run("nand", n_cfg, {"graphs": n_graphs})
	ctx.begin_group("nand")
	ctx.check("2.3 正确解全过", bool((n_ok["report"] as GateReport).all_required_passed()))
	var n_bad_graphs := n_graphs.duplicate()
	n_bad_graphs["t_or"] = _g2("and")
	var n_bad: Dictionary = Ch02ChecksScript.run("nand", n_cfg, {"graphs": n_bad_graphs})
	ctx.check("2.3 错误解失败", not bool((n_bad["report"] as GateReport).all_required_passed()))

	# ---- 2.4 等价替换 ----
	var r_cfg: Dictionary = labs["labs"]["replace"]
	var r_ok: Dictionary = Ch02ChecksScript.run("replace", r_cfg, {"graph": _xor_nand()})
	ctx.begin_group("replace")
	ctx.check("2.4 正确解 required 全过", bool((r_ok["report"] as GateReport).all_required_passed()))
	ctx.eq("2.4 pending 1", (r_ok["pending"] as Array).size(), 1)
	ctx.check("2.4 pending 不计入 required", _pending_not_required(r_ok["report"]))
	var r_bad: Dictionary = Ch02ChecksScript.run("replace", r_cfg, {"graph": _g2("and")})
	ctx.check("2.4 错误解失败", not bool((r_bad["report"] as GateReport).all_required_passed()))
	ctx.check("2.4 错误解命中等价 code",
		GateResult.E_EQUIV in (r_bad["report"] as GateReport).failure_codes())

	# ---- 2.5 功耗 ----
	var p_cfg: Dictionary = labs["labs"]["power"]
	var p_graphs := {"not": _g1("not"), "and": _g2("and"), "or": _g2("or"), "xor": _g2("xor")}
	var p_ok: Dictionary = Ch02ChecksScript.run("power", p_cfg, {"answers": {"power_mw": 0.05445, "ratio": 0.5, "T2.5-4": 1}, "graphs": p_graphs})
	ctx.begin_group("power")
	ctx.check("2.5 正确解全过", bool((p_ok["report"] as GateReport).all_required_passed()))
	var p_bad: Dictionary = Ch02ChecksScript.run("power", p_cfg, {"answers": {"power_mw": 0.05445, "ratio": 0.8, "T2.5-4": 1}, "graphs": p_graphs})
	ctx.check("2.5 错误解失败", not bool((p_bad["report"] as GateReport).all_required_passed()))
	ctx.check("2.5 错误解命中功耗比 code",
		GateResult.E_POWER_RATIO in (p_bad["report"] as GateReport).failure_codes())
	# 板子塞不下：4 个门全用 NAND 拼 → 1+2+3+4=10 门，超过 8 门预算
	var p_heavy := {
		"not": _nand_not(), "and": _nand_and(), "or": _nand_or(), "xor": _xor_nand(),
	}
	var p_over: Dictionary = Ch02ChecksScript.run("power", p_cfg,
		{"answers": {"power_mw": 0.05445, "ratio": 0.5, "T2.5-4": 1}, "graphs": p_heavy})
	ctx.check("2.5 塞不下真失败", not bool((p_over["report"] as GateReport).all_required_passed()))
	ctx.check("2.5 塞不下落 E_AREA", GateResult.E_AREA in (p_over["report"] as GateReport).failure_codes())
	# 槽位不够：同一块板只给 2 槽
	var p_narrow: Dictionary = p_cfg.duplicate(true)
	for raw in (p_narrow["gate_cases"] as Array):
		if str(raw.get("id", "")) == "T2.5-3":
			raw["slots"] = 2
	var p_slot: Dictionary = Ch02ChecksScript.run("power", p_narrow, {"answers": {"power_mw": 0.05445, "ratio": 0.5, "T2.5-4": 1}, "graphs": p_graphs})
	ctx.check("2.5 槽位不足真失败", not bool((p_slot["report"] as GateReport).all_required_passed()))
	ctx.check("2.5 槽位不足落 E_AREA", GateResult.E_AREA in (p_slot["report"] as GateReport).failure_codes())
	# 面积口径：成品 XOR 必须按展开 4 门计，否则 8 门预算会静默失效
	var budget: int = Ch02ChecksScript.BUILD_AREA_GATE_BUDGET
	var xor_used: int = Ch02ChecksScript.expanded_gate_count(_g2("xor"))
	ctx.eq("2.5 成品 XOR 展开计 4 门", xor_used, 4)
	ctx.eq("2.5 全用现成门 = 1+1+1+4 = 7 门",
		Ch02ChecksScript.expanded_gate_count(_g1("not")) + Ch02ChecksScript.expanded_gate_count(_g2("and"))
		+ Ch02ChecksScript.expanded_gate_count(_g2("or")) + xor_used, 7)
	ctx.check("2.5 7 门在预算内且过判据",
		7 <= budget and _code_of(p_ok["report"] as GateReport, "T2.5-3") == "OK")
	# 4 个成品 XOR 摊上板：4×4=16 门，必须落 E_AREA（顶层件数口径会算成 4 而假通过）
	var p_xor4: Dictionary = p_cfg.duplicate(true)
	for raw in (p_xor4["gate_cases"] as Array):
		if str(raw.get("id", "")) == "T2.5-3":
			raw["targets"] = ["xor", "xor", "xor", "xor"]
	var p_four: Dictionary = Ch02ChecksScript.run("power", p_xor4,
		{"answers": {"power_mw": 0.05445, "ratio": 0.5, "T2.5-4": 1}, "graphs": {"xor": _g2("xor")}})
	ctx.check("2.5 四个成品 XOR = %d 门超预算" % (4 * xor_used), 4 * xor_used > budget)
	ctx.check("2.5 四个成品 XOR 真失败", not bool((p_four["report"] as GateReport).all_required_passed()))
	ctx.check("2.5 四个成品 XOR 落 E_AREA", GateResult.E_AREA in (p_four["report"] as GateReport).failure_codes())

	# ---- trace 接线：判定 kind 能落到统一事件流 ----
	var sim := SimCircuit.new("ch02_judge")
	var sink := sim.enable_trace()
	Ch02ChecksScript.run("replace", r_cfg, {"graph": _xor_nand(), "sim": sim})
	ctx.begin_group("trace")
	ctx.check("2.4 写入 EQUIV trace", sink.count_kind("EQUIV") > 0)
	Ch02ChecksScript.run("transistor", t_cfg, {"answers": {"default": 1}, "sim": sim})
	ctx.check("2.1 写入 MOSFET_REGION trace", sink.count_kind("MOSFET_REGION") > 0)
	Ch02ChecksScript.run("inverter", i_cfg, {"graph": _g1("not"), "sim": sim})
	ctx.check("2.2 写入 RAIL_MARGIN trace", sink.count_kind("RAIL_MARGIN") > 0)
	ctx.eq("pending kind 不写假 trace", sink.count_kind("STATIC_CURRENT"), 0)

# ---------------------------------------------------------------- 图构造

func _g1(gate: String, out_id: String = "out") -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_gate("g1", LogicGates.from_string(gate))
	g.link("a", "g1", 0)
	g.add_output(out_id)
	g.link("g1", out_id, 0)
	return g

func _g2(gate: String, out_id: String = "out") -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_input("b")
	g.add_gate("g1", LogicGates.from_string(gate))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output(out_id)
	g.link("g1", out_id, 0)
	return g

func _nand_not() -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_gate("n1", LogicGates.Type.NAND)
	g.link("a", "n1", 0)
	g.link("a", "n1", 1)
	g.add_output("out")
	g.link("n1", "out", 0)
	return g

func _nand_and() -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_input("b")
	g.add_gate("n1", LogicGates.Type.NAND)
	g.link("a", "n1", 0)
	g.link("b", "n1", 1)
	g.add_gate("n2", LogicGates.Type.NAND)
	g.link("n1", "n2", 0)
	g.link("n1", "n2", 1)
	g.add_output("out")
	g.link("n2", "out", 0)
	return g

func _nand_or() -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_input("b")
	g.add_gate("n1", LogicGates.Type.NAND)
	g.link("a", "n1", 0)
	g.link("a", "n1", 1)
	g.add_gate("n2", LogicGates.Type.NAND)
	g.link("b", "n2", 0)
	g.link("b", "n2", 1)
	g.add_gate("n3", LogicGates.Type.NAND)
	g.link("n1", "n3", 0)
	g.link("n2", "n3", 1)
	g.add_output("out")
	g.link("n3", "out", 0)
	return g

func _xor_nand() -> CircuitGraph:
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

# ---------------------------------------------------------------- 断言工具

func _contains_all(ids: Array, seen: Dictionary) -> bool:
	for raw in ids:
		if not seen.has(str(raw)):
			return false
	return true

func _missing_item(grants: Dictionary, cat: Catalog) -> String:
	var items: Dictionary = grants.get("items", {})
	for raw in items.keys():
		if not cat.has_item(str(raw)):
			return "未知物品 %s" % str(raw)
	return ""

func _code_of(rep: GateReport, cid: String) -> String:
	for c in rep.cases:
		if str(c.get("id", "")) == cid:
			return str(c.get("code_name", ""))
	return ""

func _pending_not_required(rep: GateReport) -> bool:
	for c in rep.cases:
		if str(c.get("code_name", "")) == "E_PENDING":
			if bool(c.get("required", true)):
				return false
			if bool(c.get("ok", false)):
				return false
	return true


