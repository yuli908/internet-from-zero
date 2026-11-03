class_name UiTheme
extends RefCounted

## 视觉系统：深色工业控制台风格。所有 UI 共用这一套颜色与样式。

const BG := Color(0.035, 0.043, 0.055)
const PANEL := Color(0.066, 0.09, 0.114)
const PANEL_2 := Color(0.09, 0.122, 0.153)
const PANEL_3 := Color(0.118, 0.16, 0.196)
const BORDER := Color(0.149, 0.204, 0.255)
const TEXT := Color(0.859, 0.902, 0.941)
const MUTED := Color(0.498, 0.576, 0.643)
const ACCENT := Color(0.353, 0.82, 1.0)
const AMBER := Color(1.0, 0.702, 0.278)
const OK := Color(0.431, 0.906, 0.659)
const DANGER := Color(1.0, 0.42, 0.42)

static var _cjk: Font = null
static var _mono: Font = null

static func cjk_font() -> Font:
	if _cjk == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC", "Source Han Sans SC", "SimSun", "sans-serif"])
		f.font_weight = 400
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_cjk = f
	return _cjk

static func mono_font() -> Font:
	if _mono == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Cascadia Mono", "Consolas", "JetBrains Mono", "Courier New", "monospace"])
		_mono = f
	return _mono

static func rgb(hex: String) -> Color:
	return Color(hex)

static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

static func flat(bg: Color, border_color: Color = BORDER, radius: int = 6, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_color
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = 10
	sb.content_margin_right = 10
	sb.content_margin_top = 6
	sb.content_margin_bottom = 6
	return sb

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = cjk_font()
	t.default_font_size = 14

	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "Label", 4)

	var normal := flat(PANEL_3, BORDER, 6)
	var hover := flat(PANEL_3.lightened(0.08), ACCENT, 6)
	var pressed := flat(ACCENT.darkened(0.55), ACCENT, 6)
	var disabled := flat(PANEL_2, BORDER.darkened(0.3), 6)
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color(1, 1, 1))
	t.set_color("font_pressed_color", "Button", Color(1, 1, 1))
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font_size("font_size", "Button", 14)

	var le_normal := flat(Color(0.043, 0.059, 0.075), BORDER, 6)
	var le_focus := flat(Color(0.043, 0.059, 0.075), ACCENT, 6)
	t.set_stylebox("normal", "LineEdit", le_normal)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", TEXT)
	t.set_color("caret_color", "LineEdit", ACCENT)
	t.set_color("selection_color", "LineEdit", alpha(ACCENT, 0.25))
	t.set_color("placeholder_color", "LineEdit", MUTED)
	t.set_font_size("font_size", "LineEdit", 16)

	t.set_stylebox("panel", "PanelContainer", flat(PANEL, BORDER, 8))

	t.set_stylebox("background", "ProgressBar", flat(Color(0.043, 0.059, 0.075), BORDER, 5, 0))
	t.set_stylebox("fill", "ProgressBar", flat(ACCENT.darkened(0.2), ACCENT, 5, 0))
	t.set_color("font_color", "ProgressBar", TEXT)
	t.set_font_size("font_size", "ProgressBar", 12)

	t.set_stylebox("slider", "HSlider", flat(Color(0.043, 0.059, 0.075), BORDER, 4, 0))
	t.set_stylebox("grabber_area", "HSlider", flat(ACCENT.darkened(0.25), ACCENT, 4, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(ACCENT, ACCENT, 4, 0))

	t.set_stylebox("normal", "OptionButton", normal)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_color("font_color", "OptionButton", TEXT)

	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("normal_font_size", "RichTextLabel", 14)

	t.set_stylebox("panel", "PopupPanel", flat(PANEL_2, BORDER, 6))
	t.set_stylebox("panel", "PopupMenu", flat(PANEL_2, BORDER, 6))
	t.set_color("font_color", "PopupMenu", TEXT)
	return t
