extends RefCounted

## 第二章分母口径的 UI 接线验收（与数据侧 test_denominator.gd 分离）。
## 核心已定稿 `Ch02Checks.deferred_gates()`，但接口没人调就等于没修；
## 这里既验数值，也验「UI 文件确实走了这条口径」，能抓到接线被摘掉的回归。

const LabBaseGd = preload("res://src/ui/screens/lab_base.gd")
const Ch02ChecksScript = preload("res://src/core/ch02_checks.gd")

func run(ctx: TestContext) -> void:
	var labs: Dictionary = TestUtil.read_json("res://data/labs/ch02_labs.json").get("labs", {})
	var chapter: Dictionary = TestUtil.read_json("res://data/chapters/ch02_levels.json")
	var metas := {}
	for raw in (chapter.get("labs", []) as Array):
		if raw is Dictionary:
			var m: Dictionary = raw
			metas[str(m.get("id", ""))] = m
	var inverter: Dictionary = labs.get("inverter", {})
	var replace: Dictionary = labs.get("replace", {})
	var iv_meta: Dictionary = metas.get("inverter", {})
	var rp_meta: Dictionary = metas.get("replace", {})
	ctx.check("ch02 inverter 可读", not inverter.is_empty())
	ctx.check("ch02 replace 可读", not replace.is_empty())

	# ---- 分母：inverter 4 条里 T2.2-3 延后，进分母 3 ----
	var d := LabBaseGd.gate_denominator(inverter)
	ctx.eq("UI 分母：inverter 总 4", int(d["total"]), 4)
	ctx.eq("UI 分母：inverter 计 3", int(d["counted"]), 3)
	ctx.eq("UI 分母：inverter 延后 1", int(d["deferred"]), 1)
	ctx.eq("UI 分母：inverter 延后 id", d["ids"], ["T2.2-3"])

	# ---- 抬头行：报 3 项验收，不再报 4 ----
	var code := LabBaseGd.header_code_text(inverter, iv_meta, 2)
	ctx.eq("抬头计 3 项验收", LabBaseGd.gate_count_text(inverter, iv_meta.get("gate_ids", [])), "3 项验收")
	ctx.check("抬头行写 3 项验收、不写 4 项", code.contains("3 项验收") and not code.contains("4 项验收"), code)
	ctx.check("抬头行保留编号与副标题",
		code.begins_with("T2.2") and code.contains(str(iv_meta.get("subtitle", ""))), code)

	# ---- 结算页：3/3，不是 3/4；延后只留一行 ----
	var rep: GateReport = _not_report(inverter)
	var view := LabBaseGd.settlement_view(inverter, rep, false, {})
	ctx.eq("结算显示 3/3（不是 3/4）", str(view["title"]), "验收 · 通过 3/3")
	ctx.check("结算判绿", bool(view["ok"]))
	ctx.eq("结算延后 1", int(view["deferred"]), 1)
	ctx.eq("结算只留一行「本节 1 项延后」", str(view["detail"]), "本节 1 项延后")
	ctx.check("失败明细不含延后项", (view["failures"] as Array).is_empty(), str(view["failures"]))

	# ---- 延后项即使被当成通过，也不进分子/分母（不靠人记） ----
	var all_ids := ["T2.2-1", "T2.2-2", "T2.2-3", "T2.2-4"]
	var sc := LabBaseGd.settlement_counts(inverter, all_ids)
	ctx.eq("延后项不进分子", int(sc["ok"]), 3)
	ctx.eq("延后项不进分母", int(sc["total"]), 3)

	# ---- replace：整节 deferred，不进分母、不进进度条 ----
	var rd := LabBaseGd.gate_denominator(replace)
	ctx.eq("replace 总 4", int(rd["total"]), 4)
	ctx.eq("replace 进分母 0", int(rd["counted"]), 0)
	ctx.check("replace 整节延后标记", bool(rd["section_deferred"]))
	ctx.eq("replace 抬头不报计数", LabBaseGd.gate_count_text(replace, rp_meta.get("gate_ids", [])), "")
	var rcode := LabBaseGd.header_code_text(replace, rp_meta, 2)
	ctx.check("replace 抬头没有「0 项验收」", not rcode.contains("0 项验收"), rcode)
	var rview := LabBaseGd.settlement_view(replace, _pending_report(replace), false, {})
	ctx.eq("replace 结算不出分数", str(rview["title"]), "验收")
	ctx.eq("replace 结算总数 0", int(LabBaseGd.settlement_counts(replace, [])["total"]), 0)
	ctx.eq("replace 只留一行「本节 4 项延后」", str(rview["detail"]), "本节 4 项延后")
	ctx.eq("replace 延后只出现一次", str(rview["detail"]).count("延后"), 1)

	# ---- ready 后自动回到分母 4（同一份数据，只在内存里改） ----
	var ready: Dictionary = inverter.duplicate(true)
	for raw in (ready.get("gate_cases", []) as Array):
		if str((raw as Dictionary).get("id", "")) == "T2.2-3":
			(raw as Dictionary)["content_status"] = "ready"
	var rdy := LabBaseGd.gate_denominator(ready)
	ctx.eq("ready 后分母 4", int(rdy["counted"]), 4)
	ctx.eq("ready 后延后 0", int(rdy["deferred"]), 0)
	ctx.eq("ready 后抬头 4 项验收", LabBaseGd.gate_count_text(ready, iv_meta.get("gate_ids", [])), "4 项验收")
	var rv := LabBaseGd.settlement_view(ready, rep, false, {})
	ctx.eq("ready 后结算回到分母 4", str(rv["title"]), "验收 · 通过 3/4")
	ctx.check("ready 后 T2.2-3 不再是延后", not str(rv["detail"]).contains("延后"), str(rv["detail"]))

	# ---- 没有延后项的三节不受影响 ----
	for id in ["transistor", "nand", "power"]:
		ctx.eq("%s 分母仍 4" % id, int(LabBaseGd.gate_denominator(labs.get(id, {}))["counted"]), 4)

	# ---- 接线回归：UI 文件必须真的调接口，不能只有测试在调 ----
	var src := FileAccess.get_file_as_string("res://src/ui/screens/lab_base.gd")
	ctx.check("UI 层调用 deferred_gates", src.contains("Ch02Checks.deferred_gates("))
	ctx.check("抬头走 header_code_text", _body(src, "func _code_text").contains("header_code_text("))
	ctx.check("结算走 settlement_view", _body(src, "func show_report").contains("settlement_view("))
	ctx.check("整节延后不许凭空过关", _body(src, "func pass_report").contains("section_deferred"))

func _body(src: String, head: String) -> String:
	## 取一个函数体：从签名起到下一个顶层 func 之前，用于断言「这条口径确实在这个函数里」。
	var i := src.find(head)
	if i < 0:
		return ""
	var j := src.find("\nfunc ", i + head.length())
	return src.substr(i) if j < 0 else src.substr(i, j - i)

func _not_report(cfg: Dictionary) -> GateReport:
	var g := CircuitGraph.new()
	g.add_input("a")
	g.add_gate("g1", LogicGates.Type.NOT)
	g.link("a", "g1", 0)
	g.add_output("out")
	g.link("g1", "out", 0)
	return Ch02ChecksScript.run("inverter", cfg, {"graph": g})["report"]

func _pending_report(cfg: Dictionary) -> GateReport:
	return Ch02ChecksScript.run("replace", cfg, {})["report"]
