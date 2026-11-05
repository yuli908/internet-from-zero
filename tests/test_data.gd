extends RefCounted

const ChapterRegistry := preload("res://src/core/chapter_registry.gd")

## 数据完整性：物品、价格、配方、双树、章节、实验配置、gate 用例。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 619
const EXPECT_GROUPS := {
	"manifest": 2, "item_catalog": 1, "item_names": 86, "item_taxonomy": 5,
	"price_refs": 98, "price_values": 4, "recipe_count": 1, "recipe_outputs": 77,
	"recipe_inputs": 20, "recipe_keys": 141, "recipe_skill_refs": 1, "skill_tree": 9,
	"chapter_meta": 5, "start_items": 2, "chapter_prereq": 3, "lab_config": 6,
	"gate_case_counts": 6, "gate_case_kinds": 24, "gate_id_alignment": 6,
	"lab_node_refs": 37, "lab_reward": 6, "gate_total": 1, "sim_config": 15,
	"lab_limits": 4, "chapter_registry": 10, "ch02_labs": 4, "ch02_runtime": 5,
	"grid_count": 2, "ch02_node_refs": 27, "ch02_totals": 2, "tree_integrity": 2,
	"chapter_reward_payout": 5, "tutorial": 1, "loadable": 1,
}
const GROUP_DESCRIPTIONS := {
	"manifest": "manifest 文件清单 19 项、版本 2",
	"item_catalog": "目录条目总数 86",
	"item_names": "每个物品都有非空 name",
	"item_taxonomy": "文档物品 77 / 旧别名 7、gold 是货币而 scrap 不是",
	"price_refs": "买价/卖价表引用的物品都存在于目录",
	"price_values": "M02/G10/scrap/gate_xor 的具体价格口径",
	"recipe_count": "配方数不少于 77",
	"recipe_outputs": "每个配方的 output 必须存在于目录（空输出判红）",
	"recipe_inputs": "每个配方 inputs 引用的物品都存在",
	"recipe_keys": "每个配方 key_items 引用的物品都存在",
	"recipe_skill_refs": "配方锁定的技能节点都存在",
	"skill_tree": "节点总数/三棵树节点数、里程碑/知识/技能/旧节点存在",
	"chapter_meta": "ch01 的 id、起始金币、lab 数、objective 数、起始物品数",
	"start_items": "起始物品都在目录中",
	"chapter_prereq": "level 无前置、binary 前置含 level、lab 顺序首位",
	"lab_config": "每节 lab 配置存在",
	"gate_case_counts": "每节 gate 用例恰为 4 条",
	"gate_case_kinds": "每条 gate 用例都有非空 kind",
	"gate_id_alignment": "lab 的 gate_ids 与用例 id 顺序完全一致",
	"lab_node_refs": "lab 引用的知识节点/知识卡/技能/里程碑都存在",
	"lab_reward": "每节 lab 的 reward xp 大于 0",
	"gate_total": "全章 gate 用例合计 24",
	"sim_config": "帧步进/预算/门数上限/延迟/L3 bench 三档 p95 配置",
	"lab_limits": "half_adder 端子数与 half_adder/gate 的 max_gates",
	"chapter_registry": "章节注册表顺序、包含关系、章号、默认章节与兼容 labs",
	"ch02_labs": "ch02 labs 非空、段数 5、gate 数与原始数据一致",
	"ch02_runtime": "ch02 运行时可取、章节文档可达、排除后取不到",
	"grid_count": "ch01/ch02 房间地图节点派生数",
	"ch02_node_refs": "ch02 里程碑/知识卡/技能节点在技能树中存在",
	"ch02_totals": "ch02 知识卡 13 张、引用技能 6 个",
	"tree_integrity": "节点 ID 唯一、前置与 gate 引用无悬空",
	"chapter_reward_payout": "ch02 章末奖励走真节点，节点缺失才兜底",
	"tutorial": "教程步骤数不少于 5",
	"loadable": "DataDB 加载无错误",
}

func run(ctx: TestContext) -> void:
	var db: Node = TestUtil.data_db()
	var cat: Catalog = db.catalog
	var kg: KnowledgeGraph = db.skill_graph
	var ch: ChapterRuntime = db.chapter

	ctx.begin_group("manifest")
	ctx.eq("manifest files", int(db.manifest.get("files", []).size()), 25)
	ctx.eq("manifest version", int(db.manifest.get("version", 0)), 2)

	ctx.begin_group("item_catalog")
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
	ctx.begin_group("item_taxonomy")
	ctx.eq("doc items (non-legacy)", doc_items, 77)
	ctx.eq("legacy aliases", legacy, 7)
	ctx.check("gold is currency", cat.is_currency("gold"))
	ctx.check("scrap is not currency", not cat.is_currency("scrap"))
	for raw_id in cat.item_order:
		ctx.begin_group("item_names")
		ctx.check("item %s has name" % str(raw_id), not str(cat.item(str(raw_id)).get("name", "")).is_empty())

	ctx.begin_group("item_taxonomy")
	ctx.eq("currency", cat.currency, "gold")
	ctx.begin_group("price_refs")
	for raw_id in cat.buy_prices.keys():
		ctx.check("buy ref %s exists" % str(raw_id), cat.items.has(str(raw_id)))
	for raw_id in cat.sell_prices.keys():
		ctx.check("sell ref %s exists" % str(raw_id), cat.items.has(str(raw_id)))
	ctx.begin_group("price_values")
	ctx.check("M02 buy 6", cat.buy_price("M02") == 6, "实际 %d" % cat.buy_price("M02"))
	ctx.check("G10 buy 110", cat.buy_price("G10") == 110)
	ctx.check("scrap not buyable", cat.buy_price("scrap") == -1)
	ctx.check("gate_xor sell 4", cat.sell_price("gate_xor") == 4)

	var recipes: Array = cat.recipe_ids()
	ctx.begin_group("recipe_count")
	ctx.check("recipes >= 77", recipes.size() >= 77, "实际 %d" % recipes.size())
	for raw_rid in recipes:
		var rid := str(raw_rid)
		var r: Dictionary = cat.recipe(rid)
		var out_id := str(r.get("output", ""))
		ctx.begin_group("recipe_outputs")
		ctx.check("recipe %s output exists" % rid, cat.items.has(out_id), out_id)
		for iid in r.get("inputs", {}).keys():
			ctx.begin_group("recipe_inputs")
			ctx.check("recipe %s input %s" % [rid, str(iid)], cat.items.has(str(iid)))
		for iid in r.get("key_items", {}).keys():
			ctx.begin_group("recipe_keys")
			ctx.check("recipe %s key %s" % [rid, str(iid)], cat.items.has(str(iid)))
		var need := str(r.get("requires_skill", "")) if r.get("requires_skill", null) != null else ""
		if not need.is_empty():
			ctx.begin_group("recipe_skill_refs")
			ctx.check("recipe %s skill %s" % [rid, need], kg.nodes.has(need))

	ctx.begin_group("skill_tree")
	ctx.eq("skill node count", kg.nodes.size(), 167)
	ctx.eq("progress nodes", kg.nodes_of_tree("progress").size(), 52)
	ctx.eq("knowledge nodes", kg.nodes_of_tree("knowledge").size(), 74)
	ctx.eq("skill nodes", kg.nodes_of_tree("skill").size(), 41)
	ctx.check("CH01 milestone exists", kg.nodes.has("CH01"))
	ctx.check("KN-ELEC-01 exists", kg.nodes.has("KN-ELEC-01"))
	ctx.check("SK-LEVEL exists", kg.nodes.has("SK-LEVEL"))
	ctx.check("SK-DEMORGAN exists", kg.nodes.has("SK-DEMORGAN"))
	ctx.check("legacy voltage exists", kg.nodes.has("voltage"))

	ctx.begin_group("chapter_meta")
	ctx.eq("chapter id", ch.id(), "ch01")
	ctx.eq("start gold", ch.start_gold(), 120)
	ctx.eq("labs", ch.lab_order.size(), 6)
	ctx.eq("objectives", ch.objectives.size(), 6)
	ctx.eq("start items", ch.start_items().size(), 2)
	for key in ch.start_items().keys():
		ctx.begin_group("start_items")
		ctx.check("start item %s" % str(key), cat.items.has(str(key)))
	ctx.begin_group("chapter_prereq")
	ctx.check("level has no prereq", ch.requires("level").is_empty())
	ctx.check("binary requires level", ch.requires("binary").has("level"))
	ctx.eq("lab order first", str(ch.lab_order[0]), "level")

	var gate_total := 0
	for lid in ch.lab_order:
		var lab: Dictionary = ch.lab(str(lid))
		var key := str(lab.get("data_key", ""))
		var cfg: Dictionary = db.lab_data(key)
		ctx.begin_group("lab_config")
		ctx.check("lab %s cfg exists" % str(lid), not cfg.is_empty())
		var cases: Array = cfg.get("gate_cases", [])
		gate_total += cases.size()
		ctx.begin_group("gate_case_counts")
		ctx.eq("lab %s gate cases" % str(lid), cases.size(), 4)
		var ids := []
		for raw in cases:
			if raw is Dictionary:
				ids.append(str(raw.get("id", "")))
				ctx.begin_group("gate_case_kinds")
				ctx.check("case has kind %s" % str(raw.get("id", "")), not str(raw.get("kind", "")).is_empty())
		ctx.begin_group("gate_id_alignment")
		ctx.check("lab %s gate ids match cases" % str(lid), ids == Array(lab.get("gate_ids", [])), "配置 %s 用例 %s" % [str(lab.get("gate_ids", [])), str(ids)])
		var kn: Variant = lab.get("knowledge", null)
		ctx.begin_group("lab_node_refs")
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
		ctx.begin_group("lab_reward")
		ctx.check("lab %s reward xp" % str(lid), int(reward.get("xp", 0)) > 0)

	ctx.begin_group("gate_total")
	ctx.check("total gate cases 24", gate_total == 24, "实际 %d" % gate_total)

	var sim: Dictionary = db.sim_doc
	ctx.begin_group("sim_config")
	ctx.eq("sim frame ticks", int(sim.get("frame", {}).get("ticks_per_frame", 0)), 4)
	ctx.eq("sim budget ms", int(sim.get("frame", {}).get("budget_ms", 0)), 5)
	ctx.eq("gdscript gate limit", int(sim.get("limits", {}).get("gdscript_gates", 0)), 50)
	ctx.eq("gdscript dff limit", int(sim.get("limits", {}).get("gdscript_dff", 0)), 50)
	ctx.eq("gdextension threshold", int(sim.get("limits", {}).get("require_gdextension_above", 0)), 80)
	ctx.eq("L3 counter4 min period", int(sim.get("l3", {}).get("counter4_min_period", 0)), 14)
	ctx.eq("L3 counter8 min period", int(sim.get("l3", {}).get("counter8_min_period", 0)), 26)
	var l3b: Dictionary = sim.get("l3", {}).get("bench", {})
	ctx.eq("L3 bench scenario", str(l3b.get("scenario", "")), "l3")
	ctx.eq("L3 bench clock period", int(l3b.get("clock_period", 0)), 16)
	ctx.eq("L3 bench ticks/frame", int(l3b.get("ticks_per_frame", 0)), 4)
	var p95: Dictionary = l3b.get("p95_ms_worst", {})
	ctx.eq("L3 bench 三档 p95 齐全", p95.size(), 3)
	var bench_ok := true
	for k in ["50", "80", "100"]:
		if not p95.has(k) or float(p95[k]) > float(sim.get("frame", {}).get("budget_ms", 5)):
			bench_ok = false
	ctx.check("L3 bench 三档 p95 均 ≤ 5 ms", bench_ok, str(p95))
	ctx.eq("not delay", int(sim.get("gate_delay", {}).get("not", 0)), 1)
	ctx.eq("xor delay", int(sim.get("gate_delay", {}).get("xor", 0)), 4)
	ctx.eq("relay delay", int(sim.get("relay", {}).get("delay_per_stage_ticks", 0)), 3)

	var room: Dictionary = db.lab_data("half_adder")
	ctx.begin_group("lab_limits")
	ctx.check("half adder inputs a/b", room.get("inputs", []).size() == 2)
	ctx.check("half adder outputs sum/carry", room.get("outputs", []).size() == 2)
	ctx.eq("half adder max gates", int(room.get("max_gates", 0)), 8)
	ctx.eq("gate lab max gates", int(db.lab_data("gate").get("max_gates", 0)), 12)

	# ---- 穿过接缝：从 DataDB 入口直达 CH02，证明章节注册表真的被读 ----
	ctx.begin_group("chapter_registry")
	ctx.eq("章节注册表顺序", db.chapter_ids(), ["ch01", "ch02", "ch03", "ch04", "ch05", "ch06", "ch07", "ch08"])
	ctx.check("注册表含 ch01", db.has_chapter("ch01"))
	ctx.check("注册表含 ch02", db.has_chapter("ch02"))
	ctx.check("注册表含 ch03", db.has_chapter("ch03"))
	ctx.check("注册表含 ch04", db.has_chapter("ch04"))
	ctx.check("注册表含 ch05", db.has_chapter("ch05"))
	ctx.check("注册表含 ch06", db.has_chapter("ch06"))
	ctx.eq("ch02 章号", int(db.chapter_meta("ch02").get("number", 0)), 2)
	ctx.eq("默认章节来自注册表", db.default_chapter_id(), "ch01")
	ctx.eq("兼容 labs 指向默认章节", db.labs, db.labs_for("ch01"))
	var ch02_labs: Dictionary = db.labs_for("ch02")
	ctx.begin_group("ch02_labs")
	ctx.check("ch02 labs 非空", not ch02_labs.is_empty())
	ctx.eq("ch02 labs 段数", ch02_labs.size(), 5)
	var raw_labs: Dictionary = TestUtil.read_json("res://data/labs/ch02_labs.json").get("labs", {})
	var want_gates := 0
	for key in raw_labs.keys():
		var seg: Dictionary = raw_labs[key]
		want_gates += (seg.get("gate_cases", []) as Array).size()
	var got_gates := 0
	for key in ch02_labs.keys():
		var seg: Dictionary = ch02_labs[key]
		got_gates += (seg.get("gate_cases", []) as Array).size()
	ctx.eq("ch02 gate 数与数据一致", got_gates, want_gates)
	ctx.eq("ch02 gate 数 = 20", want_gates, 20)
	var ch02_rt: ChapterRuntime = db.runtime_for("ch02")
	ctx.begin_group("ch02_runtime")
	ctx.check("ch02 运行时可达", ch02_rt != null and ch02_rt.lab_order.size() == 5)
	ctx.check("ch02 章节文档可达", not ChapterRegistry.levels_doc("ch02").is_empty())
	# 反向验证：注册表里排除 ch02 时，同一入口必须取不到（证明不是恒真）
	var db_only1: Node = TestUtil.data_db(["ch01"])
	ctx.check("排除 ch02 后取不到 ch02 labs", db_only1.labs_for("ch02").is_empty())
	ctx.check("排除 ch02 后注册表不含 ch02", not db_only1.has_chapter("ch02"))
	ctx.check("仅 ch01 时默认章节仍 ch01", db_only1.default_chapter_id() == "ch01")

	# ---- 章内地图节点数：与 UI 派生规则一致（里程碑 + 知识卡 + 技能 + 挑战 + 章末）----
	ctx.begin_group("grid_count")
	ctx.eq("ch01 地图节点数 36", _grid_count(ch, kg), 36)
	ctx.eq("ch02 地图节点数 31", _grid_count(ch02_rt, kg), 31)

	# ---- CH02 节点齐全：章节 / 徽章 / 5 里程碑 / 13 知识卡 / 5 技能 ----
	ctx.begin_group("ch02_node_refs")
	ctx.check("CH02 存在", kg.nodes.has("CH02"))
	ctx.check("CH02-CMOS 存在", kg.nodes.has("CH02-CMOS"))
	var ch02_cards := 0
	var ch02_skills := []
	for lid in ch02_rt.lab_order:
		var lab: Dictionary = ch02_rt.lab(str(lid))
		var ms := str(lab.get("milestone", ""))
		ctx.check("ch02 %s 里程碑 %s" % [str(lid), ms], not ms.is_empty() and kg.nodes.has(ms))
		for cid in (lab.get("knowledge_cards", []) as Array):
			ctx.check("ch02 %s 知识卡 %s" % [str(lid), str(cid)], kg.nodes.has(str(cid)))
			ch02_cards += 1
		for sid in (lab.get("skill_nodes", []) as Array):
			ctx.check("ch02 %s 技能 %s" % [str(lid), str(sid)], kg.nodes.has(str(sid)))
			if not ch02_skills.has(str(sid)):
				ch02_skills.append(str(sid))
		var single := str(lab.get("skill_node", ""))
		if not single.is_empty():
			ctx.check("ch02 %s skill_node %s" % [str(lid), single], kg.nodes.has(single))
			if not ch02_skills.has(single):
				ch02_skills.append(single)
	ctx.begin_group("ch02_totals")
	ctx.eq("ch02 知识卡 13 张", ch02_cards, 13)
	ctx.eq("ch02 引用技能 6 个", ch02_skills.size(), 6)

	# ---- 节点表自检：ID 唯一、前置与 gate 引用无悬空 ----
	var tree_doc: Dictionary = TestUtil.read_json("res://data/skilltree.json")
	var seen_ids := {}
	var dup_ids := []
	for raw in tree_doc.get("nodes", []):
		var nd: Dictionary = raw
		var nid := str(nd.get("id", ""))
		if seen_ids.has(nid):
			dup_ids.append(nid)
		seen_ids[nid] = true
	ctx.begin_group("tree_integrity")
	ctx.check("节点 ID 唯一", dup_ids.is_empty(), str(dup_ids))
	var gate_ids := {}
	for cid in db.chapter_ids():
		var c: ChapterRuntime = db.runtime_for(str(cid))
		if c == null:
			continue
		for lid in c.lab_order:
			for gid in (c.lab(str(lid)).get("gate_ids", []) as Array):
				gate_ids[str(gid)] = true
	var dangling := []
	for raw in tree_doc.get("nodes", []):
		var nd: Dictionary = raw
		var nid := str(nd.get("id", ""))
		for p in (nd.get("prereq", []) as Array):
			if not kg.nodes.has(str(p)):
				dangling.append("%s->%s" % [nid, str(p)])
		var reqs: Dictionary = nd.get("requires", {})
		for r in (reqs.get("all", []) as Array):
			var req: Dictionary = r
			var rid := str(req.get("id", ""))
			if str(req.get("type", "")) == "node" and not kg.nodes.has(rid):
				dangling.append("%s->%s" % [nid, rid])
			if str(req.get("type", "")) == "gate" and not gate_ids.has(rid):
				dangling.append("%s->gate:%s" % [nid, rid])
	ctx.check("前置引用全部可解析", dangling.is_empty(), str(dangling))

	# ---- 章末奖励走真节点；兜底只在节点缺失时生效 ----
	var payout: Dictionary = ch02_rt.chapter_finish_reward(kg)
	ctx.begin_group("chapter_reward_payout")
	ctx.check("CH02 奖励不走兜底", not bool(payout.get("fallback", true)))
	ctx.eq("CH02 奖励节点", str(payout.get("node_id", "")), "CH02-CMOS")
	ctx.eq("CH02 节点金币 25", int(payout.get("gold", 0)), 25)
	var stripped: Dictionary = tree_doc.duplicate(true)
	var kept := []
	for raw in stripped.get("nodes", []):
		var nd: Dictionary = raw
		if str(nd.get("id", "")) == "CH02-CMOS" or str(nd.get("id", "")) == "CH02":
			continue
		kept.append(nd)
	stripped["nodes"] = kept
	var kg_stripped := KnowledgeGraph.from_doc(stripped)
	var payout2: Dictionary = ch02_rt.chapter_finish_reward(kg_stripped)
	ctx.check("节点缺失才走兜底", bool(payout2.get("fallback", false)))
	ctx.eq("兜底金币 = chapter_end_gold", int(payout2.get("gold", 0)), 25)

	var tut: Array = db.tutorial_doc.get("steps", [])
	ctx.begin_group("tutorial")
	ctx.check("tutorial has steps", tut.size() >= 5)
	ctx.begin_group("loadable")
	ctx.eq("DataDB errors", db.errors.size(), 0)

func _grid_count(c: ChapterRuntime, kg: KnowledgeGraph) -> int:
	## 与 UI 章节地图的派生规则一致：里程碑 + 章节点 + 知识卡 + 技能 + 每节挑战 + 章末验收。
	var count := c.lab_order.size() + 1
	var seen := {}
	for lid in c.lab_order:
		var lab: Dictionary = c.lab(str(lid))
		for cid in (lab.get("knowledge_cards", []) as Array):
			if kg.node(str(cid)).is_empty():
				continue
			count += 1
		var sks: Array = (lab.get("skill_nodes", []) as Array).duplicate()
		var single := str(lab.get("skill_node", ""))
		if not single.is_empty() and not sks.has(single):
			sks.append(single)
		for sid in sks:
			var key := str(sid)
			if seen.has(key) or kg.node(key).is_empty():
				continue
			seen[key] = true
			count += 1
	count += c.lab_order.size() + 1
	return count
