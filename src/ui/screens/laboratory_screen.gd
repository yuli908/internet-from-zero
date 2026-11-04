extends GameScreen

## 实验室·原型台（阶段 1）：三区骨架 + 元件台拖门 + 画布落门 + 一根连线。
## 本屏 local (0,0) 对应绝对 (24,92)，内容 1232×612。
## 阶段 2 的元件分类、合成、抽屉、代码编辑器都不在这里，先只保证最小可用链路。

const CircuitEditorGd = preload("res://src/ui/widgets/circuit_editor.gd")

const W_TOTAL := 1232.0
const H_CONTENT := 612.0
const W_BENCH := 236.0
const W_CANVAS := 724.0
const W_STORE := 236.0
const GUTTER := 18.0

## 三区矩形（local 坐标），测试与断言共用同一份来源。
const ZONE_BENCH := Rect2(0, 0, W_BENCH, H_CONTENT)
const ZONE_CANVAS := Rect2(W_BENCH + GUTTER, 0, W_CANVAS, H_CONTENT)
const ZONE_STORE := Rect2(W_BENCH + GUTTER + W_CANVAS + GUTTER, 0, W_STORE, H_CONTENT)

## 元件台：6 个门槽 212×64，间距 8；底部 3 个 44×44 工具位（阶段 1 空置）。
const SLOT_W := 212.0
const SLOT_H := 64.0
const SLOT_GAP := 8.0
const SLOT_X := 12.0
const SLOT_Y := 48.0
const TOOL_SIZE := 44.0
const TOOL_GAP := 8.0
const TOOL_Y := 528.0

## 收纳区：2×4 的 96×96 收纳格；底部 6 个 32×32 的章节实验位。
const BIN_SIZE := 96.0
const BIN_GAP := 8.0
const BIN_X := 12.0
const BIN_Y := 48.0
const BIN_COUNT := 8
const RACK_SLOT := 32.0
const RACK_GAP := 4.0
const RACK_X := 12.0
const RACK_Y := 520.0

const PALETTE_GATES := ["and", "or", "not", "nand", "xor", "nor"]

var _page: Control
var _editor: CircuitEditor
var _lab_slots: Array = []

## ---------- 几何唯一来源（断言直接读这里） ----------

static func zone_rects() -> Dictionary:
	return {"bench": ZONE_BENCH, "canvas": ZONE_CANVAS, "store": ZONE_STORE}

static func palette_gates() -> Array:
	return PALETTE_GATES.duplicate()

static func bench_slot_rect(i: int) -> Rect2:
	return Rect2(SLOT_X, SLOT_Y + i * (SLOT_H + SLOT_GAP), SLOT_W, SLOT_H)

static func tool_slot_rect(i: int) -> Rect2:
	return Rect2(SLOT_X + i * (TOOL_SIZE + TOOL_GAP), TOOL_Y, TOOL_SIZE, TOOL_SIZE)

static func bin_slot_rect(i: int) -> Rect2:
	var c := i % 2
	var r := int(floor(float(i) / 2.0))
	return Rect2(BIN_X + c * (BIN_SIZE + BIN_GAP), BIN_Y + r * (BIN_SIZE + BIN_GAP), BIN_SIZE, BIN_SIZE)

static func rack_slot_rect(i: int) -> Rect2:
	return Rect2(RACK_X + i * (RACK_SLOT + RACK_GAP), RACK_Y, RACK_SLOT, RACK_SLOT)

## 实验位是否可点：只有已解锁的 lab 才能进；锁定的格子点下去不动作。
static func slot_open(lab_id: String, unlocked: Dictionary) -> bool:
	return bool(unlocked.get(lab_id, false))

## ---------- 元件台槽位 ----------

class BenchSlot extends Control:
	## 一个可拖的门槽：左端 4 px 色条 + 门名，拖出时给 94×44 的预览。
	signal picked(kind: String)

	var kind := ""
	var tint := Color(1, 1, 1)

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			picked.emit(kind)

	func _get_drag_data(_at: Vector2) -> Variant:
		var preview := PanelContainer.new()
		preview.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_HIGH, UiTheme.alpha(tint, 0.85), 0, 1))
		var l := Ui.label(kind.to_upper(), UiTheme.F_LABEL, UiTheme.CHALK)
		l.custom_minimum_size = Vector2(94, 44)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		preview.add_child(l)
		set_drag_preview(preview)
		return {"bench_gate": kind}

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.PANEL_2, true)
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.LINE, false, 1.0)
		draw_rect(Rect2(0, 0, 4, size.y), tint, true)
		draw_string(UiTheme.mono_font(), Vector2(16, size.y * 0.5 + 7),
			kind.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, UiTheme.F_LABEL, UiTheme.CHALK)

## ---------- 收纳格 / 工具位 / 实验位 ----------

class BinSlot extends Control:
	## 空收纳格：只有虚线边，不放任何说明文字。
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		var c := UiTheme.alpha(UiTheme.MUTED, 0.35)
		_dash_rect(r, c)
		draw_rect(Rect2(r.position + Vector2(0, 0), Vector2(r.size.x, 3)), UiTheme.alpha(UiTheme.MUTED, 0.18), true)

	func _dash_rect(r: Rect2, c: Color) -> void:
		var step := 7.0
		var x := r.position.x
		while x < r.end.x:
			var x2 := minf(x + 4.0, r.end.x)
			draw_line(Vector2(x, r.position.y), Vector2(x2, r.position.y), c, 1.0)
			draw_line(Vector2(x, r.end.y), Vector2(x2, r.end.y), c, 1.0)
			x += step
		var y := r.position.y
		while y < r.end.y:
			var y2 := minf(y + 4.0, r.end.y)
			draw_line(Vector2(r.position.x, y), Vector2(r.position.x, y2), c, 1.0)
			draw_line(Vector2(r.end.x, y), Vector2(r.end.x, y2), c, 1.0)
			y += step

class ToolSlot extends Control:
	## 工具位：阶段 1 只是空的虚线位，不接功能、不写提示。
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		var c := UiTheme.alpha(UiTheme.AMBER, 0.28)
		draw_rect(r, c, false, 1.0)

class LabSlot extends Control:
	## 章节实验位：32×32 只写编号；锁定画锁，当前/最后已解锁画青色环。
	signal entered(lab_id: String)

	var lab_id := ""
	var label := ""
	var unlocked := false
	var active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton):
			return
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT and unlocked and not lab_id.is_empty():
			entered.emit(lab_id)

	func _draw() -> void:
		var bg := UiTheme.alpha(UiTheme.CYAN, 0.12) if active else UiTheme.PANEL_2
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		draw_rect(Rect2(Vector2.ZERO, size),
			UiTheme.alpha(UiTheme.CYAN, 0.9) if active else UiTheme.LINE, false, 1.0)
		if not unlocked:
			var c := UiTheme.MUTED_DIM
			var w := size.x
			draw_rect(Rect2(w * 0.30, w * 0.50, w * 0.40, w * 0.28), c, true)
			draw_arc(Vector2(w * 0.50, w * 0.50), w * 0.20, PI, TAU, 8, c, maxf(1.0, w * 0.09))
			return
		draw_string(UiTheme.mono_font(), Vector2(0, size.y * 0.5 + 7), label,
			HORIZONTAL_ALIGNMENT_CENTER, size.x, UiTheme.F_META, UiTheme.CHALK)

## ---------- 构建 ----------

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func on_show() -> void:
	_refresh_labs()

func _build() -> void:
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_page)
	_zone(ZONE_BENCH, UiTheme.AMBER)
	_zone(ZONE_CANVAS, UiTheme.CYAN)
	_zone(ZONE_STORE, UiTheme.RUST)
	_build_bench()
	_build_canvas()
	_build_store()
	if CliArgs.has_flag("shot-demo"):
		_demo()

func _zone(rect: Rect2, accent: Color) -> void:
	# 区隔只靠底色、1 px 边框和顶部 3 px 色条，不写区块标题。
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_HIGH, UiTheme.LINE, 0, 1))
	_page.add_child(p)
	var bar := ColorRect.new()
	bar.color = UiTheme.alpha(accent, 0.85)
	bar.position = rect.position + Vector2(1, 1)
	bar.size = Vector2(rect.size.x - 2, 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(bar)

func _build_bench() -> void:
	for i in PALETTE_GATES.size():
		var s := BenchSlot.new()
		s.kind = str(PALETTE_GATES[i])
		s.tint = _gate_tint(str(PALETTE_GATES[i]))
		s.position = bench_slot_rect(i).position
		s.size = bench_slot_rect(i).size
		s.tooltip_text = str(LogicGates.NAMES.get(LogicGates.from_string(s.kind), s.kind))
		s.picked.connect(_on_bench_pick)
		_page.add_child(s)
	for i in 3:
		var t := ToolSlot.new()
		t.position = tool_slot_rect(i).position
		t.size = tool_slot_rect(i).size
		_page.add_child(t)

func _build_canvas() -> void:
	_editor = CircuitEditorGd.new()
	_editor.quiet = true
	_editor.max_gates = 24
	_editor.position = ZONE_CANVAS.position + Vector2(1, 1)
	_editor.custom_minimum_size = ZONE_CANVAS.size - Vector2(2, 2)
	_editor.size = ZONE_CANVAS.size - Vector2(2, 2)
	_page.add_child(_editor)

func _build_store() -> void:
	# 收纳区内的元素按区内坐标排，统一加 zone 偏移，避免画到元件台上。
	var origin := ZONE_STORE.position
	for i in BIN_COUNT:
		var b := BinSlot.new()
		b.position = origin + bin_slot_rect(i).position
		b.size = bin_slot_rect(i).size
		_page.add_child(b)
	for i in 6:
		var s := LabSlot.new()
		s.position = origin + rack_slot_rect(i).position
		s.size = rack_slot_rect(i).size
		s.entered.connect(_on_lab_entered)
		_page.add_child(s)
		_lab_slots.append(s)
	# 收纳格与实验位之间的一条静默分隔线。
	var sep := ColorRect.new()
	sep.color = UiTheme.LINE
	sep.position = origin + Vector2(BIN_X, RACK_Y - 24)
	sep.size = Vector2(SLOT_W, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(sep)
	_refresh_labs()

## ---------- 行为 ----------

func _on_bench_pick(kind: String) -> void:
	## 点一下元件台就把它设成画布的当前门型，之后点空白也能落门。
	if _editor != null:
		_editor.set_selected_gate(kind)

func _on_lab_entered(lab_id: String) -> void:
	if main != null and ChapterFlow.is_lab_unlocked(lab_id):
		main.call("show_lab", lab_id)

func _last_unlocked() -> String:
	var out := ""
	for raw in DataDB.chapter.lab_order:
		if ChapterFlow.is_lab_unlocked(str(raw)):
			out = str(raw)
	return out

func _refresh_labs() -> void:
	var order: Array = DataDB.chapter.lab_order
	var ch_no := int(DataDB.chapter.data.get("number", 1))
	var active := _last_unlocked()
	for i in _lab_slots.size():
		var s: LabSlot = _lab_slots[i]
		if i >= order.size():
			s.visible = false
			continue
		var lid := str(order[i])
		s.visible = true
		s.lab_id = lid
		s.label = "%d.%d" % [ch_no, i + 1]
		s.unlocked = ChapterFlow.is_lab_unlocked(lid)
		s.active = lid == active
		var meta: Dictionary = DataDB.chapter.lab(lid)
		s.tooltip_text = str(meta.get("title", lid))
		s.queue_redraw()

func _gate_tint(kind: String) -> Color:
	match kind:
		"and", "nand":
			return UiTheme.AMBER
		"or", "nor":
			return UiTheme.CYAN
		"not":
			return UiTheme.RUST
		_:
			return UiTheme.MUTED

## 截图/验收用的最小链路：拖两个门 + 连一根线（不依赖鼠标事件）。
func _demo() -> void:
	var g1 := _editor.add_gate_at("and", Vector2(220, 200))
	var g2 := _editor.add_gate_at("not", Vector2(430, 200))
	if g1.is_empty() or g2.is_empty():
		return
	var p1: Vector2 = _editor.graph.nodes[g1]["pos"]
	var p2: Vector2 = _editor.graph.nodes[g2]["pos"]
	_editor.call("_on_left", p1 + Vector2(CircuitEditor.NODE_SIZE.x, CircuitEditor.NODE_SIZE.y * 0.5))
	_editor.call("_on_left", p2 + Vector2(0, 13))
