extends RefCounted

## CH02 兜底 `body` 的 5 条真矛盾修正 + 2.5 `build_area` 面积判据实测（7 门过 / 10 门拒）。
## 另含预算分支探针：4×成品 XOR（16>8、槽位 4）与槽位放宽副本（10 门仅预算被拒）。
## 口径来源：docs/curriculum/14-ch02-sections-sync-map.md §4.1 / §1。

const Ch02ChecksScript := preload("res://src/core/ch02_checks.gd")

func run(ctx: TestContext) -> void:
	var labs: Dictionary = TestUtil.read_json("res://data/labs/ch02_labs.json").get("labs", {})
	ctx.check("ch02_labs 可读", not labs.is_empty())
	_check_transistor(ctx, str((labs.get("transistor", {}) as Dictionary).get("body", "")))
	_check_inverter(ctx, str((labs.get("inverter", {}) as Dictionary).get("body", "")))
	_check_replace(ctx, str((labs.get("replace", {}) as Dictionary).get("body", "")))
	_check_build_area(ctx, labs.get("power", {}))

## 2.1：阈值与三区归类（不能再说「加电压就通」「按 Vds 排序」）。
func _check_transistor(ctx: TestContext, body: String) -> void:
	ctx.check("transistor body 写明 0.9 V 阈值", body.contains("阈值 0.9 V"), body)
	ctx.check("transistor body 写明低于阈值截止", body.contains("低于阈值截止"), body)
	ctx.check("transistor body 不再说「加电压就通」", not body.contains("栅极加电压，源漏之间就通"), body)
	ctx.check("transistor body 按三区归类", body.contains("按截止/线性/饱和归三个区"), body)
	ctx.check("transistor body 不再要求按 Vds 排序", not body.contains("按 Vds 从小到大排成一条"), body)

## 2.2：稳态机制（不是「有电流」，是电源到地被切断、电流 ≤1 µA）。
func _check_inverter(ctx: TestContext, body: String) -> void:
	ctx.check("inverter body 写明截止管切断", body.contains("被截止管切断"), body)
	ctx.check("inverter body 写明稳态电流 ≤1 µA", body.contains("稳态电流 ≤1 µA"), body)
	ctx.check("inverter body 不再说「有电流」", not body.contains("只有一条通路有电流"), body)

## 2.4：四项验收同时看，静态电流是 pending 不是结论。
func _check_replace(ctx: TestContext, body: String) -> void:
	ctx.check("replace body 写明行为等价是第一条", body.contains("行为等价是第一条"), body)
	ctx.check("replace body 写明四项同时看", body.contains("延迟、门数、静态电流同时看"), body)
	ctx.check("replace body 写明静态电流 pending", body.contains("标 pending，不当已知"), body)
	ctx.check("replace body 不再说「验收只看行为」", not body.contains("验收只看行为"), body)
	ctx.check("replace body 不再宣称更快更小不耗电", not body.contains("更快、更小、稳态不耗电"), body)

## 2.5 T2.5-3：展开门数预算 8；成品门 1+1+1+4=7 过，全 NAND 手搓 1+2+3+4=10 拒。
func _check_build_area(ctx: TestContext, cfg: Dictionary) -> void:
	ctx.check("ch02 power 配置存在", not cfg.is_empty())
	var answers := {"power_mw": 0.05445, "ratio": 0.5, "T2.5-4": 1}
	var seven := {"not": _g1("not"), "and": _g2("and"), "or": _g2("or"), "xor": _g2("xor")}
	var ten := {"not": _not_nand(), "and": _and_nand(), "or": _or_nand(), "xor": _xor_nand()}
	ctx.eq("成品门构型展开门数", _expanded(seven), 7)
	ctx.eq("全 NAND 构型展开门数", _expanded(ten), 10)
	var r7: Dictionary = Ch02ChecksScript.run("power", cfg, {"answers": answers, "graphs": seven})
	var r10: Dictionary = Ch02ChecksScript.run("power", cfg, {"answers": answers, "graphs": ten})
	var c7 := _case(r7["report"], "T2.5-3")
	var c10 := _case(r10["report"], "T2.5-3")
	ctx.check("7 门：T2.5-3 通过", bool(c7.get("ok", false)), str(c7.get("detail", "")))
	ctx.check("7 门：本节 required 全过", bool((r7["report"] as GateReport).all_required_passed()))
	ctx.check("10 门：T2.5-3 拒绝", not bool(c10.get("ok", false)), str(c10.get("detail", "")))
	ctx.check("10 门：拒绝码 E_AREA", GateResult.E_AREA in (r10["report"] as GateReport).failure_codes())
	ctx.check("10 门：理由写明总门数 10>8", str(c10.get("detail", "")).contains("总门数 10>8"),
		str(c10.get("detail", "")))
	ctx.check("10 门：拒绝同时报槽位 10>4 与总门数 10>8",
		str(c10.get("detail", "")).contains("槽位 10>4") and str(c10.get("detail", "")).contains("总门数 10>8"),
		str(c10.get("detail", "")))

	# 探针 A：4 个成品 XOR（顶层 4 槽、展开 16>8）。行为对 not/and/or 不成立，但预算行应报 16>8、槽位行不出现。
	var four_xor := {"not": _g2("xor"), "and": _g2("xor"), "or": _g2("xor"), "xor": _g2("xor")}
	ctx.eq("4×XOR 构型展开门数", _expanded(four_xor), 16)
	var r16: Dictionary = Ch02ChecksScript.run("power", cfg, {"answers": answers, "graphs": four_xor})
	var c16 := _case(r16["report"], "T2.5-3")
	ctx.check("4×XOR：槽位 4 不超，detail 无槽位行", not str(c16.get("detail", "")).contains("槽位"),
		str(c16.get("detail", "")))
	ctx.check("4×XOR：预算行报总门数 16>8", str(c16.get("detail", "")).contains("总门数 16>8"),
		str(c16.get("detail", "")))
	ctx.check("4×XOR：not/and/or 行为未过（✗）", str(c16.get("detail", "")).contains("✗"),
		str(c16.get("detail", "")))
	ctx.check("4×XOR：code=E_AREA（预算分支覆盖行为码）",
		GateResult.E_AREA in (r16["report"] as GateReport).failure_codes(),
		str((r16["report"] as GateReport).failure_codes()))

	# 探针 B：仅放宽本用例槽位到 10（测试副本，不改数据），10 门手搓行为全过 → 只剩预算一条理由。
	var wide: Dictionary = JSON.parse_string(JSON.stringify(cfg))
	for raw_case in (wide as Dictionary).get("gate_cases", []):
		if str((raw_case as Dictionary).get("id", "")) == "T2.5-3":
			(raw_case as Dictionary)["slots"] = 10
	var rw: Dictionary = Ch02ChecksScript.run("power", wide, {"answers": answers, "graphs": ten})
	var cw := _case(rw["report"], "T2.5-3")
	ctx.check("槽位放宽后：10 门仅因预算被拒（无槽位行）",
		not bool(cw.get("ok", false)) and str(cw.get("detail", "")).contains("总门数 10>8")
		and not str(cw.get("detail", "")).contains("槽位"), str(cw.get("detail", "")))
	ctx.check("槽位放宽后：code=E_AREA", GateResult.E_AREA in (rw["report"] as GateReport).failure_codes())

func _case(rep: GateReport, cid: String) -> Dictionary:
	for raw in rep.cases:
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

func _expanded(graphs: Dictionary) -> int:
	var total := 0
	for id in graphs:
		total += Ch02ChecksScript.expanded_gate_count(graphs[id])
	return total

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

func _not_nand() -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_gate("n1", LogicGates.Type.NAND)
	g.link("a", "n1", 0)
	g.link("a", "n1", 1)
	g.add_output("out")
	g.link("n1", "out", 0)
	return g

func _and_nand() -> CircuitGraph:
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

func _or_nand() -> CircuitGraph:
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
