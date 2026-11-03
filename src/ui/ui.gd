class_name Ui
extends RefCounted

## 轻量 UI 构造工具，避免在每个界面里重复写布局样板。

static func label(text: String, size: int = 14, color: Color = UiTheme.TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l

static func mono(text: String, size: int = 18, color: Color = UiTheme.ACCENT) -> Label:
	var l := label(text, size, color)
	l.add_theme_font_override("font", UiTheme.mono_font())
	return l

static func title(text: String, size: int = 24) -> Label:
	var l := label(text, size, UiTheme.TEXT)
	return l

static func muted(text: String, size: int = 12) -> Label:
	return label(text, size, UiTheme.MUTED)

static func wrap(text: String, size: int = 13, color: Color = UiTheme.MUTED) -> Label:
	var l := label(text, size, color)
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

static func hline(color: Color = UiTheme.BORDER) -> ColorRect:
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

static func card(bg: Color = UiTheme.PANEL, border: Color = UiTheme.BORDER, radius: int = 8) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", UiTheme.flat(bg, border, radius))
	return p

static func button(text: String, cb: Callable, primary: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.pressed.connect(cb)
	if primary:
		b.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.ACCENT.darkened(0.55), UiTheme.ACCENT, 6))
		b.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.ACCENT.darkened(0.35), UiTheme.ACCENT, 6))
		b.add_theme_stylebox_override("pressed", UiTheme.flat(UiTheme.ACCENT.darkened(0.65), UiTheme.ACCENT, 6))
	return b

static func ghost(text: String, cb: Callable) -> Button:
	var b := button(text, cb, false)
	b.add_theme_stylebox_override("normal", UiTheme.flat(Color(0, 0, 0, 0), UiTheme.BORDER, 6))
	b.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.alpha(UiTheme.ACCENT, 0.10), UiTheme.ACCENT, 6))
	return b

static func toggle(text: String, cb: Callable, pressed: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.button_pressed = pressed
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 34)
	b.toggled.connect(cb)
	return b

static func badge(text: String, color: Color = UiTheme.ACCENT) -> PanelContainer:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.alpha(color, 0.10), UiTheme.alpha(color, 0.55), 4, 1))
	var l := label(text, 12, color)
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
	h.add_child(label(label_text, 11, UiTheme.MUTED))
	h.add_child(label(value_text, 15, color))
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
