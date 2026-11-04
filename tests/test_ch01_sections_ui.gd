extends RefCounted

## 分段课文 UI 层验收（与数据侧 test_ch01_sections.gd 分离，避免同文件冲突）。
## 断言全部从 data/labs/ch01_labs.json 实读，不写死总字数/段数；检查条数与段数无关。

const LABS := ["level", "binary", "boolean", "gate", "signal", "half_adder"]
const Teach = preload("res://src/ui/teaching.gd")
const Reader = preload("res://src/ui/widgets/section_reader.gd")
const Workbench = preload("res://src/ui/screens/workbench_screen.gd")

func run(ctx: TestContext) -> void:
	var db := TestUtil.data_db()
	ctx.check("数据层 loader 无错误", db.errors.is_empty(), str(db.errors))
	var chapter := TestUtil.chapter_doc()
	var cfg := {}
	var total := 0
	var longest := 0
	for id in LABS:
		var c: Dictionary = db.lab_data(str(id))
		cfg[id] = c
		var secs := Teach.section_list(c)
		total += secs.size()
		for s in secs:
			longest = maxi(longest, str(s.get("text", "")).length())
		ctx.check("%s sections 已落地" % id, not secs.is_empty(), str(secs.size()))
		ctx.eq("%s 首段 after=0" % id, int(secs[0].get("after", -1)), 0)
		ctx.eq("%s order 连续 1..n" % id, _orders_ok(secs), true)
		ctx.eq("%s required gate 数与章节 gate_ids 对齐" % id, _required(c), _gate_ids(chapter, str(id)))
	ctx.check("所有段逐段 ≤260 字", longest <= 260, "最长 %d，合计 %d 段" % [longest, total])

	_assert_done_tiers(ctx, cfg)
	_assert_gap_protection(ctx, cfg)
	_assert_all_reachable(ctx, cfg)
	_assert_paging(ctx, cfg)
	_assert_body_fallback(ctx, cfg)
	_assert_rules(ctx, cfg)
	_assert_geometry(ctx, cfg)
	_assert_reader_slot(ctx)
	_assert_workbench_entry(ctx, chapter)
	_assert_shop_meta(ctx)

## 五条主断言之一/二：逐档显示当前段（含 0 gate 首屏与全部完成）。
func _assert_done_tiers(ctx: TestContext, cfg: Dictionary) -> void:
	for id in LABS:
		var secs := Teach.section_list(cfg[id])
		var r = Reader.new()
		r.configure(secs, 14, 16)
		for done in 5:
			r.set_done(done)
			var exp := _last_le(secs, done)
			ctx.eq("%s done=%d 当前段 order" % [id, done], int(r.current().get("order", -1)), int(exp.get("order", -2)))
			ctx.eq("%s done=%d 当前段 after" % [id, done], int(r.current().get("after", -2)), int(exp.get("after", -2)))
			ctx.check("%s done=%d 默认停在已解锁最后一段、无未解锁段" % [id, done],
				r.index == r.unlocked - 1 and r.unlocked == Teach.unlocked_count_sections(secs, done)
				and int(r.current().get("after", 999)) <= done, "idx=%d unlocked=%d" % [r.index, r.unlocked])
			ctx.check("%s done=%d 屏上正文=该段原文" % [id, done],
				Reader.flat_text(r.text_label.text) == _flat(str(exp.get("text", "")))
				and Reader.flat_text(r.text_label.text) != _flat(Teach.teaching_text(cfg[id])),
				"显示与数据段不一致")
			ctx.eq("%s done=%d 翻页标签 i/n" % [id, done], r.count_label.text,
				"%d/%d" % [r.index + 1, r.unlocked])
		r.free()

## 五条主断言之三：某档无段时必须沿用前一档最后一段，绝不留白。
func _assert_gap_protection(ctx: TestContext, cfg: Dictionary) -> void:
	for id in LABS:
		var copy: Dictionary = JSON.parse_string(JSON.stringify(cfg[id]))
		var kept: Array = []
		for raw in copy.get("sections", []):
			var s: Dictionary = raw
			if int(s.get("after", 0)) != 2:
				kept.append(s)
		copy["sections"] = kept
		var secs := Teach.section_list(copy)
		var prev := _last_le(secs, 1)
		var r = Reader.new()
		r.configure(secs, 14, 16)
		r.set_done(2)
		ctx.check("%s 删掉 after=2 整档后仍显示前一档最后一段" % id,
			not r.current().is_empty() and int(r.current().get("after", -1)) == int(prev.get("after", -2))
			and Reader.flat_text(r.text_label.text) == _flat(str(prev.get("text", ""))),
			"实际 after=%d" % int(r.current().get("after", -1)))
		r.free()

## 五条主断言之一（反向）：33 段逐段都能翻回去，且屏上文字与数据一致。
func _assert_all_reachable(ctx: TestContext, cfg: Dictionary) -> void:
	var ok := true
	var detail := ""
	for id in LABS:
		var secs := Teach.section_list(cfg[id])
		var r = Reader.new()
		r.configure(secs, 14, 16)
		r.set_done(4)
		var seen := {r.index: Reader.flat_text(r.text_label.text)}
		var guard := 0
		while r.flip(-1) and guard < 200:
			seen[r.index] = Reader.flat_text(r.text_label.text)
			guard += 1
		for i in secs.size():
			if not seen.has(i) or seen[i] != _flat(str(secs[i].get("text", ""))):
				ok = false
				detail = "%s[%d]" % [id, i + 1]
				break
		r.free()
		if not ok:
			break
	ctx.check("每一段都可回看到且屏上文字一致", ok, detail)

## 五条主断言之四/五：已解锁可来回翻，未解锁不可达。
func _assert_paging(ctx: TestContext, cfg: Dictionary) -> void:
	for id in LABS:
		var secs := Teach.section_list(cfg[id])
		var r = Reader.new()
		r.configure(secs, 14, 16)
		r.set_done(4)
		ctx.check("%s 最新段 next 灰化、prev 可翻" % id, r.next_btn.disabled and not r.prev_btn.disabled)
		var walked := true
		while r.index > 0:
			walked = r.flip(-1) and walked
		ctx.check("%s 翻到首段：prev 灰化、next 可翻" % id,
			walked and r.prev_btn.disabled and not r.next_btn.disabled)
		ctx.check("%s 首段再往前不可达" % id, not r.flip(-1))
		r.set_done(0)
		ctx.check("%s 未解锁段不可达（末段再往后翻失败）" % id, not r.flip(1) and r.next_btn.disabled)
		r.free()

## 五条主断言之六：sections 缺失时 body 兜底单段仍可用。
func _assert_body_fallback(ctx: TestContext, cfg: Dictionary) -> void:
	for id in LABS:
		var copy: Dictionary = JSON.parse_string(JSON.stringify(cfg[id]))
		copy.erase("sections")
		var secs := Teach.section_list(copy)
		ctx.check("%s 无 sections 时退回单段" % id, secs.size() == 1, str(secs.size()))
		var r = Reader.new()
		r.configure(secs, 14, 16)
		r.set_done(4)
		ctx.eq("%s 兜底正文=body(+rules)" % id, Reader.flat_text(r.text_label.text),
			_flat(Teach.teaching_text(copy)))
		ctx.check("%s 兜底翻页 1/1 且双箭头灰化" % id,
			r.count_label.text == "1/1" and r.prev_btn.disabled and r.next_btn.disabled)
		r.free()

## rules 不单独成块：有 sections 时只作为课文卡附注，且只挂在首段（避免与讲阈值来源的正文段同屏重复）。
func _assert_rules(ctx: TestContext, cfg: Dictionary) -> void:
	var lvl: Dictionary = cfg["level"]
	var secs := Teach.section_list(lvl)
	var note := Teach.rules_note(lvl)
	ctx.check("level 有 rules 可作附注", not note.is_empty(), note)
	var r = Reader.new()
	r.configure(secs, 14, 16, false, note, 1)
	r.set_done(4)
	ctx.check("附注内容=完整 rules（信息不丢）", Reader.flat_text(r.note_label.text) == _flat(note))
	var all_keep := true
	for raw in lvl.get("rules", []):
		var rule := _flat(str(raw))
		if not rule.is_empty() and Reader.flat_text(r.note_label.text).find(rule) < 0:
			all_keep = false
	ctx.check("每条规则都保留在附注里", all_keep)
	var idx1 := _index_of_order(secs, 1)
	ctx.check("首段（固定小注）附注显形", idx1 >= 0 and _note_visible(r, idx1))
	var idx3 := _index_of_order(secs, 3)
	ctx.check("讲阈值来源的 order 3 不再重复渲染附注", idx3 >= 0 and not _note_visible(r, idx3))
	var idx5 := _index_of_order(secs, secs.size())
	ctx.check("其他段附注隐藏（只有一处渲染）", idx5 >= 0 and not _note_visible(r, idx5))
	ctx.check("正文段不含 rules 整块文本", Reader.flat_text(r.text_label.text) != _flat(note))
	r.free()

## 几何硬线：课文不缩字号、不在卡内滚动，只能靠卡高固定；卡高必须给控件区留出滚动空间。
## 左栏可用 544（内容区），阅读卡 + 6 间距后余量即控件滚动区高度。
func _assert_geometry(ctx: TestContext, cfg: Dictionary) -> void:
	for id in ["level", "binary", "boolean", "signal", "half_adder"]:
		var secs := Teach.section_list(cfg[id])
		var note := Teach.rules_note(cfg[id]) if Teach.has_sections(cfg[id]) else ""
		var r = Reader.new()
		r.configure(secs, 14, 16, false, note, 1 if not note.is_empty() else 0)
		var worst := 0.0
		var worst_order := 0
		for i in secs.size():
			r.set_index(i)
			var h := float(r.get_combined_minimum_size().y)
			if h > worst:
				worst = h
				worst_order = int((secs[i] as Dictionary).get("order", 0))
		ctx.check("%s 最长段阅读卡 ≤538（544 内容区留 6 给控件滚动）" % id, worst <= 538.0,
			"最坏 order=%d 卡高 %.0f，控件滚动余量 %.0f" % [worst_order, worst, 544.0 - 6.0 - worst])
		r.free()
	var g := Reader.new()
	g.configure(Teach.section_list(cfg["gate"]), 40, 16, true)
	var gw := 0.0
	for i in g.sections.size():
		g.set_index(i)
		gw = maxf(gw, float(g.get_combined_minimum_size().y))
	ctx.check("gate 中栏讲解带 ≤178（目标条 46 + 调色板 44 + 画布 258 + 间距 18 后合计 ≤544）", gw <= 178.0,
		"带高 %.0f" % gw)
	ctx.check("gate 中栏合计 ≤544", 46.0 + 44.0 + 258.0 + 18.0 + gw <= 544.0,
		"合计 %.0f" % (46.0 + 44.0 + 258.0 + 18.0 + gw))
	g.free()

## 阅读卡在滚动区之外（控件滚动时课文卡固定）。
func _assert_reader_slot(ctx: TestContext) -> void:
	var src := FileAccess.get_file_as_string("res://src/ui/screens/lab_base.gd")
	var i_slot := src.find("side_outer.add_child(_reader_slot)")
	var i_scroll := src.find("side_outer.add_child(_side_scroll)")
	var i_side := src.find("_side_scroll.add_child(side)")
	ctx.check("阅读槽与控件滚动区并列、控件在滚动区内",
		i_slot >= 0 and i_scroll > i_slot and i_side > i_scroll,
		"%d/%d/%d" % [i_slot, i_scroll, i_side])

## 实验室入口兜底：章末 6/6 完成（next_objective 为空）时必须进 1.6。
func _assert_workbench_entry(ctx: TestContext, chapter: Dictionary) -> void:
	var order: Array = []
	var last_id := ""
	var last_title := ""
	for raw in chapter.get("labs", []):
		var l: Dictionary = raw
		last_id = str(l.get("data_key", ""))
		last_title = str(l.get("title", ""))
		order.append(last_id)
	var all_unlocked := {}
	for lid in order:
		all_unlocked[str(lid)] = true
	ctx.eq("章末无目标时入口回落到最后一节", Workbench.resolve_entry_lab("", order, all_unlocked), last_id)
	ctx.check("最后一节就是 1.6", last_title.begins_with("1.6"), last_title)
	ctx.eq("没有任何可用 lab 时入口为空（必须给反馈而非静默）", Workbench.resolve_entry_lab("", order, {}), "")
	ctx.eq("有当前目标时不被回落覆盖", Workbench.resolve_entry_lab("gate", order, all_unlocked), "gate")
	var paths: Dictionary = Workbench.LAB_PATHS
	ctx.check("回落目标在 LAB_PATHS 内（点下去真的能打开页面）",
		paths.has(Workbench.resolve_entry_lab("", order, all_unlocked)), str(paths.keys()))
	var src := FileAccess.get_file_as_string("res://src/ui/screens/workbench_screen.gd")
	ctx.check("无目标时实验室按钮灰化并给 tooltip（不是能点没反应）",
		src.find("_update_rail_lock(\"labs\", entry.is_empty())") >= 0
		and src.find("本章还没有可进入的实验") >= 0)

## 商店 hover_tween 默认值：不得再用 null（Godot 4.4 会当成没给默认值而报错）。
func _assert_shop_meta(ctx: TestContext) -> void:
	var bad: Array = []
	_scan_meta_null("res://src/ui", bad)
	ctx.check("src/ui 内无 get_meta(..., null) 残留", bad.is_empty(), str(bad))
	var probe := Control.new()
	ctx.eq("行未 set_meta 时取 hover_tween 返回非 null 默认值", probe.get_meta("hover_tween", false), false)
	probe.free()
	var shop := FileAccess.get_file_as_string("res://src/ui/screens/shop_screen.gd")
	ctx.check("shop_screen 两处 hover_tween 默认值均为 false", _count(shop, "get_meta(\"hover_tween\", false)") >= 2,
		str(_count(shop, "get_meta(\"hover_tween\", false)")))
	ctx.check("kill 前先判 is Tween（默认 false 时不会误调用）",
		shop.find("if old is Tween") >= 0 and shop.find("if tw is Tween") >= 0)

# ---------------------------------------------------------------- helpers
func _required(cfg: Dictionary) -> int:
	var n := 0
	for raw in cfg.get("gate_cases", []):
		if bool((raw as Dictionary).get("required", true)):
			n += 1
	return n

func _gate_ids(chapter: Dictionary, data_key: String) -> int:
	for raw in chapter.get("labs", []):
		var l: Dictionary = raw
		if str(l.get("data_key", "")) == data_key:
			return (l.get("gate_ids", []) as Array).size()
	return -1

func _orders_ok(secs: Array) -> bool:
	for i in secs.size():
		if int((secs[i] as Dictionary).get("order", -1)) != i + 1:
			return false
	return true

## after ≤ done 的最后一段（返回带原下标的副本）。
func _last_le(secs: Array, done: int) -> Dictionary:
	var out := {}
	for i in secs.size():
		var s: Dictionary = secs[i]
		if int(s.get("after", 0)) <= done:
			out = {"index": i, "order": int(s.get("order", -1)), "after": int(s.get("after", -1)), "text": str(s.get("text", ""))}
	return out

func _flat(s: String) -> String:
	return Reader.flat_text(s)

func _count(src: String, needle: String) -> int:
	var n := 0
	var at := src.find(needle)
	while at >= 0:
		n += 1
		at = src.find(needle, at + needle.length())
	return n

func _index_of_order(secs: Array, order: int) -> int:
	for i in secs.size():
		if int((secs[i] as Dictionary).get("order", -1)) == order:
			return i
	return -1

func _note_visible(r, i: int) -> bool:
	r.set_index(i)
	return r.note_label != null and r.note_label.visible

func _scan_meta_null(path: String, out: Array) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var p := path.path_join(f)
		if d.current_is_dir():
			_scan_meta_null(p, out)
		elif f.ends_with(".gd"):
			var src := FileAccess.get_file_as_string(p)
			# Godot 4.4 把 get_meta(key, null) 当成「没给默认值」，key 不存在即报错。
			for line in src.split("\n"):
				if line.find("get_meta(") >= 0 and line.find(", null)") >= 0:
					out.append("%s:%s" % [p, line.strip_edges()])
					break
		f = d.get_next()
	d.list_dir_end()
