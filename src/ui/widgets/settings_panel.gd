class_name SettingsPanel
extends Control

## 内联设置层（不是 OS 弹窗）：动效与颗粒开关，关闭即恢复。

signal closed
signal motion_changed(on: bool)
signal texture_changed(on: bool)

var _panel: PanelContainer
var _motion_toggle: Button
var _texture_toggle: Button

func _ready() -> void:
	add_to_group("ifz_settings")
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.028, 0.72)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	_panel = Ui.card(UiTheme.BOARD, UiTheme.LINE_STRONG)
	_panel.custom_minimum_size = Vector2(520, 300)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	add_child(_panel)

	var m := Ui.margin4(28, 22, 28, 20)
	_panel.add_child(m)
	var col := Ui.vbox(12)
	m.add_child(col)
	col.add_child(Ui.label("设置", UiTheme.F_H2, UiTheme.CHALK))
	col.add_child(Ui.label("只影响表现层；关闭后所有粉笔动效瞬切。", UiTheme.F_BODY, UiTheme.MUTED))
	col.add_child(Ui.gap(8))

	var motion_row := _row("粉笔动效", "叠字晃动、节点扫光、选中淡入")
	col.add_child(motion_row)
	_motion_toggle = Ui.toggle("开" if UiTheme.motion else "关", _toggle_motion, UiTheme.motion)
	_motion_toggle.custom_minimum_size = Vector2(64, 32)
	motion_row.add_child(_motion_toggle)

	var tex_row := _row("颗粒纹理", "黑板与开始界面的静态噪点")
	col.add_child(tex_row)
	_texture_toggle = Ui.toggle("开" if UiTheme.texture_enabled else "关", _toggle_texture, UiTheme.texture_enabled)
	_texture_toggle.custom_minimum_size = Vector2(64, 32)
	tex_row.add_child(_texture_toggle)

	col.add_child(Ui.spacer())
	var foot := Ui.hbox(10)
	foot.alignment = BoxContainer.ALIGNMENT_END
	foot.add_child(Ui.ghost("关闭", close_panel))
	col.add_child(foot)

func _row(title: String, desc: String) -> HBoxContainer:
	var row := Ui.hbox(18)
	row.custom_minimum_size = Vector2(0, 58)
	var col := Ui.vbox(2)
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(Ui.label(title, UiTheme.F_BODY_LG, UiTheme.CHALK))
	col.add_child(Ui.label(desc, UiTheme.F_BODY, UiTheme.MUTED))
	row.add_child(col)
	return row

func open() -> void:
	_motion_toggle.set_pressed_no_signal(UiTheme.motion)
	_motion_toggle.text = "开" if UiTheme.motion else "关"
	_texture_toggle.set_pressed_no_signal(UiTheme.texture_enabled)
	_texture_toggle.text = "开" if UiTheme.texture_enabled else "关"
	visible = true
	move_to_front()

func close_panel() -> void:
	visible = false
	closed.emit()

func _toggle_motion(on: bool) -> void:
	UiTheme.motion = on
	_motion_toggle.text = "开" if on else "关"
	motion_changed.emit(on)

func _toggle_texture(on: bool) -> void:
	UiTheme.texture_enabled = on
	_texture_toggle.text = "开" if on else "关"
	for node in get_tree().get_nodes_in_group("ifz_grain"):
		if node is CanvasItem:
			(node as CanvasItem).visible = on
	texture_changed.emit(on)

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close_panel()
