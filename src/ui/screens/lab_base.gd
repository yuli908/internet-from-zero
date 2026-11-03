class_name LabBase
extends Control

## 实验页基类：统一标题、说明、完成判定与解锁徽标。

signal solved(lab_id: String)

var main: Control
var lab_id := ""
var lab_data: Dictionary = {}
var objective_id := ""
var _status_slot: HBoxContainer

func setup(main_ref: Control, p_lab_id: String) -> void:
	main = main_ref
	lab_id = p_lab_id
	objective_id = DataDB.chapter.objective_for_lab(lab_id)
	var meta := DataDB.chapter.lab(lab_id)
	lab_data = DataDB.lab_data(str(meta.get("data_key", "")))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	_wrap_scroll()
	refresh_status()

func _wrap_scroll() -> void:
	## 实验页内容可能高于可视区：统一套一层滚动容器，并把唯一根节点撑满。
	if get_child_count() != 1:
		return
	var content: Control = get_child(0)
	remove_child(content)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(content)

func _build() -> void:
	pass

func _build_header(title_text: String, subtitle_text: String) -> VBoxContainer:
	var col := Ui.vbox(4)
	var row := Ui.hbox(10)
	row.add_child(Ui.label(title_text, 20, UiTheme.TEXT))
	row.add_child(Ui.spacer())
	_status_slot = Ui.hbox(6)
	_status_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(_status_slot)
	col.add_child(row)
	col.add_child(Ui.label(subtitle_text, 12, UiTheme.MUTED))
	return col

func _body_card(text: String) -> PanelContainer:
	var card := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
	var m := Ui.margin4(12, 9, 12, 9)
	card.add_child(m)
	m.add_child(Ui.wrap(text, 13, UiTheme.MUTED))
	return card

func _hint_card(text: String) -> PanelContainer:
	var card := Ui.card(UiTheme.alpha(UiTheme.ACCENT, 0.05), UiTheme.alpha(UiTheme.ACCENT, 0.35), 8)
	var m := Ui.margin4(12, 8, 12, 8)
	card.add_child(m)
	m.add_child(Ui.wrap(text, 12, UiTheme.ACCENT))
	return card

func is_done() -> bool:
	return ChapterFlow.is_objective_done(objective_id)

func refresh_status() -> void:
	if _status_slot == null:
		return
	for c in _status_slot.get_children():
		c.queue_free()
	if is_done():
		_status_slot.add_child(Ui.badge("已完成", UiTheme.OK))
	else:
		_status_slot.add_child(Ui.badge("进行中", UiTheme.AMBER))

func complete_once() -> void:
	if is_done():
		return
	solved.emit(lab_id)
	refresh_status()

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

func _mark(label: Label, done: bool, done_text: String = "已完成") -> void:
	label.text = done_text if done else "待完成"
	label.add_theme_color_override("font_color", UiTheme.OK if done else UiTheme.MUTED)

func _task_row(text: String) -> Array:
	var row := Ui.hbox(8)
	var name_label := Ui.label(text, 13, UiTheme.TEXT)
	row.add_child(name_label)
	row.add_child(Ui.spacer())
	var status := Ui.label("待完成", 12, UiTheme.MUTED)
	row.add_child(status)
	return [row, status]
