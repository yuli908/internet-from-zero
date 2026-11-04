extends RefCounted

## M4-G1/G2/G10：宏单元目录、只读分页、展开/折叠边界与预算同源。
## 预算数字一律来自 `SimDelays`，测试不硬编码 50/80。

func run(ctx: TestContext) -> void:
	_test_cells(ctx)
	_test_pages(ctx)
	_test_expand_scale(ctx)
	_test_expand_ok(ctx)
	_test_fold_determinism(ctx)
	_test_expand_page(ctx)
	_test_budget(ctx)
	_test_alu_settle(ctx)

func _test_cells(ctx: TestContext) -> void:
	var cells := SimMacro.cells()
	ctx.eq("M4-G1 宏单元条数", cells.size(), 3)
	for k in ["decoder3", "comparator4", "alu4"]:
		ctx.check("M4-G1 含 %s" % k, cells.has(k))
	ctx.eq("M4-G1 decoder3 门数", int(SimMacro.meta("decoder3")["gate_count"]), 11)
	ctx.eq("M4-G1 comparator4 门数", int(SimMacro.meta("comparator4")["gate_count"]), 33)
	ctx.eq("M4-G1 alu4 门数", int(SimMacro.meta("alu4")["gate_count"]), 166)
	ctx.check("M4-G1 decoder3 可展开", bool(SimMacro.meta("decoder3")["expandable"]))
	ctx.check("M4-G1 comparator4 可展开", bool(SimMacro.meta("comparator4")["expandable"]))
	ctx.check("M4-G1 alu4 不可展开", not bool(SimMacro.meta("alu4")["expandable"]))
	ctx.check("M4-G1 未知宏单元 meta 为空", SimMacro.meta("nand64").is_empty())
	var copy := SimMacro.cells()
	copy["decoder3"]["gate_count"] = 0
	ctx.eq("M4-G1 cells() 是深拷贝（改动不回写）", int(SimMacro.meta("decoder3")["gate_count"]), 11)

func _test_pages(ctx: TestContext) -> void:
	var limit := SimDelays.gdscript_gate_limit()
	var alu_pages := SimMacro.pages("alu4")
	ctx.eq("M4-G1 alu4 页数", alu_pages.size(), 7)
	var total := 0
	var all_within := true
	for raw in alu_pages:
		var p: Dictionary = raw
		var g := int(p.get("gates", 0))
		total += g
		if g > limit:
			all_within = false
	ctx.eq("M4-G1 alu4 七页合计", total, 166)
	ctx.check("M4-G1 alu4 每页 ≤ gdscript_gate_limit()", all_within)
	ctx.eq("M4-G1 decoder3 单页门数", int(SimMacro.page("decoder3", "decoder3.all")["gates"]), 11)
	ctx.eq("M4-G1 comparator4 单页门数", int(SimMacro.page("comparator4", "comparator4.all")["gates"]), 33)
	var ids: Array = []
	for raw in alu_pages:
		ids.append(str((raw as Dictionary).get("id", "")))
	ctx.eq("M4-G1 alu4 页 id", ids,
		["alu.ctrl", "alu.adder", "alu.flags", "alu.logic", "alu.sel1", "alu.sel2", "alu.sel3"])
	var groups := {}
	for raw in alu_pages:
		groups[str((raw as Dictionary).get("group", ""))] = true
	ctx.check("M4-G1 三块语义分组齐备", groups.has("arith") and groups.has("logic") and groups.has("select"))
	ctx.check("M4-G1 未知页为空", SimMacro.page("alu4", "alu.nope").is_empty())

func _test_expand_scale(ctx: TestContext) -> void:
	var c := SimCircuit.new("macro_scale")
	var r := SimMacro.expand("alu4", c, "alu")
	ctx.check("M4-G2 alu4 整块展开被拒", not bool(r["ok"]))
	ctx.eq("M4-G2 alu4 错误码 IFZ_E_SCALE", str(r["error"]), "IFZ_E_SCALE")
	ctx.eq("M4-G2 被拒后不写入任何门", c.gate_count(), 0)
	var u := SimMacro.expand("not_a_macro", c, "x")
	ctx.check("M4-G2 未知宏单元被拒", not bool(u["ok"]))
	ctx.eq("M4-G2 未知宏单元错误码", str(u["error"]), "IFZ_E_UNKNOWN_MACRO")

func _test_expand_ok(ctx: TestContext) -> void:
	var c := SimCircuit.new("macro_expand")
	var d := SimMacro.expand("decoder3", c, "dec")
	ctx.check("M4-G2 decoder3 展开成功", bool(d["ok"]), str(d.get("error", "")))
	ctx.eq("M4-G2 decoder3 展开门数", int(d["gates"]), 11)
	ctx.eq("M4-G2 decoder3 电路门数", c.gate_count(), 11)
	ctx.eq("M4-G2 decoder3 输出端口数", (d["outputs"] as Array).size(), 8)
	ctx.eq("M4-G2 decoder3 输入端口数", (d["inputs"] as Array).size(), 4)

	var c2 := SimCircuit.new("macro_expand2")
	var cmp := SimMacro.expand("comparator4", c2, "cmp")
	ctx.check("M4-G2 comparator4 展开成功", bool(cmp["ok"]), str(cmp.get("error", "")))
	ctx.eq("M4-G2 comparator4 展开门数", c2.gate_count(), 33)
	ctx.eq("M4-G2 comparator4 输出端口数", (cmp["outputs"] as Array).size(), 3)
	ctx.check("M4-G2 展开均 ≤ 绝对上限",
		c.gate_count() <= SimDelays.gdscript_gate_hard_cap()
		and c2.gate_count() <= SimDelays.gdscript_gate_hard_cap())

func _test_fold_determinism(ctx: TestContext) -> void:
	## 展开 → 折叠 → 再展开（新电路同前缀）→ state_digest 相同。
	var a := SimCircuit.new("macro_fold_a")
	var exp := SimMacro.expand("decoder3", a, "m")
	ctx.check("M4-G2 首次展开成功", bool(exp["ok"]))
	var digest_a := a.state_digest()
	var f := SimMacro.fold("decoder3", "m")
	ctx.check("M4-G2 折叠返回端口摘要", bool(f["ok"]))
	ctx.check("M4-G2 折叠摘要非空", not str(f["digest"]).is_empty())
	ctx.eq("M4-G2 折叠端口与展开一致", (f["ports"] as Dictionary)["outputs"], exp["outputs"])
	ctx.eq("M4-G2 折叠输入端口与展开一致", (f["ports"] as Dictionary)["inputs"], exp["inputs"])
	var b := SimCircuit.new("macro_fold_b")
	var exp2 := SimMacro.expand("decoder3", b, "m")
	ctx.check("M4-G2 再展开成功", bool(exp2["ok"]))
	ctx.eq("M4-G2 展开→折叠→再展开 state_digest 相同", digest_a, b.state_digest())
	ctx.eq("M4-G2 再展开门数相同", b.gate_count(), a.gate_count())
	ctx.eq("M4-G2 折叠可重复（摘要稳定）", str(SimMacro.fold("decoder3", "m")["digest"]), str(f["digest"]))
	var u := SimMacro.fold("nope", "x")
	ctx.check("M4-G2 未知宏单元折叠被拒", not bool(u["ok"]))
	var alu_fold := SimMacro.fold("alu4", "alu")
	ctx.check("M4-G2 alu4 折叠返回端口（只读模型）", bool(alu_fold["ok"]))
	ctx.eq("M4-G2 alu4 输出端口数", (alu_fold["ports"] as Dictionary)["outputs"].size(), 8)

func _test_expand_page(ctx: TestContext) -> void:
	var c := SimCircuit.new("macro_page")
	var r := SimMacro.expand_page("alu4", "alu.ctrl", c, "alu")
	ctx.check("M4-G1 alu4 只读页可用", bool(r["ok"]), str(r.get("error", "")))
	ctx.check("M4-G1 alu4 只读页不建门", not bool(r["built"]))
	ctx.check("M4-G1 alu4 只读页标记 read_only", bool(r.get("read_only", false)))
	ctx.eq("M4-G1 alu4 ctrl 页门数", int(r["gates"]), 5)
	ctx.eq("M4-G1 只读页不改变电路门数", c.gate_count(), 0)
	var bad := SimMacro.expand_page("alu4", "alu.nope", c, "alu")
	ctx.check("M4-G1 未知页被拒", not bool(bad["ok"]))
	ctx.eq("M4-G1 未知页错误码", str(bad["error"]), "IFZ_E_UNKNOWN_PAGE")

	var c2 := SimCircuit.new("macro_page_dec")
	var d := SimMacro.expand_page("decoder3", "decoder3.all", c2, "dec")
	ctx.check("M4-G1 decoder3 单页展开成功", bool(d["ok"]))
	ctx.check("M4-G1 可展开宏单元 built=true", bool(d["built"]))
	ctx.eq("M4-G1 decoder3 单页建门数", c2.gate_count(), 11)
	var limit := SimDelays.gdscript_gate_limit()
	var over := 0
	for raw in SimMacro.pages("alu4"):
		if int((raw as Dictionary).get("gates", 0)) > limit:
			over += 1
	ctx.eq("M4-G10 无超限页", over, 0)

func _test_budget(ctx: TestContext) -> void:
	## 预算同源：50 提示、80 拒绝都由 SimDelays 决定，不写死数字。
	var limit := SimDelays.gdscript_gate_limit()
	var hard := SimDelays.gdscript_gate_hard_cap()
	var c := SimCircuit.new("macro_budget")
	for i in limit - 5:
		c.add_gate("pad%d" % i, "buf", ["pad_in%d" % i])
	ctx.eq("M4-G10 预置门数", c.gate_count(), limit - 5)
	var r := SimMacro.expand("decoder3", c, "dec")
	ctx.check("M4-G10 50 < 合计 ≤ 80 允许构建", bool(r["ok"]), str(r.get("error", "")))
	ctx.check("M4-G10 超默认上限给出 scale_warn", bool(r.get("scale_warn", false)))
	ctx.eq("M4-G10 合计 = 预置 + 11", c.gate_count(), limit + 6)
	ctx.check("M4-G10 合计仍 ≤ 绝对上限", c.gate_count() <= hard)

	var c2 := SimCircuit.new("macro_budget_hard")
	for i in hard - 10:
		c2.add_gate("pad%d" % i, "buf", ["pad_in%d" % i])
	var before := c2.gate_count()
	var r2 := SimMacro.expand("decoder3", c2, "dec")
	ctx.check("M4-G10 超绝对上限被拒", not bool(r2["ok"]))
	ctx.eq("M4-G10 超限错误码", str(r2["error"]), "IFZ_E_SCALE")
	ctx.eq("M4-G10 超限时不写入门（禁止只画一部分）", c2.gate_count(), before)

func _test_alu_settle(ctx: TestContext) -> void:
	## R6：alu4 的 t_settle 按结构推导锁定（无门级网表，不能实测）。
	var d_not := SimDelays.delay("not")
	var d_and := SimDelays.delay("and")
	var d_or := SimDelays.delay("or")
	var expected := (d_not + d_and) \
		+ (d_not + d_and + d_or) \
		+ SimModule.declared_settle("ripple", 4) \
		+ 2 * (d_and + d_or) \
		+ (d_not + d_and + d_or + d_and)
	ctx.eq("M4-G1 alu4 t_settle = 结构推导", int(SimMacro.meta("alu4")["t_settle"]), expected)
	ctx.eq("M4-G1 decoder3 t_settle", int(SimMacro.meta("decoder3")["t_settle"]),
		SimModule.declared_settle("decoder3", 3))
	ctx.eq("M4-G1 comparator4 t_settle", int(SimMacro.meta("comparator4")["t_settle"]),
		SimModule.declared_settle("comparator4", 4))
	ctx.eq("M4-G1 alu4 t_settle 与宽度的关系（4 位）", SimMacro.alu4_settle(4), expected)
