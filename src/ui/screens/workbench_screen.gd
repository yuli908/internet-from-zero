class_name WorkbenchScreen
extends GameScreen

## 黑板 Hub：左栏 5 入口 + 抬头进度/金币/当前任务 + 36 节点树视口。
## 实验页以整屏叠层打开；Esc 一次回到黑板。

signal lab_selected(lab_id)

const LAB_PATHS := {
	"level": preload("res://src/ui/screens/lab_level.gd"),
	"binary": preload("res://src/ui/screens/lab_binary.gd"),
	"boolean": preload("res://src/ui/screens/lab_boolean.gd"),
	"gate": preload("res://src/ui/screens/lab_gate.gd"),
	"signal": preload("res://src/ui/screens/lab_signal.gd"),
	"half_adder": preload("res://src/ui/screens/lab_half_adder.gd"),
}

const LABS := ["level", "binary", "boolean", "gate", "signal", "half_adder"]
const TREE_W := 922
const TREE_H := 468
const RAIL_W := 236

# 36 节点：7 里程碑 + 13 知识 + 9 技能 + 7 挑战。
const NODES := [
	["CH01-1", "第一束电", 1, 0, "milestone"],
	["CH01-2", "两种状态", 2, 0, "milestone"],
	["CH01-3", "真值表", 3, 0, "milestone"],
	["CH01-4", "门级", 4, 0, "milestone"],
	["CH01-5", "会记忆的电路", 5, 0, "milestone"],
	["CH01-6", "加法器", 6, 0, "milestone"],
	["CH01", "第一章完成", 7, 0, "milestone"],
	["KN-ELEC-01", "两种状态装下世界", 2, 1, "knowledge"],
	["KN-BIN-01", "机械开关写数字", 3, 1, "knowledge"],
	["KN-BIN-02", "二进制数与 DIP", 4, 1, "knowledge"],
	["KN-BIN-03", "最简积之和", 5, 1, "knowledge"],
	["KN-BIN-04", "半加器真值", 6, 1, "knowledge"],
	["KN-BOOL-01", "布尔代数", 7, 1, "knowledge"],
	["KN-BOOL-02", "德摩根定律", 1, 2, "knowledge"],
	["KN-BOOL-03", "卡诺图化简", 2, 2, "knowledge"],
	["KN-GATE-01", "门延迟与扇出", 3, 2, "knowledge"],
	["KN-SIG-01", "时钟边沿", 4, 2, "knowledge"],
	["KN-SIG-02", "JK 与 D 触发器", 5, 2, "knowledge"],
	["KN-SIG-03", "计数器分频", 6, 2, "knowledge"],
	["KN-ADD-01", "半加器进位", 7, 2, "knowledge"],
	["SK-LEVEL", "电平判读", 1, 5, "skill"],
	["SK-BIN", "进制转换", 2, 5, "skill"],
	["SK-BOOL", "布尔化简", 3, 5, "skill"],
	["SK-GATE", "门级搭建", 4, 5, "skill"],
	["SK-SIGNAL", "时序分析", 5, 5, "skill"],
	["SK-ADD", "加法器设计", 6, 5, "skill"],
	["SK-ENCAP", "封装与复用", 7, 5, "skill"],
	["SK-MEASURE", "测量与排错", 1, 6, "skill"],
	["SK-DEMORGAN", "德摩根改写", 3, 6, "skill"],
	["CH01-CH-1", "1.1 电平判读", 1, 7, "challenge"],
	["CH01-CH-2", "1.2 二进制", 2, 7, "challenge"],
	["CH01-CH-3", "1.3 布尔", 3, 7, "challenge"],
	["CH01-CH-4", "1.4 门级", 4, 7, "challenge"],
	["CH01-CH-5", "1.5 时序", 5, 7, "challenge"],
	["CH01-CH-6", "1.6 半加器", 6, 7, "challenge"],
	["CH01-CH-7", "章末验收", 7, 7, "challenge"],
]

var _board: Control
var _rail_card: PanelContainer
var _rail: VBoxContainer
var _rail_buttons: Dictionary = {}
var _header_task: Label
var _header_sub: Label
var _header_kicker: Label
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

	var kicker := Ui.mono("CHAPTER 01 · 第一章", UiTheme.F_META, UiTheme.MUTED)
	_rail.add_child(kicker)
	_chapter_label = Ui.label(_chapter_name(), 22, UiTheme.CHALK)
	_rail.add_child(_chapter_label)
	_rail.add_child(Ui.gap(12))

	var stat_row := Ui.hbox(10)
	stat_row.custom_minimum_size = Vector2(0, 28)
	_rail.add_child(stat_row)
	stat_row.add_child(Ui.label("节点进度", UiTheme.F_LABEL, UiTheme.MUTED))
	_rail_progress = Ui.label("0 / 36", UiTheme.F_H3, UiTheme.CHALK)
	stat_row.add_child(_rail_progress)

	_progress_bar = ProgressBar.new()
	_progress_bar.custom_minimum_size = Vector2(0, 7)
	_progress_bar.max_value = float(NODES.size())
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
	_rail.add_child(Ui.label("单存档 · 自动写入", UiTheme.F_META, UiTheme.MUTED))
	_rail.add_child(Ui.label("F5 存档 · F9 读档", UiTheme.F_META, UiTheme.MUTED))
	_rail.add_child(Ui.label("ESC 返回开始", UiTheme.F_META, UiTheme.MUTED))

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
	_header_kicker = Ui.label("当前任务", UiTheme.F_META, UiTheme.MUTED)
	task_col.add_child(_header_kicker)
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
	_footer_zoom = Ui.label("滚轮缩放 · 拖拽平移 · 100%", UiTheme.F_BODY, UiTheme.MUTED)
	footer.add_child(_footer_zoom)
	footer.add_child(Ui.spacer())
	footer.add_child(Ui.label("点击当前节点进入实验　ESC 一次回黑板", UiTheme.F_BODY, UiTheme.CHALK))

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
	var lock := Ui.label("未解锁" if locked else "", UiTheme.F_META, UiTheme.MUTED_DIM)
	lock.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	lock.name = "Lock"
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
	_halo = Control.new()
	_halo.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_halo.visible = false
	_halo.draw.connect(_draw_halo)
	_nodes_layer.add_child(_halo)

	for raw in NODES:
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

func _node_record(raw: Array) -> Dictionary:
	var id := str(raw[0])
	var kind := str(raw[4])
	var lab := ""
	var code := ""
	if kind == "milestone" or kind == "challenge":
		if id == "CH01" or id == "CH01-CH-7":
			lab = ""
			code = "CH01" if id == "CH01" else "FINAL"
		else:
			var idx := 0
			if kind == "milestone":
				idx = int(str(raw[0]).split("-")[1]) - 1
			else:
				idx = int(str(raw[0]).split("-")[2]) - 1
			lab = LABS[clampi(idx, 0, LABS.size() - 1)]
			code = "1.%d" % (idx + 1)
	else:
		code = id
	var row := int(raw[3])
	var col := int(raw[2])
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
		"id": id, "title": str(raw[1]), "col": col, "row": row, "kind": kind,
		"lab": lab, "code": code, "pos": pos, "size": Vector2(w, h),
	}

func _node_state(rec: Dictionary) -> String:
	var id := str(rec["id"])
	if id == _current_milestone:
		return "current"
	if rec["kind"] == "knowledge" or rec["kind"] == "skill":
		return "done" if Knowledge.is_unlocked(id) else "locked"
	if id == "CH01" or id == "CH01-CH-7":
		return "done" if ChapterFlow.chapter_complete() else "locked"
	var lab := str(rec["lab"])
	if lab.is_empty():
		return "locked"
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
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb

func _update_node_states() -> void:
	_halo.visible = false
	for raw in NODES:
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
		b.modulate.a = 0.56 if st == "locked" else 1.0
		if title_l != null:
			title_l.add_theme_color_override("font_color", ink)
		if code_l != null:
			code_l.add_theme_color_override("font_color", UiTheme.alpha(ink, 0.72))
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
	for i in 6:
		var a := Vector2(i * 134.0 + 118.0, 26.0)
		var b := Vector2((i + 1) * 134.0, 26.0)
		var done := _lab_index_done(i) and _lab_index_done(i + 1)
		if done:
			_lines.draw_line(a, b, UiTheme.alpha(UiTheme.CHALK, 0.62), 2.4)
		else:
			_lines.draw_dashed_line(a, b, UiTheme.alpha(UiTheme.CHALK, 0.20), 1.4, 7.0)
	# 列内竖茎：从里程碑底部贯到技能行，卡片覆盖处自然被遮住。
	for i in LABS.size():
		var x := i * 134.0 + 59.0
		var done := _lab_index_done(i)
		if done:
			_lines.draw_line(Vector2(x, 52.0), Vector2(x, 302.0), UiTheme.alpha(UiTheme.CHALK, 0.62), 2.4)
		else:
			_lines.draw_dashed_line(Vector2(x, 52.0), Vector2(x, 302.0), UiTheme.alpha(UiTheme.CHALK, 0.20), 1.4, 7.0)

func _lab_index_done(i: int) -> bool:
	if i < 0 or i >= LABS.size():
		return false
	return ChapterFlow.is_objective_done(DataDB.chapter.objective_for_lab(LABS[i]))

func _on_node(rec: Dictionary) -> void:
	var st := _node_state(rec)
	if st == "locked":
		EventBus.toast("还没解锁：先完成前置节点", "warn")
		return
	var id := str(rec["id"])
	if rec["kind"] == "knowledge" or rec["kind"] == "skill":
		_go("skills")
		return
	if id == "CH01" or id == "CH01-CH-7":
		if ChapterFlow.chapter_complete():
			EventBus.toast("第一章已完成；可重跑任一实验或查看档案", "ok")
		else:
			EventBus.toast("完成 6 节实验后自动结算第一章", "warn")
		return
	var lab := str(rec["lab"])
	if not lab.is_empty():
		select_lab(lab, true)

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
		_footer_zoom.text = "滚轮缩放 · 拖拽平移 · %d%%" % int(round(_zoom * 100.0))

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
		var idx := LABS.find(_current_lab)
		if idx >= 0:
			_current_milestone = "CH01-%d" % (idx + 1)

func _refresh() -> void:
	_resolve_current()
	var done := 0
	for lab in LABS:
		if ChapterFlow.is_objective_done(DataDB.chapter.objective_for_lab(lab)):
			done += 1
	var p := GameState.player
	var node_done := 0
	for raw in NODES:
		if _node_state(_node_record(raw)) == "done":
			node_done += 1
	_rail_progress.text = "%d / %d" % [node_done, NODES.size()]
	_progress_bar.max_value = float(NODES.size())
	_progress_bar.value = float(node_done)
	_progress_label.text = "进度 %d/%d" % [done, LABS.size()]
	_gold_label.text = "金币 %d" % int(p.gold)
	if not _current_lab.is_empty():
		var nxt := ChapterFlow.next_objective()
		var meta := DataDB.chapter.lab(_current_lab)
		_header_task.text = str(nxt.get("title", meta.get("title", "")))
		_header_sub.text = "%s · %s" % [str(meta.get("title", "")), str(meta.get("subtitle", ""))]
		_header_kicker.text = "当前任务"
	elif ChapterFlow.chapter_complete():
		_header_task.text = "第一章已完成"
		_header_sub.text = "可重跑任一实验；档案与诊断已解锁"
		_header_kicker.text = "章节状态"
	else:
		_header_task.text = "选择节点继续"
		_header_sub.text = "点击当前节点进入实验"
		_header_kicker.text = "当前任务"
	_set_rail_active("labs", true)
	var archive_on := done >= 3
	_rail_buttons["archive"].disabled = not archive_on
	var diag_on := p.has_flag("gate:T1.1-1")
	_rail_buttons["diagnostics"].disabled = not diag_on
	_update_rail_lock("archive", not archive_on, "完成 3 节后解锁")
	_update_rail_lock("diagnostics", not diag_on, "首次通过门实验")
	_update_node_states()
	refresh_status_for_pages()

func _update_rail_lock(key: String, locked: bool, reason: String) -> void:
	var b: Button = _rail_buttons.get(key, null)
	if b == null:
		return
	b.disabled = locked
	b.add_theme_stylebox_override("normal", _rail_style(false, locked))
	var lock := b.find_child("Lock", true, false) as Label
	if lock != null:
		lock.text = reason if locked else ""
	var cap := b.find_child("Caption", true, false) as Label
	if cap != null:
		cap.add_theme_color_override("font_color", UiTheme.MUTED_DIM if locked else UiTheme.CHALK)

func _go(id: String) -> void:
	if main != null and main.has_method("show_screen"):
		main.show_screen(id)

func _enter_current_lab() -> void:
	if _current_lab.is_empty():
		EventBus.toast("本章已全部完成；可从挑战节点重跑", "ok")
		return
	if not ChapterFlow.is_lab_unlocked(_current_lab):
		EventBus.toast("当前实验室尚未解锁", "warn")
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
