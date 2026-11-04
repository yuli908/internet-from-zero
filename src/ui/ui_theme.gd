class_name UiTheme
extends RefCounted

## 视觉 token：黑板 / 粉笔风格。所有尺寸以 1280×720 逻辑像素定义。
## 字号下限：标签 ≥14、正文 ≥16（设计稿的 font/meta 12 与硬约束冲突，这里统一取 14）。

# ---------- 颜色 ----------
const BG := Color("#080B09")
const BOARD := Color("#16302A")
const BOARD_HIGH := Color("#1F3B33")
const BOARD_SUNK := Color("#12261F")
const FRAME := Color("#3B2A1C")
const CHALK := Color("#E8E4D6")
const CHALK_BRIGHT := Color("#FFFDF5")
const INK := Color("#14251F")
const MUTED := Color("#7F9189")
const MUTED_DIM := Color("#5E7068")
const LINE := Color(0.909, 0.894, 0.839, 0.16)
const LINE_STRONG := Color(0.909, 0.894, 0.839, 0.34)
const AMBER := Color("#D8A24A")
const CYAN := Color("#7FC7CF")
const GRAYBLUE := Color("#8FA3B8")
const RUST := Color("#C97862")
const DANGER := Color("#B8452F")

# ---------- 旧 token 兼容（逐屏迁移期间仍然有效） ----------
const PANEL := BOARD
const PANEL_2 := Color("#1A342D")
const PANEL_3 := BOARD_HIGH
const BORDER := LINE
const TEXT := CHALK
const ACCENT := CYAN
const OK := CHALK_BRIGHT

# ---------- 字号 ----------
const F_META := 14
const F_CAPTION := 15
const F_LABEL := 16
const F_BODY := 18
const F_BODY_LG := 18
const F_H3 := 20
const F_H2 := 26
const F_H1 := 34
const F_TITLE := 104

# ---------- 间距 / 控件 ----------
const S1 := 4
const S2 := 8
const S3 := 12
const S4 := 16
const S5 := 24
const S6 := 32
const CONTROL_H := 44
const CONTROL_LG := 52
const CONTROL_RAIL := 58
const BORDER_FRAME := 9

## 动效 / 颗粒总开关；由设置面板与 main.gd 统一写入。
static var motion := true
static var texture_enabled := true

static var _cjk: Font = null
static var _mono: Font = null
static var _title: Font = null
static var _grain: Texture2D = null

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
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_mono = f
	return _mono

static func title_font() -> Font:
	if _title == null:
		var f := SystemFont.new()
		f.font_names = PackedStringArray(["Arial Black", "Arial Bold", "Arial", "Impact", "sans-serif"])
		f.font_weight = 900
		f.antialiasing = TextServer.FONT_ANTIALIASING_GRAY
		_title = f
	return _title

static func title_font_variation(spacing_px: float = 0.0) -> Font:
	var v := FontVariation.new()
	v.base_font = title_font()
	v.spacing_glyph = spacing_px
	v.spacing_space = spacing_px
	return v

## 静态噪点纹理：256×256 分形噪声，供 chalk_grain shader 采样，不逐帧变化。
static func grain_texture() -> Texture2D:
	if _grain != null:
		return _grain
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.9
	noise.fractal_octaves = 2
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.noise = noise
	tex.generate_mipmaps = false
	_grain = tex
	return _grain

static func rgb(hex: String) -> Color:
	return Color(hex)

static func alpha(c: Color, a: float) -> Color:
	return Color(c.r, c.g, c.b, a)

static func flat(bg: Color, border_color: Color = LINE, radius: int = 0, border_w: int = 1) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = bg
	sb.border_color = border_color
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.content_margin_left = S3
	sb.content_margin_right = S3
	sb.content_margin_top = S2
	sb.content_margin_bottom = S2
	sb.anti_aliasing = false
	return sb

## 无内边距色块：进度条、色板方块等细控件用，避免 S2/S3 内边距把 7px 撑成 24px。
static func flat_tight(bg: Color, border_color: Color = LINE, border_w: int = 1) -> StyleBoxFlat:
	var sb := flat(bg, border_color, 0, border_w)
	sb.content_margin_left = 0
	sb.content_margin_right = 0
	sb.content_margin_top = 0
	sb.content_margin_bottom = 0
	return sb

static func build() -> Theme:
	var t := Theme.new()
	t.default_font = cjk_font()
	t.default_font_size = F_BODY_LG

	t.set_color("font_color", "Label", CHALK)
	t.set_color("font_shadow_color", "Label", Color(0, 0, 0, 0))
	t.set_constant("line_spacing", "Label", 4)

	var normal := flat(BOARD_HIGH, LINE)
	var hover := flat(Color("#2A4038"), CHALK)
	var pressed := flat(Color("#0F201A"), CHALK_BRIGHT)
	var disabled := flat(BOARD_SUNK, alpha(LINE, 0.10))
	t.set_stylebox("normal", "Button", normal)
	t.set_stylebox("hover", "Button", hover)
	t.set_stylebox("pressed", "Button", pressed)
	t.set_stylebox("disabled", "Button", disabled)
	t.set_stylebox("focus", "Button", flat(Color(0, 0, 0, 0), CHALK_BRIGHT))
	t.set_color("font_color", "Button", CHALK)
	t.set_color("font_hover_color", "Button", CHALK_BRIGHT)
	t.set_color("font_pressed_color", "Button", CHALK_BRIGHT)
	t.set_color("font_disabled_color", "Button", MUTED)
	t.set_font_size("font_size", "Button", F_BODY_LG)

	var le_normal := flat(BOARD_SUNK, LINE)
	var le_focus := flat(BOARD_SUNK, CHALK_BRIGHT)
	t.set_stylebox("normal", "LineEdit", le_normal)
	t.set_stylebox("focus", "LineEdit", le_focus)
	t.set_color("font_color", "LineEdit", CHALK)
	t.set_color("caret_color", "LineEdit", CHALK_BRIGHT)
	t.set_color("selection_color", "LineEdit", alpha(CHALK, 0.25))
	t.set_color("placeholder_color", "LineEdit", MUTED)
	t.set_font_size("font_size", "LineEdit", F_BODY)

	t.set_stylebox("panel", "PanelContainer", flat(BOARD, LINE))

	t.set_stylebox("background", "ProgressBar", flat(BOARD_SUNK, alpha(CHALK, 0.28), 0, 0))
	t.set_stylebox("fill", "ProgressBar", flat(CHALK, CHALK, 0, 0))
	t.set_color("font_color", "ProgressBar", CHALK)
	t.set_font_size("font_size", "ProgressBar", F_META)

	t.set_stylebox("slider", "HSlider", flat(BOARD_SUNK, LINE, 0, 0))
	t.set_stylebox("grabber_area", "HSlider", flat(CHALK, CHALK, 0, 0))
	t.set_stylebox("grabber_area_highlight", "HSlider", flat(CHALK_BRIGHT, CHALK_BRIGHT, 0, 0))

	t.set_stylebox("normal", "OptionButton", normal)
	t.set_stylebox("hover", "OptionButton", hover)
	t.set_stylebox("pressed", "OptionButton", pressed)
	t.set_color("font_color", "OptionButton", CHALK)

	t.set_color("default_color", "RichTextLabel", CHALK)
	t.set_font_size("normal_font_size", "RichTextLabel", F_BODY)

	t.set_stylebox("panel", "PopupPanel", flat(BOARD_HIGH, LINE))
	t.set_stylebox("panel", "PopupMenu", flat(BOARD_HIGH, LINE))
	t.set_color("font_color", "PopupMenu", CHALK)
	return t
