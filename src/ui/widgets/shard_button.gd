class_name ShardButton
extends Control

## 45° 菱形碎片菜单的单块：_draw 多边形 + 反向旋转 Label，无 shader、无圆角。

signal activated
signal hovered

const SIZE := Vector2(340, 167)

var label_text := ""
var mirrored := false

var _selected := false
var _hover := false
var _points := PackedVector2Array()
var _label: Label
var _font: FontVariation
var _font_sel: FontVariation

func setup(text: String, mirrored_shard: bool) -> void:
	label_text = text
	mirrored = mirrored_shard
	custom_minimum_size = SIZE
	size = SIZE
	clip_contents = false
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	_points = _build_points(mirrored)
	_font = _make_font(6)
	_font_sel = _make_font(7)
	_label = Label.new()
	_label.text = text
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_label.clip_text = true
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.add_theme_font_size_override("font_size", UiTheme.F_H2)
	_label.add_theme_color_override("font_color", Color("#AAB6AF"))
	_label.add_theme_font_override("font", _font)
	_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_label)
	_label.rotation = deg_to_rad(-45.0)
	_label.resized.connect(_sync_label)
	resized.connect(_sync_label)
	_sync_label()
	queue_redraw()

func _make_font(spacing: int) -> FontVariation:
	var f := FontVariation.new()
	f.base_font = UiTheme.cjk_font()
	f.spacing_glyph = spacing
	f.spacing_space = spacing
	return f

func _build_points(mirror: bool) -> PackedVector2Array:
	if mirror:
		# 右上块：左上 / 右上切角，下方两角直角。
		return PackedVector2Array([
			Vector2(0, 11.7), Vector2(30.6, 0), Vector2(340, 0),
			Vector2(340, 147.0), Vector2(309.4, 167), Vector2(0, 167),
		])
	# 左下块：右下 / 左下切角，上方两角直角。
	return PackedVector2Array([
		Vector2(0, 0), Vector2(340, 0), Vector2(340, 155.3),
		Vector2(309.4, 167), Vector2(30.6, 167), Vector2(0, 147.0),
	])

func _sync_label() -> void:
	if _label == null:
		return
	_label.pivot_offset = SIZE * 0.5

func set_selected(on: bool) -> void:
	if _selected == on:
		return
	_selected = on
	_label.add_theme_font_override("font", _font_sel if on else _font)
	_label.add_theme_color_override("font_color", Color("#F5F1E6") if on else Color("#AAB6AF"))
	queue_redraw()

func _draw() -> void:
	var on := _selected or has_focus()
	draw_colored_polygon(_points, Color("#2A352F") if on else Color("#151A17"))
	var border := Color("#D9E4DC") if on else Color("#2B3530")
	draw_polyline(_points + PackedVector2Array([_points[0]]), border, 2.0 if has_focus() else 1.0, false)
	if on:
		draw_line(Vector2(1, 2), Vector2(1, SIZE.y - 2), Color("#D9E4DC"), 2.0)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if Geometry2D.is_point_in_polygon(event.position, _points):
			accept_event()
			activated.emit()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.is_action_pressed("ui_accept"):
			accept_event()
			activated.emit()
		return

func _notification(what: int) -> void:
	if what == NOTIFICATION_MOUSE_ENTER:
		_hover = true
		hovered.emit()
	elif what == NOTIFICATION_MOUSE_EXIT:
		_hover = false
	elif what == NOTIFICATION_FOCUS_ENTER:
		queue_redraw()
	elif what == NOTIFICATION_FOCUS_EXIT:
		queue_redraw()
