extends Node

## 数据层：启动时加载并校验所有 JSON 配置。UI 不得硬编码章节/物品/配方。

const ChapterRegistry := preload("res://src/core/chapter_registry.gd")

var ready_ok := false
var errors: Array = []
var catalog: Catalog
var skill_graph: KnowledgeGraph
var skills: KnowledgeGraph
var chapter: ChapterRuntime
var labs: Dictionary = {}
var labs_doc: Dictionary = {}
## 章节注册表：`id -> {id, number, title, levels_path, labs_path, has_labs, next_chapter}`，
## 顺序按章节 `number`（见 `ChapterRegistry`），不依赖文件名。
var chapters: Dictionary = {}
var chapter_order: Array = []
var labs_by_chapter: Dictionary = {}
var _runtimes: Dictionary = {}
## 只装了部分章节（测试用探针）时为真：跳过跨章节的 gate 条件校验。
var partial_load := false
var tutorial_doc: Dictionary = {}
var sim_doc: Dictionary = {}
var manifest: Dictionary = {}
var data_version := 0
var loaded_files := 0

func _ready() -> void:
	load_all()

func load_all(only_chapters: Array = []) -> void:
	errors.clear()
	loaded_files = 0
	partial_load = not only_chapters.is_empty()
	manifest = _json("res://data/manifest.json")
	var files: Array = manifest.get("files", [])
	for f in files:
		var doc := _json(str(f))
		if doc.is_empty():
			errors.append("无法加载或解析 %s" % str(f))
		else:
			loaded_files += 1
	catalog = Catalog.from_data(_json("res://data/items/items.json"), _json("res://data/economy/prices.json"), _json("res://data/economy/recipes.json"))
	var skill_doc := _json("res://data/skilltree.json")
	skill_graph = KnowledgeGraph.from_doc(skill_doc)
	skills = skill_graph
	_build_registry(only_chapters)
	var default_id := default_chapter_id()
	chapter = runtime_for(default_id) if not default_id.is_empty() else ChapterRuntime.from_doc({})
	labs_doc = ChapterRegistry.labs_doc(default_id)
	labs = labs_for(default_id)
	tutorial_doc = _json("res://data/tutorial.json")
	sim_doc = _json("res://data/sim/delays.json")
	SimDelays.configure(sim_doc)
	data_version = int(ChapterRegistry.levels_doc(default_id).get("version", 0))
	_validate()
	ready_ok = errors.is_empty()
	if not ready_ok:
		for e in errors:
			printerr("[DATA] ", e)

func _build_registry(only_chapters: Array = []) -> void:
	chapters.clear()
	chapter_order.clear()
	labs_by_chapter.clear()
	_runtimes.clear()
	for raw in ChapterRegistry.entries():
		var e: Dictionary = raw
		var cid := str(e.get("id", ""))
		if not only_chapters.is_empty() and not only_chapters.has(cid):
			continue
		chapters[cid] = e
		chapter_order.append(cid)
		if bool(e.get("has_labs", false)):
			labs_by_chapter[cid] = ChapterRegistry.labs(cid)
	if chapter_order.is_empty():
		errors.append("章节注册表为空（%s 下没有 *_levels.json）" % ChapterRegistry.CHAPTER_DIR)

func chapter_ids() -> Array:
	## 稳定章节序（按章节 `number`）。
	return chapter_order.duplicate()

func has_chapter(chapter_id_in: String) -> bool:
	return chapters.has(chapter_id_in)

func chapter_meta(chapter_id_in: String) -> Dictionary:
	return chapters.get(chapter_id_in, {})

func default_chapter_id() -> String:
	## 默认章节来自注册表首个，不写死任何章节 ID。
	return str(chapter_order[0]) if not chapter_order.is_empty() else ""

func labs_for(chapter_id_in: String) -> Dictionary:
	## 按章节取实验数据段（`data_key -> 配置`）；未知章节返回空表。
	return labs_by_chapter.get(chapter_id_in, {})

func runtime_for(chapter_id_in: String) -> ChapterRuntime:
	if not chapters.has(chapter_id_in):
		return null
	if not _runtimes.has(chapter_id_in):
		_runtimes[chapter_id_in] = ChapterRuntime.from_doc(ChapterRegistry.levels_doc(chapter_id_in))
	return _runtimes[chapter_id_in]

func use_chapter(chapter_id_in: String) -> bool:
	## 切到指定章节：只替换"当前章节"缓存（运行时 / 实验数据段 / 数据版本）。
	## 玩家进度是全局的，切章不改存档字段；未知章节返回 false 且不改现状。
	if not chapters.has(chapter_id_in):
		return false
	chapter = runtime_for(chapter_id_in)
	labs_doc = ChapterRegistry.labs_doc(chapter_id_in)
	labs = labs_for(chapter_id_in)
	data_version = int(ChapterRegistry.levels_doc(chapter_id_in).get("version", 0))
	EventBus.fire("chapter_switched:%s" % chapter_id_in)
	return true

func _json(path: String) -> Dictionary:
	var text := FileAccess.get_file_as_string(path)
	if text.is_empty():
		return {}
	var parsed: Variant = JSON.parse_string(text)
	if parsed is Dictionary:
		return parsed
	return {}

func lab_data(data_key: String) -> Dictionary:
	return labs.get(data_key, {})

func gate_cases(lab_id: String) -> Array:
	var lab := chapter.lab(lab_id)
	var cfg := lab_data(str(lab.get("data_key", "")))
	return cfg.get("gate_cases", [])

func skill_nodes() -> Dictionary:
	return skill_graph.nodes

func chapter_id() -> String:
	return chapter.id()

func validate() -> Array:
	errors.clear()
	_validate()
	ready_ok = errors.is_empty()
	return errors

func _validate() -> void:
	for file_err in chapter.dsl_errors():
		errors.append(file_err)
	for id in catalog.buy_prices.keys():
		if not catalog.has_item(str(id)):
			errors.append("价格表引用了不存在的物品 %s" % str(id))
	for id in catalog.sell_prices.keys():
		if not catalog.has_item(str(id)):
			errors.append("回收表引用了不存在的物品 %s" % str(id))
	for recipe_id in catalog.recipe_order:
		var recipe := catalog.recipe(str(recipe_id))
		var ins: Dictionary = recipe.get("inputs", {})
		var keys: Dictionary = recipe.get("key_items", {})
		var outs: Dictionary = recipe.get("outputs", {})
		var out_single := str(recipe.get("output", ""))
		for k in ins.keys():
			if not catalog.has_item(str(k)):
				errors.append("配方 %s 的输入 %s 不存在" % [str(recipe_id), str(k)])
		for k in keys.keys():
			if not catalog.has_item(str(k)):
				errors.append("配方 %s 的关键件 %s 不存在" % [str(recipe_id), str(k)])
		for k in outs.keys():
			if not catalog.has_item(str(k)):
				errors.append("配方 %s 的输出 %s 不存在" % [str(recipe_id), str(k)])
		if not out_single.is_empty() and not catalog.has_item(out_single):
			errors.append("配方 %s 的输出物品 %s 不存在" % [str(recipe_id), out_single])
		var skill := str(recipe.get("requires_skill", recipe.get("unlock_skill", ""))) if recipe.get("requires_skill", recipe.get("unlock_skill")) != null else ""
		if not skill.is_empty() and not skill_graph.has_node(skill):
			errors.append("配方 %s 依赖不存在的技能 %s" % [str(recipe_id), skill])
	var gate_ids := {}
	for cid in chapter_order:
		var rt := runtime_for(str(cid))
		if rt == null:
			continue
		var chap_labs := labs_for(str(cid))
		for lab_id in rt.lab_order:
			var lab := rt.lab(str(lab_id))
			var key := str(lab.get("data_key", ""))
			if not chap_labs.has(key):
				errors.append("章节 %s 实验 %s 缺少实验数据段 %s" % [str(cid), str(lab_id), key])
				continue
			var primary_knowledge := str(lab.get("knowledge", ""))
			if not primary_knowledge.is_empty() and not skill_graph.has_node(primary_knowledge):
				errors.append("实验 %s 指向不存在的知识节点" % str(lab_id))
			for card in lab.get("knowledge_cards", []):
				if not skill_graph.has_node(str(card)):
					errors.append("实验 %s 的知识卡 %s 不存在" % [str(lab_id), str(card)])
			if not skill_graph.has_node(str(lab.get("skill_node", ""))):
				errors.append("实验 %s 的技能节点 %s 不存在" % [str(lab_id), str(lab.get("skill_node", ""))])
			if not str(lab.get("milestone", "")).is_empty() and not skill_graph.has_node(str(lab.get("milestone", ""))):
				errors.append("实验 %s 的里程碑 %s 不存在" % [str(lab_id), str(lab.get("milestone", ""))])
			var cases: Array = (chap_labs.get(key, {}) as Dictionary).get("gate_cases", [])
			if cases.is_empty():
				errors.append("实验 %s 没有 gate 用例" % str(lab_id))
			var case_ids := {}
			for raw in cases:
				var c: Dictionary = raw
				gate_ids[str(c.get("id", ""))] = true
				case_ids[str(c.get("id", ""))] = true
				if str(c.get("id", "")).is_empty() or str(c.get("title", "")).is_empty():
					errors.append("实验 %s 的 gate 用例缺少 id/title" % str(lab_id))
			for gid in lab.get("gate_ids", []):
				if not case_ids.has(str(gid)):
					errors.append("实验 %s 的 gate_ids 引用了未定义的用例 %s" % [str(lab_id), str(gid)])
			var grants: Dictionary = rt.grants(str(lab_id), chap_labs)
			var gitems: Variant = grants.get("items", {})
			if not (gitems is Dictionary):
				errors.append("实验 %s 的 grants.items 必须是字典" % str(lab_id))
			else:
				for iid in (gitems as Dictionary).keys():
					if not catalog.has_item(str(iid)):
						errors.append("实验 %s 的奖励物品 %s 不存在" % [str(lab_id), str(iid)])
					if int((gitems as Dictionary)[iid]) < 1:
						errors.append("实验 %s 的奖励物品 %s 数量非法" % [str(lab_id), str(iid)])
	for node_id in skill_graph.order:
		for p in skill_graph.prereqs(str(node_id)):
			if not skill_graph.has_node(str(p)):
				errors.append("技能 %s 的前置 %s 不存在" % [str(node_id), str(p)])
		if partial_load:
			continue
		var req: Dictionary = skill_graph.node(str(node_id)).get("requires", {})
		_validate_conditions(str(node_id), req.get("all", []), gate_ids)
		_validate_conditions(str(node_id), req.get("any", []), gate_ids)
	if sim_doc.is_empty():
		errors.append("缺少 data/sim/delays.json")
	else:
		var gates_table: Dictionary = sim_doc.get("gate_delay", {})
		for g in ["buf", "not", "and", "or", "xor", "nand", "nor", "xnor"]:
			if not gates_table.has(g):
				errors.append("延迟表缺少门类型 %s" % g)
	for step in tutorial_doc.get("steps", []):
		var s: Dictionary = step
		if str(s.get("trigger", "")).is_empty():
			errors.append("引导步骤 %s 缺少触发事件" % str(s.get("id", "?")))
	for id in chapter.start_items().keys():
		if not catalog.has_item(str(id)):
			errors.append("开局物品 %s 不存在" % str(id))

func _validate_conditions(node_id: String, conds: Array, gate_ids: Dictionary) -> void:
	for raw in conds:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var typ := str(c.get("type", ""))
		var cid := str(c.get("id", ""))
		if typ == "node" and not skill_graph.has_node(cid):
			errors.append("节点 %s 的条件引用了不存在的节点 %s" % [node_id, cid])
		elif typ == "gate" and not gate_ids.has(cid):
			errors.append("节点 %s 的条件引用了未定义的 gate %s" % [node_id, cid])
