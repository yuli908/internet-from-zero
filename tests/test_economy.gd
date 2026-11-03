extends RefCounted

func run(ctx: TestContext) -> void:
	var cat := TestUtil.catalog()
	var nodes := TestUtil.skill_nodes()
	ctx.eq("catalog items", cat.items.size(), 8)
	ctx.eq("wire buy price", cat.buy_price("wire"), 2)
	ctx.eq("scrap not for sale", cat.buy_price("scrap"), -1)
	ctx.eq("gate_xor sell price", cat.sell_price("gate_xor"), 4)

	var st := PlayerState.new()
	st.scrap = 20
	var r := EconomyCore.buy(st, cat, nodes, "wire", 1)
	ctx.check("buy wire ok", bool(r["ok"]), str(r["error"]))
	ctx.eq("buy cost", int(r["cost"]), 2)
	ctx.eq("scrap after buy", st.scrap, 18)
	ctx.eq("wire count", st.item_count("wire"), 1)

	var r2 := EconomyCore.buy(st, cat, nodes, "gate_xor", 3)
	ctx.check("insufficient rejected", not bool(r2["ok"]))
	ctx.eq("scrap unchanged", st.scrap, 18)
	ctx.eq("xor not added", st.item_count("gate_xor"), 0)

	var cheap := PlayerState.new()
	cheap.scrap = 100
	cheap.grant_knowledge("bargain")
	var r3 := EconomyCore.buy(cheap, cat, nodes, "gate_xor", 1)
	ctx.eq("discounted price", int(r3["cost"]), 7)
	ctx.eq("scrap after discount", cheap.scrap, 93)

	var crafter := PlayerState.new()
	crafter.scrap = 10
	var c1 := EconomyCore.craft(crafter, cat, "bundle_wire")
	ctx.check("craft wire ok", bool(c1["ok"]), str(c1["error"]))
	ctx.eq("craft scrap left", crafter.scrap, 7)
	ctx.eq("craft wire gained", crafter.item_count("wire"), 3)

	var c2 := EconomyCore.craft(crafter, cat, "make_switch")
	ctx.check("craft switch ok", bool(c2["ok"]), str(c2["error"]))
	ctx.eq("wire after switch", crafter.item_count("wire"), 1)
	ctx.eq("switch after craft", crafter.item_count("switch"), 1)
	ctx.eq("scrap after switch", crafter.scrap, 6)

	var c3 := EconomyCore.craft(crafter, cat, "bundle_wire", 10)
	ctx.check("craft too many rejected", not bool(c3["ok"]))
	ctx.eq("scrap untouched on failure", crafter.scrap, 6)

	var locked := EconomyCore.can_craft(crafter, cat, "demorgan_and")
	ctx.check("recipe locked without skill", not bool(locked["ok"]))
	ctx.check("lock message", str(locked["error"]).contains("未解锁"))

	crafter.grant_knowledge("demorgan")
	crafter.add_item("gate_or", 1)
	crafter.add_item("gate_not", 1)
	var c4 := EconomyCore.craft(crafter, cat, "demorgan_and")
	ctx.check("demorgan craft ok", bool(c4["ok"]), str(c4["error"]))
	ctx.eq("and gate made", crafter.item_count("gate_and"), 1)
	ctx.eq("or consumed", crafter.item_count("gate_or"), 0)

	var s := EconomyCore.sell(crafter, cat, "wire", 1)
	ctx.check("sell wire ok", bool(s["ok"]))
	ctx.eq("scrap from sell", crafter.scrap, 7)
	ctx.check("sell currency rejected", not bool(EconomyCore.sell(crafter, cat, "scrap", 1)["ok"]))
	ctx.check("negative qty rejected", not bool(EconomyCore.buy(crafter, cat, nodes, "wire", -1)["ok"]))
