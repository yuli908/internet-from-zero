extends RefCounted

## M7 · 章节注册与可达性：ch07–ch08 能被 ChapterRegistry 装载、use_chapter 可达、
## labs_by_chapter 非空、manifest 无漏登记、gate_ids 无悬空。
## 红验证：在临时 DataDB 实例上删节点 / 加悬空 gate / 删 manifest 项，validate 或直接断言必须变红。

const ChapterRegistry := preload("res://src/core/chapter_registry.gd")

const EXPECT := 38
const EXPECT_GROUPS := {
	"loadable": 1, "order": 1, "chapter_loaded": 3, "use_chapter": 2,
	"labs_nonempty": 2, "runtime": 2, "manifest": 7, "levels_ids": 2,
	"next_chain": 3, "gate_dangling": 2, "node_refs": 2, "gate_count": 2,
	"gate_alignment": 2, "validate": 1, "red_proof": 5, "totals": 1,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "DataDB 可读",
	"order": "章节顺序 ch01..ch08",
	"chapter_loaded": "两章均被注册表装载且章号正确",
	"use_chapter": "use_chapter 逐章可达",
	"labs_nonempty": "labs_by_chapter 非空且数量正确",
	"runtime": "两章运行时可取且 lab_order 对齐",
	"manifest": "4 个新数据文件全部登记，且每章 levels+labs 成对",
	"levels_ids": "levels 文档 id/number 与注册表一致",
	"next_chain": "ch06→ch07→ch08→ch09（ch09 数据未建）",
	"gate_dangling": "每章 gate_ids 全部能在本章用例中找到",
	"node_refs": "每章里程碑/知识卡/技能节点都存在",
	"gate_count": "每章实验各 4 条 gate",
	"gate_alignment": "gate_ids 顺序与 gate_cases 顺序一致",
	"validate": "全量 validate 无错误",
	"red_proof": "删节点/悬空 gate/删 manifest 项/删 lab 副本均能变红",
	"totals": "两章实验合计 7",
}
const LAB_COUNTS := {"ch07": 4, "ch08": 3}
const GATE_TOTALS := {"ch07": 16, "ch08": 12}
const CHAPTER_NUMBERS := {"ch07": 7, "ch08": 8}
const NEW_FILES := [
	"res://data/chapters/ch07_levels.json", "res://data/labs/ch07_labs.json",
	"res://data/chapters/ch08_levels.json", "res://data/labs/ch08_labs.json",
]

func run(ctx: TestContext) -> void:
	var db = TestUtil.data_db()

	ctx.begin_group("loadable")
	ctx.check("DataDB 可读", db != null and db.chapter_ids().size() >= 8)

	ctx.begin_group("order")
	ctx.check("章节顺序 ch01..ch08", db.chapter_ids() == ["ch01", "ch02", "ch03", "ch04",
		"ch05", "ch06", "ch07", "ch08"], str(db.chapter_ids()))

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("chapter_loaded")
		ctx.check("%s 已装载" % cid, db.has_chapter(cid))
	ctx.check("章号 7..8", int(db.chapter_meta("ch07").get("number", 0)) == 7
		and int(db.chapter_meta("ch08").get("number", 0)) == 8)

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("use_chapter")
		ctx.check("%s use_chapter 可达" % cid, db.use_chapter(cid) and db.chapter_id() == cid,
			"chapter_id=%s" % db.chapter_id())

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("labs_nonempty")
		var labs: Dictionary = db.labs_for(cid)
		ctx.check("%s labs_by_chapter 非空且 %d 个" % [cid, int(LAB_COUNTS[cid])],
			not labs.is_empty() and labs.size() == int(LAB_COUNTS[cid]), str(labs.size()))

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("runtime")
		var rt: ChapterRuntime = db.runtime_for(cid)
		ctx.check("%s 运行时 lab_order 对齐" % cid,
			rt != null and rt.lab_order.size() == int(LAB_COUNTS[cid]),
			str(rt.lab_order.size() if rt else -1))

	ctx.begin_group("manifest")
	var files: Array = db.manifest.get("files", [])
	for path in NEW_FILES:
		ctx.check("manifest 登记 %s" % path, files.has(path))
	for cid in ["ch07", "ch08"]:
		ctx.check("%s levels+labs 成对登记" % cid,
			files.has("res://data/chapters/%s_levels.json" % cid)
			and files.has("res://data/labs/%s_labs.json" % cid))
	ctx.check("manifest 25 项", files.size() == 25, str(files.size()))

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("levels_ids")
		var doc: Dictionary = ChapterRegistry.levels_doc(cid)
		ctx.check("%s levels id/number" % cid,
			str(doc.get("id", "")) == cid and int(doc.get("number", 0)) == int(CHAPTER_NUMBERS[cid]),
			"%s/%s" % [str(doc.get("id", "")), str(doc.get("number", ""))])

	ctx.begin_group("next_chain")
	ctx.check("ch06→ch07", str(ChapterRegistry.levels_doc("ch06").get("next_chapter", "")) == "ch07")
	ctx.check("ch07→ch08", str(ChapterRegistry.levels_doc("ch07").get("next_chapter", "")) == "ch08")
	ctx.check("ch08→ch09（ch09 数据未建）",
		str(ChapterRegistry.levels_doc("ch08").get("next_chapter", "")) == "ch09")

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("gate_dangling")
		var levels: Dictionary = ChapterRegistry.levels_doc(cid)
		var labs: Dictionary = db.labs_for(cid)
		ctx.check("%s gate_ids 无悬空" % cid, _dangling(levels, labs).is_empty(),
			str(_dangling(levels, labs)))

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("node_refs")
		var missing := []
		for raw in (db.labs_for(cid) as Dictionary).values():
			var lab: Dictionary = raw
			for key in ["knowledge", "milestone", "skill_node"]:
				var nid := str(lab.get(key, ""))
				if not nid.is_empty() and not db.skill_graph.nodes.has(nid):
					missing.append(nid)
			for card in lab.get("knowledge_cards", []):
				if not db.skill_graph.nodes.has(str(card)):
					missing.append(str(card))
		ctx.check("%s 引用节点均存在" % cid, missing.is_empty(), str(missing))

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("gate_count")
		var total := 0
		for raw in (db.labs_for(cid) as Dictionary).values():
			var cfg: Dictionary = raw
			total += (cfg.get("gate_cases", []) as Array).size()
		ctx.check("%s gate 总数 %d" % [cid, int(GATE_TOTALS[cid])],
			total == int(GATE_TOTALS[cid]), str(total))

	for cid in ["ch07", "ch08"]:
		ctx.begin_group("gate_alignment")
		var bad := []
		var labs: Dictionary = db.labs_for(cid)
		var levels: Dictionary = ChapterRegistry.levels_doc(cid)
		var by_key := {}
		for lab in levels.get("labs", []):
			var ld: Dictionary = lab
			by_key[str(ld.get("data_key", ld.get("id", "")))] = ld
		for lid in labs.keys():
			var cases: Array = (labs[lid] as Dictionary).get("gate_cases", [])
			var case_ids := []
			for c in cases:
				case_ids.append(str((c as Dictionary).get("id", "")))
			var gate_ids: Array = (by_key.get(str(lid), {}) as Dictionary).get("gate_ids", [])
			if gate_ids != case_ids:
				bad.append(str(lid))
		ctx.check("%s gate_ids 与用例顺序一致" % cid, bad.is_empty(), str(bad))

	ctx.begin_group("validate")
	var errors: Array = db.validate()
	ctx.check("全量 validate 无错误", errors.is_empty(), str(errors))

	ctx.begin_group("red_proof")
	var d1 = TestUtil.data_db()
	d1.skill_graph.nodes.erase("CH07-1")
	ctx.check("删 CH07-1 → validate 红", not d1.validate().is_empty())
	var d2 = TestUtil.data_db()
	var bad_levels: Dictionary = ChapterRegistry.levels_doc("ch07").duplicate(true)
	((bad_levels["labs"][0] as Dictionary)["gate_ids"] as Array).append("T7.1-9")
	ctx.check("加悬空 gate T7.1-9 → 悬空断言红",
		not _dangling(bad_levels, d2.labs_for("ch07")).is_empty())
	var d3 = TestUtil.data_db()
	var fs: Array = d3.manifest.get("files", [])
	fs.erase("res://data/chapters/ch08_levels.json")
	ctx.check("删 manifest 项 → 漏登记断言红", not _manifest_missing(d3).is_empty())
	var d4 = TestUtil.data_db()
	var copy4: Dictionary = (d4.labs_for("ch07") as Dictionary).duplicate(true)
	copy4.erase("two_machine")
	ctx.check("删 ch07 two_machine 副本 → labs 数量断言红", copy4.size() != 4, str(copy4.size()))
	var d5 = TestUtil.data_db()
	d5.skill_graph.nodes.erase("SK-CAPTURE")
	ctx.check("删 SK-CAPTURE → validate 红", not d5.validate().is_empty())

	ctx.begin_group("totals")
	ctx.check("两章实验合计 7", _all_labs(db) == 7, str(_all_labs(db)))

# ---------------------------------------------------------------- 工具

func _dangling(levels: Dictionary, labs: Dictionary) -> Array:
	var out := []
	for raw in levels.get("labs", []):
		var lab: Dictionary = raw
		var lid := str(lab.get("id", ""))
		var cfg: Dictionary = labs.get(str(lab.get("data_key", lid)), {})
		var case_ids := {}
		for c in cfg.get("gate_cases", []):
			case_ids[str((c as Dictionary).get("id", ""))] = true
		for gid in lab.get("gate_ids", []):
			if not case_ids.has(str(gid)):
				out.append("%s.%s" % [lid, str(gid)])
	return out

func _all_labs(db) -> int:
	var n := 0
	for cid in ["ch07", "ch08"]:
		n += db.labs_for(cid).size()
	return n

func _manifest_missing(db) -> Array:
	var out := []
	var files: Array = db.manifest.get("files", [])
	for path in NEW_FILES:
		if not files.has(path):
			out.append(str(path))
	return out
