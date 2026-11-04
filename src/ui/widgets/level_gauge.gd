class_name LevelGauge
extends Control

## 电平可视化：灯泡 + 三段电压带（0 / X 禁止区 / 1）+ 双阈值标记。

var voltage := 0.0
var low_max := 0.8
var high_min := 2.0
var max_voltage := 3.3
var _font: Font

func _ready() -> void:
	custom_minimum_size = Vector2(0, 270)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = UiTheme.cjk_font()

func set_values(v: float, low: float, high: float, maxv: float) -> void:
	voltage = v
	low_max = low
	high_min = high
	max_voltage = maxv
	queue_redraw()

func _logic() -> String:
	return VoltageModel.judge(voltage, low_max, high_min)

func _draw() -> void:
	var w := size.x
	var h := size.y
	if w <= 60.0 or h <= 60.0:
		return
	var logic := _logic()
	var center := Vector2(w * 0.5, 76.0)

	if logic == SimValue.ONE:
		for i in range(5, 0, -1):
			draw_circle(center, 30.0 + i * 8.0, UiTheme.alpha(UiTheme.AMBER, 0.05))
	draw_circle(center, 34.0, Color(0.075, 0.098, 0.125))
	draw_arc(center, 34.0, 0.0, TAU, 48, UiTheme.BORDER, 2.0, true)
	var fill := Color(0.13, 0.17, 0.21)
	if logic == SimValue.ONE:
		fill = Color(1.0, 0.83, 0.50)
	elif logic == SimValue.X:
		fill = Color(0.95, 0.45, 0.30)
	draw_circle(center, 26.0, fill)
	draw_line(center + Vector2(-11, 0), center + Vector2(11, 0), UiTheme.AMBER if logic == SimValue.ONE else UiTheme.MUTED, 2.0)
	var text := "灯泡 · %s" % ("亮" if logic == SimValue.ONE else ("不确定" if logic == SimValue.X else "灭"))
	draw_string(_font, Vector2(center.x - 110, center.y + 60), text, HORIZONTAL_ALIGNMENT_CENTER, 220, 16, UiTheme.TEXT if logic == SimValue.ONE else UiTheme.MUTED)
	draw_string(_font, Vector2(center.x - 110, center.y + 84), "判读 %s" % logic, HORIZONTAL_ALIGNMENT_CENTER, 220, 22, UiTheme.OK if logic == SimValue.ONE else (UiTheme.DANGER if logic == SimValue.X else UiTheme.MUTED))

	var bar := Rect2(56.0, h - 62.0, w - 112.0, 16.0)
	var low_x := bar.position.x + bar.size.x * (low_max / max_voltage)
	var high_x := bar.position.x + bar.size.x * (high_min / max_voltage)
	draw_rect(Rect2(bar.position, Vector2(low_x - bar.position.x, bar.size.y)), UiTheme.alpha(UiTheme.MUTED, 0.35), true)
	draw_rect(Rect2(Vector2(low_x, bar.position.y), Vector2(high_x - low_x, bar.size.y)), UiTheme.alpha(UiTheme.DANGER, 0.25), true)
	draw_rect(Rect2(Vector2(high_x, bar.position.y), Vector2(bar.end.x - high_x, bar.size.y)), UiTheme.alpha(UiTheme.OK, 0.30), true)

	var fx := bar.position.x + bar.size.x * clampf(voltage / max_voltage, 0.0, 1.0)
	draw_line(Vector2(fx, bar.position.y - 10), Vector2(fx, bar.end.y + 10), UiTheme.AMBER, 2.0)
	draw_circle(Vector2(fx, bar.position.y + bar.size.y * 0.5), 4.0, UiTheme.AMBER)

	draw_line(Vector2(low_x, bar.position.y - 6), Vector2(low_x, bar.end.y + 6), UiTheme.DANGER, 1.2)
	draw_line(Vector2(high_x, bar.position.y - 6), Vector2(high_x, bar.end.y + 6), UiTheme.OK, 1.2)
	draw_string(_font, Vector2(low_x - 46, bar.position.y - 10), "%.1f V" % low_max, HORIZONTAL_ALIGNMENT_CENTER, 92, 14, UiTheme.DANGER)
	draw_string(_font, Vector2(high_x - 46, bar.position.y - 10), "%.1f V" % high_min, HORIZONTAL_ALIGNMENT_CENTER, 92, 14, UiTheme.OK)
	draw_string(_font, Vector2(bar.position.x, bar.end.y + 20), "0 V", HORIZONTAL_ALIGNMENT_LEFT, 60, 14, UiTheme.MUTED)
	draw_string(_font, Vector2(bar.end.x - 70, bar.end.y + 20), "%.1f V" % max_voltage, HORIZONTAL_ALIGNMENT_RIGHT, 70, 14, UiTheme.MUTED)
	draw_string(_font, Vector2(low_x, bar.end.y + 20), "0", HORIZONTAL_ALIGNMENT_CENTER, high_x - low_x, 14, UiTheme.DANGER)
	draw_string(_font, Vector2(high_x, bar.end.y + 20), "1", HORIZONTAL_ALIGNMENT_CENTER, bar.end.x - high_x, 14, UiTheme.OK)
