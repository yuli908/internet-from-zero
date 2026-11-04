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
	_assert_duplicate_after(ctx, cfg)
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

## 同一档出现两段时：默认停在已解锁末段（后一段），回翻能看到前一段。
func _assert_duplicate_after(ctx: TestContext, cfg: Dictionary) -> void:
	var ok_default := true
	var ok_back := true
	var detail := ""
	for id in LABS:
		var secs := Teach.section_list(cfg[id])
		if secs.is_empty():
			continue
		var max_after := 0
		for raw in secs:
			max_after = maxi(max_after, int((raw as Dictionary).get("after", 0)))
		var n_at := 0
		for raw in secs:
			if int((raw as Dictionary).get("after", 0)) == max_after:
				n_at += 1
		if n_at < 2:
			continue
		var r = Reader.new()
		r.configure(secs, 14, 16)
		r.set_done(max_after)
		if r.index != secs.size() - 1 or int(r.current().get("after", -1)) != max_after:
			ok_default = false
			detail = "%s 默认 idx=%d" % [id, r.index]
		var second := Reader.flat_text(r.text_label.text)
		if not r.flip(-1) or r.index != secs.size() - 2 or int(r.current().get("after", -1)) != max_after:
			ok_back = false
			detail = "%s 回翻 idx=%d" % [id, r.index]
		if Reader.flat_text(r.text_label.text) == second:
			ok_back = false
			detail = "%s 回翻文字未变" % id
		r.free()
	ctx.check("after 重复档：done=末档默认显示后一段", ok_default, detail)
	ctx.check("after 重复档：回翻能看到同一档的前一段", ok_back, detail)

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

## 五条主断言之一（反向）：每一段都能翻回去，且屏上文字与数据一致（段数实读）。
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

## rules 与 sections 去重：有 sections 时一律不渲染 rules；只有删掉 sections 的副本才兜底出现。
func _assert_rules(ctx: TestContext, cfg: Dictionary) -> void:
	for id in LABS:
		var secs := Teach.section_list(cfg[id])
		var note := Teach.fallback_note(cfg[id])
		var r = Reader.new()
		r.configure(secs, 14, 16, false, note, 0)
		r.set_done(4)
		var note_flat: String = Reader.flat_text(r.note_label.text) if r.note_label != null else ""
		var note_shown: bool = r.note_label != null and r.note_label.visible
		ctx.check("%s 有 sections 时不渲染 rules（附注为空）" % id,
			note.is_empty() and note_flat.is_empty() and not note_shown,
			"note=%d 字" % note_flat.length())
		r.free()
	var copy: Dictionary = JSON.parse_string(JSON.stringify(cfg["level"]))
	copy.erase("sections")
	var rules := Teach.rules_note(copy)
	var fb := Teach.fallback_note(copy)
	ctx.check("删掉 sections 后 rules 作为兜底出现", not fb.is_empty() and fb == rules, fb)
	var fr = Reader.new()
	fr.configure(Teach.section_list(copy), 14, 16, false, fb, 0)
	fr.set_done(4)
	ctx.check("兜底附注保留完整 rules（信息不丢）", Reader.flat_text(fr.note_label.text) == _flat(rules))
	var all_keep := true
	for raw in copy.get("rules", []):
		var line := _flat(str(raw))
		if not line.is_empty() and Reader.flat_text(fr.note_label.text).find(line) < 0:
			all_keep = false
	ctx.check("兜底附注逐条保留每条规则", all_keep)
	ctx.check("兜底附注在唯一段落上可见", _note_visible(fr, 0))
	fr.free()
	var src := FileAccess.get_file_as_string("res://src/ui/screens/lab_base.gd")
	ctx.check("UI 侧用同一 fallback_note 决定 rules 去留", src.find("Teach.fallback_note(lab_data)") >= 0)

## 几何硬线：课文不缩字号、不在卡内滚动；任何可达状态下控件滚动区 ≥80 px。
## 左栏 544 = 阅读卡 + 6 间距 + 控件滚动区 → 卡高上限 544-6-80 = 458。
func _assert_geometry(ctx: TestContext, cfg: Dictionary) -> void:
	var card_cap := 544.0 - 6.0 - 80.0
	for id in ["level", "binary", "boolean", "signal", "half_adder"]:
		var secs := Teach.section_list(cfg[id])
		var worst := 0.0
		var worst_order := 0
		for i in secs.size():
			# 每段新建一个实例：容器的最小尺寸缓存只在首次计算时读取当前文本，
			# 同一实例连续 set_index 会读到旧缓存（headless 下没有帧来刷新布局）。
			var r = Reader.new()
			Engine.get_main_loop().root.add_child(r)
			r.configure(secs, 14, 16, false, Teach.fallback_note(cfg[id]), 0)
			r.set_done(4)
			r.set_index(i)
			var h := float(r.get_combined_minimum_size().y)
			if h > worst:
				worst = h
				worst_order = int((secs[i] as Dictionary).get("order", 0))
			r.free()
		ctx.check("%s 每一段阅读卡 ≤458（控件滚动区 ≥80）" % id, worst <= card_cap,
			"最坏 order=%d 卡高 %.0f，控件滚动区 %.0f" % [worst_order, worst, 544.0 - 6.0 - worst])
	var gw := 0.0
	for i in Teach.section_list(cfg["gate"]).size():
		var g = Reader.new()
		Engine.get_main_loop().root.add_child(g)
		g.configure(Teach.section_list(cfg["gate"]), 40, 16, true)
		g.set_done(4)
		g.set_index(i)
		gw = maxf(gw, float(g.get_combined_minimum_size().y))
		g.free()
	ctx.check("gate 中栏讲解带 ≤178（目标条 46 + 调色板 44 + 画布 258 + 间距 18 后合计 ≤544）", gw <= 178.0,
		"带高 %.0f" % gw)
	ctx.check("gate 中栏合计 ≤544", 46.0 + 44.0 + 258.0 + 18.0 + gw <= 544.0,
		"合计 %.0f" % (46.0 + 44.0 + 258.0 + 18.0 + gw))

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
