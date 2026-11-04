extends Control

## 主外壳：开始界面 ↔ 黑板 Hub ↔ 二级页（实验室/商店/知识树/档案/诊断）。
## 命令行：--shot=<png> [--shot-screen=start|workbench|shop|skills|archive|diagnostics] [--shot-lab=<id>] [--fresh]

const SCREEN_SCRIPTS := {
	"workbench": preload("res://src/ui/screens/workbench_screen.gd"),
	"skills": preload("res://src/ui/screens/skill_screen.gd"),
	"shop": preload("res://src/ui/screens/shop_screen.gd"),
	"archive": preload("res://src/ui/screens/archive_screen.gd"),
	"diagnostics": preload("res://src/ui/screens/diagnostics_screen.gd"),
	"laboratory": preload("res://src/ui/screens/laboratory_screen.gd"),
}

const SCREEN_TITLES := {
	"skills": "知识树",
	"shop": "商店",
	"archive": "档案",
	"diagnostics": "诊断",
	"laboratory": "实验室",
}

var _screens: Dictionary = {}
var _current := ""
var _start: StartScreen
var _hub: WorkbenchScreen
var _sub_frame: Control
var _sub_title: Label
var _sub_host: Control
var _toast_box: VBoxContainer

func _ready() -> void:
	set_process_unhandled_key_input(true)
	theme = UiTheme.build()
	_build()
	_connect_events()
	GameState.boot()
	_restore_chapter()
	print("IFZ_BOOT data_ok=%s files=%d chapter=%s" % [str(DataDB.ready_ok), DataDB.loaded_files, DataDB.chapter_id()])
	if not DataDB.ready_ok:
		EventBus.toast("数据校验有 %d 个问题，见诊断页" % DataDB.errors.size(), "error")
	_show_start()
	_handle_cli()

func _restore_chapter() -> void:
	## 当前章节跟着存档走；`--chapter=<id>` 可覆盖（截图/验收用）。未知章节回退默认章。
	var want := str(GameState.player.chapter_id)
	var cli := CliArgs.value("chapter", "")
	if not cli.is_empty():
		want = cli
	if want.is_empty() or not DataDB.use_chapter(want):
		DataDB.use_chapter(DataDB.default_chapter_id())
	if _hub != null:
		_hub.rebuild_for_chapter()
	if _start != null:
		_start.refresh_chapter()

func _connect_events() -> void:
	EventBus.notify.connect(_on_notify)

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	_build_sub_frame()

	_hub = WorkbenchScreen.new()
	_hub.setup(self)
	add_child(_hub)
	_hub.visible = false

	_start = StartScreen.new()
	_start.setup(self)
	_start.start_game.connect(func(): _show_screen("workbench", false))
	add_child(_start)
	_start.visible = false

	_toast_box = VBoxContainer.new()
	_toast_box.add_theme_constant_override("separation", 6)
	_toast_box.anchor_left = 1.0
	_toast_box.anchor_right = 1.0
	_toast_box.anchor_top = 1.0
	_toast_box.anchor_bottom = 1.0
	_toast_box.offset_left = -460
	_toast_box.offset_right = -20
	_toast_box.offset_top = -140
	_toast_box.offset_bottom = -20
	_toast_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_toast_box.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_toast_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_toast_box)

func _build_sub_frame() -> void:
	_sub_frame = Control.new()
	_sub_frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sub_frame.visible = false
	add_child(_sub_frame)

	# board 用 Panel（不是 PanelContainer）：容器会接管子节点坐标，绝对布局会被内边距改写。
	var board := Panel.new()
	board.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD, UiTheme.FRAME, 0, UiTheme.BORDER_FRAME))
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 12
	board.offset_top = 12
	board.offset_right = -12
	board.offset_bottom = -12
	_sub_frame.add_child(board)

	# 三级页抬头：返回 44×44 @ (24,30)，标题 (86,30) 26 号；内容从 y=92 起。
	# layer 反向偏移 12 px（board 自身内缩 12），让这里的坐标等于窗口绝对坐标。
	var layer := Control.new()
	layer.position = Vector2(-12, -12)
	layer.size = Vector2(1280, 720)
	board.add_child(layer)

	var back := Ui.back_icon(func(): _show_screen("workbench"))
	back.position = Vector2(24, 30)
	back.size = Vector2(44, 44)
	layer.add_child(back)

	_sub_title = Ui.label("", UiTheme.F_H2, UiTheme.CHALK)
	_sub_title.position = Vector2(86, 30)
	_sub_title.size = Vector2(600, 44)
	_sub_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_sub_title.clip_text = true
	layer.add_child(_sub_title)

	_sub_host = Control.new()
	_sub_host.position = Vector2(24, 92)
	_sub_host.size = Vector2(1232, 612)
	layer.add_child(_sub_host)

func _show_start() -> void:
	_current = "start"
	if _hub != null:
		_hub.close_lab()
	if _sub_frame != null:
		_sub_frame.visible = false
	if _hub != null:
		_hub.visible = false
	_start.visible = true

func _show_hub(lab_id: String = "") -> void:
	_current = "workbench"
	_start.visible = false
	_sub_frame.visible = false
	_hub.visible = true
	_hub.on_show()
	if not lab_id.is_empty():
		_hub.select_lab(lab_id, false)

func show_lab(lab_id: String) -> void:
	_show_hub()
	_hub.select_lab(lab_id, true)

func show_screen(id: String, announce: bool = true) -> void:
	_show_screen(id, announce)

func _show_screen(id: String, announce: bool = true) -> void:
	if id == "start":
		_show_start()
		return
	if id == "workbench" or id == "hub":
		_show_hub()
		return
	if not SCREEN_SCRIPTS.has(id):
		return
	if not _screens.has(id):
		var script: Script = SCREEN_SCRIPTS[id]
		var screen: GameScreen = script.new()
		screen.setup(self)
		_sub_host.add_child(screen)
		_screens[id] = screen
	for key in _screens.keys():
		(_screens[key] as Control).visible = str(key) == id
	_current = id
	_start.visible = false
	_hub.visible = false
	_hub.close_lab()
	_sub_frame.visible = true
	_sub_title.text = str(SCREEN_TITLES.get(id, id))
	var screen: GameScreen = _screens[id]
	screen.on_show()
	if announce:
		EventBus.screen_changed.emit(id)

func back_to_hub() -> void:
	_hub.close_lab()
	_show_hub()

func _on_notify(text: String, kind: String) -> void:
	var color := UiTheme.CYAN
	if kind == "ok":
		color = UiTheme.CHALK_BRIGHT
	elif kind == "warn":
		color = UiTheme.AMBER
	elif kind == "error":
		color = UiTheme.DANGER
	var card := Ui.card(UiTheme.BOARD_HIGH, color, 0, 1)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.size_flags_horizontal = Control.SIZE_SHRINK_END
	var m := Ui.margin4(14, 8, 14, 8)
	card.add_child(m)
	var l := Ui.wrap(text, UiTheme.F_BODY, color)
	l.custom_minimum_size = Vector2(360, 0)
	card.custom_minimum_size = Vector2(400, 0)
	m.add_child(l)
	_toast_box.add_child(card)
	if UiTheme.motion:
		var tw := create_tween()
		tw.tween_interval(2.6)
		tw.tween_property(card, "modulate:a", 0.0, 0.4)
		tw.tween_callback(card.queue_free)
	else:
		_toast_box.remove_child(card)
		card.queue_free()

func _input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo or key.keycode != KEY_ESCAPE:
		return
	var settings := get_tree().get_first_node_in_group("ifz_settings")
	if settings is Control and (settings as Control).visible:
		return
	get_viewport().set_input_as_handled()
	if _current == "workbench":
		if _hub.lab_open():
			_hub.close_lab()
		else:
			_show_start()
	elif _current != "start":
		_show_hub()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_F5:
		SaveManager.save_game(1)
		return
	if event.keycode == KEY_F9:
		SaveManager.load_game(1)
		return
	if event.keycode == KEY_M:
		UiTheme.motion = not UiTheme.motion
		_hub.reapply_motion()
		get_viewport().set_input_as_handled()

func _handle_cli() -> void:
	var walk := CliArgs.value("walkthrough", "")
	if not walk.is_empty():
		_run_walkthrough(walk)
		return
	var verify := CliArgs.value("verify-walkthrough", "")
	if not verify.is_empty():
		_verify_walkthrough(verify)
		return
	if CliArgs.has_flag("ui-probe"):
		_run_ui_probe()
		return
	var shot := CliArgs.value("shot", "")
	if shot.is_empty():
		return
	var screen_id := CliArgs.value("shot-screen", "workbench")
	var lab_id := CliArgs.value("shot-lab", "")
	_show_screen(screen_id, false)
	if not lab_id.is_empty():
		_hub.select_lab(lab_id, false)
	for i in 4:
		await get_tree().process_frame
	_clear_toasts()
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png(shot)
	print("SHOT_SAVED=%s err=%d size=%dx%d" % [shot, err, img.get_width(), img.get_height()])
	get_tree().quit(0 if err == OK else 1)

func _clear_toasts() -> void:
	## 截图/探测时清掉瞬时提示，避免挡住验收画面。
	if _toast_box == null:
		return
	for c in _toast_box.get_children():
		_toast_box.remove_child(c)
		c.queue_free()

func _run_ui_probe() -> void:
	for i in 4:
		await get_tree().process_frame
	_show_hub()
	for i in 3:
		await get_tree().process_frame
	var scale := float(DisplayServer.window_get_size().y) / 720.0
	print("IFZ_PROBE window=%s logical=%s scale=%.3f" % [str(DisplayServer.window_get_size()), str(get_viewport().get_visible_rect().size), scale])
	print("IFZ_HUB_CLICKABLE=%d" % _hub.clickable_count())
	print("IFZ_HUB_NODES=%d" % _hub.node_count())
	var m := _hub.font_metrics()
	print("IFZ_HUB_FONT min_label=%d min_body=%d (logical)" % [int(m.get("min_label", 0)), int(m.get("min_body", 0))])
	print("IFZ_MIN_BODY_PX=%.1f (1280 基准)" % float(m.get("min_body", 0)))
	_hub.select_lab("gate", false)
	for i in 3:
		await get_tree().process_frame
	var lm := _hub.font_metrics()
	print("IFZ_LAB_FONT min_label=%d min_body=%d (logical)" % [int(lm.get("min_label", 0)), int(lm.get("min_body", 0))])
	var ev := InputEventKey.new()
	ev.keycode = KEY_ESCAPE
	ev.physical_keycode = KEY_ESCAPE
	ev.pressed = true
	Input.parse_input_event(ev)
	Input.flush_buffered_events()
	for i in 3:
		await get_tree().process_frame
	print("IFZ_ESC_STEPS=%d lab_open=%s screen=%s" % [0 if _hub.lab_open() else 1, str(_hub.lab_open()), _current])
	var idle := await _measure_idle_frames(120)
	print("IFZ_UI_IDLE_MS=%.3f" % idle)
	var dir := "res://artifacts/shots/ui_v2"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	_clear_toasts()
	await get_tree().process_frame
	var hub_img := get_viewport().get_texture().get_image()
	hub_img.save_png(ProjectSettings.globalize_path("%s/probe_%dx%d_hub.png" % [dir, hub_img.get_width(), hub_img.get_height()]))
	_show_start()
	for i in 3:
		await get_tree().process_frame
	var sm := _start_font_metrics()
	print("IFZ_START_FONT min_label=%d min_body=%d (logical)" % [int(sm.get("min_label", 0)), int(sm.get("min_body", 0))])
	_clear_toasts()
	await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(ProjectSettings.globalize_path("%s/probe_%dx%d_start.png" % [dir, img.get_width(), img.get_height()]))
	get_tree().quit(0)

func _measure_idle_frames(frames: int) -> float:
	## UI 空闲帧开销：Hub 静止、无输入时每帧 process 时间均值（ms）。
	## 与仿真的 5 ms/帧硬线独立计，用来证明 UI 不吃仿真预算。
	var total := 0.0
	var peak := 0.0
	for i in frames:
		await get_tree().process_frame
		var ms := float(Performance.get_monitor(Performance.TIME_PROCESS))
		total += ms
		peak = maxf(peak, ms)
	print("IFZ_UI_IDLE_PEAK_MS=%.3f" % peak)
	return total / float(maxi(frames, 1))

func _start_font_metrics() -> Dictionary:
	var res := {"min_label": 999, "min_body": 999}
	_collect_fonts(_start, res)
	return res

func _collect_fonts(node: Node, res: Dictionary) -> void:
	for c in node.get_children():
		if c is Label and (c as Label).is_visible_in_tree() and not (c as Label).text.strip_edges().is_empty():
			var l := c as Label
			var fs := l.get_theme_font_size("font_size")
			res["min_label"] = mini(int(res["min_label"]), fs)
			if l.text.strip_edges().length() >= 8:
				res["min_body"] = mini(int(res["min_body"]), fs)
		_collect_fonts(c, res)

# ---- 6 节脚本走查（--walkthrough / --verify-walkthrough） --------------------

func _run_walkthrough(path: String) -> void:
	for i in 3:
		await get_tree().process_frame
	var wb: WorkbenchScreen = _hub
	_show_hub()
	var p := GameState.player
	var fails: Array = []
	var checks := 0
	var labs: Dictionary = {}
	for raw_id in DataDB.chapter.lab_order:
		var lid := str(raw_id)
		var meta: Dictionary = DataDB.chapter.lab(lid)
		var gold_before := p.gold
		var xp_before := p.xp
		var inv_want := _inv_with_grants(p.inventory, lid, ChapterFlow.is_objective_done(str(meta.get("objective", ""))))
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
		if _inv_signature(p.inventory) != _inv_signature(inv_want):
			fails.append("%s: 物品变化 %s，期望 %s" % [lid, _inv_signature(p.inventory), _inv_signature(inv_want)])
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

func _inv_with_grants(before: Dictionary, lab_id: String, already_done: bool) -> Dictionary:
	## 走查期望：结算该实验后，物品 = 现有 + 数据段 grants.items（首个通关才发）。
	var out := {}
	for k in before.keys():
		out[str(k)] = int(before[k])
	if already_done:
		return out
	var grants: Dictionary = ChapterFlow.runtime().grants(lab_id, DataDB.labs_doc, GameState.player)
	var items: Variant = grants.get("items", {})
	if items is Dictionary:
		for k in (items as Dictionary).keys():
			out[str(k)] = int(out.get(str(k), 0)) + int((items as Dictionary)[k])
	return out

func _inv_signature(inv: Dictionary) -> String:
	var keys := inv.keys()
	keys.sort()
	var parts := []
	for k in keys:
		parts.append("%s:%d" % [str(k), int(inv[k])])
	return ",".join(PackedStringArray(parts))

func _chapter_completion_reward() -> Dictionary:
	## 章节完成时的两笔结算：complete_reward + 本章里程碑节点（节点 ID 由章节数据推导，不写死）。
	var fin: Dictionary = DataDB.chapter.data.get("complete_reward", {})
	var gold := int(fin.get("gold", 0))
	var xp := int(fin.get("xp", 0))
	var n := _chapter_milestone_node(fin)
	gold += int(n.get("gold_award", 0))
	xp += int(n.get("xp_award", 0))
	if n.is_empty():
		# 与 ChapterFlow._finish_chapter 同一口径：里程碑节点缺失时按章末预算发金币。
		gold += int(DataDB.chapter.data.get("economy", {}).get("chapter_end_gold", 0))
	return {"gold": gold, "xp": xp}

func _chapter_milestone_node(fin: Dictionary) -> Dictionary:
	## 优先用 complete_reward.badge 当节点 ID（如 CH02-CMOS），再退回章节 ID 大写（CH01）。
	var badge := str(fin.get("badge", ""))
	if not badge.is_empty():
		var hit: Dictionary = DataDB.skill_graph.node(badge)
		if not hit.is_empty():
			return hit
	return DataDB.skill_graph.node(DataDB.chapter.id().to_upper())

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
	print("WALKTHROUGH_VERIFY_%s checks=%d failures=%d" % ["OK" if errs.is_empty() else "FAIL", 6 + DataDB.chapter.objective_order.size() + (f.get("gates", {}) as Dictionary).size(), errs.size()])
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
