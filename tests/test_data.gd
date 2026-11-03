extends RefCounted

func run(ctx: TestContext) -> void:
	var manifest := TestUtil.read_json("res://data/manifest.json")
	var files: Array = manifest.get("files", [])
	ctx.eq("manifest file count", files.size(), 7)
	for f in files:
		ctx.check("data file exists %s" % str(f), FileAccess.file_exists(str(f)))
		ctx.check("data file parses %s" % str(f), not TestUtil.read_json(str(f)).is_empty())

	var items_doc := TestUtil.items_doc()
	var item_rows: Array = items_doc.get("items", [])
	var ids := {}
	for raw in item_rows:
		var item: Dictionary = raw
		ids[str(item["id"])] = item
	ctx.eq("item count", ids.size(), 8)
	var scrap_item: Dictionary = ids["scrap"]
	ctx.eq("scrap is currency", str(scrap_item["kind"]), "currency")

	var prices := TestUtil.prices_doc()
	ctx.eq("currency id", str(prices["currency"]), "scrap")
	var buy_map: Dictionary = prices.get("buy", {})
	var sell_map: Dictionary = prices.get("sell", {})
	for key in buy_map.keys():
		ctx.check("buy price item exists %s" % str(key), ids.has(str(key)))
	for key in sell_map.keys():
		ctx.check("sell price item exists %s" % str(key), ids.has(str(key)))

	var recipes := TestUtil.recipes_doc()
	var recipe_rows: Array = recipes.get("recipes", [])
	var recipe_ids := {}
	for raw in recipe_rows:
		var recipe: Dictionary = raw
		recipe_ids[str(recipe["id"])] = recipe
		var ins: Dictionary = recipe.get("inputs", {})
		var outs: Dictionary = recipe.get("outputs", {})
		for key in ins.keys():
			ctx.check("recipe input exists %s" % str(key), ids.has(str(key)))
		for key in outs.keys():
			ctx.check("recipe output exists %s" % str(key), ids.has(str(key)))
	ctx.eq("recipe count", recipe_ids.size(), 3)

	var skills := TestUtil.skill_doc()
	var skill_rows: Array = skills.get("nodes", [])
	var skill_map := TestUtil.skill_nodes()
	for raw in skill_rows:
		var node: Dictionary = raw
		var nid := str(node["id"])
		for p in node.get("prereq", []):
			ctx.check("prereq exists %s" % str(p), skill_map.has(str(p)))
		if str(node["kind"]) == "skill":
			ctx.check("skill has xp cost %s" % nid, int(node.get("xp_cost", -1)) >= 0)
		else:
			ctx.check("knowledge has xp award %s" % nid, int(node.get("xp_award", -1)) > 0)
		if node.has("effects"):
			var effects: Dictionary = node["effects"]
			if effects.has("unlock_recipe"):
				var rid := str(effects["unlock_recipe"])
				ctx.check("effect recipe exists %s" % rid, recipe_ids.has(rid))

	var chapter := TestUtil.chapter_doc()
	var labs: Array = chapter.get("labs", [])
	var objectives: Array = chapter.get("objectives", [])
	ctx.eq("chapter lab count", labs.size(), 6)
	ctx.eq("chapter objective count", objectives.size(), 6)
	var obj_ids := {}
	for raw in objectives:
		var o: Dictionary = raw
		obj_ids[str(o["id"])] = o
		ctx.check("objective knowledge exists %s" % str(o["knowledge"]), skill_map.has(str(o["knowledge"])))
	var lab_ids := {}
	for raw in labs:
		var lab: Dictionary = raw
		lab_ids[str(lab["id"])] = lab
		ctx.check("lab objective exists %s" % str(lab["objective"]), obj_ids.has(str(lab["objective"])))
		ctx.check("lab knowledge exists %s" % str(lab["knowledge"]), skill_map.has(str(lab["knowledge"])))
		var rv: Variant = lab.get("requires", null)
		if rv != null and not str(rv).is_empty():
			ctx.check("lab requires exists %s" % str(rv), lab_ids.has(str(rv)))

	var labs_doc := TestUtil.labs_doc()
	var labs_data: Dictionary = labs_doc.get("labs", {})
	for raw in labs:
		var lab2: Dictionary = raw
		ctx.check("lab data key exists %s" % str(lab2["data_key"]), labs_data.has(str(lab2["data_key"])))

	var quiz: Dictionary = labs_data.get("binary", {}).get("quiz", {})
	var options: Array = quiz.get("options", [])
	ctx.check("quiz answer in range", int(quiz.get("answer", -1)) >= 0 and int(quiz.get("answer", -1)) < options.size())
	ctx.check("quiz explain present", not str(quiz.get("explain", "")).is_empty())

	var gate_lab: Dictionary = labs_data.get("gate", {})
	var puzzles: Array = gate_lab.get("puzzles", [])
	ctx.eq("gate puzzle count", puzzles.size(), 3)
	for raw in puzzles:
		var p: Dictionary = raw
		ctx.check("puzzle target valid %s" % str(p["target"]), LogicGates.from_string(str(p["target"])) >= 0)

	var adder: Dictionary = labs_data.get("half_adder", {})
	ctx.check("half adder sum gate valid", LogicGates.from_string(str(adder.get("sum_gate", ""))) >= 0)
	ctx.check("half adder carry gate valid", LogicGates.from_string(str(adder.get("carry_gate", ""))) >= 0)
	var sig: Dictionary = labs_data.get("signal", {})
	ctx.check("signal ticks required > 0", int(sig.get("ticks_required", 0)) > 0)
	ctx.check("signal delay <= ticks", int(sig.get("gate_delay_ticks", 99)) <= int(sig.get("ticks_required", 0)))

	var tutorial := TestUtil.tutorial_doc()
	var steps: Array = tutorial.get("steps", [])
	ctx.check("tutorial steps non-empty", steps.size() > 0)
	for raw in steps:
		var s: Dictionary = raw
		ctx.check("tutorial trigger present %s" % str(s["id"]), not str(s.get("trigger", "")).is_empty())
