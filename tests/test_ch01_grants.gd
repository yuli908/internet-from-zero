extends RefCounted

## M5 · CH01 教学奖励：grants 首次发放 / 二次不发 / 旧档补发一次 / bound_first 幂等。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 43
const EXPECT_GROUPS := {
	"data_grants": 5, "item_bound_first": 4, "first_grant": 6, "duplicate_blocked": 4,
	"half_adder_grant": 2, "half_adder_duplicate": 2, "replay_path": 6,
	"legacy_backfill": 8, "backfill_idempotent": 4, "no_completion_no_backfill": 2,
}
const GROUP_DESCRIPTIONS := {
	"data_grants": "奖励只写在 labs 段且 items/bound_first 与数据一致、章节内联不重复",
	"item_bound_first": "G01–G04 四件物品各自 bound_first 为真（防转手套利）",
	"first_grant": "首次通关发放：ok、非重复、三件入库 1、写 granted 标记",
	"duplicate_blocked": "同一 lab 二次调用 already=true 且不重复发",
	"half_adder_grant": "半加器首次发放 ok 且 G04 入库 1",
	"half_adder_duplicate": "半加器二次调用 already 且 G04 仍为 1",
	"replay_path": "ChapterRuntime.grants 回收路径按 lab 拦重复刷关，不同 lab 各发各的",
	"legacy_backfill": "旧档已通关未领奖：补发 2 节、四件入库 1、总发放 4 项",
	"backfill_idempotent": "连续补发只发一次：二/三次无新增且数量不变",
	"no_completion_no_backfill": "未通关的 lab 不补发",
}

func run(ctx: TestContext) -> void:
	var db := TestUtil.data_db()
	var cat: Catalog = db.catalog
	var ch: ChapterRuntime = db.chapter

	# ---- 数据落地：奖励只写在 labs 段，章节内联不重复 ----
	var gate_g: Dictionary = ch.grants("gate", db.labs_doc)
	var add_g: Dictionary = ch.grants("half_adder", db.labs_doc)
	ctx.begin_group("data_grants")
	ctx.eq("gate 段 grants.items", gate_g.get("items", {}), {"G01": 1.0, "G02": 1.0, "G03": 1.0})
	ctx.check("gate 段 bound_first", bool(gate_g.get("bound_first", false)))
	ctx.eq("half_adder 段 grants.items", add_g.get("items", {}), {"G04": 1.0})
	ctx.check("half_adder 段 bound_first", bool(add_g.get("bound_first", false)))
	ctx.check("章节内联不重复奖励", not db.chapter.lab("gate").has("grants"))

	# ---- 物品侧 bound_first：首件绑定，防转手套利 ----
	for item_id in ["G01", "G02", "G03", "G04"]:
		var it: Dictionary = cat.item(str(item_id))
		ctx.begin_group("item_bound_first")
		ctx.check("%s 物品 bound_first" % item_id, bool(it.get("bound_first", false)))

	# ---- 正式路径：首次发放 / 二次不发 ----
	var p := PlayerState.new(11)
	var r1 := p.grant_items("gate", gate_g, cat)
	ctx.begin_group("first_grant")
	ctx.check("首次：ok", bool(r1.get("ok", false)), str(r1.get("error", "")))
	ctx.check("首次：非重复", not bool(r1.get("already", true)))
	ctx.eq("首次：G01 入库 1", p.item_count("G01"), 1)
	ctx.eq("首次：G02 入库 1", p.item_count("G02"), 1)
	ctx.eq("首次：G03 入库 1", p.item_count("G03"), 1)
	ctx.check("首次：写 granted 标记", p.has_flag("granted:gate"))

	var r2 := p.grant_items("gate", gate_g, cat)
	ctx.begin_group("duplicate_blocked")
	ctx.check("二次：already=true", bool(r2.get("already", false)))
	ctx.eq("二次：G01 不重复发", p.item_count("G01"), 1)
	ctx.eq("二次：G02 不重复发", p.item_count("G02"), 1)
	ctx.eq("二次：G03 不重复发", p.item_count("G03"), 1)

	var r3 := p.grant_items("half_adder", add_g, cat)
	ctx.begin_group("half_adder_grant")
	ctx.check("半加器：首次 ok", bool(r3.get("ok", false)))
	ctx.eq("半加器：G04 入库 1", p.item_count("G04"), 1)
	var r4 := p.grant_items("half_adder", add_g, cat)
	ctx.begin_group("half_adder_duplicate")
	ctx.check("半加器：二次 already", bool(r4.get("already", false)))
	ctx.eq("半加器：G04 仍为 1", p.item_count("G04"), 1)

	# ---- bound_first 真读：ChapterRuntime.grants 回收路径拦重复刷关 ----
	var rep := PlayerState.new(14)
	var g1: Dictionary = ch.grants("gate", db.labs_doc, rep)
	ctx.begin_group("replay_path")
	ctx.check("回收路径：首次有奖励", not g1.is_empty())
	rep.grant_items("gate", g1, cat)
	var g2: Dictionary = ch.grants("gate", db.labs_doc, rep)
	ctx.eq("同 lab 连跑两次：第二次不再发放", g2, {})
	rep.grant_items("gate", g2, cat)
	ctx.eq("同 lab 连跑两次：G01 仍为 1", rep.item_count("G01"), 1)
	var other: Dictionary = ch.grants("half_adder", db.labs_doc, rep)
	ctx.check("不同 lab 各发各的", not other.is_empty())
	rep.grant_items("half_adder", other, cat)
	ctx.eq("不同 lab：G04 入库 1", rep.item_count("G04"), 1)
	ctx.check("不同 lab：half_adder 也写标记", rep.has_flag("granted:half_adder"))

	# ---- 旧档补发：已通关但从未领奖，读档补一次 ----
	var legacy := PlayerState.new(12)
	legacy.mark_lab_completed("gate")
	legacy.mark_lab_completed("half_adder")
	legacy.complete_objective("obj_gate")
	legacy.complete_objective("obj_half_adder")
	ctx.begin_group("legacy_backfill")
	ctx.check("旧档：补发前无 G01", legacy.item_count("G01") == 0)
	var bf1 := legacy.backfill_lab_grants(ch, db.labs_doc, cat)
	ctx.check("旧档：补发 ok", bool(bf1.get("ok", false)), str(bf1.get("error", "")))
	ctx.eq("旧档：补发 2 节", (bf1.get("labs", []) as Array).size(), 2)
	ctx.eq("旧档：G01 补发 1", legacy.item_count("G01"), 1)
	ctx.eq("旧档：G02 补发 1", legacy.item_count("G02"), 1)
	ctx.eq("旧档：G03 补发 1", legacy.item_count("G03"), 1)
	ctx.eq("旧档：G04 补发 1", legacy.item_count("G04"), 1)
	ctx.eq("旧档：补发总额 2 节", (bf1.get("granted", {}) as Dictionary).size(), 4)

	# ---- bound_first 幂等：连续补发只发一次 ----
	var bf2 := legacy.backfill_lab_grants(ch, db.labs_doc, cat)
	ctx.begin_group("backfill_idempotent")
	ctx.check("二次补发：无新增", (bf2.get("granted", {}) as Dictionary).is_empty())
	ctx.eq("二次补发：G01 仍为 1", legacy.item_count("G01"), 1)
	ctx.eq("二次补发：G04 仍为 1", legacy.item_count("G04"), 1)
	var bf3 := legacy.backfill_lab_grants(ch, db.labs_doc, cat)
	ctx.check("三次补发：无新增", (bf3.get("granted", {}) as Dictionary).is_empty())

	# ---- 未通关的 lab 不补发 ----
	var fresh := PlayerState.new(13)
	var bf0 := fresh.backfill_lab_grants(ch, db.labs_doc, cat)
	ctx.begin_group("no_completion_no_backfill")
	ctx.check("未通关：不补发", (bf0.get("granted", {}) as Dictionary).is_empty())
	ctx.eq("未通关：G01 仍为 0", fresh.item_count("G01"), 0)
