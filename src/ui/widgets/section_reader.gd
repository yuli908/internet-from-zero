class_name SectionReader
extends PanelContainer

## 分段课文阅读卡：同一时间只显示一段，卡底「‹ i/n ›」翻页。
## 正文手工折行（不缩字号、不滚动）；翻页只在已解锁段内移动。
## 由 LabBase 安放在固定位置（左栏阅读槽 / 1.4 中栏讲解带），控件区另放滚动容器。

const Teach = preload("res://src/ui/teaching.gd")

var sections: Array = []
var unlocked := 0
var index := 0

var title_label: Label
var text_label: Label
var note_label: Label
var prev_btn: Button
var next_btn: Button
var count_label: Label

var _chars_per_line := 13
var _font_size := UiTheme.F_LABEL
var _pager_in_head := false
var _note := ""
var _note_order := 0

func configure(secs: Array, chars_per_line: int = 13, font_size: int = UiTheme.F_LABEL, pager_in_head: bool = false, note: String = "", note_order: int = 0) -> void:
	sections = secs
	_chars_per_line = chars_per_line
	_font_size = font_size
	_pager_in_head = pager_in_head
	_note = note
	_note_order = note_order
	_dress()
	_build()
	_refresh()

func set_done(done: int, reset_to_latest: bool = true) -> void:
	unlocked = Teach.unlocked_count_sections(sections, done)
	if reset_to_latest:
		index = maxi(0, unlocked - 1)
	_clamp()
	_refresh()

func set_index(i: int) -> void:
	index = i
	_clamp()
	_refresh()

func flip(delta: int) -> bool:
	_clamp()
	var target := index + delta
	if target < 0 or target >= unlocked:
		return false
	index = target
	_refresh()
	return true

func current() -> Dictionary:
	if sections.is_empty() or index >= sections.size():
		return {}
	return sections[index]

## 证据接口：测试与截图读取「界面上真的显示了什么」。
func probe() -> Dictionary:
	var s := current()
	var in_scroll := false
	var node: Node = text_label
	while node != null:
		if node is ScrollContainer:
			in_scroll = true
			break
		node = node.get_parent()
	return {
		"text": text_label.text if text_label != null else "",
		"title": title_label.text if title_label != null else "",
		"index": index,
		"unlocked": unlocked,
		"total": sections.size(),
		"after": int(s.get("after", -1)) if not s.is_empty() else -1,
		"order": int(s.get("order", -1)) if not s.is_empty() else -1,
		"note": note_label.text if note_label != null else "",
		"pager": count_label.text if count_label != null else "",
		"prev_disabled": prev_btn.disabled if prev_btn != null else true,
		"next_disabled": next_btn.disabled if next_btn != null else true,
		"in_scroll": in_scroll,
		"rect": [get_rect().position.x, get_rect().position.y, get_rect().size.x, get_rect().size.y],
	}

func _dress() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# 紧凑面板（内容边距交给下面的 margin4），把宽度都留给正文。
	add_theme_stylebox_override("panel", UiTheme.flat_tight(UiTheme.alpha(UiTheme.CHALK, 0.05), UiTheme.alpha(UiTheme.CHALK, 0.26)))

func _build() -> void:
	for c in get_children():
		c.queue_free()
	var m := Ui.margin4(9, 8, 9, 7)
	add_child(m)
	var col := Ui.vbox(5)
	m.add_child(col)

	title_label = Ui.label("", _font_size, UiTheme.CHALK_BRIGHT)
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS

	prev_btn = _arrow("‹", -1)
	count_label = Ui.label("1/1", _font_size, UiTheme.MUTED)
	count_label.custom_minimum_size = Vector2(36, 0)
	count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	count_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	next_btn = _arrow("›", 1)

	if _pager_in_head:
		var head := Ui.hbox(4)
		head.add_child(title_label)
		head.add_child(prev_btn)
		head.add_child(count_label)
		head.add_child(next_btn)
		col.add_child(head)
		text_label = Ui.label("", _font_size, UiTheme.CHALK)
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(text_label)
		_add_note(col)
	else:
		col.add_child(title_label)
		text_label = Ui.label("", _font_size, UiTheme.CHALK)
		text_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_child(text_label)
		_add_note(col)
		var pager := Ui.hbox(4)
		pager.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		pager.add_child(prev_btn)
		pager.add_child(count_label)
		pager.add_child(next_btn)
		col.add_child(pager)

## rules 附注：有 sections 时唯一承载阈值速查表的地方（不再另起一块）。
func _add_note(col: VBoxContainer) -> void:
	if _note.is_empty():
		return
	note_label = Ui.label(flow(_note, _chars_per_line), _font_size, UiTheme.MUTED)
	note_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	note_label.add_theme_constant_override("line_spacing", 2)
	note_label.tooltip_text = _note
	note_label.visible = false
	col.add_child(note_label)

func _arrow(glyph: String, delta: int) -> Button:
	var b := Button.new()
	b.text = glyph
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(24, 22)
	b.add_theme_font_size_override("font_size", _font_size)
	b.add_theme_color_override("font_color", UiTheme.CHALK)
	b.add_theme_color_override("font_hover_color", UiTheme.CHALK_BRIGHT)
	b.add_theme_color_override("font_disabled_color", UiTheme.MUTED_DIM)
	b.add_theme_stylebox_override("normal", UiTheme.flat(Color(0, 0, 0, 0), UiTheme.alpha(UiTheme.CHALK, 0.22)))
	b.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.alpha(UiTheme.CHALK, 0.10), UiTheme.CHALK))
	b.add_theme_stylebox_override("disabled", UiTheme.flat(Color(0, 0, 0, 0), UiTheme.alpha(UiTheme.LINE, 0.35)))
	b.pressed.connect(func(): flip(delta))
	return b

func _clamp() -> void:
	unlocked = clampi(unlocked, 0, sections.size())
	index = clampi(index, 0, maxi(0, unlocked - 1))

func _refresh() -> void:
	if text_label == null:
		return
	_clamp()
	var s := current()
	title_label.text = str(s.get("title", ""))
	title_label.tooltip_text = title_label.text
	text_label.text = flow(str(s.get("text", "")), _chars_per_line)
	text_label.tooltip_text = str(s.get("text", ""))
	# 折行间距压到 2（字号不动）：省下的高度留给左栏控件区。
	text_label.add_theme_constant_override("line_spacing", 2)
	# rules 附注只挂在讲阈值来源的那一段（order 3）：不与其他段同屏重复，也不丢信息。
	if note_label != null:
		note_label.visible = _note_order <= 0 or int(s.get("order", 0)) == _note_order
	count_label.text = Teach.pager_label(index, unlocked)
	var can_prev := index > 0
	var can_next := index < unlocked - 1
	prev_btn.disabled = not can_prev
	next_btn.disabled = not can_next

## 手工折行：只加换行、不改字、不缩字号。
static func flow(text: String, chars_per_line: int) -> String:
	var out := PackedStringArray()
	for para in text.split("\n"):
		var line := ""
		for ch in para:
			line += ch
			if line.length() >= chars_per_line:
				out.append(line)
				line = ""
		if not line.is_empty():
			out.append(line)
	return "\n".join(out)

static func flat_text(s: String) -> String:
	return s.replace("\n", "").replace(" ", "").replace("\t", "")
