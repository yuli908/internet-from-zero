class_name Waveform
extends Control

## 数字波形：输入 [{t:int, v:"0"/"1"/"X"}]，按 tick 画阶梯线并高亮窄脉冲。

var changes: Array = []
var span := 24
var label := ""
var _font: Font

func _ready() -> void:
	custom_minimum_size = Vector2(0, 150)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.mono_font()

func set_changes(rows: Array, tick_span: int = 24, title: String = "") -> void:
	changes = rows
	span = maxi(tick_span, 1)
	label = title
	queue_redraw()

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w < 80.0 or h < 60.0:
		return
	var pad := Vector2(52.0, 30.0)
	var plot := Rect2(pad.x, pad.y, w - pad.x - 18.0, h - pad.y - 34.0)
	draw_rect(plot, Color(0.043, 0.059, 0.075), true)
	draw_rect(plot, UiTheme.BORDER, false, 1.0)
	for i in range(0, span + 1, 4):
		var x := plot.position.x + plot.size.x * float(i) / float(span)
		draw_line(Vector2(x, plot.position.y), Vector2(x, plot.end.y), UiTheme.alpha(UiTheme.BORDER, 0.35), 1.0)
		draw_string(_font, Vector2(x - 12, plot.position.y - 6), str(i), HORIZONTAL_ALIGNMENT_CENTER, 24, 10, UiTheme.MUTED)
	if label.is_empty():
		draw_string(_font, Vector2(plot.position.x, plot.position.y - 18), "wire", HORIZONTAL_ALIGNMENT_LEFT, 200, 11, UiTheme.MUTED)
	else:
		draw_string(_font, Vector2(plot.position.x, plot.position.y - 18), label, HORIZONTAL_ALIGNMENT_LEFT, 300, 11, UiTheme.ACCENT)

	var hi_y := plot.position.y + 10.0
	var lo_y := plot.end.y - 10.0
	var mid_y := (hi_y + lo_y) * 0.5
	var prev_v := "0"
	var prev_x := plot.position.x
	if not changes.is_empty():
		var first: Dictionary = changes[0]
		if int(first.get("t", 0)) < 0:
			prev_v = str(first.get("v", "0"))
	for raw in changes:
		if not (raw is Dictionary):
			continue
		var ev: Dictionary = raw
		var t := int(ev.get("t", 0))
		var v := str(ev.get("v", "0"))
		var x := plot.position.x + plot.size.x * clampf(float(t) / float(span), 0.0, 1.0)
		_draw_segment(prev_x, x, prev_v, hi_y, lo_y, mid_y)
		if x - prev_x <= 6.0:
			draw_rect(Rect2(prev_x - 1.0, hi_y, maxf(x - prev_x, 2.0), lo_y - hi_y), UiTheme.alpha(UiTheme.DANGER, 0.18), true)
		prev_v = v
		prev_x = x
	_draw_segment(prev_x, plot.end.x, prev_v, hi_y, lo_y, mid_y)

func _draw_segment(x0: float, x1: float, v: String, hi_y: float, lo_y: float, mid_y: float) -> void:
	if x1 <= x0:
		return
	var y := mid_y
	var color := UiTheme.MUTED
	if v == "1":
		y = hi_y
		color = UiTheme.OK
	elif v == "0":
		y = lo_y
		color = UiTheme.ACCENT
	else:
		y = mid_y
		color = UiTheme.DANGER
	draw_line(Vector2(x0, y), Vector2(x1, y), color, 2.5)
	if x0 <= x1:
		draw_line(Vector2(x0, y), Vector2(x0, mid_y), color, 1.0)
