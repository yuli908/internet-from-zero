extends RefCounted

## 经济：买、卖、折扣、配方消耗/保留、技能锁。

func run(ctx: TestContext) -> void:
	var db: Node = TestUtil.data_db()
	var cat: Catalog = db.catalog
	var nodes: Dictionary = TestUtil.skill_nodes()

	ctx.eq("catalog items", cat.items.size(), 85)
	ctx.check("scrap currency", cat.buy_price("scrap") == -1)
	ctx.check("M02 price", cat.buy_price("M02") == 6)
	ctx.check("gate_xor legacy sell", cat.sell_price("gate_xor") == 4)

	var st := PlayerState.new()
	st.scrap = 20
	var r := EconomyCore.buy(st, cat, nodes, "M02", 1)
	ctx.check("buy M02 ok", bool(r.get("ok", false)), str(r.get("error", "")))
	ctx.eq("buy M02 scrap", st.scrap, 14)
	ctx.eq("buy M02 count", st.item_count("M02"), 1)

	st.scrap = 14
	var r2 := EconomyCore.buy(st, cat, nodes, "gate_xor", 3)
	ctx.check("buy 3 xor fails", not bool(r2.get("ok", false)))
	ctx.eq("failed buy leaves scrap", st.scrap, 14)
	ctx.eq("failed buy leaves inventory", st.item_count("gate_xor"), 0)

	var st2 := PlayerState.new()
	st2.scrap = 100
	st2.grant_knowledge("bargain")
	var r3 := EconomyCore.buy(st2, cat, nodes, "gate_xor", 1)
	ctx.check("discount buy ok", bool(r3.get("ok", false)))
	ctx.eq("discount cost", int(r3.get("cost", -1)), 54)
	ctx.eq("discount price", st2.scrap, 46)

	var st3 := PlayerState.new()
	st3.scrap = 10
	st3.add_item("M00", 1)
	var c1 := EconomyCore.craft(st3, cat, "craft_M02")
	ctx.check("craft M02 ok", bool(c1.get("ok", false)), str(c1.get("error", "")))
	ctx.eq("craft cost", st3.scrap, 6)
	ctx.eq("craft consumes M00", st3.item_count("M00"), 0)
	ctx.eq("craft produces M02", st3.item_count("M02"), 1)
	var c2 := EconomyCore.craft(st3, cat, "craft_M02")
	ctx.check("craft again fails", not bool(c2.get("ok", false)))
	ctx.eq("failed craft leaves scrap", st3.scrap, 6)

	var st4 := PlayerState.new()
	st4.scrap = 10
	st4.add_item("gate_or", 1)
	st4.add_item("gate_not", 1)
	var locked := EconomyCore.craft(st4, cat, "demorgan_and")
	ctx.check("demorgan locked", not bool(locked.get("ok", false)))
	ctx.check("lock says skill", str(locked.get("error", "")).contains("demorgan"), str(locked.get("error", "")))
	ctx.eq("locked craft keeps or", st4.item_count("gate_or"), 1)
	st4.grant_knowledge("demorgan")
	var made := EconomyCore.craft(st4, cat, "demorgan_and")
	ctx.check("demorgan craft ok", bool(made.get("ok", false)), str(made.get("error", "")))
	ctx.eq("demorgan consumes or", st4.item_count("gate_or"), 0)
	ctx.eq("demorgan consumes not", st4.item_count("gate_not"), 0)
	ctx.eq("demorgan produces and", st4.item_count("gate_and"), 1)

	var st5 := PlayerState.new()
	st5.scrap = 0
	st5.add_item("M01", 1)
	var sale := EconomyCore.sell(st5, cat, "M01", 1)
	ctx.check("sell M01 ok", bool(sale.get("ok", false)))
	ctx.eq("sell M01 scrap", st5.scrap, 4)
	ctx.eq("sell M01 count", st5.item_count("M01"), 0)
	ctx.eq("total earned", int(sale.get("gain", 0)), 4)
	ctx.check("cannot sell nothing", not bool(EconomyCore.sell(st5, cat, "M01", 1).get("ok", false)))
