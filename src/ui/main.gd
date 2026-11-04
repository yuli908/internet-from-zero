extends Control

## 主界面外壳：顶栏、导航、内容宿主、页脚、提示与引导浮层。
## 命令行：--shot=<png> [--shot-screen=workbench|shop|skills|archive|diagnostics] [--shot-lab=<id>] [--fresh]

const SCREEN_SCRIPTS := {
	"workbench": preload("res://src/ui/screens/workbench_screen.gd"),
	"skills": preload("res://src/ui/screens/skill_screen.gd"),
	"shop": preload("res://src/ui/screens/shop_screen.gd"),
	"archive": preload("res://src/ui/screens/archive_screen.gd"),
	"diagnostics": preload("res://src/ui/screens/diagnostics_screen.gd"),
}

const NAV_ITEMS := [
	{"id": "workbench", "label": "工作台", "hint": "章节实验"},
	{"id": "skills", "label": "知识树", "hint": "解锁与技能"},
	{"id": "shop", "label": "商店", "hint": "元件与合成"},
	{"id": "archive", "label": "档案", "hint": "存档管理"},
	{"id": "diagnostics", "label": "诊断", "hint": "自检与数据"},
]

var _screens: Dictionary = {}
var _nav_buttons: Dictionary = {}
var _current := ""
var _host: MarginContainer
var _page: VBoxContainer
var _status_label: Label
var _stat_gold: Label
var _stat_xp: Label
var _stat_knowledge: Label
var _stat_level: Label
var _chapter_label: Label
var _toast_box: VBoxContainer
var _tutorial_panel: PanelContainer
var _tutorial_title: Label
var _tutorial_text: Label
var _tutorial_count: Label

func _ready() -> void:
	theme = UiTheme.build()
	_build()
	_connect_events()
	GameState.boot()
	_refresh_all()
	_refresh_tutorial()
	_show_screen("workbench")
	print("IFZ_BOOT data_ok=%s files=%d chapter=%s" % [str(DataDB.ready_ok), DataDB.loaded_files, DataDB.chapter_id()])
	if not DataDB.ready_ok:
		EventBus.toast("数据校验有 %d 个问题，见诊断页" % DataDB.errors.size(), "error")
	_handle_cli()

func _connect_events() -> void:
	EventBus.notify.connect(_on_notify)
	EventBus.state_changed.connect(_refresh_all)
	EventBus.tutorial_updated.connect(func(_step): _refresh_tutorial())
	EventBus.chapter_completed.connect(func(_id): _refresh_all())

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var root_margin := Ui.margin4(18, 14, 18, 12)
	root_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(root_margin)

	var page := Ui.vbox(10)
	_page = page
	root_margin.add_child(page)

	page.add_child(_build_header())
	page.add_child(_build_tutorial())

	var body := Ui.hbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)
	body.add_child(_build_sidebar())

	var content_panel := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 10)
	content_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(content_panel)
	_host = Ui.margin4(16, 14, 16, 14)
	content_panel.add_child(_host)

	page.add_child(_build_footer())

	_build_toasts()

func _build_header() -> PanelContainer:
	var header := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 10)
	var m := Ui.margin4(16, 10, 16, 10)
	header.add_child(m)
	var row := Ui.hbox(14)
	m.add_child(row)

	var brand := Ui.vbox(2)
	brand.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	row.add_child(brand)
	brand.add_child(Ui.label("互联网 · 从零重建", 21, UiTheme.TEXT))
	brand.add_child(Ui.label("INTERNET FROM ZERO", 10, UiTheme.MUTED))
	row.add_child(Ui.spacer())

	var stats := Ui.hbox(18)
	stats.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(stats)
	stats.add_child(Ui.stat("金币", "0", UiTheme.AMBER))
	_stat_gold = stats.get_child(stats.get_child_count() - 1).get_child(1)
	stats.add_child(Ui.stat("等级", "Lv 1", UiTheme.ACCENT))
	_stat_level = stats.get_child(stats.get_child_count() - 1).get_child(1)
	stats.add_child(Ui.stat("经验", "0", UiTheme.OK))
	_stat_xp = stats.get_child(stats.get_child_count() - 1).get_child(1)
	stats.add_child(Ui.stat("知识", "0/0", UiTheme.TEXT))
	_stat_knowledge = stats.get_child(stats.get_child_count() - 1).get_child(1)

	var actions := Ui.hbox(8)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)
	actions.add_child(Ui.button("保存", func(): SaveManager.save_game(1), true))
	actions.add_child(Ui.button("读取", func(): SaveManager.load_game(1)))
	return header

func _build_sidebar() -> PanelContainer:
	var side := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 10)
	side.custom_minimum_size = Vector2(198, 0)
	side.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var m := Ui.margin4(12, 14, 12, 12)
	side.add_child(m)
	var col := Ui.vbox(6)
	m.add_child(col)

	col.add_child(Ui.label("导航", 11, UiTheme.MUTED))
	var group := ButtonGroup.new()
	for item in NAV_ITEMS:
		var b := Ui.button(str(item["label"]), func(): _show_screen(str(item["id"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = Vector2(0, 40)
		col.add_child(b)
		_nav_buttons[str(item["id"])] = b
		var tip := Ui.label("  " + str(item["hint"]), 10, UiTheme.MUTED)
		col.add_child(tip)

	col.add_child(Ui.spacer())
	col.add_child(Ui.hline())
	col.add_child(Ui.gap(6))
	var d1 := Ui.label("数据 v%d · %d 文件" % [DataDB.data_version, DataDB.loaded_files], 10, UiTheme.MUTED)
	var d2 := Ui.label("存档目录 user://saves", 10, UiTheme.MUTED)
	var d3 := Ui.label("Godot 4.4.1 · GDScript", 10, UiTheme.MUTED)
	d1.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	d2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(d1)
	col.add_child(d2)
	col.add_child(d3)
	return side

func _build_footer() -> HBoxContainer:
	var footer := Ui.hbox(10)
	footer.custom_minimum_size = Vector2(0, 22)
	_status_label = Ui.label("就绪", 11, UiTheme.MUTED)
	footer.add_child(_status_label)
	footer.add_child(Ui.spacer())
	footer.add_child(Ui.label("F5 保存 · F9 读取 · 自动存档开启", 10, UiTheme.MUTED))
	return footer

func _build_toasts() -> void:
	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.anchor_left = 1.0
	_toast_box.anchor_right = 1.0
	_toast_box.anchor_top = 0.0
	_toast_box.anchor_bottom = 0.0
	_toast_box.offset_left = -420
	_toast_box.offset_right = -22
	_toast_box.offset_top = 104
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)

func _build_tutorial() -> PanelContainer:
	## 引导条固定在标题栏下方的正常文档流里，不再浮在实验区上方遮挡操作。
	_tutorial_panel = Ui.card(UiTheme.PANEL_2, UiTheme.ACCENT, 8)
	var m := Ui.margin4(14, 8, 14, 8)
	_tutorial_panel.add_child(m)
	var row := Ui.hbox(12)
	m.add_child(row)
	_tutorial_count = Ui.label("引导 1/6", 10, UiTheme.ACCENT)
	_tutorial_count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tutorial_count)
	_tutorial_title = Ui.label("", 15, UiTheme.TEXT)
	_tutorial_title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tutorial_title)
	_tutorial_text = Ui.label("", 12, UiTheme.MUTED)
	_tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tutorial_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tutorial_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_tutorial_text)
	var close := Ui.ghost("稍后", func(): _tutorial_panel.visible = false)
	close.custom_minimum_size = Vector2(60, 26)
	row.add_child(close)
	row.add_child(Ui.button("知道了", func(): Tutorial.acknowledge(), true))
	_tutorial_panel.visible = false
	return _tutorial_panel

func _refresh_all() -> void:
	var p := GameState.player
	if p == null:
		return
	_stat_gold.text = str(p.gold)
	_stat_level.text = "Lv %d" % p.level()
	if p.xp_for_next_level() > 0:
		_stat_xp.text = "%d / %d" % [p.xp_into_level(), p.xp_for_next_level()]
	else:
		_stat_xp.text = str(p.xp)
	var kp := Knowledge.progress()
	_stat_knowledge.text = "%d / %d" % [int(kp.get("done", 0)), int(kp.get("total", 0))]
	var cp := ChapterFlow.progress()
	if _status_label != null:
		_status_label.text = "章节进度 %d/%d · %s" % [int(cp.get("done", 0)), int(cp.get("total", 0)), SaveManager.last_message if not SaveManager.last_message.is_empty() else "就绪"]

func _refresh_tutorial() -> void:
	if _tutorial_panel == null:
		return
	var step := Tutorial.current_step()
	if step.is_empty():
		_tutorial_panel.visible = false
		return
	_tutorial_panel.visible = true
	var prog := Tutorial.progress()
	_tutorial_count.text = "引导 %d/%d" % [int(prog.get("done", 0)) + 1, int(prog.get("total", 0))]
	_tutorial_title.text = str(step.get("title", ""))
	_tutorial_text.text = str(step.get("text", ""))

func _on_notify(text: String, kind: String) -> void:
	var color := UiTheme.ACCENT
	if kind == "ok":
		color = UiTheme.OK
	elif kind == "warn":
		color = UiTheme.AMBER
	elif kind == "error":
		color = UiTheme.DANGER
	var card := Ui.card(UiTheme.PANEL_2, color, 8)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	var m := Ui.margin4(12, 7, 12, 7)
	card.add_child(m)
	var l := Ui.label(text, 12, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(320, 0)
	card.custom_minimum_size = Vector2(360, 0)
	m.add_child(l)
	_toast_box.add_child(card)
	var tw := create_tween()
	tw.tween_interval(2.4)
	tw.tween_property(card, "modulate:a", 0.0, 0.5)
	tw.tween_callback(card.queue_free)

func _show_screen(id: String, announce: bool = true) -> void:
	if not SCREEN_SCRIPTS.has(id):
		return
	if not _screens.has(id):
		var script: Script = SCREEN_SCRIPTS[id]
		var screen: GameScreen = script.new()
		screen.setup(self)
		_host.add_child(screen)
		_screens[id] = screen
	for key in _screens.keys():
		_screens[key].visible = str(key) == id
	_current = id
	if _nav_buttons.has(id):
		_nav_buttons[id].set_pressed_no_signal(true)
	var screen: GameScreen = _screens[id]
	screen.on_show()
	if announce:
		EventBus.screen_changed.emit(id)

func show_lab(lab_id: String) -> void:
	_show_screen("workbench")
	if _screens.has("workbench"):
		_screens["workbench"].select_lab(lab_id, true)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F5:
			SaveManager.save_game(1)
		elif event.keycode == KEY_F9:
			SaveManager.load_game(1)

func _handle_cli() -> void:
	var walk := CliArgs.value("walkthrough", "")
	if not walk.is_empty():
		_run_walkthrough(walk)
		return
	var verify := CliArgs.value("verify-walkthrough", "")
	if not verify.is_empty():
		_verify_walkthrough(verify)
		return
	var shot := CliArgs.value("shot", "")
	if shot.is_empty():
		return
	var screen_id := CliArgs.value("shot-screen", "workbench")
	var lab_id := CliArgs.value("shot-lab", "")
	_show_screen(screen_id, false)
	if not lab_id.is_empty() and _screens.has("workbench"):
		_screens["workbench"].select_lab(lab_id, false)
	for i in 3:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot)
	print("SHOT_SAVED=%s err=%d size=%dx%d" % [shot, err, img.get_width(), img.get_height()])
	get_tree().quit(0 if err == OK else 1)

# ---- 6 节脚本走查（--walkthrough / --verify-walkthrough） --------------------

func _run_walkthrough(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var wb: WorkbenchScreen = _screens.get("workbench", null)
	_show_screen("workbench", false)
	var p := GameState.player
	var fails: Array = []
	var checks := 0
	var labs: Dictionary = {}
	for raw_id in DataDB.chapter.lab_order:
		var lid := str(raw_id)
		var meta: Dictionary = DataDB.chapter.lab(lid)
		var gold_before := p.gold
		var xp_before := p.xp
		var inv_before := _inv_signature(p.inventory)
		var chapter_before := ChapterFlow.chapter_complete()
		wb.select_lab(lid, false)
		for i in 2:
			await get_tree().process_frame
		var page := wb.page_for(lid)
		var solved := false
		if page == null:
			fails.append("%s: 实验页缺失" % lid)
		else:
			solved = page.scripted_solve()
			if not solved:
				fails.append("%s: scripted_solve 未通过" % lid)
		var obj := str(meta.get("objective", ""))
		if not ChapterFlow.is_objective_done(obj):
			fails.append("%s: 目标 %s 未完成" % [lid, obj])
		var gates_total := 0
		var gates: Dictionary = {}
		for raw_g in meta.get("gate_ids", []):
			var gid := str(raw_g)
			var ok := p.has_flag("gate:%s" % gid)
			gates[gid] = ok
			gates_total += 1
			if not ok:
				fails.append("%s: gate %s 未记账" % [lid, gid])
		var exp := _expected_reward(meta)
		var chapter_done := false
		if not chapter_before and ChapterFlow.chapter_complete():
			# 最后一节同时触发章节结算：complete_reward + 章节里程碑节点奖励。
			var fin := _chapter_completion_reward()
			exp["gold"] = int(exp.get("gold", 0)) + int(fin.get("gold", 0))
			exp["xp"] = int(exp.get("xp", 0)) + int(fin.get("xp", 0))
			chapter_done = true
		var dg := p.gold - gold_before
		var dx := p.xp - xp_before
		if dg != int(exp.get("gold", 0)):
			fails.append("%s: 金币 +%d，期望 +%d" % [lid, dg, int(exp.get("gold", 0))])
		if dx != int(exp.get("xp", 0)):
			fails.append("%s: XP +%d，期望 +%d" % [lid, dx, int(exp.get("xp", 0))])
		if _inv_signature(p.inventory) != inv_before:
			fails.append("%s: 物品发生未定义变化（数据里没有物品奖励）" % lid)
		labs[lid] = {
			"objective": obj, "solved": solved,
			"gold_before": gold_before, "gold_after": p.gold,
			"xp_before": xp_before, "xp_after": p.xp,
			"expected_gold": int(exp.get("gold", 0)), "expected_xp": int(exp.get("xp", 0)),
			"gates": gates, "inventory_after": _inv_signature(p.inventory),
			"chapter_completion": chapter_done,
		}
		checks += 8 + gates_total
		EventBus.fire("state_changed")
	SaveManager.save_game(1)
	var final := _final_snapshot()
	var snap := {
		"ok": fails.is_empty(), "checks": checks,
		"failures": fails, "labs": labs, "final": final,
		"item_rewards_defined": false,
	}
	_write_json(path, snap)
	print("WALKTHROUGH_DONE checks=%d failures=%d path=%s" % [checks, fails.size(), path])
	for f in fails:
		print("WALKTHROUGH_FAIL %s" % f)
	get_tree().quit(0 if fails.is_empty() else 1)

func _expected_reward(meta: Dictionary) -> Dictionary:
	var reward: Dictionary = meta.get("reward", {})
	var gold := int(reward.get("gold", 0))
	var xp := int(reward.get("xp", 0))
	var ids: Array = []
	for key in ["knowledge", "milestone", "skill_node"]:
		var v := str(meta.get(key, ""))
		if not v.is_empty():
			ids.append(v)
	ids += meta.get("knowledge_cards", [])
	ids += meta.get("skill_nodes", [])
	var seen: Dictionary = {}
	for raw in ids:
		var id := str(raw)
		if seen.has(id):
			continue
		seen[id] = true
		var n: Dictionary = DataDB.skill_graph.node(id)
		gold += int(n.get("gold_award", 0))
		xp += int(n.get("xp_award", 0)) - int(n.get("xp_cost", 0))
	return {"gold": gold, "xp": xp}

func _inv_signature(inv: Dictionary) -> String:
	## 存档 JSON 往返会把整数读成浮点，物品数量统一按整数比较。
	var keys := inv.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s:%d" % [str(k), int(inv[k])])
	return ",".join(PackedStringArray(parts))

func _chapter_completion_reward() -> Dictionary:
	## 章节完成时的两笔结算：complete_reward + 章节里程碑节点（ChapterFlow._finish_chapter 解锁 CH01）。
	var fin: Dictionary = DataDB.chapter.data.get("complete_reward", {})
	var gold := int(fin.get("gold", 0))
	var xp := int(fin.get("xp", 0))
	var n: Dictionary = DataDB.skill_graph.node("CH01")
	gold += int(n.get("gold_award", 0))
	xp += int(n.get("xp_award", 0))
	return {"gold": gold, "xp": xp}

func _final_snapshot() -> Dictionary:
	var p := GameState.player
	var objs: Dictionary = {}
	for raw_oid in DataDB.chapter.objective_order:
		var oid := str(raw_oid)
		objs[oid] = ChapterFlow.is_objective_done(oid)
	var gates: Dictionary = {}
	for raw_lab in DataDB.chapter.labs.values():
		var lab: Dictionary = raw_lab
		for raw_g in lab.get("gate_ids", []):
			var gid := str(raw_g)
			gates[gid] = p.has_flag("gate:%s" % gid)
	var ks: Array = p.knowledge.keys()
	ks.sort()
	return {
		"gold": p.gold, "xp": p.xp, "level": p.level(),
		"inventory": _inv_signature(p.inventory),
		"knowledge": ks, "objectives": objs, "gates": gates,
		"chapter_complete": ChapterFlow.chapter_complete(),
	}

func _verify_walkthrough(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var txt := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		print("WALKTHROUGH_VERIFY_FAIL 快照不可读：%s" % path)
		get_tree().quit(1)
		return
	var snap: Dictionary = parsed
	var f: Dictionary = snap.get("final", {})
	var p := GameState.player
	var errs: Array = []
	if p.gold != int(f.get("gold", -1)):
		errs.append("gold %d != %d" % [p.gold, int(f.get("gold", -1))])
	if p.xp != int(f.get("xp", -1)):
		errs.append("xp %d != %d" % [p.xp, int(f.get("xp", -1))])
	if p.level() != int(f.get("level", -1)):
		errs.append("level %d != %d" % [p.level(), int(f.get("level", -1))])
	if _inv_signature(p.inventory) != str(f.get("inventory", "")):
		errs.append("inventory 不一致：%s vs %s" % [_inv_signature(p.inventory), str(f.get("inventory", ""))])
	var ks: Array = p.knowledge.keys()
	ks.sort()
	if JSON.stringify(ks) != JSON.stringify(f.get("knowledge", [])):
		errs.append("knowledge 不一致")
	for raw_oid in DataDB.chapter.objective_order:
		var oid := str(raw_oid)
		var want := bool((f.get("objectives", {}) as Dictionary).get(oid, false))
		if ChapterFlow.is_objective_done(oid) != want:
			errs.append("objective %s 不一致" % oid)
	for key in (f.get("gates", {}) as Dictionary).keys():
		var gid := str(key)
		if p.has_flag("gate:%s" % gid) != bool((f.get("gates", {}) as Dictionary)[key]):
			errs.append("gate %s 不一致" % gid)
	if ChapterFlow.chapter_complete() != bool(f.get("chapter_complete", false)):
		errs.append("chapter_complete 不一致")
	print("WALKTHROUGH_VERIFY_%s checks=%d failures=%d" % ["OK" if errs.is_empty() else "FAIL", 6 + DataDB.chapter.objectives.size() + (f.get("gates", {}) as Dictionary).size(), errs.size()])
	for e in errs:
		print("WALKTHROUGH_VERIFY_FAIL %s" % e)
	get_tree().quit(0 if errs.is_empty() else 1)

func _write_json(path: String, data: Dictionary) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		print("WALKTHROUGH_FAIL 无法写快照 %s" % path)
		return
	f.store_string(JSON.stringify(data, "  "))
	f.close()
