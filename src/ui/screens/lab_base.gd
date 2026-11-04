class_name LabBase
extends Control

## 三级页统一骨架：返回条 / 左步骤栏 / 中编辑区 / 右检查器 / 底部结果条。
## 子类只实现 `_build()`，把内容放进 side / center / inspector，结果写进 result。

signal solved(lab_id: String)

var main: Control
var lab_id := ""
var lab_data: Dictionary = {}
var objective_id := ""

var side: VBoxContainer
var center: VBoxContainer
var inspector: VBoxContainer

var _side_card: PanelContainer
var _inspector_card: PanelContainer
var _header_title: Label
var _header_code: Label
var _status_badge: Label
var _gold_label: Label
var _result_strip: PanelContainer
var _result_bar: ColorRect
var _result_title: Label
var _result_detail: Label
var _result_ok := false

func setup(main_ref: Control, p_lab_id: String) -> void:
	main = main_ref
	lab_id = p_lab_id
	objective_id = DataDB.chapter.objective_for_lab(lab_id)
	var meta := DataDB.chapter.lab(lab_id)
	lab_data = DataDB.lab_data(str(meta.get("data_key", "")))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell(meta)
	_build()
	_finish_shell()
	refresh_status()

func _build_shell(meta: Dictionary) -> void:
	# 背景 + 6px 木框 + 黑板。左右各 18 内容边距，中心净宽 696。
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var frame := ColorRect.new()
	frame.color = UiTheme.FRAME
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var board := ColorRect.new()
	board.color = UiTheme.BOARD
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 6
	board.offset_top = 6
	board.offset_right = -6
	board.offset_bottom = -6
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	var grain := GrainOverlay.new()
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.offset_left = 6
	grain.offset_top = 6
	grain.offset_right = -6
	grain.offset_bottom = -6
	add_child(grain)

	var content := Ui.margin4(18, 10, 18, 10)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 6
	content.offset_top = 6
	content.offset_right = -6
	content.offset_bottom = -6
	add_child(content)
	var root := Ui.vbox(10)
	content.add_child(root)

	# 返回条 66
	var header := Ui.hbox(14)
	header.custom_minimum_size = Vector2(0, 66)
	root.add_child(header)
	var back := Ui.ghost("← 返回黑板", func(): _go_back())
	back.custom_minimum_size = Vector2(140, UiTheme.CONTROL_H)
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(back)
	var title_col := Ui.vbox(0)
	title_col.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title_col)
	_header_title = Ui.label(str(lab_data.get("title", meta.get("title", lab_id))), UiTheme.F_H2, UiTheme.CHALK)
	title_col.add_child(_header_title)
	_header_code = Ui.label(_code_text(meta), UiTheme.F_LABEL, UiTheme.MUTED)
	_header_code.add_theme_font_override("font", UiTheme.mono_font())
	title_col.add_child(_header_code)
	header.add_child(Ui.spacer())
	_status_badge = Ui.label("进行中", UiTheme.F_META, UiTheme.AMBER)
	_status_badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_status_badge)
	var gold_dot := ColorRect.new()
	gold_dot.color = UiTheme.AMBER
	gold_dot.custom_minimum_size = Vector2(6, 6)
	gold_dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	gold_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(gold_dot)
	_gold_label = Ui.label("金币 --", UiTheme.F_BODY, UiTheme.AMBER)
	_gold_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(_gold_label)

	# 三栏
	var body := Ui.hbox(18)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(body)

	_side_card = Ui.card(UiTheme.alpha(UiTheme.CHALK, 0.04), UiTheme.LINE)
	_side_card.custom_minimum_size = Vector2(248, 0)
	_side_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_side_card)
	side = Ui.vbox(6)
	_side_card.add_child(side)

	center = Ui.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)

	_inspector_card = Ui.card(UiTheme.alpha(UiTheme.CHALK, 0.04), UiTheme.LINE)
	_inspector_card.custom_minimum_size = Vector2(252, 0)
	_inspector_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_inspector_card)
	inspector = Ui.vbox(6)
	_inspector_card.add_child(inspector)

	# 结果条 58（上下内边距收紧到 5，保证 58 而不是 62）
	_result_strip = Ui.card(UiTheme.BOARD_SUNK, UiTheme.LINE)
	_result_strip.custom_minimum_size = Vector2(0, 58)
	var strip_sb: StyleBoxFlat = UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.LINE)
	strip_sb.content_margin_top = 5
	strip_sb.content_margin_bottom = 5
	_result_strip.add_theme_stylebox_override("panel", strip_sb)
	root.add_child(_result_strip)
	var rm := Ui.hbox(12)
	_result_strip.add_child(rm)
	_result_bar = ColorRect.new()
	_result_bar.color = UiTheme.LINE_STRONG
	_result_bar.custom_minimum_size = Vector2(3, 0)
	_result_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rm.add_child(_result_bar)
	var rc := Ui.vbox(0)
	rc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rm.add_child(rc)
	_result_title = Ui.label("等待验收", UiTheme.F_BODY, UiTheme.CHALK)
	rc.add_child(_result_title)
	_result_detail = Ui.label("按右侧按钮运行；结果会直接写回存档。", UiTheme.F_BODY, UiTheme.MUTED)
	_result_detail.clip_text = true
	_result_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_result_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.add_child(_result_detail)

func _build() -> void:
	pass

func _code_text(meta: Dictionary) -> String:
	## 编号跟着当前章节走：T2.1 / T3.4 …，不再固定 T1。
	var order := int(meta.get("order", 0))
	var gates: Array = meta.get("gate_ids", [])
	return "T%d.%d · %d 项验收 · %s" % [int(DataDB.chapter.data.get("number", 1)), order, gates.size(), str(meta.get("subtitle", ""))]

func _finish_shell() -> void:
	## 子类 `_build()` 结束后调用：没用的检查器列直接隐藏，把宽度让给编辑区。
	if _inspector_card != null and inspector.get_child_count() == 0:
		_inspector_card.visible = false

func refresh_status() -> void:
	if GameState.player == null:
		return
	if _status_badge != null:
		_status_badge.text = "已完成" if is_done() else "进行中"
		_status_badge.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if is_done() else UiTheme.AMBER)
	if _gold_label != null:
		_gold_label.text = "金币 %d" % GameState.player.gold

func is_done() -> bool:
	return ChapterFlow.is_objective_done(objective_id)

func complete_once() -> void:
	if is_done():
		return
	solved.emit(lab_id)
	refresh_status()
	if _result_ok:
		var reward: Dictionary = DataDB.chapter.lab(lab_id).get("reward", {})
		_result_detail.text = "已记账 · 金币 +%d · XP +%d" % [int(reward.get("gold", 0)), int(reward.get("xp", 0))]
		_result_detail.add_theme_color_override("font_color", UiTheme.CHALK)

func scripted_solve() -> bool:
	return false

func save_state(data: Dictionary) -> void:
	if GameState.player == null:
		return
	GameState.player.set_flag("labstate:%s" % lab_id, data)
	EventBus.state_changed.emit()

func load_state() -> Dictionary:
	if GameState.player == null:
		return {}
	var raw: Variant = GameState.player.get_flag("labstate:%s" % lab_id, {})
	return raw if raw is Dictionary else {}

func mark_gate(gate_id: String, ok: bool = true) -> void:
	if GameState.player == null:
		return
	GameState.player.set_flag("gate:%s" % gate_id, ok)

func gate_passed(gate_id: String) -> bool:
	return ChapterFlow.gate_passed(gate_id)

func pass_report(report: GateReport) -> bool:
	## gate 结果逐条写存档；全部 required 通过才允许完成。
	if report == null or not report.all_required_passed():
		return false
	for raw in report.cases:
		var c: Dictionary = raw
		if bool(c.get("ok", false)):
			mark_gate(str(c.get("id", "")), true)
	EventBus.state_changed.emit()
	complete_once()
	return true

func show_report(report: GateReport) -> void:
	if report == null:
		return
	var ok_count := 0
	var fail_details: Array = []
	for raw in report.cases:
		var c: Dictionary = raw
		if bool(c.get("ok", false)):
			ok_count += 1
		else:
			fail_details.append("%s %s" % [str(c.get("id", "")), str(c.get("detail", ""))])
	_result_ok = ok_count == report.cases.size()
	var color := UiTheme.CHALK_BRIGHT if _result_ok else UiTheme.DANGER
	_result_bar.color = color
	_result_strip.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.alpha(color, 0.7)))
	_result_title.text = "验收 · 通过 %d/%d" % [ok_count, report.cases.size()]
	_result_title.add_theme_color_override("font_color", color)
	if fail_details.is_empty():
		_result_detail.text = "全部通过，结果已写回存档。" if is_done() else "全部通过，正在记账…"
		_result_detail.add_theme_color_override("font_color", UiTheme.CHALK)
	else:
		_result_detail.text = "未通过：" + " / ".join(PackedStringArray(fail_details))
		_result_detail.add_theme_color_override("font_color", UiTheme.RUST)

func _go_back() -> void:
	if main != null and main.has_method("back_to_hub"):
		main.back_to_hub()

func _task_row(text: String) -> Array:
	var row := Ui.hbox(8)
	var name_label := Ui.label(text, UiTheme.F_BODY, UiTheme.CHALK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = text
	row.add_child(name_label)
	row.add_child(Ui.spacer())
	var status := Ui.label("待完成", UiTheme.F_META, UiTheme.MUTED)
	row.add_child(status)
	return [row, status]

func _mark(label: Label, done: bool, done_text: String = "已完成") -> void:
	label.text = done_text if done else "待完成"
	label.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if done else UiTheme.MUTED)

func _section(text: String) -> Label:
	var l := Ui.label(text, UiTheme.F_META, UiTheme.MUTED)
	return l

func _body_card(text: String) -> PanelContainer:
	var card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	var m := Ui.margin4(12, 9, 12, 9)
	card.add_child(m)
	m.add_child(Ui.wrap(text, UiTheme.F_BODY, UiTheme.MUTED))
	return card

func _hint_card(text: String) -> PanelContainer:
	var card := Ui.card(UiTheme.alpha(UiTheme.CYAN, 0.05), UiTheme.alpha(UiTheme.CYAN, 0.35))
	var m := Ui.margin4(12, 8, 12, 8)
	card.add_child(m)
	m.add_child(Ui.wrap(text, UiTheme.F_BODY, UiTheme.CYAN))
	return card
