class_name WorkbenchScreen
extends GameScreen

## 黑板 Hub：左栏 5 入口 + 抬头进度/金币 + 章节树视口。
## 实验页以整屏叠层打开；Esc 一次回到黑板。

signal lab_selected(lab_id)

const LAB_PATHS := {
	"level": preload("res://src/ui/screens/lab_level.gd"),
	"binary": preload("res://src/ui/screens/lab_binary.gd"),
	"boolean": preload("res://src/ui/screens/lab_boolean.gd"),
	"gate": preload("res://src/ui/screens/lab_gate.gd"),
	"signal": preload("res://src/ui/screens/lab_signal.gd"),
	"half_adder": preload("res://src/ui/screens/lab_half_adder.gd"),
	"transistor": preload("res://src/ui/screens/lab_ch02.gd"),
	"inverter": preload("res://src/ui/screens/lab_ch02.gd"),
	"nand": preload("res://src/ui/screens/lab_ch02.gd"),
	"power": preload("res://src/ui/screens/lab_ch02.gd"),
}

const TREE_W := 922
const TREE_H := 468
const RAIL_W := 236

## 布局槽位（坐标固定，内容按当前章节数据填）：知识 13 格、技能 9 格。
## 改章节不重排坐标，只换填充内容。
const KNOW_SLOTS := [[2, 1], [3, 1], [4, 1], [5, 1], [6, 1], [7, 1], [1, 2], [2, 2], [3, 2], [4, 2], [5, 2], [6, 2], [7, 2]]
const SKILL_SLOTS := [[1, 5], [2, 5], [3, 5], [4, 5], [5, 5], [6, 5], [7, 5], [1, 6], [3, 6]]

## 当前章节派生出来的节点与实验列表（不写死章节 ID）。
var _nodes: Array = []
var _labs: Array = []

var _board: Control
var _rail_card: PanelContainer
var _rail: VBoxContainer
var _rail_buttons: Dictionary = {}
var _header_task: Label
var _header_sub: Label
var _progress_label: Label
var _progress_bar: ProgressBar
var _gold_label: Label
var _chapter_label: Label
var _rail_progress: Label
var _viewport: Control
var _tree_canvas: Control
var _lines: Control
var _nodes_layer: Control
var _node_buttons: Dictionary = {}
var _node_texts: Dictionary = {}
var _footer_zoom: Label

var _lab_layer: Control
var _pages: Dictionary = {}
var _lab_open := false
var _current_lab := ""
var _current_obj := ""
var _current_milestone := ""
var _zoom := 1.0
var _pan := Vector2.ZERO
var _dragging := false
var _halo: Control
var _halo_tween: Tween
var _settings: SettingsPanel

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()
	_settings = SettingsPanel.new()
	_settings.motion_changed.connect(func(_on): reapply_motion())
	add_child(_settings)
	if EventBus.state_changed.is_connected(_refresh):
		EventBus.state_changed.disconnect(_refresh)
	EventBus.state_changed.connect(_refresh)

func on_show() -> void:
	_refresh()
	_layout_tree.call_deferred()

func _build() -> void:
	var backdrop := ColorRect.new()
	backdrop.color = UiTheme.BG
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	var frame := ColorRect.new()
	frame.color = UiTheme.FRAME
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.offset_left = 12
	frame.offset_top = 12
	frame.offset_right = -12
	frame.offset_bottom = -12
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)

	_board = Control.new()
	_board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.offset_left = 21
	_board.offset_top = 21
	_board.offset_right = -21
	_board.offset_bottom = -21
	_board.clip_contents = true
	add_child(_board)

	var board_bg := ColorRect.new()
	board_bg.color = UiTheme.BOARD
	board_bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_board.add_child(board_bg)

	var grain := GrainOverlay.new()
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(grain)

	var content := Ui.margin4(0, 0, 0, 0)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_board.add_child(content)
	var row := Ui.hbox(0)
	content.add_child(row)

	# ---- 左栏 ----
	_rail_card = Ui.card(Color("#13261F"), UiTheme.LINE)
	_rail_card.custom_minimum_size = Vector2(RAIL_W, 0)
	_rail_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_rail_card)
	var rail_margin := Ui.margin4(20, 18, 16, 16)
	_rail_card.add_child(rail_margin)
	_rail = Ui.vbox(0)
	rail_margin.add_child(_rail)

	_chapter_label = Ui.label(_chapter_name(), 22, UiTheme.CHALK)
	_rail.add_child(_chapter_label)
	_rail.add_child(Ui.gap(12))

	var stat_row := Ui.hbox(10)
	stat_row.custom_minimum_size = Vector2(0, 28)
	_rail.add_child(stat_row)
	stat_row.add_child(Ui.label("节点", UiTheme.F_LABEL, UiTheme.MUTED))
	_rail_progress = Ui.label("0 / 36", UiTheme.F_H3, UiTheme.CHALK)
	stat_row.add_child(_rail_progress)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 7)
	_progress_bar.max_value = float(maxi(_nodes.size(), 1))
	_progress_bar.show_percentage = false
	_progress_bar.add_theme_stylebox_override("background", UiTheme.flat_tight(UiTheme.alpha(UiTheme.CHALK, 0.10), UiTheme.alpha(UiTheme.CHALK, 0.22)))
	_progress_bar.add_theme_stylebox_override("fill", UiTheme.flat_tight(UiTheme.CHALK, UiTheme.CHALK))
	_rail.add_child(_progress_bar)
	_rail.add_child(Ui.gap(14))
	_rail.add_child(Ui.hline(UiTheme.LINE))
	_rail.add_child(Ui.gap(10))

	_rail_buttons["labs"] = _rail_item("实验室", Color("#7FC7CF"), func(): _enter_current_lab(), false)
	_rail.add_child(_rail_buttons["labs"])
	_rail_buttons["shop"] = _rail_item("商店", Color("#D8A24A"), func(): _go("shop"), false)
	_rail.add_child(_rail_buttons["shop"])
	_rail_buttons["skills"] = _rail_item("知识树", Color("#E8E4D6"), func(): _go("skills"), false)
	_rail.add_child(_rail_buttons["skills"])
	_rail_buttons["archive"] = _rail_item("档案", Color("#8FA3B8"), func(): _go("archive"), false)
	_rail.add_child(_rail_buttons["archive"])
	_rail_buttons["diagnostics"] = _rail_item("诊断", Color("#C97862"), func(): _go("diagnostics"), false)
	_rail.add_child(_rail_buttons["diagnostics"])

	_rail.add_child(Ui.spacer())
	_rail.add_child(Ui.hline(UiTheme.LINE))
	_rail.add_child(Ui.gap(10))

	# ---- 右侧主区 ----
	var main_col := Ui.vbox(0)
	main_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_col.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(main_col)

	var header := Ui.hbox(18)
	header.custom_minimum_size = Vector2(0, 94)
	var hm := Ui.margin4(24, 12, 24, 6)
	hm.size_flags_vertical = Control.SIZE_FILL
	main_col.add_child(hm)
	hm.add_child(header)

	var task_col := Ui.vbox(0)
	task_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	task_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(task_col)
	_header_task = Ui.label("—", UiTheme.F_H2, UiTheme.CHALK)
	_header_task.clip_text = true
	_header_task.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	task_col.add_child(_header_task)
	_header_sub = Ui.label("", UiTheme.F_BODY, UiTheme.MUTED)
	_header_sub.clip_text = true
	_header_sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	task_col.add_child(_header_sub)

	var chips := Ui.vbox(6)
	chips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(chips)
	_progress_label = Ui.label("进度 0/6", UiTheme.F_BODY, UiTheme.CHALK)
	_progress_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chips.add_child(_progress_label)
	_gold_label = Ui.label("金币 0", UiTheme.F_BODY, UiTheme.AMBER)
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	chips.add_child(_gold_label)
	var settings_btn := Ui.ghost("设置", func(): _settings.open())
	settings_btn.custom_minimum_size = Vector2(84, UiTheme.CONTROL_H)
	settings_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(settings_btn)

	# 树视口
	_viewport = Control.new()
	_viewport.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_viewport.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_viewport.clip_contents = true
	_viewport.mouse_filter = Control.MOUSE_FILTER_STOP
	_viewport.gui_input.connect(_on_viewport_input)
	_viewport.resized.connect(_layout_tree)
	main_col.add_child(_viewport)

	_tree_canvas = Control.new()
	_tree_canvas.size = Vector2(TREE_W, TREE_H)
	_tree_canvas.custom_minimum_size = Vector2(TREE_W, TREE_H)
	_tree_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_viewport.add_child(_tree_canvas)
	_lines = Control.new()
	_lines.size = Vector2(TREE_W, TREE_H)
	_lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_lines.draw.connect(_draw_lines)
	_tree_canvas.add_child(_lines)
	_nodes_layer = Control.new()
	_nodes_layer.size = Vector2(TREE_W, TREE_H)
	_nodes_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tree_canvas.add_child(_nodes_layer)
	_build_nodes()

	# 底栏
	var footer := Ui.hbox(16)
	footer.custom_minimum_size = Vector2(0, 46)
	var fm := Ui.margin4(24, 6, 24, 8)
	fm.size_flags_vertical = Control.SIZE_FILL
	main_col.add_child(fm)
	fm.add_child(footer)
	_footer_zoom = Ui.label("100%", UiTheme.F_BODY, UiTheme.MUTED)
	footer.add_child(_footer_zoom)

	# 实验页叠层
	_lab_layer = Control.new()
	_lab_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_lab_layer.visible = false
	_lab_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_lab_layer)

func _rail_item(text: String, tone: Color, cb: Callable, locked: bool) -> Button:
	var b := Button.new()
	b.text = ""
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(0, UiTheme.CONTROL_RAIL)
	b.disabled = locked
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.pressed.connect(cb)
	b.add_theme_stylebox_override("normal", _rail_style(false, false))
	b.add_theme_stylebox_override("hover", _rail_style(true, false))
	b.add_theme_stylebox_override("pressed", _rail_style(true, false))
	b.add_theme_stylebox_override("disabled", _rail_style(false, true))
	var m := Ui.margin4(7, 0, 10, 0)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var h := Ui.hbox(14)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(h)
	var swatch := ColorRect.new()
	swatch.color = tone
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.modulate.a = 0.45 if locked else 1.0
	h.add_child(swatch)
	var tl := Ui.label(text, UiTheme.F_H3, Color("#E3E8E3") if not locked else UiTheme.MUTED_DIM)
	tl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	tl.name = "Caption"
	h.add_child(tl)
	h.add_child(Ui.spacer())
	var lock := Ui.glyph("lock", UiTheme.MUTED_DIM, 16)
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.name = "LockIcon"
	lock.visible = locked
	h.add_child(lock)
	return b

func _rail_style(hot: bool, locked: bool) -> StyleBoxFlat:
	var sb := UiTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0)
	if hot and not locked:
		sb.bg_color = UiTheme.alpha(UiTheme.CHALK, 0.08)
	if locked:
		sb.bg_color = Color(0, 0, 0, 0)
	return sb

func _set_rail_active(key: String, active: bool) -> void:
	var b: Button = _rail_buttons.get(key, null)
	if b == null:
		return
	var sb := _rail_style(false, b.disabled)
	if active:
		sb.bg_color = UiTheme.alpha(UiTheme.CHALK, 0.10)
		sb.border_width_left = 2
		sb.border_color = UiTheme.CHALK
	b.add_theme_stylebox_override("normal", sb)
	var cap := b.find_child("Caption", true, false) as Label
	if cap != null:
		cap.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if active else (UiTheme.MUTED_DIM if b.disabled else UiTheme.CHALK))

func _build_nodes() -> void:
	_build_chapter_nodes()
	_halo = Control.new()
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.visible = false
	_halo.draw.connect(_draw_halo)
	_nodes_layer.add_child(_halo)

	for raw in _nodes:
		var rec := _node_record(raw)
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.custom_minimum_size = Vector2.ZERO
		b.position = rec["pos"]
		b.size = rec["size"]
		b.text = ""
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.add_theme_stylebox_override("normal", _node_style("locked"))
		b.add_theme_stylebox_override("hover", _node_style("open"))
		b.add_theme_stylebox_override("pressed", _node_style("current"))
		b.add_theme_stylebox_override("disabled", _node_style("locked"))
		b.pressed.connect(func(): _on_node(rec))
		_nodes_layer.add_child(b)
		_node_buttons[str(rec["id"])] = b
		_build_node_labels(b, rec)
	_update_node_states()

func _build_node_labels(b: Button, rec: Dictionary) -> void:
	var m := Ui.margin4(8, 3, 7, 3)
	m.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	m.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(m)
	var v := Ui.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	m.add_child(v)
	var texts := {"code": null, "title": null}
	if rec["kind"] == "challenge":
		var t := Ui.label(str(rec["title"]), 15, UiTheme.CHALK)
		t.clip_text = true
		t.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.add_child(t)
		texts["title"] = t
	else:
		var code := Ui.mono(str(rec["code"]), 14, UiTheme.MUTED)
		code.clip_text = true
		code.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		v.add_child(code)
		texts["code"] = code
		var title := Ui.label(str(rec["title"]), 16 if rec["kind"] == "milestone" else 15, UiTheme.CHALK)
		title.clip_text = true
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		v.add_child(title)
		texts["title"] = title
	_node_texts[str(rec["id"])] = texts

func _node_record(raw: Dictionary) -> Dictionary:
	var id := str(raw.get("id", ""))
	var kind := str(raw.get("kind", ""))
	var lab := str(raw.get("lab", ""))
	var code := str(raw.get("code", id))
	var row := int(raw.get("row", 0))
	var col := int(raw.get("col", 1))
	var w := 110.0 if kind == "challenge" else 118.0
	var h := 38.0 if kind == "challenge" else (52.0 if kind == "milestone" else 46.0)
	var y := 0.0
	if row >= 1 and row <= 4:
		y = 62.0 + (row - 1) * 58.0
	elif row == 5:
		y = 302.0
	elif row == 6:
		y = 358.0
	elif row == 7:
		y = 420.0
	var pos := Vector2((col - 1) * 134.0 + (4.0 if kind == "challenge" else 0.0), y)
	return {
		"id": id, "title": str(raw.get("title", "")), "col": col, "row": row, "kind": kind,
		"lab": lab, "code": code, "pos": pos, "size": Vector2(w, h),
	}

func _build_chapter_nodes() -> void:
	## 节点清单全部从当前章节运行时派生：里程碑、章末、知识、技能、挑战都在数据里。
	## 槽位坐标固定，章节内容不同只换填充，不重排布局。
	_nodes.clear()
	_labs.clear()
	var c: ChapterRuntime = DataDB.chapter
	if c == null:
		return
	var num := int(c.data.get("number", 0))
	var up := c.id().to_upper()
	for raw in c.lab_order:
		_labs.append(str(raw))
	var n := _labs.size()
	for i in n:
		var lab := c.lab(_labs[i])
		_nodes.append({
			"id": str(lab.get("milestone", "")), "title": _short_title(str(lab.get("title", ""))),
			"col": mini(i + 1, 7), "row": 0, "kind": "milestone", "lab": str(lab.get("id", "")),
			"code": "%d.%d" % [num, i + 1],
		})
	_nodes.append({
		"id": up, "title": "%s完成" % _chapter_name(), "col": mini(n + 1, 7), "row": 0,
		"kind": "chapter", "lab": "", "code": "CH%02d" % num,
	})
	var seen := {}
	var ki := 0
	for lid in _labs:
		var lab := c.lab(lid)
		for raw_card in lab.get("knowledge_cards", []):
			var kid := str(raw_card)
			if ki >= KNOW_SLOTS.size() or DataDB.skill_graph.node(kid).is_empty():
				continue
			var ks: Array = KNOW_SLOTS[ki]
			_nodes.append({"id": kid, "title": _node_title(kid), "col": int(ks[0]), "row": int(ks[1]), "kind": "knowledge", "lab": "", "code": kid})
			ki += 1
	var si := 0
	for lid in _labs:
		var lab := c.lab(lid)
		var sk_names: Array = []
		sk_names.append_array(lab.get("skill_nodes", []))
		if lab.has("skill_node"):
			sk_names.append(str(lab.get("skill_node")))
		for raw_sk in sk_names:
			var sid := str(raw_sk)
			if sid.is_empty() or seen.has(sid) or si >= SKILL_SLOTS.size():
				continue
			if DataDB.skill_graph.node(sid).is_empty():
				continue
			seen[sid] = true
			var ss: Array = SKILL_SLOTS[si]
			_nodes.append({"id": sid, "title": _node_title(sid), "col": int(ss[0]), "row": int(ss[1]), "kind": "skill", "lab": "", "code": sid})
			si += 1
	for i in n:
		var lab := c.lab(_labs[i])
		_nodes.append({
			"id": "%s-CH-%d" % [up, i + 1], "title": str(lab.get("title", "")),
			"col": mini(i + 1, 7), "row": 7, "kind": "challenge", "lab": str(lab.get("id", "")),
			"code": "%d.%d" % [num, i + 1],
		})
	_nodes.append({
		"id": "%s-CH-FINAL" % up, "title": "章末验收", "col": mini(n + 1, 7), "row": 7,
		"kind": "final", "lab": "", "code": "FINAL",
	})

func _short_title(title: String) -> String:
	## "2.1 三端开关" → "三端开关"：里程碑格子只放短名，编号单独一行。
	var parts := title.split(" ", false, 1)
	return parts[1].strip_edges() if parts.size() > 1 else title

func _node_title(node_id: String) -> String:
	var n: Dictionary = DataDB.skill_graph.node(node_id)
	var t := str(n.get("title", ""))
	return t if not t.is_empty() else node_id

func _chapter_number() -> int:
	return int(DataDB.chapter.data.get("number", 0))

func _node_state(rec: Dictionary) -> String:
	var id := str(rec["id"])
	var kind := str(rec["kind"])
	if id == _current_milestone:
		return "current"
	if kind == "knowledge" or kind == "skill":
		return "done" if Knowledge.is_unlocked(id) else "locked"
	if kind == "chapter" or kind == "final":
		return "done" if ChapterFlow.chapter_complete() else "locked"
	var lab := str(rec["lab"])
	if lab.is_empty():
		return "locked"
	if DataDB.chapter.content_status(lab) != "ready":
		return "deferred"
	if ChapterFlow.is_objective_done(DataDB.chapter.objective_for_lab(lab)):
		return "done"
	if ChapterFlow.is_lab_unlocked(lab):
		return "open"
	return "locked"

func _node_style(state: String) -> StyleBoxFlat:
	var sb := UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.alpha(UiTheme.CHALK, 0.30), 0, 1)
	match state:
		"done":
			sb.bg_color = UiTheme.alpha(UiTheme.CHALK, 0.90)
			sb.border_color = UiTheme.CHALK
		"open":
			sb.bg_color = UiTheme.alpha(UiTheme.CHALK, 0.07)
			sb.border_color = UiTheme.alpha(UiTheme.CHALK, 0.42)
		"current":
			sb.bg_color = UiTheme.alpha(UiTheme.CHALK, 0.12)
			sb.border_color = UiTheme.CHALK_BRIGHT
			sb.set_border_width_all(2)
		"deferred":
			sb.bg_color = UiTheme.alpha(UiTheme.RUST, 0.06)
			sb.border_color = UiTheme.alpha(UiTheme.RUST, 0.55)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb

func _update_node_states() -> void:
	_halo.visible = false
	for raw in _nodes:
		var rec := _node_record(raw)
		var id := str(rec["id"])
		var b: Button = _node_buttons.get(id, null)
		if b == null:
			continue
		var st := _node_state(rec)
		b.disabled = st == "locked"
		b.add_theme_stylebox_override("normal", _node_style(st))
		b.add_theme_stylebox_override("hover", _node_style("open" if st != "locked" else "locked"))
		var texts: Dictionary = _node_texts.get(id, {})
		var title_l: Label = texts.get("title", null)
		var code_l: Label = texts.get("code", null)
		var ink := UiTheme.CHALK
		if st == "locked":
			ink = Color("#B4C1BA")
		elif st == "done":
			ink = Color("#14251F")
		elif st == "current":
			ink = Color("#FFFDF5")
		elif st == "deferred":
			ink = UiTheme.RUST
		b.modulate.a = 0.56 if st == "locked" else 1.0
		## 未开放不写字：标题保留数据里的节名，状态由虚线边 + 45° 斜纹 + 锁标表达。
		if title_l != null:
			title_l.text = str(rec["title"])
			title_l.add_theme_color_override("font_color", ink)
		if code_l != null:
			code_l.add_theme_color_override("font_color", UiTheme.alpha(ink, 0.72))
		if st == "deferred":
			var lab := str(rec["lab"])
			if not lab.is_empty():
				b.tooltip_text = DataDB.chapter.lab_lock_reason(GameState.player, lab)
		else:
			b.tooltip_text = ""
		if st == "current":
			_halo.position = Vector2(rec["pos"]) - Vector2(6, 6)
			_halo.size = Vector2(rec["size"]) + Vector2(12, 12)
			_halo.queue_redraw()
			_halo.visible = true
	_pulse_halo()
	_lines.queue_redraw()

func _draw_halo() -> void:
	var s := _halo.size
	var c := UiTheme.CHALK_BRIGHT
	_halo.draw_dashed_line(Vector2(0, 0), Vector2(s.x, 0), c, 1.0, 6.0)
	_halo.draw_dashed_line(Vector2(s.x, 0), Vector2(s.x, s.y), c, 1.0, 6.0)
	_halo.draw_dashed_line(Vector2(s.x, s.y), Vector2(0, s.y), c, 1.0, 6.0)
	_halo.draw_dashed_line(Vector2(0, s.y), Vector2(0, 0), c, 1.0, 6.0)

func _pulse_halo() -> void:
	if _halo_tween != null and _halo_tween.is_valid():
		_halo_tween.kill()
	if not UiTheme.motion:
		_halo.modulate.a = 0.85
		return
	_halo.modulate.a = 0.22
	_halo_tween = create_tween()
	_halo_tween.set_loops()
	_halo_tween.tween_property(_halo, "modulate:a", 0.85, 1.9)
	_halo_tween.tween_property(_halo, "modulate:a", 0.22, 1.9)

func _draw_lines() -> void:
	# 里程碑横向主干：走过实线 2.4 px α.62，未走虚线 1.4 px α.20。
	for i in maxi(_labs.size(), 1):
		var a := Vector2(i * 134.0 + 118.0, 26.0)
		var b := Vector2((i + 1) * 134.0, 26.0)
		var done := _lab_index_done(i) and (i + 1 >= _labs.size() or _lab_index_done(i + 1))
		if done:
			_lines.draw_line(a, b, UiTheme.alpha(UiTheme.CHALK, 0.62), 2.4)
		else:
			_lines.draw_dashed_line(a, b, UiTheme.alpha(UiTheme.CHALK, 0.20), 1.4, 7.0)
	# 列内竖茎：从里程碑底部贯到技能行，卡片覆盖处自然被遮住。
	for i in _labs.size():
		var x := i * 134.0 + 59.0
		var done := _lab_index_done(i)
		if done:
			_lines.draw_line(Vector2(x, 52.0), Vector2(x, 302.0), UiTheme.alpha(UiTheme.CHALK, 0.62), 2.4)
		else:
			_lines.draw_dashed_line(Vector2(x, 52.0), Vector2(x, 302.0), UiTheme.alpha(UiTheme.CHALK, 0.20), 1.4, 7.0)

func _lab_index_done(i: int) -> bool:
	if i < 0 or i >= _labs.size():
		return ChapterFlow.chapter_complete()
	return ChapterFlow.is_objective_done(DataDB.chapter.objective_for_lab(_labs[i]))

func _on_node(rec: Dictionary) -> void:
	var st := _node_state(rec)
	var kind := str(rec["kind"])
	var lab := str(rec["lab"])
	if st == "locked":
		return
	if st == "deferred":
		## 未开放：点不进，原因只在 hover tooltip 出现（来自数据 deferred_reason）。
		return
	if kind == "knowledge" or kind == "skill":
		_go("skills")
		return
	if kind == "chapter":
		_advance_chapter()
		return
	if kind == "final":
		return
	if not lab.is_empty():
		select_lab(lab, true)

func _advance_chapter() -> void:
	## 进度推进式切章：章末节点（或抬头按钮）完成本章后进入下一章，不弹窗。
	if not ChapterFlow.chapter_complete():
		return
	var nxt := str(DataDB.chapter.next_chapter())
	if nxt.is_empty() or nxt == DataDB.chapter.id():
		# 已到最后一章：静默返回，不写状态 toast。
		return
	switch_chapter(nxt)

func switch_chapter(cid: String) -> bool:
	## 切章就地把树、实验页、抬头换成目标章节；存档里的 chapter_id 同步，下次进入自动恢复。
	if not DataDB.use_chapter(cid):
		EventBus.toast("没有这一章：%s" % cid, "warn")
		return false
	GameState.player.chapter_id = cid
	SaveManager.save_game(1, true)
	rebuild_for_chapter()
	EventBus.toast("已进入%s" % _chapter_name(), "ok")
	return true

func rebuild_for_chapter() -> void:
	## 章节数据换了，整屏按新章节重搭（节点坐标模板不变，只换内容）。
	close_lab()
	_pages.clear()
	_node_buttons.clear()
	_node_texts.clear()
	_current_obj = ""
	_current_lab = ""
	_current_milestone = ""
	for c in get_children():
		remove_child(c)
		c.queue_free()
	_build()

func _on_viewport_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom = clampf(_zoom + 0.1, 0.8, 1.4)
			_layout_tree()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom = clampf(_zoom - 0.1, 0.8, 1.4)
			_layout_tree()
		elif mb.button_index == MOUSE_BUTTON_MIDDLE or mb.button_index == MOUSE_BUTTON_RIGHT:
			_dragging = mb.pressed
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.double_click:
			_zoom = 1.0
			_pan = Vector2.ZERO
			_layout_tree()
	elif event is InputEventMouseMotion and _dragging:
		_pan += (event as InputEventMouseMotion).relative
		_layout_tree()

func _layout_tree() -> void:
	if _viewport == null or _tree_canvas == null:
		return
	var vp := _viewport.size
	var w := TREE_W * _zoom
	var h := TREE_H * _zoom
	_tree_canvas.scale = Vector2(_zoom, _zoom)
	_tree_canvas.position = (vp - Vector2(w, h)) * 0.5 + _pan
	if _footer_zoom != null:
		_footer_zoom.text = "%d%%" % int(round(_zoom * 100.0))

func _chapter_name() -> String:
	var t := DataDB.chapter.title()
	var parts := t.split("·")
	if parts.size() > 1:
		return parts[1].strip_edges()
	return t

func _resolve_current() -> void:
	var nxt := ChapterFlow.next_objective()
	_current_obj = str(nxt.get("id", "")) if not nxt.is_empty() else ""
	_current_lab = str(nxt.get("lab", "")) if not nxt.is_empty() else ""
	_current_milestone = ""
	if not _current_lab.is_empty():
		_current_milestone = str(DataDB.chapter.lab(_current_lab).get("milestone", ""))

func _refresh() -> void:
	_resolve_current()
	var done := 0
	var active: Array = DataDB.chapter.active_objective_ids()
	for raw_o in active:
		if ChapterFlow.is_objective_done(str(raw_o)):
			done += 1
	var p := GameState.player
	var node_done := 0
	for raw in _nodes:
		if _node_state(_node_record(raw)) == "done":
			node_done += 1
	_rail_progress.text = "%d / %d" % [node_done, _nodes.size()]
	_progress_bar.max_value = float(maxi(_nodes.size(), 1))
	_progress_bar.value = float(node_done)
	_progress_label.text = "进度 %d/%d" % [done, active.size()]
	_gold_label.text = "金币 %d" % int(p.gold)
	if not _current_lab.is_empty():
		var nxt := ChapterFlow.next_objective()
		var meta := DataDB.chapter.lab(_current_lab)
		_header_task.text = str(nxt.get("title", meta.get("title", "")))
		_header_sub.text = "%s · %s" % [str(meta.get("title", "")), str(meta.get("subtitle", ""))]
	elif ChapterFlow.chapter_complete():
		_header_task.text = _chapter_name()
		_header_sub.text = ""
	else:
		_header_task.text = _chapter_name()
		_header_sub.text = ""
	_set_rail_active("labs", true)
	var archive_on := done >= 3
	_rail_buttons["archive"].disabled = not archive_on
	var diag_on := p.has_flag("gate:T%d.1-1" % _chapter_number())
	_rail_buttons["diagnostics"].disabled = not diag_on
	_update_rail_lock("archive", not archive_on)
	_update_rail_lock("diagnostics", not diag_on)
	_chapter_label.text = _chapter_name()
	_update_node_states()
	refresh_status_for_pages()

func _update_rail_lock(key: String, locked: bool) -> void:
	var b: Button = _rail_buttons.get(key, null)
	if b == null:
		return
	b.disabled = locked
	b.add_theme_stylebox_override("normal", _rail_style(false, locked))
	var lock := b.find_child("LockIcon", true, false) as Control
	if lock != null:
		lock.visible = locked
	var cap := b.find_child("Caption", true, false) as Label
	if cap != null:
		cap.add_theme_color_override("font_color", UiTheme.MUTED_DIM if locked else UiTheme.CHALK)

func _go(id: String) -> void:
	if main != null and main.has_method("show_screen"):
		main.show_screen(id)

func _enter_current_lab() -> void:
	if _current_lab.is_empty():
		return
	if not ChapterFlow.is_lab_unlocked(_current_lab):
		return
	select_lab(_current_lab, true)

func select_lab(lab_id: String, announce: bool = true) -> void:
	if not LAB_PATHS.has(lab_id):
		EventBus.toast("找不到实验 %s" % lab_id, "error")
		return
	if not _pages.has(lab_id):
		var page: LabBase = (LAB_PATHS[lab_id] as Script).new()
		page.setup(main, lab_id)
		page.solved.connect(_on_lab_solved)
		_lab_layer.add_child(page)
		_pages[lab_id] = page
	for key in _pages.keys():
		(_pages[key] as Control).visible = str(key) == lab_id
	_lab_layer.visible = true
	_lab_open = true
	var page: LabBase = _pages[lab_id]
	page.refresh_status()
	if announce:
		lab_selected.emit(lab_id)
		EventBus.fire("lab_opened:%s" % lab_id)

func page_for(lab_id: String) -> LabBase:
	return _pages.get(lab_id, null)

func close_lab() -> void:
	if _lab_layer == null:
		return
	_lab_layer.visible = false
	_lab_open = false

func lab_open() -> bool:
	return _lab_open

func refresh_status_for_pages() -> void:
	for key in _pages.keys():
		(_pages[key] as LabBase).refresh_status()

func _on_lab_solved(id: String) -> void:
	ChapterFlow.complete_lab(id)
	SaveManager.save_game(1)
	_refresh()
	var page: LabBase = _pages.get(id, null)
	if page != null:
		page.refresh_status()

func reapply_motion() -> void:
	_pulse_halo()

func clickable_count() -> int:
	return _count_clickable(self)

func _count_clickable(node: Node) -> int:
	var n := 0
	for c in node.get_children():
		if c is Button and (c as Button).is_visible_in_tree() and not (c as Button).disabled:
			n += 1
		n += _count_clickable(c)
	return n

func node_count() -> int:
	return _node_buttons.size()

func font_metrics() -> Dictionary:
	var res := {"min_label": 999, "min_body": 999}
	_collect_fonts(self, res)
	return res

func _collect_fonts(node: Node, res: Dictionary) -> void:
	for c in node.get_children():
		if c is Label and (c as Label).is_visible_in_tree() and not (c as Label).text.strip_edges().is_empty():
			var l := c as Label
			var fs := l.get_theme_font_size("font_size")
			res["min_label"] = mini(int(res["min_label"]), fs)
			if l.text.strip_edges().length() >= 18:
				res["min_body"] = mini(int(res["min_body"]), fs)
		_collect_fonts(c, res)
