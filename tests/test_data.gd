extends RefCounted

## 数据完整性：物品、价格、配方、双树、章节、实验配置、gate 用例。

func run(ctx: TestContext) -> void:
	var db: Node = TestUtil.data_db()
	var cat: Catalog = db.catalog
	var kg: KnowledgeGraph = db.skill_graph
	var ch: ChapterRuntime = db.chapter

	ctx.eq("manifest files", int(db.manifest.get("files", []).size()), 8)
	ctx.eq("manifest version", int(db.manifest.get("version", 0)), 2)

	ctx.eq("items total", cat.items.size(), 86)
	var doc_items := 0
	var legacy := 0
	for raw_id in cat.item_order:
		var it: Dictionary = cat.item(str(raw_id))
		if str(raw_id) == "scrap" or str(raw_id) == "gold":
			continue
		if bool(it.get("legacy", false)):
			legacy += 1
		else:
			doc_items += 1
	ctx.eq("doc items (non-legacy)", doc_items, 77)
	ctx.eq("legacy aliases", legacy, 7)
	ctx.check("gold is currency", cat.is_currency("gold"))
	ctx.check("scrap is not currency", not cat.is_currency("scrap"))
	for raw_id in cat.item_order:
		ctx.check("item %s has name" % str(raw_id), not str(cat.item(str(raw_id)).get("name", "")).is_empty())

	ctx.eq("currency", cat.currency, "gold")
	for raw_id in cat.buy_prices.keys():
		ctx.check("buy ref %s exists" % str(raw_id), cat.items.has(str(raw_id)))
	for raw_id in cat.sell_prices.keys():
		ctx.check("sell ref %s exists" % str(raw_id), cat.items.has(str(raw_id)))
	ctx.check("M02 buy 6", cat.buy_price("M02") == 6, "实际 %d" % cat.buy_price("M02"))
	ctx.check("G10 buy 110", cat.buy_price("G10") == 110)
	ctx.check("scrap not buyable", cat.buy_price("scrap") == -1)
	ctx.check("gate_xor sell 4", cat.sell_price("gate_xor") == 4)

	var recipes: Array = cat.recipe_ids()
	ctx.check("recipes >= 77", recipes.size() >= 77, "实际 %d" % recipes.size())
	for raw_rid in recipes:
		var rid := str(raw_rid)
		var r: Dictionary = cat.recipe(rid)
		var out_id := str(r.get("output", ""))
		ctx.check("recipe %s output exists" % rid, out_id.is_empty() or cat.items.has(out_id), out_id)
		for iid in r.get("inputs", {}).keys():
			ctx.check("recipe %s input %s" % [rid, str(iid)], cat.items.has(str(iid)))
		for iid in r.get("key_items", {}).keys():
			ctx.check("recipe %s key %s" % [rid, str(iid)], cat.items.has(str(iid)))
		var need := str(r.get("requires_skill", "")) if r.get("requires_skill", null) != null else ""
		if not need.is_empty():
			ctx.check("recipe %s skill %s" % [rid, need], kg.nodes.has(need))

	ctx.eq("skill node count", kg.nodes.size(), 36)
	ctx.eq("progress nodes", kg.nodes_of_tree("progress").size(), 7)
	ctx.eq("knowledge nodes", kg.nodes_of_tree("knowledge").size(), 19)
	ctx.eq("skill nodes", kg.nodes_of_tree("skill").size(), 10)
	ctx.check("CH01 milestone exists", kg.nodes.has("CH01"))
	ctx.check("KN-ELEC-01 exists", kg.nodes.has("KN-ELEC-01"))
	ctx.check("SK-LEVEL exists", kg.nodes.has("SK-LEVEL"))
	ctx.check("legacy voltage exists", kg.nodes.has("voltage"))

	ctx.eq("chapter id", ch.id(), "ch01")
	ctx.eq("start gold", ch.start_gold(), 120)
	ctx.eq("labs", ch.lab_order.size(), 6)
	ctx.eq("objectives", ch.objectives.size(), 6)
	ctx.eq("start items", ch.start_items().size(), 2)
	for key in ch.start_items().keys():
		ctx.check("start item %s" % str(key), cat.items.has(str(key)))
	ctx.check("level has no prereq", ch.requires("level").is_empty())
	ctx.check("binary requires level", ch.requires("binary").has("level"))
	ctx.eq("lab order first", str(ch.lab_order[0]), "level")

	var gate_total := 0
	for lid in ch.lab_order:
		var lab: Dictionary = ch.lab(str(lid))
		var key := str(lab.get("data_key", ""))
		var cfg: Dictionary = db.lab_data(key)
		ctx.check("lab %s cfg exists" % str(lid), not cfg.is_empty())
		var cases: Array = cfg.get("gate_cases", [])
		gate_total += cases.size()
		ctx.eq("lab %s gate cases" % str(lid), cases.size(), 4)
		var ids := []
		for raw in cases:
			if raw is Dictionary:
				ids.append(str(raw.get("id", "")))
				ctx.check("case has kind %s" % str(raw.get("id", "")), not str(raw.get("kind", "")).is_empty())
		ctx.check("lab %s gate ids match cases" % str(lid), ids == Array(lab.get("gate_ids", [])), "配置 %s 用例 %s" % [str(lab.get("gate_ids", [])), str(ids)])
		var kn: Variant = lab.get("knowledge", null)
		if kn is String and not str(kn).is_empty():
			ctx.check("lab %s knowledge %s" % [str(lid), str(kn)], kg.nodes.has(str(kn)))
		var cards: Array = lab.get("knowledge_cards", [])
		for cid in cards:
			ctx.check("lab %s card %s" % [str(lid), str(cid)], kg.nodes.has(str(cid)))
		var nodes: Array = lab.get("skill_nodes", [])
		for nid in nodes:
			ctx.check("lab %s skill node %s" % [str(lid), str(nid)], kg.nodes.has(str(nid)))
		var sk := str(lab.get("skill_node", ""))
		if not sk.is_empty():
			ctx.check("lab %s skill_node %s" % [str(lid), sk], kg.nodes.has(sk))
		var ms := str(lab.get("milestone", ""))
		if not ms.is_empty():
			ctx.check("lab %s milestone %s" % [str(lid), ms], kg.nodes.has(ms))
		var reward: Dictionary = lab.get("reward", {})
		ctx.check("lab %s reward xp" % str(lid), int(reward.get("xp", 0)) > 0)

	ctx.check("total gate cases 24", gate_total == 24, "实际 %d" % gate_total)

	var sim: Dictionary = db.sim_doc
	ctx.eq("sim frame ticks", int(sim.get("frame", {}).get("ticks_per_frame", 0)), 4)
	ctx.eq("sim budget ms", int(sim.get("frame", {}).get("budget_ms", 0)), 5)
	ctx.eq("gdscript gate limit", int(sim.get("limits", {}).get("gdscript_gates", 0)), 100)
	ctx.eq("gdscript dff limit", int(sim.get("limits", {}).get("gdscript_dff", 0)), 100)
	ctx.eq("gdextension threshold", int(sim.get("limits", {}).get("require_gdextension_above", 0)), 100)
	ctx.eq("not delay", int(sim.get("gate_delay", {}).get("not", 0)), 1)
	ctx.eq("xor delay", int(sim.get("gate_delay", {}).get("xor", 0)), 4)
	ctx.eq("relay delay", int(sim.get("relay", {}).get("delay_per_stage_ticks", 0)), 3)

	var room: Dictionary = db.lab_data("half_adder")
	ctx.check("half adder inputs a/b", room.get("inputs", []).size() == 2)
	ctx.check("half adder outputs sum/carry", room.get("outputs", []).size() == 2)
	ctx.eq("half adder max gates", int(room.get("max_gates", 0)), 8)
	ctx.eq("gate lab max gates", int(db.lab_data("gate").get("max_gates", 0)), 12)

	var tut: Array = db.tutorial_doc.get("steps", [])
	ctx.check("tutorial has steps", tut.size() >= 5)
	ctx.eq("DataDB errors", db.errors.size(), 0)
