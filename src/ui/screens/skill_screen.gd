class_name SkillScreen
extends GameScreen

## 知识树：三幕横带 / 分支竖枝 / 底部挑战环 / 终章。整屏自绘，坐标以本屏左上角为原点。
## 左栏 0..236，树视口 236..1232，画布 974×504 置于视口内 (11,17)。

const NODE_W := 94.0
const NODE_H := 44.0
const COL_STEP := 110.0
const CANVAS_W := 974.0
const CANVAS_H := 504.0
const TIP_W := 336.0
const TIP_H := 26.0

const ACT_Y := [0, 152, 304]
const BRANCH_Y := [60, 212, 364]
const MAIN_X := [0, 330]
const KNOWLEDGE_X := [[110, 220, 440, 550], [110, 220, 440, 550], [110, 220, 440, 550, 660]]
const BRANCH_X := [[110, 440], [110, 220, 440, 550], [110, 440, 660]]
const CHALLENGE_Y := 460
const RING_Y := 452.0
const FINAL_LINK_Y := 482.0

## 知识短名固定映射：≤4 字，缺失时回落到 title 截断。
const SHORT_KN := {
	"KN-ELEC-01": "阈值",
	"KN-BIN-01": "两态",
	"KN-BIN-02": "位权",
	"KN-BIN-03": "位宽",
	"KN-BIN-04": "编码",
	"KN-BOOL-01": "真值表",
	"KN-BOOL-02": "与或非",
	"KN-BOOL-03": "德摩根",
	"KN-GATE-01": "黑盒",
	"KN-SIG-01": "延迟",
	"KN-SIG-02": "毛刺",
	"KN-SIG-03": "冒险",
	"KN-ADD-01": "进位",
	"KN-TR-01": "三端",
	"KN-TR-02": "三区",
	"KN-TR-03": "阈值",
	"KN-TR-04": "器件族",
	"KN-CMOS-01": "互补对",
	"KN-CMOS-02": "零电流",
	"KN-CMOS-03": "噪声",
	"KN-NAND-01": "万能门",
	"KN-NAND-02": "德摩根",
	"KN-EQUIV-01": "等价",
	"KN-COST-01": "三角",
	"KN-PWR-01": "功耗",
	"KN-PWR-02": "降频",
}

var _root: Control
var _canvas: Control
var _cells: Array = []
var _selected_key := ""
var _selected_cell: NodeCell = null
var _block: Panel
var _block_t1: Label
var _block_t2: Label
var _block_code: Label
var _unlock_btn: Button
var _bar_fill: ColorRect
var _stats: Label
var _tip: Panel
var _tip_label: Label
var _tip_cell: NodeCell = null
var _tip_show_timer: Timer
var _tip_hide_timer: Timer
var _printed: Dictionary = {}

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func on_show() -> void:
	_refresh()


# ---------------------------------------------------------------- 节点自绘

class NodeCell extends Control:
	signal hovered(cell)
	signal unhovered(cell)
	signal got_focus(cell)
	signal lost_focus(cell)
	signal picked(cell)

	const W := 94.0
	const H := 44.0
	const CHALK_DEFERRED := Color("#B4C1BA")

	var kind := "main"
	var state := "locked"
	var code := ""
	var short_name := ""
	var title := ""
	var detail := ""
	var node_id := ""
	var lab_id := ""
	var key := ""
	var _pulse := 0.0
	var _hovering := false

	func _init() -> void:
		size = Vector2(W, H)
		custom_minimum_size = Vector2(W, H)
		mouse_filter = Control.MOUSE_FILTER_STOP
		focus_mode = Control.FOCUS_ALL
		set_process(false)
		mouse_entered.connect(_on_mouse_entered)
		mouse_exited.connect(_on_mouse_exited)
		focus_entered.connect(func() -> void: got_focus.emit(self))
		focus_exited.connect(func() -> void: lost_focus.emit(self))

	func _on_mouse_entered() -> void:
		_hovering = true
		hovered.emit(self)

	func _on_mouse_exited() -> void:
		_hovering = false
		unhovered.emit(self)

	func is_hovering() -> bool:
		return _hovering

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton:
			var mb := event as InputEventMouseButton
			if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
				accept_event()
				grab_focus()
				picked.emit(self)
		elif event is InputEventKey:
			var key_event := event as InputEventKey
			if key_event.pressed and not key_event.echo and (key_event.keycode == KEY_ENTER or key_event.keycode == KEY_KP_ENTER):
				accept_event()
				picked.emit(self)

	func _process(delta: float) -> void:
		_pulse = fmod(_pulse + delta, 2.4)
		queue_redraw()

	# ---- 状态 → 颜色 / 亮度（只改填充与亮度，轮廓恒定）
	func _text_color() -> Color:
		match state:
			"done":
				return UiTheme.INK
			"current":
				return UiTheme.CHALK_BRIGHT
			"available":
				return UiTheme.CHALK
			"deferred":
				return CHALK_DEFERRED
			_:
				return UiTheme.MUTED

	func _border_alpha() -> float:
		match state:
			"done":
				return 0.62
			"current":
				return 0.55
			"available":
				return 0.42
			"deferred":
				return 0.30
			_:
				return 0.18

	func _fill_color() -> Color:
		match state:
			"done":
				return UiTheme.alpha(UiTheme.CHALK, 0.90)
			"current":
				return UiTheme.alpha(UiTheme.CHALK, 0.12)
			"available":
				return UiTheme.alpha(UiTheme.CHALK, 0.07)
			"deferred":
				return UiTheme.alpha(UiTheme.CHALK, 0.02)
			_:
				return Color(0, 0, 0, 0)

	func _mark() -> Color:
		if state == "locked":
			return UiTheme.alpha(_text_color(), 0.18)
		if state == "deferred":
			return UiTheme.alpha(_text_color(), 0.45)
		return _text_color()

	func _faint(weight: float) -> Color:
		if state == "locked":
			return UiTheme.alpha(_text_color(), 0.18)
		return UiTheme.alpha(_text_color(), weight)

	# ---- 四类轮廓（顶点固定，不随状态变化）
	func _outline() -> PackedVector2Array:
		match kind:
			"branch":
				return PackedVector2Array([
					Vector2(0, 0), Vector2(84, 0), Vector2(94, 10), Vector2(94, 44), Vector2(0, 44),
				])
			"challenge", "final":
				return PackedVector2Array([
					Vector2(0, 8), Vector2(8, 0), Vector2(94, 0), Vector2(94, 44), Vector2(0, 44),
				])
			_:
				return PackedVector2Array([
					Vector2(0, 0), Vector2(94, 0), Vector2(94, 44), Vector2(0, 44),
				])

	func _draw() -> void:
		var pts := _outline()
		if state == "deferred":
			_hatch(UiTheme.alpha(UiTheme.CHALK, 0.04))
		var fill := _fill_color()
		if fill.a > 0.0:
			draw_colored_polygon(pts, fill)
		_draw_border(pts)
		_draw_marks()
		_draw_texts()
		if state == "done":
			_draw_check()
		if state == "current":
			_draw_pulse()

	func _draw_border(pts: PackedVector2Array) -> void:
		var a := _border_alpha()
		var col := UiTheme.alpha(UiTheme.CHALK, a)
		if kind == "final":
			_loop(_expand(pts, 2.0), col, 2.0)
			_loop(pts, UiTheme.alpha(UiTheme.CHALK, a * 0.5), 1.0)
		elif kind == "challenge":
			var on_len := 7.0 if state == "deferred" else 6.0
			var off_len := 6.0 if state == "deferred" else 4.0
			_dash_loop(pts, col, 1.0, on_len, off_len)
		else:
			_loop(pts, col, 1.0)

	func _loop(pts: PackedVector2Array, col: Color, width: float) -> void:
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, col, width)

	func _dash_loop(pts: PackedVector2Array, col: Color, width: float, on_len: float, off_len: float) -> void:
		var drawing := true
		var remain := on_len
		for i in pts.size():
			var a := pts[i]
			var b := pts[(i + 1) % pts.size()]
			var seg_len := a.distance_to(b)
			if seg_len <= 0.01:
				continue
			var t := 0.0
			while t < seg_len:
				var step := minf(remain, seg_len - t)
				if drawing:
					draw_line(a.lerp(b, t / seg_len), a.lerp(b, (t + step) / seg_len), col, width)
				t += step
				remain -= step
				if remain <= 0.001:
					drawing = not drawing
					remain = on_len if drawing else off_len

	func _expand(pts: PackedVector2Array, by: float) -> PackedVector2Array:
		var center := Vector2(W * 0.5, H * 0.5)
		var out := PackedVector2Array()
		for p in pts:
			var dir := p - center
			if dir.length() < 0.001:
				out.append(p)
			else:
				out.append(p + dir.normalized() * by)
		return out

	# 五通道：挑战「已走过」态的三角必须实心（填充与轮廓同时变化，不能只靠颜色）。
	func challenge_tri_filled() -> bool:
		return kind == "challenge" and state == "done"

	func _draw_marks() -> void:
		var m := _mark()
		match kind:
			"main":
				draw_rect(Rect2(0, 0, 3, H), m, true)
			"branch":
				draw_rect(Rect2(8, 0, 20, 1), _faint(0.28), true)
				draw_rect(Rect2(0, 0, 3, H), _faint(0.28), true)
				draw_polyline(PackedVector2Array([Vector2(76, 29), Vector2(81, 36), Vector2(86, 29)]), m, 1.5)
			"challenge":
				var tri := PackedVector2Array([Vector2(81, 28), Vector2(76, 38), Vector2(86, 38)])
				if challenge_tri_filled():
					draw_colored_polygon(tri, UiTheme.alpha(m, 0.40))
				var tri_line := tri.duplicate()
				tri_line.append(tri[0])
				draw_polyline(tri_line, m, 1.5)
			"final":
				draw_rect(Rect2(0, 0, 3, H), m, true)
				draw_rect(Rect2(91, 0, 3, H), m, true)
				draw_colored_polygon(PackedVector2Array([
					Vector2(81, 30), Vector2(84, 33), Vector2(81, 36), Vector2(78, 33),
				]), m)
		if state == "deferred" and kind == "challenge":
			draw_polyline(PackedVector2Array([Vector2(86, 4), Vector2(81, 14), Vector2(91, 14), Vector2(86, 4)]), m, 1.5)

	func _draw_texts() -> void:
		var col := _text_color()
		var mono := UiTheme.mono_font()
		draw_string(mono, Vector2(6, 5 + mono.get_ascent(UiTheme.F_META)), code, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.F_META, col)
		var cjk := UiTheme.cjk_font()
		draw_string(cjk, Vector2(6, 22 + cjk.get_ascent(UiTheme.F_LABEL)), short_name, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.F_LABEL, col)

	func _draw_check() -> void:
		draw_polyline(PackedVector2Array([Vector2(79, 11), Vector2(82, 14), Vector2(87, 8)]), UiTheme.INK, 2.0)

	func _draw_pulse() -> void:
		var a := 0.55
		if UiTheme.motion:
			a = 0.55 + 0.15 * sin(TAU * _pulse / 2.4)
		draw_rect(Rect2(-8, -8, 110, 60), UiTheme.alpha(UiTheme.CHALK, a), false, 6.0)

	func _hatch(col: Color) -> void:
		var c := -H
		while c <= W:
			var p1 := Vector2(0.0, -c)
			if c >= 0.0:
				p1 = Vector2(c, 0.0)
			var p2 := Vector2(c + H, H)
			if c + H > W:
				p2 = Vector2(W, W - c)
			if p1.distance_to(p2) > 0.5:
				draw_line(p1, p2, col, 1.0)
			c += 8.0


# ---------------------------------------------------------------- 轨道层

class Track extends Control:
	const CANVAS_W_REF := 974.0

	var segments: Array = []
	var bands: Array = [120.0, 272.0]
	var notes: Array = []

	func _init() -> void:
		position = Vector2.ZERO
		size = Vector2(974, 504)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 0

	func _draw() -> void:
		for raw in segments:
			var seg: Dictionary = raw
			var a: Vector2 = seg.get("a", Vector2.ZERO)
			var b: Vector2 = seg.get("b", Vector2.ZERO)
			var col: Color = seg.get("c", Color(1, 1, 1, 1))
			var width: float = float(seg.get("w", 1.0))
			var dash: float = float(seg.get("dash", 0.0))
			if dash > 0.0:
				_dash(a, b, col, width, dash, float(seg.get("gap", 9.0)))
			else:
				draw_line(a, b, col, width)
		var band_col := UiTheme.alpha(UiTheme.CHALK, 0.16)
		for raw in bands:
			var y := float(raw)
			draw_line(Vector2(0, y), Vector2(CANVAS_W_REF, y), band_col, 1.0)
		var f := UiTheme.cjk_font()
		for raw in notes:
			var note: Dictionary = raw
			var at: Vector2 = note.get("at", Vector2.ZERO)
			var txt := str(note.get("text", ""))
			draw_string(f, Vector2(at.x, at.y + f.get_ascent(UiTheme.F_META)), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, UiTheme.F_META, UiTheme.alpha(UiTheme.CHALK, 0.34))

	func _dash(a: Vector2, b: Vector2, col: Color, width: float, on_len: float, off_len: float) -> void:
		var total := a.distance_to(b)
		if total <= 0.01:
			return
		var t := 0.0
		var drawing := true
		var remain := on_len
		while t < total:
			var step := minf(remain, total - t)
			if drawing:
				draw_line(a.lerp(b, t / total), a.lerp(b, (t + step) / total), col, width)
			t += step
			remain -= step
			if remain <= 0.001:
				drawing = not drawing
				remain = on_len if drawing else off_len


# ---------------------------------------------------------------- 骨架

func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_root)

	var bar_bg := ColorRect.new()
	bar_bg.color = UiTheme.alpha(UiTheme.CHALK, 0.18)
	bar_bg.position = Vector2(20, 0)
	bar_bg.size = Vector2(196, 7)
	bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(bar_bg)

	_bar_fill = ColorRect.new()
	_bar_fill.color = UiTheme.CHALK
	_bar_fill.position = Vector2(20, 0)
	_bar_fill.size = Vector2(0, 7)
	_bar_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_bar_fill)

	_stats = Ui.mono("", UiTheme.F_META, UiTheme.CHALK)
	_stats.position = Vector2(20, 14)
	_stats.size = Vector2(196, 18)
	_root.add_child(_stats)

	var view := Panel.new()
	view.position = Vector2(236, 28)
	view.size = Vector2(996, 538)
	view.clip_contents = true
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_theme_stylebox_override("panel", UiTheme.flat_tight(UiTheme.BOARD_SUNK, UiTheme.alpha(UiTheme.CHALK, 0.32)))
	_root.add_child(view)

	_canvas = Control.new()
	_canvas.position = Vector2(11, 17)
	_canvas.size = Vector2(CANVAS_W, CANVAS_H)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.add_child(_canvas)

	var shelf := Control.new()
	shelf.position = Vector2(236, 566)
	shelf.size = Vector2(996, 46)
	shelf.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(shelf)

	var shelf_line := ColorRect.new()
	shelf_line.color = UiTheme.alpha(UiTheme.CHALK, 0.16)
	shelf_line.size = Vector2(996, 1)
	shelf_line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shelf.add_child(shelf_line)

	_block = Panel.new()
	_block.position = Vector2(20, 208)
	_block.size = Vector2(196, 72)
	_block.visible = false
	_block.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_block.add_theme_stylebox_override("panel", UiTheme.flat_tight(UiTheme.BOARD_HIGH, UiTheme.alpha(UiTheme.CHALK, 0.32)))
	_root.add_child(_block)

	_block_t1 = Ui.label("", UiTheme.F_BODY, UiTheme.CHALK_BRIGHT)
	_block_t1.position = Vector2(10, 6)
	_block_t1.size = Vector2(176, 22)
	_block_t1.clip_text = true
	_block.add_child(_block_t1)

	_block_t2 = Ui.label("", UiTheme.F_BODY, UiTheme.CHALK_BRIGHT)
	_block_t2.position = Vector2(10, 28)
	_block_t2.size = Vector2(176, 22)
	_block_t2.clip_text = true
	_block.add_child(_block_t2)

	_block_code = Ui.mono("", UiTheme.F_META, UiTheme.MUTED)
	_block_code.position = Vector2(10, 50)
	_block_code.size = Vector2(176, 18)
	_block.add_child(_block_code)

	_unlock_btn = Ui.button("解锁", _do_unlock, true)
	_unlock_btn.position = Vector2(20, 292)
	_unlock_btn.size = Vector2(196, 44)
	_unlock_btn.visible = false
	_root.add_child(_unlock_btn)

	_tip = Panel.new()
	_tip.position = Vector2(247, 45)
	_tip.size = Vector2(TIP_W, TIP_H)
	_tip.z_index = 2
	_tip.visible = false
	_tip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tip_style := StyleBoxFlat.new()
	tip_style.bg_color = UiTheme.alpha(Color("#16302A"), 0.94)
	tip_style.border_width_top = 1
	tip_style.border_color = UiTheme.alpha(UiTheme.CHALK, 0.32)
	tip_style.content_margin_left = 0
	tip_style.content_margin_right = 0
	tip_style.content_margin_top = 0
	tip_style.content_margin_bottom = 0
	tip_style.anti_aliasing = false
	_tip.add_theme_stylebox_override("panel", tip_style)
	_root.add_child(_tip)

	_tip_label = Ui.label("", UiTheme.F_LABEL, UiTheme.CHALK_BRIGHT)
	_tip_label.position = Vector2(9, 0)
	_tip_label.size = Vector2(318, TIP_H)
	_tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_tip_label.clip_text = true
	_tip.add_child(_tip_label)

	_tip_show_timer = Timer.new()
	_tip_show_timer.one_shot = true
	_tip_show_timer.wait_time = 0.26
	_tip_show_timer.timeout.connect(_on_tip_show_timeout)
	add_child(_tip_show_timer)

	_tip_hide_timer = Timer.new()
	_tip_hide_timer.one_shot = true
	_tip_hide_timer.wait_time = 0.12
	_tip_hide_timer.timeout.connect(_on_tip_hide_timeout)
	add_child(_tip_hide_timer)


# ---------------------------------------------------------------- 装配

func _refresh() -> void:
	_tip_show_timer.stop()
	_tip_hide_timer.stop()
	_tip_cell = null
	_tip.visible = false
	_tip_label.text = ""
	for c in _canvas.get_children():
		_canvas.remove_child(c)
		c.queue_free()
	_cells.clear()

	var chapter_no := int(DataDB.chapter.data.get("number", 1))
	var chapter_id := str(DataDB.chapter.id())
	var milestones := _progress_ids(chapter_no)
	var terminal_id := ""
	if not milestones.is_empty():
		terminal_id = str(milestones[milestones.size() - 1])
		milestones.remove_at(milestones.size() - 1)
	var knowledge := _knowledge_ids()
	var branches := _skill_ids(chapter_id)
	var lab_ids: Array = DataDB.chapter.lab_order.duplicate()

	var row_entries: Array = [[], [], []]
	var slots: Array = []
	for act in 3:
		for raw_x in KNOWLEDGE_X[act]:
			slots.append({"act": act, "x": float(raw_x)})

	for i in mini(milestones.size(), 6):
		var act := int(i / 2)
		var id := str(milestones[i])
		var n: Dictionary = DataDB.skill_graph.node(id)
		var title := str(n.get("title", id))
		row_entries[act].append({
			"kind": "main", "x": float(MAIN_X[i % 2]), "y": float(ACT_Y[act]),
			"code": str(i + 1), "short": _short(title),
			"title": title, "detail": str(n.get("desc", "")),
			"node_id": id, "lab_id": "", "key": "n:" + id,
			"state": _graph_state(id), "act": act,
		})

	for i in mini(knowledge.size(), slots.size()):
		var slot: Dictionary = slots[i]
		var id := str(knowledge[i])
		var n: Dictionary = DataDB.skill_graph.node(id)
		var pos: Dictionary = n.get("pos", {})
		var act := int(slot.get("act", 0))
		var code := "%d.%d" % [int(pos.get("col", 0)), int(pos.get("row", 0))]
		var short := str(SHORT_KN.get(id, ""))
		if short.is_empty():
			short = _short(str(n.get("title", id)))
		row_entries[act].append({
			"kind": "main", "x": float(slot.get("x", 0.0)), "y": float(ACT_Y[act]),
			"code": code, "short": short,
			"title": str(n.get("title", id)), "detail": str(n.get("desc", "")),
			"node_id": id, "lab_id": "", "key": "n:" + id,
			"state": _graph_state(id), "act": act,
		})

	var rows: Array = [[], [], []]
	var entries: Array = []
	for act in 3:
		var row: Array = row_entries[act]
		row.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
		rows[act] = row
		for e in row:
			entries.append(e)

	var branch_by_act: Array = [[], [], []]
	var used := [0, 0, 0]
	for i in mini(branches.size(), 9):
		var id := str(branches[i])
		var n: Dictionary = DataDB.skill_graph.node(id)
		var pos: Dictionary = n.get("pos", {})
		var col := int(pos.get("col", 0))
		var act := clampi(floori(float(col - 1) / 2.0), 0, 2)
		var idx: int = used[act]
		var xs: Array = BRANCH_X[act]
		if idx >= xs.size():
			continue
		used[act] = idx + 1
		branch_by_act[act].append({
			"kind": "branch", "x": float(xs[idx]), "y": float(BRANCH_Y[act]),
			"code": "B%d" % [i + 1], "short": _short(str(n.get("title", id))),
			"title": str(n.get("title", id)), "detail": str(n.get("desc", "")),
			"node_id": id, "lab_id": "", "key": "n:" + id,
			"state": _graph_state(id), "act": act,
		})
	for act in 3:
		var row: Array = branch_by_act[act]
		row.sort_custom(func(a, b): return float(a["x"]) < float(b["x"]))
		for e in row:
			entries.append(e)

	var challenge_entries: Array = []
	for i in range(lab_ids.size() + 1):
		var x := COL_STEP * float(i)
		var lab_id := ""
		if i < lab_ids.size():
			lab_id = str(lab_ids[i])
		var lab: Dictionary = {}
		if not lab_id.is_empty():
			lab = DataDB.chapter.lab(lab_id)
		var st := "locked"
		if lab_id.is_empty():
			if ChapterFlow.chapter_complete():
				st = "done"
			elif GameState.player != null and DataDB.chapter.all_done(GameState.player):
				st = "available"
		else:
			var obj := str(lab.get("objective", ""))
			if ChapterFlow.is_objective_done(obj):
				st = "done"
			elif DataDB.chapter.content_status(lab_id) != "ready":
				st = "deferred"
			elif ChapterFlow.is_lab_unlocked(lab_id):
				st = "available"
		var title := str(lab.get("title", ""))
		if lab_id.is_empty():
			title = str(DataDB.chapter.title())
		var entry := {
			"kind": "challenge", "x": x, "y": float(CHALLENGE_Y),
			"code": "C%d" % [i + 1], "short": "挑%d" % [i + 1],
			"title": title, "detail": title, "node_id": "", "lab_id": lab_id,
			"key": "l:%d" % i, "state": st, "act": -1,
		}
		challenge_entries.append(entry)
		entries.append(entry)

	var final_entry: Dictionary = {}
	if not terminal_id.is_empty():
		var n: Dictionary = DataDB.skill_graph.node(terminal_id)
		final_entry = {
			"kind": "final", "x": COL_STEP * float(lab_ids.size() + 1), "y": float(CHALLENGE_Y),
			"code": "END", "short": "终章",
			"title": str(n.get("title", terminal_id)), "detail": str(n.get("desc", "")),
			"node_id": terminal_id, "lab_id": "", "key": "n:" + terminal_id,
			"state": _graph_state(terminal_id), "act": -1,
		}
		entries.append(final_entry)

	# 当前所在 = 阅读顺序中第一个可进入且未走到的节点
	var promoted := false
	for raw in entries:
		var entry: Dictionary = raw
		if not promoted and str(entry.get("state", "")) == "available":
			entry["state"] = "current"
			promoted = true

	_build_track(rows, branch_by_act, challenge_entries, final_entry)
	_build_cells(entries)

	# 左栏数据：本树节点进度（走到的节点 / 全部节点），不写任何说明句。
	var total := entries.size()
	var done := 0
	for raw in entries:
		var e: Dictionary = raw
		if str(e.get("state", "")) == "done":
			done += 1
	var ratio := 0.0
	if total > 0:
		ratio = float(done) / float(total)
	_bar_fill.size = Vector2(196.0 * ratio, 7)
	_stats.text = "%d / %d" % [done, total]

	_report(chapter_id, entries)
	_reselect()
	_refresh_left()

func _build_track(rows: Array, branch_by_act: Array, challenges: Array, final_entry: Dictionary) -> void:
	var segments: Array = []
	for act in 3:
		var row: Array = rows[act]
		for i in range(row.size() - 1):
			var a: Dictionary = row[i]
			var b: Dictionary = row[i + 1]
			var walked := str(a.get("state", "")) == "done" and str(b.get("state", "")) == "done"
			segments.append({
				"a": Vector2(float(a["x"]) + NODE_W, float(a["y"]) + NODE_H * 0.5),
				"b": Vector2(float(b["x"]), float(b["y"]) + NODE_H * 0.5),
				"c": UiTheme.alpha(UiTheme.CHALK, 0.62 if walked else 0.18),
				"w": 2.4 if walked else 1.0,
				"dash": 0.0 if walked else 7.0,
				"gap": 9.0,
			})
		for e in branch_by_act[act]:
			var branch: Dictionary = e
			var branch_walked := str(branch.get("state", "")) == "done"
			segments.append({
				"a": Vector2(float(branch["x"]) + 47.0, float(ACT_Y[act]) + NODE_H),
				"b": Vector2(float(branch["x"]) + 47.0, float(branch["y"])),
				"c": UiTheme.alpha(UiTheme.CHALK, 0.55 if branch_walked else 0.15),
				"w": 1.4 if branch_walked else 1.0,
				"dash": 0.0 if branch_walked else 7.0,
				"gap": 9.0,
			})
	var last_x := 0.0
	if not challenges.is_empty():
		last_x = float((challenges[challenges.size() - 1] as Dictionary).get("x", 0.0))
		segments.append({
			"a": Vector2(0, RING_Y), "b": Vector2(last_x + NODE_W, RING_Y),
			"c": UiTheme.alpha(UiTheme.CHALK, 0.16), "w": 1.0, "dash": 0.0,
		})
	if not final_entry.is_empty() and not challenges.is_empty():
		segments.append({
			"a": Vector2(last_x + NODE_W, FINAL_LINK_Y),
			"b": Vector2(float(final_entry.get("x", 0.0)), FINAL_LINK_Y),
			"c": UiTheme.alpha(UiTheme.CHALK, 0.40), "w": 1.4, "dash": 0.0,
		})

	var track := Track.new()
	track.segments = segments
	track.notes = [
		{"at": Vector2(0, 104), "text": "I"},
		{"at": Vector2(0, 256), "text": "II"},
	]
	_canvas.add_child(track)

func _build_cells(entries: Array) -> void:
	for raw in entries:
		var e: Dictionary = raw
		var cell := NodeCell.new()
		cell.kind = str(e.get("kind", "main"))
		cell.state = str(e.get("state", "locked"))
		cell.code = str(e.get("code", ""))
		cell.short_name = str(e.get("short", ""))
		cell.title = str(e.get("title", ""))
		cell.detail = str(e.get("detail", ""))
		cell.node_id = str(e.get("node_id", ""))
		cell.lab_id = str(e.get("lab_id", ""))
		cell.key = str(e.get("key", ""))
		cell.position = Vector2(float(e.get("x", 0.0)), float(e.get("y", 0.0)))
		cell.set_process(cell.state == "current" and UiTheme.motion)
		cell.picked.connect(_on_picked)
		cell.hovered.connect(_on_cell_hovered)
		cell.unhovered.connect(_on_cell_unhovered)
		cell.got_focus.connect(_on_cell_focused)
		cell.lost_focus.connect(_on_cell_unfocused)
		_canvas.add_child(cell)
		_cells.append(cell)

func _report(chapter_id: String, entries: Array) -> void:
	if _printed.has(chapter_id):
		return
	_printed[chapter_id] = true
	var main_count := 0
	var branch_count := 0
	var challenge_count := 0
	for raw in entries:
		var e: Dictionary = raw
		match str(e.get("kind", "")):
			"main":
				main_count += 1
			"branch":
				branch_count += 1
			"challenge":
				challenge_count += 1
	print("IFZ_TREE chapter=%s nodes=%d mainline=%d branch=%d challenge=%d" % [chapter_id, entries.size(), main_count, branch_count, challenge_count])
	var wanted := 0
	if chapter_id == "ch01":
		wanted = 36
	elif chapter_id == "ch02":
		wanted = 31
	if wanted > 0:
		print("IFZ_TREE_CHECK chapter=%s want=%d got=%d ok=%s" % [chapter_id, wanted, entries.size(), str(entries.size() == wanted)])
	var done_ch := 0
	var filled_ch := 0
	for raw in _cells:
		var c = raw
		if c.kind == "challenge" and c.state == "done":
			done_ch += 1
			if c.challenge_tri_filled():
				filled_ch += 1
	if done_ch > 0:
		# 断言：已走过的挑战节点三角必须实心（填充通道）。
		print("IFZ_TREE_CHECK challenge_done_fill=%s (%d/%d)" % [str(filled_ch == done_ch), filled_ch, done_ch])


# ---------------------------------------------------------------- 数据装配

func _progress_ids(chapter_no: int) -> Array:
	var out: Array = []
	for raw in DataDB.skill_graph.nodes_of_tree("progress"):
		var id := str(raw)
		var n: Dictionary = DataDB.skill_graph.node(id)
		if int(n.get("level", 0)) != chapter_no:
			continue
		if not (n.get("pos", null) is Dictionary):
			continue
		out.append(id)
	out.sort_custom(_by_col)
	return out

func _knowledge_ids() -> Array:
	var out: Array = []
	var seen := {}
	for raw in DataDB.chapter.lab_order:
		var lab: Dictionary = DataDB.chapter.lab(str(raw))
		for card in lab.get("knowledge_cards", []):
			var id := str(card)
			if seen.has(id) or not DataDB.skill_graph.has_node(id):
				continue
			seen[id] = true
			out.append(id)
	out.sort_custom(_by_col_row)
	return out

func _skill_ids(chapter_id: String) -> Array:
	# 技能节点按颁发实验归属章节；先前章节已登记的不重复计入本章。
	var claimed := {}
	for raw in DataDB.chapter_order:
		var cid := str(raw)
		if cid == chapter_id:
			break
		var rt: ChapterRuntime = DataDB.runtime_for(cid)
		if rt == null:
			continue
		for lab_id in rt.lab_order:
			for sid in _skills_of(rt.lab(str(lab_id))):
				claimed[str(sid)] = true
	var out: Array = []
	for raw in DataDB.chapter.lab_order:
		var lab: Dictionary = DataDB.chapter.lab(str(raw))
		for sid in _skills_of(lab):
			var id := str(sid)
			if claimed.has(id) or not DataDB.skill_graph.has_node(id):
				continue
			claimed[id] = true
			out.append(id)
	out.sort_custom(_by_col_row)
	return out

func _skills_of(lab: Dictionary) -> Array:
	var out: Array = []
	var single := str(lab.get("skill_node", ""))
	if not single.is_empty():
		out.append(single)
	for raw in lab.get("skill_nodes", []):
		var sid := str(raw)
		if not out.has(sid):
			out.append(sid)
	return out

func _graph_state(id: String) -> String:
	if GameState.player == null or id.is_empty() or not DataDB.skill_graph.has_node(id):
		return "locked"
	match DataDB.skill_graph.node_state(GameState.player, id):
		"completed":
			return "done"
		"available":
			return "available"
		_:
			return "locked"

func _by_col(a, b) -> bool:
	var pa: Dictionary = DataDB.skill_graph.node(str(a)).get("pos", {})
	var pb: Dictionary = DataDB.skill_graph.node(str(b)).get("pos", {})
	return int(pa.get("col", 0)) < int(pb.get("col", 0))

func _by_col_row(a, b) -> bool:
	var pa: Dictionary = DataDB.skill_graph.node(str(a)).get("pos", {})
	var pb: Dictionary = DataDB.skill_graph.node(str(b)).get("pos", {})
	var ca := int(pa.get("col", 0))
	var cb := int(pb.get("col", 0))
	if ca != cb:
		return ca < cb
	return int(pa.get("row", 0)) < int(pb.get("row", 0))


# ---------------------------------------------------------------- 文本

func _short(s: String) -> String:
	if s.length() > 5:
		return s.substr(0, 4) + "…"
	return s

func _tip_text(s: String) -> String:
	if s.length() > 18:
		return s.substr(0, 17) + "…"
	return s

func _title_lines(s: String) -> Array:
	var out: Array = []
	if s.length() <= 9:
		out.append(s)
		return out
	out.append(s.substr(0, 9))
	var rest := s.substr(9)
	if rest.length() > 9:
		rest = rest.substr(0, 8) + "…"
	out.append(rest)
	return out


# ---------------------------------------------------------------- 选中与左栏

func _on_picked(cell: NodeCell) -> void:
	_selected_key = cell.key
	_selected_cell = cell
	_refresh_left()

func _reselect() -> void:
	_selected_cell = null
	if _selected_key.is_empty():
		return
	for raw in _cells:
		var cell: NodeCell = raw
		if cell.key == _selected_key:
			_selected_cell = cell
			return

func _refresh_left() -> void:
	if _selected_cell == null or not is_instance_valid(_selected_cell):
		_block.visible = false
		_unlock_btn.visible = false
		return
	_block.visible = true
	var lines := _title_lines(_selected_cell.title)
	_block_t1.text = str(lines[0])
	_block_t2.text = ""
	if lines.size() > 1:
		_block_t2.text = str(lines[1])
	_block_code.text = _selected_cell.code
	_unlock_btn.visible = _can_unlock_selected()

func _can_unlock_selected() -> bool:
	if _selected_cell == null or _selected_cell.node_id.is_empty():
		return false
	if GameState.player == null:
		return false
	return bool(Knowledge.can_unlock(_selected_cell.node_id).get("ok", false))

func _do_unlock() -> void:
	if _selected_cell == null or _selected_cell.node_id.is_empty():
		return
	var res := Knowledge.unlock(_selected_cell.node_id)
	if not bool(res.get("ok", false)):
		EventBus.toast(str(res.get("error", "")), "error")
	_refresh()


# ---------------------------------------------------------------- 浮条

func _on_cell_hovered(cell: NodeCell) -> void:
	if cell == _tip_cell:
		_tip_hide_timer.stop()
		return
	_tip_hide_timer.stop()
	_hide_tip()
	_tip_cell = cell
	_tip_show_timer.start()

func _on_cell_unhovered(cell: NodeCell) -> void:
	if cell != _tip_cell:
		return
	_tip_show_timer.stop()
	_schedule_tip_hide()

func _on_cell_focused(cell: NodeCell) -> void:
	_tip_show_timer.stop()
	_tip_hide_timer.stop()
	_show_tip(cell)

func _on_cell_unfocused(cell: NodeCell) -> void:
	if cell != _tip_cell:
		return
	_schedule_tip_hide()

func _on_tip_show_timeout() -> void:
	if _tip_cell == null or not is_instance_valid(_tip_cell):
		return
	if not _tip_cell.has_focus() and not _tip_cell.is_hovering():
		return
	_show_tip(_tip_cell)

func _on_tip_hide_timeout() -> void:
	if _tip_cell != null and is_instance_valid(_tip_cell):
		if _tip_cell.has_focus() or _tip_cell.is_hovering():
			return
	_hide_tip()
	_tip_cell = null

func _show_tip(cell: NodeCell) -> void:
	if cell == null or not is_instance_valid(cell):
		return
	var at := cell.position
	# 统一在节点上方 32 px：下方 y+50 在挑战行会到 647，溢出画布底边 641。
	at.y -= 32.0
	at.x = clampf(at.x, 0.0, CANVAS_W - TIP_W)
	_tip_cell = cell
	_tip_label.text = _tip_text(cell.detail)
	_tip.position = Vector2(247, 45) + Vector2(at.x, at.y)
	_tip.visible = true

func _schedule_tip_hide() -> void:
	if not UiTheme.motion:
		_hide_tip()
		_tip_cell = null
		return
	_tip_hide_timer.start()

func _hide_tip() -> void:
	_tip.visible = false
	_tip_label.text = ""
