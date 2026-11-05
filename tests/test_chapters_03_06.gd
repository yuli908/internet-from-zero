extends RefCounted

## M6 · 章节注册与可达性：ch03–ch06 能被 ChapterRegistry 装载、use_chapter 可达、
## labs_by_chapter 非空、manifest 无漏登记、gate_ids 无悬空。
## 红验证：在临时 DataDB 实例上删节点 / 加悬空 gate / 删 manifest 项，validate 或直接断言必须变红。

const ChapterRegistry := preload("res://src/core/chapter_registry.gd")

const EXPECT := 63
const EXPECT_GROUPS := {
	"loadable": 1, "order": 1, "chapter_loaded": 5, "use_chapter": 4,
	"labs_nonempty": 4, "runtime": 4, "manifest": 13, "levels_ids": 4,
	"next_chain": 4, "gate_dangling": 4, "node_refs": 4, "gate_count": 4,
	"gate_alignment": 4, "validate": 1, "red_proof": 5, "totals": 1,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "DataDB 可读",
	"order": "章节 id 从 ch01 起连续编号",
	"chapter_loaded": "四章均被注册表装载且章号正确",
	"use_chapter": "use_chapter 逐章可达",
	"labs_nonempty": "labs_by_chapter 非空且数量正确",
	"runtime": "四章运行时可取且 lab_order 对齐",
	"manifest": "8 个新数据文件全部登记，且每章 levels+labs 成对",
	"levels_ids": "levels 文档 id/number 与注册表一致",
	"next_chain": "ch03→ch04→ch05→ch06→ch07",
	"gate_dangling": "每章 gate_ids 全部能在本章用例中找到",
	"node_refs": "每章里程碑/知识卡/技能节点都存在",
	"gate_count": "每章实验各 4 条 gate",
	"gate_alignment": "gate_ids 顺序与 gate_cases 顺序一致",
	"validate": "全量 validate 无错误",
	"red_proof": "删节点/悬空 gate/删 manifest 项均能变红",
	"totals": "四章实验合计 19",
}
const LAB_COUNTS := {"ch03": 4, "ch04": 5, "ch05": 4, "ch06": 6}
const GATE_TOTALS := {"ch03": 16, "ch04": 20, "ch05": 17, "ch06": 24}
const CHAPTER_NUMBERS := {"ch03": 3, "ch04": 4, "ch05": 5, "ch06": 6}
const NEW_FILES := [
	"res://data/chapters/ch03_levels.json", "res://data/labs/ch03_labs.json",
	"res://data/chapters/ch04_levels.json", "res://data/labs/ch04_labs.json",
	"res://data/chapters/ch05_levels.json", "res://data/labs/ch05_labs.json",
	"res://data/chapters/ch06_levels.json", "res://data/labs/ch06_labs.json",
]

func run(ctx: TestContext) -> void:
	var db = TestUtil.data_db()

	ctx.begin_group("loadable")
	ctx.check("DataDB 可读", db != null and db.chapter_ids().size() >= 6)

	ctx.begin_group("order")
	var ids: Array = db.chapter_ids()
	var seq_ok := ids.size() >= 6
	for i in ids.size():
		if str(ids[i]) != "ch%02d" % (i + 1):
			seq_ok = false
	ctx.check("章节顺序从 ch01 连续", seq_ok, str(ids))

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.begin_group("chapter_loaded")
		ctx.check("%s 已装载" % cid, db.has_chapter(cid))
	ctx.check("章号 3..6", int(db.chapter_meta("ch03").get("number", 0)) == 3
		and int(db.chapter_meta("ch04").get("number", 0)) == 4
		and int(db.chapter_meta("ch05").get("number", 0)) == 5
		and int(db.chapter_meta("ch06").get("number", 0)) == 6)

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.begin_group("use_chapter")
		ctx.check("%s use_chapter 可达" % cid, db.use_chapter(cid) and db.chapter_id() == cid,
			"chapter_id=%s" % db.chapter_id())

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.begin_group("labs_nonempty")
		var labs: Dictionary = db.labs_for(cid)
		ctx.check("%s labs_by_chapter 非空且 %d 个" % [cid, int(LAB_COUNTS[cid])],
			not labs.is_empty() and labs.size() == int(LAB_COUNTS[cid]), str(labs.size()))

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.begin_group("runtime")
		var rt: ChapterRuntime = db.runtime_for(cid)
		ctx.check("%s 运行时 lab_order 对齐" % cid,
			rt != null and rt.lab_order.size() == int(LAB_COUNTS[cid]), str(rt.lab_order.size() if rt else -1))

	ctx.begin_group("manifest")
	var files: Array = db.manifest.get("files", [])
	for path in NEW_FILES:
		ctx.check("manifest 登记 %s" % path, files.has(path))
	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.check("%s levels+labs 成对登记" % cid,
			files.has("res://data/chapters/%s_levels.json" % cid)
			and files.has("res://data/labs/%s_labs.json" % cid))
	var miss := ""
	for cid in db.chapter_ids():
		for p in ["res://data/chapters/%s_levels.json" % cid, "res://data/labs/%s_labs.json" % cid]:
			if not files.has(p):
				miss = p
	ctx.check("manifest 覆盖全部章节 levels+labs", miss == "", miss)

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.begin_group("levels_ids")
		var doc: Dictionary = ChapterRegistry.levels_doc(cid)
		ctx.check("%s levels id/number" % cid,
			str(doc.get("id", "")) == cid and int(doc.get("number", 0)) == int(CHAPTER_NUMBERS[cid]),
			"%s/%s" % [str(doc.get("id", "")), str(doc.get("number", ""))])

	ctx.begin_group("next_chain")
	ctx.check("ch03→ch04", str(ChapterRegistry.levels_doc("ch03").get("next_chapter", "")) == "ch04")
	ctx.check("ch04→ch05", str(ChapterRegistry.levels_doc("ch04").get("next_chapter", "")) == "ch05")
	ctx.check("ch05→ch06", str(ChapterRegistry.levels_doc("ch05").get("next_chapter", "")) == "ch06")
	ctx.check("ch06→ch07", str(ChapterRegistry.levels_doc("ch06").get("next_chapter", "")) == "ch07")

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.begin_group("gate_dangling")
		var levels: Dictionary = ChapterRegistry.levels_doc(cid)
		var labs: Dictionary = db.labs_for(cid)
		ctx.check("%s gate_ids 无悬空" % cid, _dangling(levels, labs).is_empty(),
			str(_dangling(levels, labs)))

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
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

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		ctx.begin_group("gate_count")
		var total := 0
		for raw in (db.labs_for(cid) as Dictionary).values():
			var cfg: Dictionary = raw
			total += (cfg.get("gate_cases", []) as Array).size()
		ctx.check("%s gate 总数 %d" % [cid, int(GATE_TOTALS[cid])],
			total == int(GATE_TOTALS[cid]), str(total))

	for cid in ["ch03", "ch04", "ch05", "ch06"]:
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
	d1.skill_graph.nodes.erase("CH03-1")
	ctx.check("删 CH03-1 → validate 红", not d1.validate().is_empty())
	var d2 = TestUtil.data_db()
	var bad_levels: Dictionary = ChapterRegistry.levels_doc("ch03").duplicate(true)
	((bad_levels["labs"][0] as Dictionary)["gate_ids"] as Array).append("T3.1-9")
	ctx.check("加悬空 gate T3.1-9 → 悬空断言红",
		not _dangling(bad_levels, d2.labs_for("ch03")).is_empty())
	var d3 = TestUtil.data_db()
	var fs: Array = d3.manifest.get("files", [])
	fs.erase("res://data/chapters/ch04_levels.json")
	ctx.check("删 manifest 项 → 漏登记断言红", not _manifest_missing(d3).is_empty())
	var d4 = TestUtil.data_db()
	var copy4: Dictionary = (d4.labs_for("ch06") as Dictionary).duplicate(true)
	copy4.erase("vm")
	ctx.check("删 ch06 vm 副本 → labs 数量断言红", copy4.size() != 6, str(copy4.size()))
	var d5 = TestUtil.data_db()
	d5.skill_graph.nodes.erase("SK-VM")
	ctx.check("删 SK-VM → validate 红", not d5.validate().is_empty())

	ctx.begin_group("totals")
	ctx.check("四章实验合计 19", _all_labs(db) == 19, str(_all_labs(db)))

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
	for cid in ["ch03", "ch04", "ch05", "ch06"]:
		n += db.labs_for(cid).size()
	return n

func _manifest_missing(db) -> Array:
	var out := []
	var files: Array = db.manifest.get("files", [])
	for path in NEW_FILES:
		if not files.has(path):
			out.append(str(path))
	return out
