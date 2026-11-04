extends GameScreen

## 实验室外壳：首屏（制作台 604×470 + 原型台 610×470 + 模块架 1232×124）
## 二级（制作台 / 原型台 / 模块架）与三级（代码编辑器）都在本屏内切换，返回键逐级回退。
## 阶段 1 原型台三区几何（236 + 18 + 724 + 18 + 236）仍作为二级页保留，断言直接读静态函数。

const CircuitEditorGd = preload("res://src/ui/widgets/circuit_editor.gd")
const CraftGd = preload("res://src/ui/screens/lab_craft.gd")
const RackGd = preload("res://src/ui/screens/lab_rack.gd")
const CodeGd = preload("res://src/ui/screens/lab_code_editor.gd")

const W_TOTAL := 1232.0
const H_CONTENT := 612.0

# ---------- 阶段 1：原型台三区 ----------
const W_BENCH := 236.0
const W_CANVAS := 724.0
const W_STORE := 236.0
const GUTTER := 18.0

const ZONE_BENCH := Rect2(0, 0, W_BENCH, H_CONTENT)
const ZONE_CANVAS := Rect2(W_BENCH + GUTTER, 0, W_CANVAS, H_CONTENT)
const ZONE_STORE := Rect2(W_BENCH + GUTTER + W_CANVAS + GUTTER, 0, W_STORE, H_CONTENT)

const SLOT_W := 212.0
const SLOT_H := 64.0
const SLOT_GAP := 8.0
const SLOT_X := 12.0
const SLOT_Y := 48.0
const TOOL_SIZE := 44.0
const TOOL_GAP := 8.0
const TOOL_Y := 528.0

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

# ---------- 阶段 2：首屏三块 ----------
const HUB_BENCH := Rect2(0, 0, 604, 470)
const HUB_PROTO := Rect2(622, 0, 610, 470)
const HUB_RACK := Rect2(0, 488, 1232, 124)
const HUB_ROW_X := 12.0
const HUB_ROW_Y := 48.0
const HUB_ROW_W := 580.0
const HUB_ROW_H := 92.0
const HUB_ROW_GAP := 8.0
const HUB_ROW_MAX := 4
const HUB_RACK_SLOT := 88.0
const HUB_RACK_GAP := 8.0
const HUB_RACK_X := 12.0
const HUB_RACK_Y := 32.0
const HUB_RACK_COUNT := 12

var _page: Control
var _levels: Dictionary = {}
var _level := "hub"
var _editor: CircuitEditor
var _lab_slots: Array = []
var _craft = null
var _rack = null
var _code = null
var _hub_bench: Control
var _hub_proto: Control
var _hub_rack: Control
var _loaded_module := ""

## ---------- 几何唯一来源（断言直接读这里） ----------

static func zone_rects() -> Dictionary:
	return {"bench": ZONE_BENCH, "canvas": ZONE_CANVAS, "store": ZONE_STORE}

static func hub_rects() -> Dictionary:
	return {"bench": HUB_BENCH, "proto": HUB_PROTO, "rack": HUB_RACK}

static func hub_row_rect(i: int) -> Rect2:
	return Rect2(HUB_ROW_X, HUB_ROW_Y + i * (HUB_ROW_H + HUB_ROW_GAP), HUB_ROW_W, HUB_ROW_H)

static func hub_rack_slot_rect(i: int) -> Rect2:
	return Rect2(HUB_RACK_X + i * (HUB_RACK_SLOT + HUB_RACK_GAP), HUB_RACK_Y, HUB_RACK_SLOT, HUB_RACK_SLOT)

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

## 首屏制作台 4 行：按 M→G→S→H→W→P 顺序取前 4 条配方（含 M00 购买行）。
static func hub_rows() -> Array:
	var out := []
	for c in LabCraft.CATS:
		for raw in LabCraft.rows_for(str(c["key"])):
			if out.size() < HUB_ROW_MAX:
				out.append(raw)
	return out

## ---------- 元件台槽位（阶段 1 保留） ----------

class BenchSlot extends Control:
	## 一个可拖的门槽：左端 4 px 色条 + 门名，拖出时给 94×44 的预览。
	signal picked(kind: String)

	var kind := ""
	var tint := Color(1, 1, 1)
	var unlocked := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and unlocked:
			picked.emit(kind)

	func _get_drag_data(_at: Vector2) -> Variant:
		if not unlocked:
			return null
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
		var col := UiTheme.CHALK if unlocked else Color("#9AA9A0")
		draw_string(UiTheme.mono_font(), Vector2(16, size.y * 0.5 + 7),
			kind.to_upper(), HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, UiTheme.F_LABEL, col)
		if not unlocked:
			LabDraw.hatch(self, Rect2(4, 0, size.x - 4, size.y), UiTheme.alpha(UiTheme.GRAYBLUE, 0.14), 12.0)
			LabDraw.prereq_node(self, Rect2(size.x - 50, size.y * 0.5 - 8, 34, 16), "LG", UiTheme.GRAYBLUE)

## ---------- 收纳格 / 工具位 / 实验位 ----------

class BinSlot extends Control:
	## 空收纳格：只有虚线边，不放任何说明文字。
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(2, 2), size - Vector2(4, 4))
		LabDraw.dash_rect(self, r, UiTheme.alpha(UiTheme.MUTED, 0.35))
		draw_rect(Rect2(r.position + Vector2(0, 0), Vector2(r.size.x, 3)), UiTheme.alpha(UiTheme.MUTED, 0.18), true)

class ToolSlot extends Control:
	## 工具位：阶段 1 只是空的虚线位，不接功能、不写提示。
	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
		draw_rect(r, UiTheme.alpha(UiTheme.AMBER, 0.28), false, 1.0)

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

## ---------- 首屏三块 ----------

class HubBench extends Control:
	signal opened

	const ROW_MAX := 4
	const ROW_X := 12.0
	const ROW_Y := 48.0
	const ROW_W := 580.0
	const ROW_H := 92.0
	const ROW_GAP := 8.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			opened.emit()

	func _draw() -> void:
		var rows := []
		for c in LabCraft.CATS:
			for raw in LabCraft.rows_for(str(c["key"])):
				if rows.size() < ROW_MAX:
					rows.append(raw)
		var ready_n := 0
		for raw in rows:
			if LabCraft.state_of(raw) == "ok":
				ready_n += 1
		var f := UiTheme.cjk_font()
		draw_string(f, Vector2(14, 28), "制作台", HORIZONTAL_ALIGNMENT_LEFT, 200, UiTheme.F_H3, UiTheme.CHALK_BRIGHT)
		var badge := Rect2(556, 10, 34, 20)
		draw_rect(badge, UiTheme.alpha(UiTheme.CHALK, 0.06), true)
		draw_rect(badge, UiTheme.LINE, false, 1.0)
		draw_string(UiTheme.mono_font(), badge.position + Vector2(0, 15), str(ready_n),
			HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, UiTheme.F_META, UiTheme.MUTED)
		for i in ROW_MAX:
			var r := Rect2(ROW_X, ROW_Y + i * (ROW_H + ROW_GAP), ROW_W, ROW_H)
			if i >= rows.size():
				LabDraw.dash_rect(self, r, UiTheme.alpha(UiTheme.MUTED, 0.22))
				continue
			var row: Dictionary = rows[i]
			var st: String = LabCraft.state_of(row)
			draw_rect(r, UiTheme.alpha(UiTheme.CHALK, 0.08) if st == "ok" else UiTheme.alpha(UiTheme.CHALK, 0.02), true)
			if st == "locked":
				LabDraw.hatch(self, r, UiTheme.alpha(UiTheme.GRAYBLUE, 0.16), 12.0)
			draw_rect(r, UiTheme.LINE, false, 1.0)
			var bar := UiTheme.alpha(UiTheme.CHALK, 0.90) if st == "ok" else (UiTheme.alpha(UiTheme.CHALK, 0.20) if st == "short" else UiTheme.alpha(UiTheme.GRAYBLUE, 0.35))
			draw_rect(Rect2(r.position.x, r.position.y, 3, r.size.y), bar, true)
			draw_string(f, r.position + Vector2(14, 28), str(row.get("name", "")),
				HORIZONTAL_ALIGNMENT_LEFT, 300, UiTheme.F_LABEL,
				UiTheme.CHALK_BRIGHT if st == "ok" else (UiTheme.CHALK if st == "short" else Color("#9AA9A0")))
			_draw_mats(row, st, r.position)
			var times := LabCraft.max_times(row)
			var tb := Rect2(r.position.x + 442, r.position.y + 36, 34, 20)
			draw_rect(tb, UiTheme.alpha(UiTheme.CHALK, 0.06), true)
			draw_rect(tb, UiTheme.LINE, false, 1.0)
			draw_string(UiTheme.mono_font(), tb.position + Vector2(0, 15), str(times),
				HORIZONTAL_ALIGNMENT_CENTER, tb.size.x, UiTheme.F_META, UiTheme.MUTED)
			var btn := Rect2(r.position.x + 484, r.position.y + 28, 84, 36)
			var label := "购买" if str(row.get("kind", "")) == "buy" else "制作"
			draw_rect(btn, UiTheme.CHALK if st == "ok" else UiTheme.BOARD_SUNK, true)
			draw_rect(btn, UiTheme.alpha(UiTheme.CHALK, 0.5) if st == "ok" else UiTheme.LINE, false, 1.0)
			if st != "locked":
				draw_string(f, btn.position + Vector2(0, 24), label,
					HORIZONTAL_ALIGNMENT_CENTER, btn.size.x, UiTheme.F_BODY,
					UiTheme.INK if st == "ok" else UiTheme.MUTED)

	func _draw_mats(row: Dictionary, st: String, origin: Vector2) -> void:
		var rec: Dictionary = DataDB.catalog.recipe(str(row.get("rid", "")))
		var inputs: Dictionary = rec.get("inputs", {})
		var keys: Array = inputs.keys()
		var p = GameState.player
		var x := origin.x + 300.0
		for i in mini(keys.size(), 5):
			var iid := str(keys[i])
			var need := int(inputs[iid])
			var have := 0 if p == null else p.item_count(iid)
			var ir := Rect2(x, origin.y + 36, 20, 20)
			LabDraw.item_icon(self, ir, iid, str(DataDB.catalog.item(iid).get("layer", "L0")), UiTheme.CHALK)
			if st == "short" and have < need:
				LabDraw.cross(self, Vector2(ir.end.x - 2, ir.position.y + 2), UiTheme.DANGER, 6.0)
			x += 26.0

class HubProto extends Control:
	signal opened
	var gate_count := 0
	var loaded := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			opened.emit()

	func _draw() -> void:
		var f := UiTheme.cjk_font()
		draw_string(f, Vector2(14, 28), "原型台", HORIZONTAL_ALIGNMENT_LEFT, 200, UiTheme.F_H3, UiTheme.CHALK_BRIGHT)
		var badge := Rect2(558, 10, 34, 20)
		draw_rect(badge, UiTheme.alpha(UiTheme.CHALK, 0.06), true)
		draw_rect(badge, UiTheme.LINE, false, 1.0)
		draw_string(UiTheme.mono_font(), badge.position + Vector2(0, 15), str(gate_count),
			HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, UiTheme.F_META, UiTheme.MUTED)
		var grid := Rect2(12, 48, 586, 336)
		draw_rect(grid, UiTheme.BOARD_SUNK, true)
		draw_rect(grid, UiTheme.LINE, false, 1.0)
		var g := 16.0
		var x := grid.position.x + g
		while x < grid.end.x:
			draw_line(Vector2(x, grid.position.y), Vector2(x, grid.end.y), UiTheme.alpha(UiTheme.CHALK, 0.06), 1.0)
			x += g
		var y := grid.position.y + g
		while y < grid.end.y:
			draw_line(Vector2(grid.position.x, y), Vector2(grid.end.x, y), UiTheme.alpha(UiTheme.CHALK, 0.06), 1.0)
			y += g
		var kinds := ["and", "or", "not"].slice(0, mini(3, maxi(1, gate_count)))
		for i in kinds.size():
			var r := Rect2(grid.position.x + 24 + i * 110, grid.position.y + 40, 94, 44)
			draw_rect(r, UiTheme.alpha(UiTheme.CHALK, 0.08), true)
			draw_rect(r, UiTheme.LINE, false, 1.0)
			LabDraw.item_icon(self, Rect2(r.position + Vector2(10, 8), Vector2(28, 28)), str(kinds[i]), "L1", UiTheme.CHALK)
			draw_string(UiTheme.mono_font(), r.position + Vector2(46, 28), str(kinds[i]).to_upper(),
				HORIZONTAL_ALIGNMENT_LEFT, 44, UiTheme.F_META, UiTheme.CHALK)
		var b1 := Rect2(12, 396, 136, 36)
		var b2 := Rect2(160, 396, 136, 36)
		draw_rect(b1, UiTheme.BOARD_SUNK, true)
		draw_rect(b1, UiTheme.alpha(UiTheme.CHALK, 0.45), false, 1.0)
		draw_string(f, b1.position + Vector2(0, 24), "新建原型",
			HORIZONTAL_ALIGNMENT_CENTER, b1.size.x, UiTheme.F_BODY, UiTheme.CHALK)
		var can_continue := gate_count > 0
		draw_rect(b2, UiTheme.BOARD_SUNK, true)
		draw_rect(b2, UiTheme.alpha(UiTheme.CHALK, 0.45) if can_continue else UiTheme.LINE, false, 1.0)
		draw_string(f, b2.position + Vector2(0, 24), "继续",
			HORIZONTAL_ALIGNMENT_CENTER, b2.size.x, UiTheme.F_BODY,
			UiTheme.CHALK if can_continue else UiTheme.MUTED_DIM)
		if not loaded.is_empty():
			var chip := Rect2(452, 396, 146, 36)
			draw_rect(chip, UiTheme.alpha(UiTheme.CYAN, 0.12), true)
			draw_rect(chip, UiTheme.alpha(UiTheme.CYAN, 0.7), false, 1.0)
			LabDraw.item_icon(self, Rect2(chip.position + Vector2(6, 6), Vector2(24, 24)), loaded, "L4", UiTheme.CHALK)
			draw_string(UiTheme.mono_font(), chip.position + Vector2(34, 23), loaded,
				HORIZONTAL_ALIGNMENT_LEFT, 104, UiTheme.F_META, UiTheme.CHALK)
		else:
			draw_string(UiTheme.mono_font(), Vector2(452, 420), "%d 门" % gate_count,
				HORIZONTAL_ALIGNMENT_RIGHT, 146, UiTheme.F_META, UiTheme.MUTED)

class HubRack extends Control:
	signal slot_picked(index: int)

	const MAX_SLOTS := 12
	const SLOT := 88.0
	const GAP := 8.0
	const X0 := 12.0
	const Y0 := 32.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _slot_at(p: Vector2) -> int:
		for i in MAX_SLOTS:
			var r := Rect2(X0 + i * (SLOT + GAP), Y0, SLOT, SLOT)
			if r.has_point(p):
				return i
		return -1

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var idx := _slot_at((event as InputEventMouseButton).position)
			slot_picked.emit(idx if idx >= 0 else -2)

	func _draw() -> void:
		var f := UiTheme.cjk_font()
		draw_string(f, Vector2(14, 24), "模块架", HORIZONTAL_ALIGNMENT_LEFT, 200, UiTheme.F_H3, UiTheme.CHALK_BRIGHT)
		var rows := LabRack.inventory_rows()
		for i in MAX_SLOTS:
			var r := Rect2(X0 + i * (SLOT + GAP), Y0, SLOT, SLOT)
			if i >= rows.size():
				LabDraw.dash_rect(self, r, UiTheme.alpha(UiTheme.MUTED, 0.25))
				continue
			var id := str(rows[i]["id"])
			var layer := str(rows[i]["layer"])
			draw_rect(r, UiTheme.alpha(UiTheme.CHALK, 0.06), true)
			draw_rect(r, UiTheme.LINE, false, 1.0)
			LabDraw.item_icon(self, Rect2(r.position + Vector2(26, 14), Vector2(36, 36)), id, layer, UiTheme.CHALK)
			draw_string(UiTheme.mono_font(), r.position + Vector2(4, 76), id,
				HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 8, UiTheme.F_META, UiTheme.MUTED)
			var q := int(rows[i]["qty"])
			if q > 1:
				draw_string(UiTheme.mono_font(), r.position + Vector2(0, 20), "×%d" % q,
					HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 8, UiTheme.F_META, UiTheme.CHALK)

## ---------- 构建 ----------

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func _build() -> void:
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_page)

	var hub := _level_node("hub")
	_build_hub(hub)

	var proto := _level_node("proto")
	_build_prototype(proto)

	var craft_node := _level_node("craft")
	_craft = CraftGd.new()
	(_craft as Control).position = Vector2.ZERO
	(_craft as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	(_craft as Control).call("build", self)
	craft_node.add_child(_craft)

	var rack_node := _level_node("rack")
	_rack = RackGd.new()
	(_rack as Control).position = Vector2.ZERO
	(_rack as Control).mouse_filter = Control.MOUSE_FILTER_PASS
	(_rack as Control).call("build", self)
	rack_node.add_child(_rack)

	show_level("hub")
	_refresh_labs()
	if CliArgs.has_flag("shot-demo"):
		show_level("proto")
		_demo()

func _level_node(nm: String) -> Control:
	var c := Control.new()
	c.name = nm
	c.size = Vector2(W_TOTAL, H_CONTENT)
	c.mouse_filter = Control.MOUSE_FILTER_PASS
	c.visible = false
	_page.add_child(c)
	_levels[nm] = c
	return c

func show_level(nm: String) -> void:
	if nm == "editor" and not _levels.has("editor"):
		var host := _level_node("editor")
		_code = CodeGd.new()
		(_code as Control).position = Vector2.ZERO
		(_code as Control).mouse_filter = Control.MOUSE_FILTER_PASS
		(_code as Control).call("build", self)
		host.add_child(_code)
	for k in _levels.keys():
		(_levels[k] as Control).visible = str(k) == nm
	_level = nm
	match nm:
		"hub":
			_refresh_hub()
		"craft":
			if _craft != null:
				(_craft as Control).call("refresh")
		"rack":
			if _rack != null:
				(_rack as Control).call("refresh")
		"editor":
			if _code != null:
				(_code as Control).call("on_open")

## 逐级返回：三级→模块架、二级→首屏；首屏返回 false 交给主壳回黑板。
func back_one_level() -> bool:
	match _level:
		"hub":
			return false
		"editor":
			show_level("rack")
		_:
			show_level("hub")
	return true

func on_show() -> void:
	_refresh_labs()
	_refresh_hub()
	var lp := CliArgs.value("lab-page", "")
	if not lp.is_empty() and lp != "hub":
		if lp == "editor":
			open_code_editor()
		else:
			show_level(lp)
	if lp == "rack" and CliArgs.value("lab-menu", "") == "1":
		open_rack()
		if _rack != null:
			(_rack as Control).call("open_menu_for", LabRack.CODE_ITEM, Vector2(30, 30))

func _build_hub(host: Control) -> void:
	_zone(host, HUB_BENCH, UiTheme.AMBER)
	_zone(host, HUB_PROTO, UiTheme.CYAN)
	_zone(host, HUB_RACK, UiTheme.RUST)
	_hub_bench = HubBench.new()
	_hub_bench.position = HUB_BENCH.position
	_hub_bench.size = HUB_BENCH.size
	_hub_bench.opened.connect(open_craft)
	host.add_child(_hub_bench)
	_hub_proto = HubProto.new()
	_hub_proto.position = HUB_PROTO.position
	_hub_proto.size = HUB_PROTO.size
	_hub_proto.opened.connect(open_prototype)
	host.add_child(_hub_proto)
	_hub_rack = HubRack.new()
	_hub_rack.position = HUB_RACK.position
	_hub_rack.size = HUB_RACK.size
	_hub_rack.slot_picked.connect(_on_hub_rack_picked)
	host.add_child(_hub_rack)

func _on_hub_rack_picked(index: int) -> void:
	open_rack()
	if index < 0 or _rack == null:
		return
	var rows := LabRack.inventory_rows()
	if index < rows.size():
		(_rack as Control).call("select_item", str(rows[index]["id"]))

func _refresh_hub() -> void:
	if _hub_proto != null:
		_hub_proto.gate_count = 0
		if _editor != null:
			_hub_proto.gate_count = _editor.graph.gate_ids().size()
		_hub_proto.loaded = _loaded_module
		_hub_proto.queue_redraw()
	if _hub_bench != null:
		_hub_bench.queue_redraw()
	if _hub_rack != null:
		_hub_rack.queue_redraw()

## ---------- 阶段 1 原型台页 ----------

func _build_prototype(host: Control) -> void:
	_zone(host, ZONE_BENCH, UiTheme.AMBER)
	_zone(host, ZONE_CANVAS, UiTheme.CYAN)
	_zone(host, ZONE_STORE, UiTheme.RUST)
	_build_bench(host)
	_build_canvas(host)
	_build_store(host)

func _zone(host: Control, rect: Rect2, accent: Color) -> void:
	# 区隔只靠底色、1 px 边框和顶部 3 px 色条，不写区块标题。
	var p := Panel.new()
	p.position = rect.position
	p.size = rect.size
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	p.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_HIGH, UiTheme.LINE, 0, 1))
	host.add_child(p)
	var bar := ColorRect.new()
	bar.color = UiTheme.alpha(accent, 0.85)
	bar.position = rect.position + Vector2(1, 1)
	bar.size = Vector2(rect.size.x - 2, 3)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(bar)

func _build_bench(host: Control) -> void:
	var unlocked := _gate_unlock_map()
	for i in PALETTE_GATES.size():
		var s := BenchSlot.new()
		s.kind = str(PALETTE_GATES[i])
		s.tint = _gate_tint(str(PALETTE_GATES[i]))
		s.unlocked = bool(unlocked.get(str(PALETTE_GATES[i]), true))
		s.position = bench_slot_rect(i).position
		s.size = bench_slot_rect(i).size
		s.tooltip_text = str(LogicGates.NAMES.get(LogicGates.from_string(s.kind), s.kind))
		s.picked.connect(_on_bench_pick)
		host.add_child(s)
	for i in 3:
		var t := ToolSlot.new()
		t.position = tool_slot_rect(i).position
		t.size = tool_slot_rect(i).size
		host.add_child(t)

func _build_canvas(host: Control) -> void:
	_editor = CircuitEditorGd.new()
	_editor.quiet = true
	_editor.max_gates = 24
	_editor.snap_grid = Vector2(110, 60)
	_editor.snap_origin = Vector2(18, 18)
	_editor.position = ZONE_CANVAS.position + Vector2(1, 1)
	_editor.custom_minimum_size = ZONE_CANVAS.size - Vector2(2, 2)
	_editor.size = ZONE_CANVAS.size - Vector2(2, 2)
	host.add_child(_editor)

func _build_store(host: Control) -> void:
	# 收纳区内的元素按区内坐标排，统一加 zone 偏移，避免画到元件台上。
	var origin := ZONE_STORE.position
	for i in BIN_COUNT:
		var b := BinSlot.new()
		b.position = origin + bin_slot_rect(i).position
		b.size = bin_slot_rect(i).size
		host.add_child(b)
	for i in 6:
		var s := LabSlot.new()
		s.position = origin + rack_slot_rect(i).position
		s.size = rack_slot_rect(i).size
		s.entered.connect(_on_lab_entered)
		host.add_child(s)
		_lab_slots.append(s)
	var sep := ColorRect.new()
	sep.color = UiTheme.LINE
	sep.position = origin + Vector2(BIN_X, RACK_Y - 24)
	sep.size = Vector2(SLOT_W, 1)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.add_child(sep)
	_refresh_labs()

## ---------- 行为 ----------

func open_craft() -> void:
	show_level("craft")

func open_prototype() -> void:
	show_level("proto")
	_refresh_hub()

func open_rack() -> void:
	show_level("rack")

## 只从模块架 W05 右键「编写代码」调用；三级页单独界面。
func open_code_editor() -> void:
	show_level("editor")

func open_skills() -> void:
	if main != null:
		main.call("show_screen", "skills")

func load_module(item_id: String) -> void:
	_loaded_module = item_id
	_refresh_hub()

func focus_craft(item_id: String) -> void:
	if _craft != null:
		(_craft as Control).call("focus_item", item_id)

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

## 门型解锁：按知识节点，无节点数据时默认解锁 and/or/not。
func _gate_unlock_map() -> Dictionary:
	var p = GameState.player
	var out := {"and": true, "or": true, "not": true}
	if p == null:
		out["nand"] = false
		out["xor"] = false
		out["nor"] = false
		return out
	out["nand"] = p.has_knowledge("demorgan") or p.has_knowledge("logic_gates")
	out["xor"] = p.has_knowledge("xor")
	out["nor"] = p.has_knowledge("demorgan")
	return out

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
	_refresh_hub()
