class_name Ui
extends RefCounted

## 轻量 UI 构造工具，避免在每个界面里重复写布局样板。
## 字号在这里统一兜底：标签 ≥14、正文 ≥16，禁止 10–12 px。

static func _min_label(size: int) -> int:
	return maxi(size, UiTheme.F_META)

static func _min_body(size: int) -> int:
	return maxi(size, UiTheme.F_BODY)

static func label(text: String, size: int = UiTheme.F_BODY_LG, color: Color = UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", _min_label(size))
	l.add_theme_color_override("font_color", color)
	return l

static func mono(text: String, size: int = 18, color: Color = UiTheme.CYAN) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", UiTheme.mono_font())
	return l

static func title(text: String, size: int = UiTheme.F_H2) -> Label:
	return label(text, maxi(size, UiTheme.F_H3), UiTheme.CHALK)

static func muted(text: String, size: int = UiTheme.F_META) -> Label:
	return label(text, size, UiTheme.MUTED)

static func wrap(text: String, size: int = UiTheme.F_BODY, color: Color = UiTheme.MUTED) -> Label:
	var l := label(text, _min_body(size), color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l

static func vbox(sep: int = 8) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", sep)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return v

static func hbox(sep: int = 8) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", sep)
	h.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return h

static func spacer() -> Control:
	var c := Control.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func gap(height: int = 8) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, height)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func vseparator() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.custom_minimum_size = Vector2(1, 0)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hourglass(width: int = 1) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(width, 1)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func hline(color: Color = UiTheme.LINE) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.custom_minimum_size = Vector2(0, 1)
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r

static func margin(all: int = 12) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", all)
	m.add_theme_constant_override("margin_right", all)
	m.add_theme_constant_override("margin_top", all)
	m.add_theme_constant_override("margin_bottom", all)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return m

static func margin4(left: int, top: int, right: int, bottom: int) -> MarginContainer:
	var m := MarginContainer.new()
	m.add_theme_constant_override("margin_left", left)
	m.add_theme_constant_override("margin_top", top)
	m.add_theme_constant_override("margin_right", right)
	m.add_theme_constant_override("margin_bottom", bottom)
	m.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.size_flags_vertical = Control.SIZE_EXPAND_FILL
	return m

static func card(bg: Color = UiTheme.PANEL, border: Color = UiTheme.LINE, radius: int = 0, border_w: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.flat(bg, border, radius, border_w))
	return p

## 无内边距卡片：给画布类子控件用，保证 696×416 画布放进 696 宽的栏里不被内边距挤破。
static func card_tight(bg: Color = UiTheme.PANEL, border: Color = UiTheme.LINE, border_w: int = 1) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := UiTheme.flat(bg, border, 0, border_w)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	p.add_theme_stylebox_override("panel", sb)
	return p

static func button(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	b.pressed.connect(cb)
	if primary:
		b.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.CHALK, UiTheme.CHALK))
		b.add_theme_color_override("font_color", UiTheme.INK)
		b.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.CHALK_BRIGHT, UiTheme.CHALK_BRIGHT))
		b.add_theme_color_override("font_hover_color", UiTheme.INK)
		b.add_theme_stylebox_override("pressed", UiTheme.flat(UiTheme.MUTED, UiTheme.MUTED))
		b.add_theme_color_override("font_pressed_color", UiTheme.INK)
	return b

static func ghost(text: String, cb: Callable) -> Button:
	var b := button(text, cb, false)
	b.add_theme_stylebox_override("normal", UiTheme.flat(Color(0, 0, 0, 0), UiTheme.LINE))
	b.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.alpha(UiTheme.CHALK, 0.10), UiTheme.CHALK))
	return b

static func toggle(text: String, cb: Callable, pressed: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	b.toggled.connect(cb)
	return b

static func badge(text: String, color: Color = UiTheme.CYAN) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.alpha(color, 0.10), UiTheme.alpha(color, 0.55), 0, 1))
	var l := label(text, UiTheme.F_META, color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var m := margin4(9, 3, 9, 3)
	m.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	m.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	m.add_child(l)
	p.add_child(m)
	return p

static func stat(label_text: String, value_text: String, color: Color = UiTheme.TEXT) -> HBoxContainer:
	var h := hbox(6)
	h.add_theme_constant_override("separation", 6)
	h.mouse_filter = Control.MOUSE_FILTER_IGNORE
	h.add_child(label(label_text, UiTheme.F_META, UiTheme.MUTED))
	h.add_child(label(value_text, UiTheme.F_BODY, color))
	return h

static func scroll() -> ScrollContainer:
	var s := ScrollContainer.new()
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_EXPAND_FILL
	s.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	return s

static func set_margins(node: MarginContainer, left: int, top: int, right: int, bottom: int) -> void:
	node.add_theme_constant_override("margin_left", left)
	node.add_theme_constant_override("margin_top", top)
	node.add_theme_constant_override("margin_right", right)
	node.add_theme_constant_override("margin_bottom", bottom)

static func status_dot(color: Color, size: int = 8) -> Control:
	var c := ColorRect.new()
	c.color = color
	c.custom_minimum_size = Vector2(size, size)
	c.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

static func back_icon(cb: Callable) -> Button:
	## 44×44 返回热区：只有箭头，没有文字；Esc 与它等价。
	var b := Button.new()
	b.text = "←"
	b.focus_mode = Control.FOCUS_ALL
	b.custom_minimum_size = Vector2(44, 44)
	b.add_theme_font_size_override("font_size", 20)
	b.add_theme_color_override("font_color", UiTheme.MUTED)
	b.add_theme_color_override("font_hover_color", UiTheme.CHALK_BRIGHT)
	b.add_theme_color_override("font_pressed_color", UiTheme.CHALK_BRIGHT)
	b.add_theme_stylebox_override("normal", UiTheme.flat(Color(0, 0, 0, 0), UiTheme.alpha(UiTheme.CHALK, 0.12)))
	b.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.alpha(UiTheme.CHALK, 0.06), UiTheme.alpha(UiTheme.CHALK, 0.40)))
	b.add_theme_stylebox_override("pressed", UiTheme.flat(UiTheme.alpha(UiTheme.CHALK, 0.10), UiTheme.CHALK))
	b.add_theme_stylebox_override("focus", UiTheme.flat(Color(0, 0, 0, 0), UiTheme.alpha(UiTheme.CHALK, 0.55)))
	b.pressed.connect(cb)
	return b

class Glyph extends Control:
	## 极简图标：锁 / 对勾。用绘图而非字形，避免字体缺字。
	var kind := ""
	var color := Color(1, 1, 1)

	func _init(p_kind: String, p_color: Color, px: int) -> void:
		kind = p_kind
		color = p_color
		custom_minimum_size = Vector2(px, px)
		size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var w := size.x
		var h := size.y
		if kind == "lock":
			var bw := w * 0.70
			var bh := h * 0.44
			draw_rect(Rect2(w * 0.15, h * 0.50, bw, bh), color, true)
			draw_arc(Vector2(w * 0.5, h * 0.50), w * 0.26, PI, TAU, 10, color, maxf(1.5, w * 0.09))
			draw_circle(Vector2(w * 0.5, h * 0.72), w * 0.08, UiTheme.BG)
		elif kind == "check":
			var pts := PackedVector2Array([
				Vector2(w * 0.16, h * 0.52),
				Vector2(w * 0.40, h * 0.78),
				Vector2(w * 0.84, h * 0.22),
			])
			draw_polyline(pts, color, maxf(1.5, w * 0.12))

static func glyph(kind: String, color: Color, px: int = 24) -> Control:
	return Glyph.new(kind, color, px)
