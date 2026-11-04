class_name LabCodeEditor
extends Control

## 实验室·代码编辑器（三级）：目录树 + 代码区 + 终端，三栏 236/724/236。
## 只从模块架 W05 右键「编写代码」进入。文件读写走宿主真实文件系统：
##   1) --lab-fs-root=<绝对路径>（用户指定，可指向 WSL 的 \\wsl$\<distro>\home\<user>）
##   2) 工程内可见目录 res://sandbox/linuxfs（宿主可直接打开）
##   3) user://linuxfs 仅作最后兜底
## 无 P03 时只读 + 顶部 1px 红线 + 运行禁用；运行优先调用真实 gcc，缺失时退回括号结构检查并在终端说明。

const Z_TREE := Rect2(0, 0, 236, 612)
const Z_EDIT := Rect2(254, 0, 724, 612)
const Z_TERM := Rect2(996, 0, 236, 612)

const GUTTER_W := 44.0
const LINE_H := 22.0
const EDITOR_FONT := 14
const TERM_FONT := 14

const PROJ_REL := "res://sandbox/linuxfs"
const ROOT_REL := "user://linuxfs"
const SEED_SUB := "home/user"
const MAX_TREE_ROWS := 18

var _lab: Control
var _code: TextEdit
var _line_layer: Control
var _term: RichTextLabel
var _tree_box: Control
var _run_btn: Button
var _save_btn: Button
var _files: Array = []
var _current := ""
var _err_line := 0
var _gcc_ok := false
var _gcc_checked := false
var _root := ""
var _root_state: Dictionary = {}
var _root_ok := false
var _root_label: Label

static func zone_rects() -> Dictionary:
	return {"tree": Z_TREE, "edit": Z_EDIT, "terminal": Z_TERM}

static func can_run(has_p03: bool) -> bool:
	return has_p03

## 运行双门禁：有 P03 且根路径可用；根不可用时绝不跑。
static func run_allowed(has_p03: bool, root_ok: bool) -> bool:
	return has_p03 and root_ok

## 解析根路径，返回 {ok, abs, kind, reason}。
## 顺序：用户指定绝对路径 → 工程内可见目录 → user:// 兜底。
## kind: override / project / user；失败 reason: empty / relative / unavailable。
static func resolve_fs_root(override: String = "", project_dir: String = "", fallback: String = "") -> Dictionary:
	if not override.strip_edges().is_empty():
		# 用户显式指定：可用就用，不可用直接拒绝，不偷偷退回其它目录。
		return _check_abs(override, "override")
	var proj := project_dir
	if proj.strip_edges().is_empty():
		proj = ProjectSettings.globalize_path(PROJ_REL)
	var pr := _check_abs(proj, "project")
	if bool(pr["ok"]):
		return pr
	var fb := fallback
	if fb.strip_edges().is_empty():
		fb = ProjectSettings.globalize_path(ROOT_REL)
	return _check_abs(fb, "user")

static func _check_abs(path: String, kind: String) -> Dictionary:
	var raw := path.strip_edges()
	if raw.is_empty():
		return {"ok": false, "abs": "", "kind": kind, "reason": "empty"}
	if not raw.is_absolute_path():
		return {"ok": false, "abs": raw, "kind": kind, "reason": "relative"}
	var abs := raw.replace("\\", "/").simplify_path()
	if not DirAccess.dir_exists_absolute(abs):
		DirAccess.make_dir_recursive_absolute(abs)
	var d := DirAccess.open(abs)
	if d == null:
		return {"ok": false, "abs": abs, "kind": kind, "reason": "unavailable"}
	return {"ok": true, "abs": abs, "kind": kind, "reason": ""}

static func root_abs() -> String:
	return str(resolve_fs_root()["abs"])

## 括号结构检查：返回首个出错行（1 起），0 表示平衡。仅用于无 gcc 的退回路径。
static func first_brace_error(src: String) -> int:
	var depth := 0
	var line := 1
	for i in src.length():
		var ch := src.substr(i, 1)
		if ch == "\n":
			line += 1
		elif ch == "{":
			depth += 1
		elif ch == "}":
			depth -= 1
			if depth < 0:
				return line
	return 0 if depth == 0 else line

## ---------- 构建 ----------

func build(lab_ref: Control) -> void:
	_lab = lab_ref
	apply_root(CliArgs.value("lab-fs-root", ""))
	_add_zone(Z_TREE, UiTheme.AMBER)
	_add_zone(Z_EDIT, UiTheme.CYAN)
	_add_zone(Z_TERM, UiTheme.RUST)
	_ensure_fs()

	var tree := Panel.new()
	tree.position = Z_TREE.position
	tree.size = Z_TREE.size
	tree.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tree.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.LINE, 0, 1))
	add_child(tree)
	_tree_box = Control.new()
	_tree_box.position = Z_TREE.position + Vector2(0, 0)
	_tree_box.size = Vector2(Z_TREE.size.x, 452)
	_tree_box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_tree_box)

	_line_layer = LineLayer.new()
	_line_layer.position = Z_EDIT.position
	_line_layer.size = Z_EDIT.size
	_line_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_line_layer.owner_editor = self
	add_child(_line_layer)

	_code = TextEdit.new()
	_code.name = "CodeEdit"
	_code.position = Z_EDIT.position + Vector2(GUTTER_W, 0)
	_code.size = Vector2(Z_EDIT.size.x - GUTTER_W, Z_EDIT.size.y)
	_code.wrap_mode = TextEdit.LINE_WRAPPING_NONE
	_code.add_theme_font_override("font", UiTheme.mono_font())
	_code.add_theme_font_size_override("font_size", EDITOR_FONT)
	_code.add_theme_constant_override("line_spacing", 3)
	_code.add_theme_stylebox_override("normal", UiTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	_code.add_theme_stylebox_override("focus", UiTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	_code.add_theme_color_override("caret_color", UiTheme.CHALK_BRIGHT)
	_code.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT)
	_code.text_changed.connect(_on_text_changed)
	_code.gui_input.connect(_on_code_input)
	add_child(_code)

	var term_panel := Panel.new()
	term_panel.position = Z_TERM.position
	term_panel.size = Z_TERM.size
	term_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	term_panel.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.LINE, 0, 1))
	add_child(term_panel)

	_term = RichTextLabel.new()
	_term.position = Z_TERM.position + Vector2(10, 10)
	_term.size = Vector2(Z_TERM.size.x - 20, Z_TERM.size.y - 20)
	_term.bbcode_enabled = true
	_term.scroll_following = true
	_term.add_theme_font_override("normal_font", UiTheme.mono_font())
	_term.add_theme_font_size_override("normal_font_size", TERM_FONT)
	_term.add_theme_constant_override("line_separation", 4)
	_term.add_theme_stylebox_override("normal", UiTheme.flat(Color(0, 0, 0, 0), Color(0, 0, 0, 0), 0, 0))
	add_child(_term)

	_save_btn = _text_button(Vector2(14, 508), "保存")
	_save_btn.pressed.connect(_save)
	add_child(_save_btn)
	_run_btn = _text_button(Vector2(14, 556), "运行")
	_run_btn.pressed.connect(_run)
	add_child(_run_btn)

	_root_label = Label.new()
	_root_label.position = Z_TREE.position + Vector2(12, 470)
	_root_label.size = Vector2(212, 22)
	_root_label.clip_text = true
	_root_label.add_theme_font_override("font", UiTheme.mono_font())
	_root_label.add_theme_font_size_override("font_size", 11)
	_root_label.add_theme_color_override("font_color", UiTheme.MUTED)
	add_child(_root_label)

	on_open()

func _text_button(pos: Vector2, label: String) -> Button:
	var b := Button.new()
	b.position = Z_TREE.position + pos
	b.size = Vector2(208, 36)
	b.text = label
	b.add_theme_font_override("font", UiTheme.cjk_font())
	b.add_theme_font_size_override("font_size", UiTheme.F_BODY)
	b.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.alpha(UiTheme.CHALK, 0.45), 0, 1))
	b.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.alpha(UiTheme.CHALK, 0.10), UiTheme.CHALK, 0, 1))
	b.add_theme_stylebox_override("pressed", UiTheme.flat(UiTheme.CHALK, UiTheme.CHALK, 0, 1))
	b.add_theme_stylebox_override("disabled", UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.LINE, 0, 1))
	b.add_theme_color_override("font_color", UiTheme.CHALK)
	b.add_theme_color_override("font_disabled_color", UiTheme.MUTED_DIM)
	return b

func _add_zone(r: Rect2, accent: Color) -> void:
	var p := Panel.new()
	p.position = r.position
	p.size = r.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_HIGH, UiTheme.LINE, 0, 1))
	add_child(p)
	var bar := ColorRect.new()
	bar.color = UiTheme.alpha(accent, 0.85)
	bar.position = r.position + Vector2(1, 1)
	bar.size = Vector2(r.size.x - 2, 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)

## ---------- 入口 ----------

func on_open() -> void:
	_ensure_fs()
	refresh_tree()
	var can := run_allowed(_has_p03(), _root_ok)
	_code.editable = can
	_run_btn.disabled = not can
	_save_btn.disabled = not _root_ok
	_line_layer.readonly = not can
	_root_label.text = _root
	_root_label.add_theme_color_override("font_color", UiTheme.MUTED if _root_ok else UiTheme.DANGER)
	_root_label.tooltip_text = _root
	if _current.is_empty() and not _files.is_empty():
		_open_file(str(_files[0]["abs"]))
	_term_clear()
	_term_line("user@lab:~$", UiTheme.MUTED)
	if _root_ok:
		_term_line(_root + " -> /", UiTheme.MUTED)
	else:
		_term_line("fs unavailable (%s)" % str(_root_state.get("reason", "?")), UiTheme.DANGER)
		_term_line(str(_root_state.get("abs", "")), UiTheme.DANGER)
	_line_layer.queue_redraw()

## 应用根路径（build 时自动调用；测试可显式喂路径）。
func apply_root(override: String = "") -> Dictionary:
	_root_state = resolve_fs_root(override)
	_root = str(_root_state.get("abs", ""))
	_root_ok = bool(_root_state.get("ok", false))
	return _root_state

func root_ready() -> bool:
	return _root_ok

func root_path() -> String:
	return _root

func _has_p03() -> bool:
	var p = GameState.player
	return p != null and p.item_count("P03") > 0

## ---------- 文件系统 ----------

func _ensure_fs() -> void:
	if not _root_ok:
		return
	var dir := _root + "/" + SEED_SUB
	DirAccess.make_dir_recursive_absolute(dir)
	var main_c := dir + "/main.c"
	if not FileAccess.file_exists(main_c):
		var f := FileAccess.open(main_c, FileAccess.WRITE)
		if f != null:
			f.store_string("int main(void) {\n    int n = 0;\n    n = n + 1;\n    return n;\n}\n")
			f.close()
	var readme := dir + "/notes.txt"
	if not FileAccess.file_exists(readme):
		var g := FileAccess.open(readme, FileAccess.WRITE)
		if g != null:
			g.store_string("lab mirror\n")
			g.close()
	DirAccess.make_dir_recursive_absolute(_root + "/etc")
	var host := _root + "/etc/hostname"
	if not FileAccess.file_exists(host):
		var h := FileAccess.open(host, FileAccess.WRITE)
		if h != null:
			h.store_string("lab\n")
			h.close()

func refresh_tree() -> void:
	for c in _tree_box.get_children():
		_tree_box.remove_child(c)
		c.queue_free()
	_files = []
	if not _root_ok:
		return
	var root := _root
	var stack := [{"abs": root, "rel": "", "depth": 0}]
	while not stack.is_empty():
		var cur: Dictionary = stack.pop_back()
		var d := DirAccess.open(str(cur["abs"]))
		if d == null:
			continue
		d.list_dir_begin()
		while true:
			var name := d.get_next()
			if name.is_empty():
				break
			if name.begins_with("."):
				continue
			var abs := str(cur["abs"]) + "/" + name
			var rel := str(cur["rel"]) + "/" + name
			if d.current_is_dir():
				if int(cur["depth"]) < 2:
					stack.append({"abs": abs, "rel": rel, "depth": int(cur["depth"]) + 1})
			else:
				_files.append({"abs": abs, "rel": rel})
		d.list_dir_end()
	if _files.is_empty():
		return
	for i in mini(_files.size(), MAX_TREE_ROWS):
		var row := FileRow.new()
		row.rel = str(_files[i]["rel"])
		row.abs = str(_files[i]["abs"])
		row.size = Vector2(Z_TREE.size.x, 24)
		row.position = Z_TREE.position + Vector2(0, 40 + i * 24)
		row.picked.connect(_open_file)
		row.is_current = row.abs == _current
		_tree_box.add_child(row)

func _open_file(abs_path: String) -> void:
	_current = abs_path
	var f := FileAccess.open(abs_path, FileAccess.READ)
	if f == null:
		_term_line("open failed: %s" % _display(abs_path), UiTheme.DANGER)
		return
	_code.text = f.get_as_text()
	f.close()
	_err_line = 0
	_line_layer.queue_redraw()
	for c in _tree_box.get_children():
		if c is FileRow:
			(c as FileRow).is_current = (c as FileRow).abs == _current
			(c as FileRow).queue_redraw()
	_code.grab_focus()

func _display(abs_path: String) -> String:
	var root := _root
	if abs_path.begins_with(root):
		return abs_path.substr(root.length())
	return abs_path

func _save() -> void:
	if _current.is_empty() or not _code.editable:
		return
	var f := FileAccess.open(_current, FileAccess.WRITE)
	if f == null:
		_term_line("write failed: %s" % _display(_current), UiTheme.DANGER)
		return
	f.store_string(_code.text)
	f.close()
	_term_line("write %s  %d B" % [_display(_current), _code.text.length()], UiTheme.MUTED)

func _run() -> void:
	if not run_allowed(_has_p03(), _root_ok):
		return
	if _current.is_empty():
		return
	_save_silent()
	if not _gcc_checked:
		_gcc_checked = true
		var probe := []
		_gcc_ok = OS.execute("gcc", ["--version"], probe) == 0
		if not _gcc_ok:
			_gcc_ok = OS.execute("cc", ["--version"], probe) == 0
	_term_line("user@lab:~$ run %s" % _display(_current), UiTheme.CHALK_BRIGHT)
	if _gcc_ok:
		var out := []
		var exe := "gcc" if OS.execute("gcc", ["--version"], out) == 0 else "cc"
		var code := OS.execute(exe, ["-fsyntax-only", _current], out)
		var raw := "".join(out)
		if not raw.is_empty():
			_term_line(raw.strip_edges(), UiTheme.DANGER if code != 0 else UiTheme.MUTED)
		if code != 0:
			_err_line = _line_from_diag(raw)
			_line_layer.queue_redraw()
			return
		_term_line("syntax ok", UiTheme.CHALK)
		return
	# 无编译器：只做括号结构检查，并在终端标明口径。
	_err_line = first_brace_error(_code.text)
	if _err_line > 0:
		_term_line("brace mismatch line %d (no gcc)" % _err_line, UiTheme.DANGER)
		_line_layer.queue_redraw()
		return
	_term_line("brace balance ok (no gcc)", UiTheme.CHALK)

func _save_silent() -> void:
	var f := FileAccess.open(_current, FileAccess.WRITE)
	if f != null:
		f.store_string(_code.text)
		f.close()

static func _line_from_diag(text: String) -> int:
	var re := RegEx.new()
	re.compile(":(\\d+):")
	var m := re.search(text)
	return 0 if m == null else int(m.get_string(1))

func _on_text_changed() -> void:
	_line_layer.queue_redraw()

func _on_code_input(_event: InputEvent) -> void:
	_line_layer.queue_redraw()

## ---------- 终端 ----------

func _term_clear() -> void:
	_term.clear()

func _term_line(text: String, color: Color) -> void:
	_term.push_color(color)
	_term.add_text(text + "\n")
	_term.pop()

func term_text() -> String:
	return _term.get_parsed_text()

func current_path() -> String:
	return _current

func error_line() -> int:
	return _err_line

## ---------- 子控件 ----------

class FileRow extends Control:
	signal picked(abs: String)
	var rel := ""
	var abs := ""
	var is_current := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			picked.emit(abs)

	func _draw() -> void:
		if is_current:
			draw_rect(Rect2(Vector2.ZERO, size), UiTheme.alpha(UiTheme.CHALK, 0.10), true)
		draw_line(Vector2(0, size.y), Vector2(size.x, size.y), UiTheme.alpha(UiTheme.LINE, 0.6), 1.0)
		# 只显示文件名，层级用缩进表示，不重复父路径。
		var depth := maxi(0, rel.split("/").size() - 2)
		var x := 10.0 + float(depth) * 12.0
		draw_string(UiTheme.mono_font(), Vector2(x, 17), rel.get_file(),
			HORIZONTAL_ALIGNMENT_LEFT, size.x - x - 10, UiTheme.F_META,
			UiTheme.CHALK_BRIGHT if is_current else UiTheme.CHALK)

class LineLayer extends Control:
	var readonly := false
	var owner_editor: LabCodeEditor

	func _draw() -> void:
		var code: TextEdit = null
		if owner_editor != null:
			code = owner_editor._code
		var scroll := 0
		if code != null:
			scroll = int(code.scroll_vertical)
		# 顶部 1px：有 P03 白 α.32，无 P03 红。
		draw_line(Vector2(0, 0), Vector2(size.x, 0),
			UiTheme.DANGER if readonly else UiTheme.alpha(UiTheme.CHALK, 0.32), 1.0)
		draw_rect(Rect2(0, 0, LabCodeEditor.GUTTER_W, size.y), UiTheme.BOARD_SUNK, true)
		draw_line(Vector2(LabCodeEditor.GUTTER_W, 0), Vector2(LabCodeEditor.GUTTER_W, size.y), UiTheme.LINE, 1.0)
		var lines := 1
		if code != null:
			lines = int(code.get_line_count())
		var err_line := 0
		if owner_editor != null:
			err_line = int(owner_editor.error_line())
		for i in range(scroll, mini(lines, scroll + 32)):
			var y := 6.0 + float(i - scroll) * LabCodeEditor.LINE_H
			var num := str(i + 1)
			var hot := err_line == i + 1
			draw_string(UiTheme.mono_font(), Vector2(0, y + 12), num,
				HORIZONTAL_ALIGNMENT_RIGHT, LabCodeEditor.GUTTER_W - 8, UiTheme.F_META,
				UiTheme.DANGER if hot else UiTheme.MUTED)
			if hot:
				draw_line(Vector2(0, y + 15), Vector2(LabCodeEditor.GUTTER_W, y + 15), UiTheme.DANGER, 2.0)
