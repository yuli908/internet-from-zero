class_name LabRack
extends Control

## 实验室·模块架（二级）：6×5 格 + 右侧检查器 + 模块右键菜单。
## 右键菜单只在模块（L4）上出现；「编写代码」只出现在 W05（单板电脑）。
## 图标按层编码，数量用角标，不写状态句。

const Z_GRID := Rect2(0, 0, 908, 612)
const Z_DETAIL := Rect2(926, 0, 306, 612)

const COLS := 6
const ROWS := 5
const SLOT_W := 144.0
const SLOT_H := 112.0
const SLOT_GAP := 8.0
const GRID_COUNT := COLS * ROWS

const MENU_W := 208.0
const MENU_ITEM_H := 44.0

const CODE_ITEM := "W05"

var _lab: Control
var _slots: Array = []
var _selected := ""
var _menu: Control
var _menu_layer: Control
var _detail: Control
var _new_ids: Dictionary = {}

static func zone_rects() -> Dictionary:
	return {"grid": Z_GRID, "detail": Z_DETAIL}

static func slot_count() -> int:
	return GRID_COUNT

static func slot_rect(i: int) -> Rect2:
	var c := i % COLS
	var r := int(floor(float(i) / float(COLS)))
	return Rect2(2.0 + c * (SLOT_W + SLOT_GAP), 2.0 + r * (SLOT_H + SLOT_GAP), SLOT_W, SLOT_H)

## 右键菜单项：模块才有；W05 多一条「编写代码」，且只在 W05 上出现。
static func menu_items(item_id: String) -> Array:
	var out := []
	var layer := str(DataDB.catalog.item(item_id).get("layer", ""))
	if layer != "L4":
		return out
	if item_id == CODE_ITEM:
		out.append({"id": "code", "label": "编写代码"})
	out.append({"id": "load", "label": "装入原型台"})
	out.append({"id": "view", "label": "查看"})
	return out

static func code_entry_allowed(item_id: String) -> bool:
	return item_id == CODE_ITEM

static func menu_height(item_id: String) -> float:
	return float(menu_items(item_id).size()) * MENU_ITEM_H

static func is_module(item_id: String) -> bool:
	return str(DataDB.catalog.item(item_id).get("layer", "")) == "L4"

## 背包顺序按目录顺序，只取持有量 >0 的件。
static func inventory_rows() -> Array:
	var cat: Catalog = DataDB.catalog
	var p = GameState.player
	var out := []
	if p == null:
		return out
	for raw_id in cat.item_order:
		var id := str(raw_id)
		if cat.is_currency(id):
			continue
		var n := p.item_count(id)
		if n <= 0:
			continue
		out.append({"id": id, "qty": n, "layer": str(cat.item(id).get("layer", ""))})
	return out

## ---------- 构建 ----------

func build(lab_ref: Control) -> void:
	_lab = lab_ref
	size = Vector2(1232, 612)
	_add_zone(Z_GRID, UiTheme.CYAN)
	_add_zone(Z_DETAIL, UiTheme.RUST)
	for i in GRID_COUNT:
		var s := RackSlot.new()
		s.index = i
		s.position = Z_GRID.position + slot_rect(i).position
		s.size = slot_rect(i).size
		s.picked.connect(_on_slot_pick)
		s.menu_requested.connect(_on_slot_menu)
		add_child(s)
		_slots.append(s)
	_detail = DetailView.new()
	_detail.position = Z_DETAIL.position
	_detail.size = Z_DETAIL.size
	_detail.acted.connect(_on_detail_action)
	add_child(_detail)
	_menu_layer = Control.new()
	_menu_layer.position = Z_GRID.position
	_menu_layer.size = Z_GRID.size
	_menu_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_menu_layer)
	refresh()

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

func refresh() -> void:
	var rows := inventory_rows()
	for i in _slots.size():
		var s: RackSlot = _slots[i]
		if i < rows.size():
			s.visible = true
			s.item_id = str(rows[i]["id"])
			s.qty = int(rows[i]["qty"])
			s.is_new = _new_ids.has(s.item_id)
		else:
			s.visible = true
			s.item_id = ""
			s.qty = 0
			s.is_new = false
		s.selected = s.item_id == _selected
		s.queue_redraw()
	_detail.visible = true
	_detail.item_id = _selected
	_detail.qty = 0 if _selected.is_empty() else int(GameState.player.item_count(_selected))
	_detail.can_code = code_entry_allowed(_selected)
	_detail.queue_redraw()

## 右键菜单：主界面只给模块；非模块右键不弹。
func _on_slot_menu(index: int, at: Vector2) -> void:
	_build_menu(str((_slots[index] as RackSlot).item_id), at)

func _build_menu(id: String, at: Vector2) -> void:
	var items := menu_items(id)
	if items.is_empty():
		return
	_close_menu()
	_menu = MenuPanel.new()
	_menu.items = items
	_menu.item_id = id
	_menu.size = Vector2(MENU_W, menu_height(id))
	var pos := at
	pos.x = clampf(pos.x, 0.0, size.x - MENU_W - 12.0)
	pos.y = clampf(pos.y, 0.0, size.y - menu_height(id) - 12.0)
	_menu.position = pos
	_menu.acted.connect(_on_menu_action)
	_menu_layer.add_child(_menu)
	_menu.queue_redraw()

func _close_menu() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null

func _on_menu_action(action: String) -> void:
	var id := "" if _menu == null else str(_menu.item_id)
	_close_menu()
	if id.is_empty() or _lab == null:
		return
	match action:
		"code":
			_lab.call("open_code_editor")
		"load":
			_lab.call("load_module", id)
			_lab.call("open_prototype")
		"view":
			_selected = id
			refresh()

func _on_slot_pick(index: int) -> void:
	_close_menu()
	var id := str((_slots[index] as RackSlot).item_id)
	_selected = id
	refresh()

func _on_detail_action(action: String) -> void:
	if _selected.is_empty() or _lab == null:
		return
	match action:
		"code":
			_lab.call("open_code_editor")
		"load":
			if is_module(_selected):
				_lab.call("load_module", _selected)
				_lab.call("open_prototype")
		"recipe":
			_lab.call("open_craft")
			_lab.call("focus_craft", _selected)

## 新增件标记：合成/购买后调用，画 8×8 角标与 α.62 边框，2 秒后消退。
func mark_new(item_id: String) -> void:
	if item_id.is_empty():
		return
	_new_ids[item_id] = Time.get_ticks_msec()
	refresh()
	var t := Timer.new()
	t.one_shot = true
	t.wait_time = 2.0
	t.timeout.connect(func():
		_new_ids.erase(item_id)
		refresh()
	)
	add_child(t)
	t.start()

func select_item(item_id: String) -> void:
	_selected = item_id
	refresh()

## 截图/验收入口：按物品 id 打开右键菜单。
func open_menu_for(item_id: String, at: Vector2) -> void:
	select_item(item_id)
	for i in _slots.size():
		if str((_slots[i] as RackSlot).item_id) == item_id:
			_on_slot_menu(i, at)
			return
	_build_menu(item_id, at)

func menu_open() -> bool:
	return _menu != null

## ---------- 子控件 ----------

class RackSlot extends Control:
	signal picked(index: int)
	signal menu_requested(index: int, at: Vector2)
	var index := 0
	var item_id := ""
	var qty := 0
	var selected := false
	var is_new := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed:
			return
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			picked.emit(index)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and not item_id.is_empty():
			menu_requested.emit(index, position + mb.position)

	func _draw() -> void:
		var r := Rect2(Vector2.ZERO, size)
		if item_id.is_empty():
			LabDraw.dash_rect(self, r.grow(-2), UiTheme.alpha(UiTheme.MUTED, 0.28))
			return
		var layer := str(DataDB.catalog.item(item_id).get("layer", "L0"))
		draw_rect(r, UiTheme.alpha(UiTheme.CHALK, 0.06), true)
		draw_rect(r, UiTheme.alpha(UiTheme.CHALK, 0.62) if is_new else (UiTheme.CHALK if selected else UiTheme.LINE),
			false, 2.0 if selected or is_new else 1.0)
		if selected:
			draw_rect(Rect2(0, 0, 3, size.y), UiTheme.CHALK_BRIGHT, true)
		LabDraw.item_icon(self, Rect2(20, 20, 48, 48), item_id, layer, UiTheme.CHALK)
		if is_new:
			draw_rect(Rect2(size.x - 18, 8, 8, 8), UiTheme.AMBER, true)
		if qty > 1:
			var b := Rect2(56, 4, 26, 16)
			draw_rect(b, UiTheme.BOARD_SUNK, true)
			draw_rect(b, UiTheme.LINE, false, 1.0)
			draw_string(UiTheme.mono_font(), b.position + Vector2(0, 12), "×%d" % qty,
				HORIZONTAL_ALIGNMENT_CENTER, b.size.x, UiTheme.F_META, UiTheme.CHALK)
		draw_string(UiTheme.mono_font(), Vector2(8, size.y - 10), item_id,
			HORIZONTAL_ALIGNMENT_LEFT, size.x - 16, UiTheme.F_META, UiTheme.MUTED)

class MenuPanel extends Control:
	signal acted(action: String)
	var items: Array = []
	var item_id := ""

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			var mb := event as InputEventMouseButton
			var idx := int(floor(mb.position.y / LabRack.MENU_ITEM_H))
			if idx >= 0 and idx < items.size():
				acted.emit(str((items[idx] as Dictionary).get("id", "")))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BOARD_HIGH, true)
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.alpha(UiTheme.CHALK, 0.5), false, 1.0)
		for i in items.size():
			var y := i * LabRack.MENU_ITEM_H
			if i > 0:
				draw_line(Vector2(0, y), Vector2(size.x, y), UiTheme.LINE, 1.0)
			draw_string(UiTheme.cjk_font(), Vector2(14, y + 28),
				str((items[i] as Dictionary).get("label", "")),
				HORIZONTAL_ALIGNMENT_LEFT, size.x - 28, UiTheme.F_BODY, UiTheme.CHALK_BRIGHT)

class DetailView extends Control:
	signal acted(action: String)
	var item_id := ""
	var qty := 0
	var can_code := false
	var _buttons: Array = []

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _button_rect(i: int) -> Rect2:
		return Rect2(14, 420 + i * 52, 278, 44)

	func _gui_input(event: InputEvent) -> void:
		if not (event is InputEventMouseButton) or not (event as InputEventMouseButton).pressed \
				or (event as InputEventMouseButton).button_index != MOUSE_BUTTON_LEFT:
			return
		if item_id.is_empty():
			return
		var p := (event as InputEventMouseButton).position
		var ids := _action_ids()
		for i in ids.size():
			if _button_rect(i).has_point(p):
				acted.emit(str(ids[i]))
				return

	func _action_ids() -> Array:
		if item_id.is_empty():
			return []
		var out := []
		if LabRack.is_module(item_id):
			out.append("load")
		if can_code:
			out.append("code")
		out.append("recipe")
		return out

	func _draw() -> void:
		var f := UiTheme.cjk_font()
		if item_id.is_empty():
			LabDraw.dash_rect(self, Rect2(61, 120, 184, 184), UiTheme.alpha(UiTheme.MUTED, 0.35))
			return
		var layer := str(DataDB.catalog.item(item_id).get("layer", "L0"))
		draw_rect(Rect2(105, 24, 96, 96), UiTheme.alpha(UiTheme.CHALK, 0.06), true)
		LabDraw.item_icon(self, Rect2(125, 44, 56, 56), item_id, layer, UiTheme.CHALK)
		draw_string(f, Vector2(14, 160), str(DataDB.catalog.item_name(item_id)),
			HORIZONTAL_ALIGNMENT_LEFT, 278, UiTheme.F_H3, UiTheme.CHALK_BRIGHT)
		draw_string(UiTheme.mono_font(), Vector2(14, 192), "×%d" % qty,
			HORIZONTAL_ALIGNMENT_LEFT, 278, UiTheme.F_META, UiTheme.MUTED)
		draw_string(f, Vector2(14, 232), str(DataDB.catalog.item_desc(item_id)),
			HORIZONTAL_ALIGNMENT_LEFT, 278, UiTheme.F_META, UiTheme.MUTED)
		var ids := _action_ids()
		for i in ids.size():
			var b := _button_rect(i)
			draw_rect(b, UiTheme.BOARD_SUNK, true)
			draw_rect(b, UiTheme.alpha(UiTheme.CHALK, 0.45), false, 1.0)
			var label := "装入原型台" if str(ids[i]) == "load" else ("编写代码" if str(ids[i]) == "code" else "查看配方")
			draw_string(f, b.position + Vector2(0, 28), label,
				HORIZONTAL_ALIGNMENT_CENTER, b.size.x, UiTheme.F_BODY, UiTheme.CHALK)
