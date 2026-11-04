extends RefCounted

## 经济：买、卖、折扣、配方消耗/保留、技能锁。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 42
const EXPECT_GROUPS := {
	"catalog_prices": 4, "buy": 3, "buy_rejected": 3, "discount": 3,
	"craft": 4, "craft_rejected": 2, "craft_skill_lock": 3, "craft_recipe": 4,
	"sell": 5, "bound_sell": 5, "bound_material": 1, "plain_sell": 3, "mixed_bag": 2,
}
const GROUP_DESCRIPTIONS := {
	"catalog_prices": "目录条目总数、scrap 不可买、M02 买价、gate_xor 旧卖价",
	"buy": "买 1 个 M02 成功并扣金、加库存",
	"buy_rejected": "金币不足时购买失败且金币与库存不变",
	"discount": "技能折扣后单价 54、实扣 54",
	"craft": "配方合成成功、扣金币、消耗输入、产出成品",
	"craft_rejected": "材料不足再次合成失败且金币不变",
	"craft_skill_lock": "缺技能时配方被锁且提示技能名、输入不扣",
	"craft_recipe": "解锁后 demorgan 合成成功并消耗两路输入",
	"sell": "卖 M08 成功、金币与库存变化、gain 回报、空库存再卖失败",
	"bound_sell": "绑定件 G01 拒卖：明确原因、留包、不加金、gain 0",
	"bound_material": "标 bound_first 的材料 M01 同样拒卖且留包",
	"plain_sell": "非绑定件正常出售并入账、扣件",
	"mixed_bag": "混合背包只拒绑定件，非绑定件照常可卖",
}

func run(ctx: TestContext) -> void:
	var db: Node = TestUtil.data_db()
	var cat: Catalog = db.catalog
	var nodes: Dictionary = TestUtil.skill_nodes()

	ctx.begin_group("catalog_prices")
	ctx.eq("catalog items", cat.items.size(), 86)
	ctx.check("scrap not buyable", cat.buy_price("scrap") == -1)
	ctx.check("M02 price", cat.buy_price("M02") == 6)
	ctx.check("gate_xor legacy sell", cat.sell_price("gate_xor") == 4)

	ctx.begin_group("buy")
	var st := PlayerState.new()
	st.gold = 20
	var r := EconomyCore.buy(st, cat, nodes, "M02", 1)
	ctx.check("buy M02 ok", bool(r.get("ok", false)), str(r.get("error", "")))
	ctx.eq("buy M02 gold", st.gold, 14)
	ctx.eq("buy M02 count", st.item_count("M02"), 1)

	ctx.begin_group("buy_rejected")
	st.gold = 14
	var r2 := EconomyCore.buy(st, cat, nodes, "gate_xor", 3)
	ctx.check("buy 3 xor fails", not bool(r2.get("ok", false)))
	ctx.eq("failed buy leaves gold", st.gold, 14)
	ctx.eq("failed buy leaves inventory", st.item_count("gate_xor"), 0)

	ctx.begin_group("discount")
	var st2 := PlayerState.new()
	st2.gold = 100
	st2.grant_knowledge("bargain")
	var r3 := EconomyCore.buy(st2, cat, nodes, "gate_xor", 1)
	ctx.check("discount buy ok", bool(r3.get("ok", false)))
	ctx.eq("discount cost", int(r3.get("cost", -1)), 54)
	ctx.eq("discount price", st2.gold, 46)

	ctx.begin_group("craft")
	var st3 := PlayerState.new()
	st3.gold = 10
	st3.add_item("M00", 1)
	var c1 := EconomyCore.craft(st3, cat, "craft_M02")
	ctx.check("craft M02 ok", bool(c1.get("ok", false)), str(c1.get("error", "")))
	ctx.eq("craft cost", st3.gold, 6)
	ctx.eq("craft consumes M00", st3.item_count("M00"), 0)
	ctx.eq("craft produces M02", st3.item_count("M02"), 1)
	ctx.begin_group("craft_rejected")
	var c2 := EconomyCore.craft(st3, cat, "craft_M02")
	ctx.check("craft again fails", not bool(c2.get("ok", false)))
	ctx.eq("failed craft leaves gold", st3.gold, 6)

	var st4 := PlayerState.new()
	st4.gold = 10
	st4.add_item("gate_or", 1)
	st4.add_item("gate_not", 1)
	ctx.begin_group("craft_skill_lock")
	var locked := EconomyCore.craft(st4, cat, "demorgan_and")
	ctx.check("demorgan locked", not bool(locked.get("ok", false)))
	ctx.check("lock says skill", str(locked.get("error", "")).contains("demorgan"), str(locked.get("error", "")))
	ctx.eq("locked craft keeps or", st4.item_count("gate_or"), 1)
	st4.grant_knowledge("demorgan")
	ctx.begin_group("craft_recipe")
	var made := EconomyCore.craft(st4, cat, "demorgan_and")
	ctx.check("demorgan craft ok", bool(made.get("ok", false)), str(made.get("error", "")))
	ctx.eq("demorgan consumes or", st4.item_count("gate_or"), 0)
	ctx.eq("demorgan consumes not", st4.item_count("gate_not"), 0)
	ctx.eq("demorgan produces and", st4.item_count("gate_and"), 1)

	var st5 := PlayerState.new()
	st5.gold = 0
	st5.add_item("M08", 1)
	ctx.begin_group("sell")
	var sale := EconomyCore.sell(st5, cat, "M08", 1)
	ctx.check("sell M08 ok", bool(sale.get("ok", false)))
	ctx.eq("sell M08 gold", st5.gold, 5)
	ctx.eq("sell M08 count", st5.item_count("M08"), 0)
	ctx.eq("total earned", int(sale.get("gain", 0)), 5)
	ctx.check("cannot sell nothing", not bool(EconomyCore.sell(st5, cat, "M08", 1).get("ok", false)))

	# 绑定件（bound_first）不可出售：拒绝要明确、不扣件、不加金币
	var st6 := PlayerState.new()
	st6.gold = 0
	st6.add_item("G01", 1)
	ctx.begin_group("bound_sell")
	var bound_sale := EconomyCore.sell(st6, cat, "G01", 1)
	ctx.check("绑定件出售被拒", not bool(bound_sale.get("ok", false)))
	ctx.check("绑定件拒绝原因明确", str(bound_sale.get("error", "")).contains("绑定"))
	ctx.eq("绑定件仍在背包", st6.item_count("G01"), 1)
	ctx.eq("绑定件出售不加金币", st6.gold, 0)
	ctx.eq("绑定件出售 gain 0", int(bound_sale.get("gain", -1)), 0)
	# M01 虽是可交易材料，但标了 bound_first，同样按绑定件拒卖
	st6.add_item("M01", 1)
	ctx.begin_group("bound_material")
	ctx.check("M01 绑定件同样被拒且留包",
		not bool(EconomyCore.sell(st6, cat, "M01", 1).get("ok", true)) and st6.item_count("M01") == 1)
	ctx.begin_group("plain_sell")
	# 非绑定件照常出售
	st6.add_item("M08", 2)
	var plain_sale := EconomyCore.sell(st6, cat, "M08", 1)
	ctx.check("非绑定件可正常出售", bool(plain_sale.get("ok", false)))
	ctx.eq("非绑定件出售入账", st6.gold, 5)
	ctx.eq("非绑定件扣件", st6.item_count("M08"), 1)
	# 混合背包：只拒绑定件，其余照常
	st6.add_item("G02", 1)
	ctx.begin_group("mixed_bag")
	ctx.check("混合背包：绑定件仍被拒且留包",
		not bool(EconomyCore.sell(st6, cat, "G02", 1).get("ok", true)) and st6.item_count("G02") == 1)
	ctx.check("混合背包：非绑定件仍可卖",
		bool(EconomyCore.sell(st6, cat, "M08", 1).get("ok", false)) and st6.gold == 10)
