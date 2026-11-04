class_name LabDraw
extends RefCounted

## 实验室共用绘制：虚线、45° 斜线、按层编码的器件图标。
## 只画几何，不写任何状态文字；三态靠色条/底色/叉号/斜线，不靠颜色本身。

static func dash_rect(ci: CanvasItem, r: Rect2, c: Color, dash: float = 4.0, step: float = 7.0) -> void:
	var x := r.position.x
	while x < r.end.x:
		var x2 := minf(x + dash, r.end.x)
		ci.draw_line(Vector2(x, r.position.y), Vector2(x2, r.position.y), c, 1.0)
		ci.draw_line(Vector2(x, r.end.y), Vector2(x2, r.end.y), c, 1.0)
		x += step
	var y := r.position.y
	while y < r.end.y:
		var y2 := minf(y + dash, r.end.y)
		ci.draw_line(Vector2(r.position.x, y), Vector2(r.position.x, y2), c, 1.0)
		ci.draw_line(Vector2(r.end.x, y), Vector2(r.end.x, y2), c, 1.0)
		y += step

## 45° 斜线填充：锁定态用，不占用任何文字。
static func hatch(ci: CanvasItem, r: Rect2, c: Color, step: float = 10.0, width: float = 1.0) -> void:
	var x := r.position.x - r.size.y
	while x < r.end.x:
		var a := Vector2(maxf(x, r.position.x), r.end.y - maxf(0.0, r.position.x - x))
		var b := Vector2(minf(x + r.size.y, r.end.x), r.position.y + maxf(0.0, x + r.size.y - r.end.x))
		ci.draw_line(a, b, c, width)
		x += step

## 缺件叉号：14×14 红叉，压在材料图标右上角。
static func cross(ci: CanvasItem, center: Vector2, color: Color, size: float = 7.0) -> void:
	ci.draw_line(center - Vector2(size, size), center + Vector2(size, size), color, 1.6)
	ci.draw_line(center + Vector2(size, -size), center - Vector2(size, -size), color, 1.6)

## 前置小节点：16×16，只写 ≤3 字符节点缩写。
static func prereq_node(ci: CanvasItem, r: Rect2, token: String, color: Color) -> void:
	ci.draw_rect(r, UiTheme.alpha(color, 0.10), true)
	ci.draw_rect(r, color, false, 1.0)
	var f := UiTheme.mono_font()
	ci.draw_string(f, r.position + Vector2(0, r.size.y * 0.5 + 5), token,
		HORIZONTAL_ALIGNMENT_CENTER, r.size.x, UiTheme.F_META, color)

## 按物品层编码的图标：
##  L0 散件/元件：方框 + 中心点；L1 门：D 形；L2 开关：断点线；
##  L3 传感：圆 + 探针；L4 模块：芯片 + 8×8 角标；L5 代码：&lt;/&gt;。
## 图标只表达类别，不承担“能不能做”的状态。
static func item_icon(ci: CanvasItem, r: Rect2, item_id: String, layer: String, color: Color) -> void:
	var c := r.position
	var s := r.size
	match layer:
		"L1":
			_gate_shape(ci, r, color)
		"L2":
			var y := c.y + s.y * 0.5
			ci.draw_line(Vector2(c.x + s.x * 0.12, y), Vector2(c.x + s.x * 0.40, y), color, 1.6)
			ci.draw_line(Vector2(c.x + s.x * 0.62, y), Vector2(c.x + s.x * 0.88, y), color, 1.6)
			ci.draw_circle(Vector2(c.x + s.x * 0.52, y - s.y * 0.18), s.x * 0.06, color)
			ci.draw_line(Vector2(c.x + s.x * 0.52, y - s.y * 0.18), Vector2(c.x + s.x * 0.64, y), color, 1.2)
		"L3":
			ci.draw_arc(c + s * 0.5, s.x * 0.30, 0.0, TAU, 20, color, 1.4)
			ci.draw_line(c + Vector2(s.x * 0.5, s.y * 0.2), c + Vector2(s.x * 0.5, s.y * 0.05), color, 1.2)
		"L4":
			ci.draw_rect(Rect2(c + s * 0.12, s * 0.72), UiTheme.alpha(color, 0.16), true)
			ci.draw_rect(Rect2(c + s * 0.12, s * 0.72), color, false, 1.2)
			for i in 4:
				var px := c.x + s.x * (0.22 + 0.18 * i)
				ci.draw_line(Vector2(px, c.y + s.y * 0.12), Vector2(px, c.y + s.y * 0.24), color, 1.0)
				ci.draw_line(Vector2(px, c.y + s.y * 0.72), Vector2(px, c.y + s.y * 0.84), color, 1.0)
			ci.draw_rect(Rect2(c + Vector2(s.x * 0.72, s.y * 0.06), Vector2(8, 8)), color, true)
		"L5":
			ci.draw_string(UiTheme.mono_font(), c + Vector2(0, s.y * 0.5 + 6), "</>",
				HORIZONTAL_ALIGNMENT_CENTER, s.x, int(maxf(12.0, s.y * 0.34)), color)
		_:
			ci.draw_rect(Rect2(c + s * 0.18, s * 0.64), UiTheme.alpha(color, 0.16), true)
			ci.draw_rect(Rect2(c + s * 0.18, s * 0.64), color, false, 1.0)
			ci.draw_circle(c + s * 0.5, maxf(2.0, s.x * 0.07), color)

static func _gate_shape(ci: CanvasItem, r: Rect2, color: Color) -> void:
	var c := r.position
	var s := r.size
	var pts := PackedVector2Array([
		c + Vector2(s.x * 0.16, s.y * 0.22),
		c + Vector2(s.x * 0.62, s.y * 0.22),
		c + Vector2(s.x * 0.86, s.y * 0.50),
		c + Vector2(s.x * 0.62, s.y * 0.78),
		c + Vector2(s.x * 0.16, s.y * 0.78),
	])
	ci.draw_colored_polygon(pts, UiTheme.alpha(color, 0.16))
	ci.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[4], pts[0]]), color, 1.2)
	ci.draw_line(c + Vector2(s.x * 0.02, s.y * 0.42), c + Vector2(s.x * 0.16, s.y * 0.42), color, 1.0)
	ci.draw_line(c + Vector2(s.x * 0.02, s.y * 0.58), c + Vector2(s.x * 0.16, s.y * 0.58), color, 1.0)
	ci.draw_line(c + Vector2(s.x * 0.86, s.y * 0.50), c + Vector2(s.x * 0.98, s.y * 0.50), color, 1.0)

static func layer_of(item_id: String, catalog: Catalog) -> String:
	return str(catalog.item(item_id).get("layer", ""))
