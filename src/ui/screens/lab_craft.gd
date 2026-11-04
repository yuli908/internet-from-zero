class_name LabCraft
extends Control

## 实验室·制作台（二级）：分类带 + 抽屉列表 + 检查器。
## 分类与前置筛选：左带 6 段按层切换；行内三态用色条/底色/叉号/斜线编码，不写状态句。
## 合成一律走 Economy.craft / Economy.buy，价格只从数据读，不写字面量。

const W_BAND := 236.0
const W_LIST := 724.0
const W_INSP := 236.0
const H_CONTENT := 612.0
const GUTTER := 18.0

const Z_BAND := Rect2(0, 0, W_BAND, H_CONTENT)
const Z_LIST := Rect2(W_BAND + GUTTER, 0, W_LIST, H_CONTENT)
const Z_INSP := Rect2(W_BAND + GUTTER + W_LIST + GUTTER, 0, W_INSP, H_CONTENT)

const CAT_H := 96.0
const CAT_GAP := 6.0
const CAT_COUNT := 6

const HEADER_H := 56.0
const DRAWER_GAP := 8.0
const DRAWER_H := 520.0
const ROW_W := 690.0
const ROW_H := 56.0
const ROW_GAP := 8.0
const ROW_X := 12.0
const ROW_Y := 12.0
const ROW_COUNT := 8

## 分类顺序与物品层一一对应；M 在前，P 在后。
const CATS := [
	{"key": "M", "layer": "L0", "name": "元件"},
	{"key": "G", "layer": "L1", "name": "门电路"},
	{"key": "S", "layer": "L2", "name": "开关"},
	{"key": "H", "layer": "L3", "name": "传感"},
	{"key": "W", "layer": "L4", "name": "模块"},
	{"key": "P", "layer": "L5", "name": "载板"},
]

var _lab: Control
var _cat := "M"
var _open := true
var _selected: Dictionary = {}
var _rows_box: Control
var _list_head: Control
var _insp: Control
var _segments: Array = []

## ---------- 几何唯一来源 ----------

static func zone_rects() -> Dictionary:
	return {"band": Z_BAND, "list": Z_LIST, "inspector": Z_INSP}

static func category_keys() -> Array:
	var out := []
	for c in CATS:
		out.append(str(c["key"]))
	return out

static func cat_rect(i: int) -> Rect2:
	return Rect2(0, i * (CAT_H + CAT_GAP), W_BAND, CAT_H)

static func drawer_header_rect() -> Rect2:
	return Rect2(0, 0, W_LIST, HEADER_H)

static func drawer_body_rect() -> Rect2:
	return Rect2(0, HEADER_H + DRAWER_GAP, W_LIST, DRAWER_H)

static func row_rect(i: int) -> Rect2:
	return Rect2(ROW_X, ROW_Y + i * (ROW_H + ROW_GAP), ROW_W, ROW_H)

static func inspector_button_rect() -> Rect2:
	return Rect2(14, 548, 208, 44)

static func category_for(layer: String) -> String:
	for c in CATS:
		if str(c["layer"]) == layer:
			return str(c["key"])
	return "M"

## ---------- 数据 ----------

## 全量可做行：M00 散件包只走购买，其余走配方；旧版隐藏件不进列表。
static func all_rows() -> Array:
	var cat: Catalog = DataDB.catalog
	var out := []
	if cat.has_item("M00"):
		out.append({"kind": "buy", "id": "M00", "rid": "", "layer": "L0", "name": cat.item_name("M00")})
	for raw_rid in cat.recipe_ids():
		var rid := str(raw_rid)
		var rec: Dictionary = cat.recipe(rid)
		var oid := str(rec.get("output", ""))
		if oid.is_empty() or not cat.has_item(oid):
			continue
		if bool(cat.item(oid).get("hidden", false)):
			continue
		out.append({
			"kind": "craft", "id": oid, "rid": rid,
			"layer": str(cat.item(oid).get("layer", "L0")), "name": cat.item_name(oid),
		})
	return out

static func rows_for(category: String, catalog: Catalog = null) -> Array:
	var cat: Catalog = catalog if catalog != null else DataDB.catalog
	var out := []
	for raw in all_rows():
		var row: Dictionary = raw
		if category_for(str(row.get("layer", ""))) == category and cat.has_item(str(row.get("id", ""))):
			out.append(row)
	return out

static func recipe_ready(row: Dictionary) -> Dictionary:
	if str(row.get("kind", "")) != "craft":
		return {"ok": false, "missing": []}
	return Economy.can_craft(str(row.get("rid", "")))

static func is_locked(row: Dictionary) -> bool:
	if str(row.get("kind", "")) != "craft":
		return false
	var rec: Dictionary = DataDB.catalog.recipe(str(row.get("rid", "")))
	var raw: Variant = rec.get("requires_skill", rec.get("unlock_skill", ""))
	var skill := "" if raw == null else str(raw)
	if skill.is_empty():
		return false
	var p = GameState.player
	return p == null or not p.has_knowledge(skill)

static func state_of(row: Dictionary) -> String:
	if is_locked(row):
		return "locked"
	if str(row.get("kind", "")) == "buy":
		var p = GameState.player
		return "ok" if p != null and int(p.gold) >= Economy.price_of(str(row.get("id", ""))) else "short"
	return "ok" if bool(recipe_ready(row).get("ok", false)) else "short"

## 行角标：当前还能做/买几次；用数据算，不写死。
static func max_times(row: Dictionary) -> int:
	var p = GameState.player
	if p == null:
		return 0
	if str(row.get("kind", "")) == "buy":
		var price := Economy.price_of(str(row.get("id", "")))
		return 0 if price <= 0 else int(p.gold) / price
	var rec: Dictionary = DataDB.catalog.recipe(str(row.get("rid", "")))
	if is_locked(row):
		return 0
	var times := 999
	var inputs: Dictionary = rec.get("inputs", {})
	for k in inputs.keys():
		var need := int(inputs[k])
		if need <= 0:
			continue
		times = mini(times, p.item_count(str(k)) / need)
	var cash := EconomyCore.craft_cash(rec, 1)
	if cash > 0:
		times = mini(times, int(p.gold) / cash)
	return maxi(0, mini(times, 99))

## ---------- 构建 ----------

func build(lab_ref: Control) -> void:
	_lab = lab_ref
	size = Vector2(1232, 612)
	_add_zone(Z_BAND, UiTheme.AMBER)
	_add_zone(Z_LIST, UiTheme.CYAN)
	_add_zone(Z_INSP, UiTheme.RUST)
	_build_categories()
	_build_list()
	_build_inspector()
	_select_category("M")

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

func _build_categories() -> void:
	for i in CATS.size():
		var seg := CatSeg.new()
		seg.key = str(CATS[i]["key"])
		seg.layer = str(CATS[i]["layer"])
		seg.label = str(CATS[i]["name"])
		seg.position = cat_rect(i).position
		seg.size = cat_rect(i).size
		seg.picked.connect(_select_category)
		add_child(seg)
		_segments.append(seg)

func _build_list() -> void:
	var head := DrawerHead.new()
	head.position = Z_LIST.position + drawer_header_rect().position
	head.size = drawer_header_rect().size
	head.toggled.connect(_toggle_open)
	_list_head = head
	add_child(head)
	_rows_box = Control.new()
	_rows_box.position = Z_LIST.position + drawer_body_rect().position
	_rows_box.size = drawer_body_rect().size
	_rows_box.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_rows_box)

func _build_inspector() -> void:
	_insp = Control.new()
	_insp.position = Z_INSP.position
	_insp.size = Z_INSP.size
	_insp.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_insp)

func _select_category(key: String) -> void:
	_cat = key
	_open = true
	for seg in _segments:
		(seg as CatSeg).active = (seg as CatSeg).key == _cat
		(seg as CatSeg).queue_redraw()
	_list_head.title = _title_for(_cat)
	_list_head.queue_redraw()
	if not _selected.is_empty() and category_for(str(_selected.get("layer", ""))) != _cat:
		_selected = {}
	var rows := rows_for(_cat)
	if _selected.is_empty() and not rows.is_empty():
		_selected = rows[0]
	_rebuild_rows()
	_rebuild_inspector()

func _title_for(key: String) -> String:
	for c in CATS:
		if str(c["key"]) == key:
			return "%s · %s" % [key, str(c["name"])]
	return key

func _toggle_open() -> void:
	_open = not _open
	_rows_box.visible = _open
	_list_head.opened = _open
	_list_head.queue_redraw()

func _rebuild_rows() -> void:
	for c in _rows_box.get_children():
		_rows_box.remove_child(c)
		c.queue_free()
	var rows := rows_for(_cat)
	var n := mini(rows.size(), ROW_COUNT)
	for i in n:
		var row: Dictionary = rows[i]
		var rr := CraftRow.new()
		rr.row = row
		rr.position = row_rect(i).position
		rr.size = row_rect(i).size
		rr.active = _selected.get("rid", "") == str(row.get("rid", "")) and _selected.get("id", "") == str(row.get("id", ""))
		rr.acted.connect(_on_row)
		rr.picked.connect(_on_row_pick)
		_rows_box.add_child(rr)

func _on_row_pick(row: Dictionary) -> void:
	_selected = row
	_rebuild_rows()
	_rebuild_inspector()

func _on_row(row: Dictionary) -> void:
	var st := state_of(row)
	if st == "locked":
		if _lab != null:
			_lab.call("open_skills")
		return
	if st != "ok":
		return
	_selected = row
	if str(row.get("kind", "")) == "buy":
		Economy.buy(str(row.get("id", "")), 1)
	else:
		Economy.craft(str(row.get("rid", "")), 1)
	refresh()

func _rebuild_inspector() -> void:
	for c in _insp.get_children():
		_insp.remove_child(c)
		c.queue_free()
	var view := InspectView.new()
	view.row = _selected
	view.position = Vector2.ZERO
	view.size = Z_INSP.size
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	view.acted.connect(_on_inspector_action)
	_insp.add_child(view)

func _on_inspector_action() -> void:
	if _selected.is_empty():
		return
	_on_row(_selected)

func refresh() -> void:
	for raw in all_rows():
		var row: Dictionary = raw
		if str(row.get("rid", "")) == str(_selected.get("rid", "")) and str(row.get("id", "")) == str(_selected.get("id", "")):
			_selected = row
			break
	_rebuild_rows()
	_rebuild_inspector()

## 从模块架「查看配方」进入时，直接定到对应分类与行。
func focus_item(item_id: String) -> void:
	var layer := str(DataDB.catalog.item(item_id).get("layer", "L0"))
	_select_category(category_for(layer))
	for raw in all_rows():
		var row: Dictionary = raw
		if str(row.get("id", "")) == item_id:
			_selected = row
			break
	_rebuild_rows()
	_rebuild_inspector()

## ---------- 子控件 ----------

class CatSeg extends Control:
	signal picked(key: String)
	var key := ""
	var layer := ""
	var label := ""
	var active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			picked.emit(key)

	func _draw() -> void:
		var bg := UiTheme.alpha(UiTheme.CHALK, 0.08) if active else UiTheme.PANEL_2
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.alpha(UiTheme.CHALK, 0.42) if active else UiTheme.LINE, false, 1.0)
		if active:
			draw_rect(Rect2(0, 0, 4, size.y), UiTheme.CHALK_BRIGHT, true)
		var f := UiTheme.cjk_font()
		draw_string(f, Vector2(18, 34), key, HORIZONTAL_ALIGNMENT_LEFT, 40, UiTheme.F_H3, UiTheme.CHALK_BRIGHT)
		draw_string(f, Vector2(18, 62), label, HORIZONTAL_ALIGNMENT_LEFT, 190, UiTheme.F_BODY, UiTheme.CHALK if active else UiTheme.MUTED)
		var count := LabCraft.rows_for(key).size()
		draw_string(UiTheme.mono_font(), Vector2(size.x - 56, 34), str(count),
			HORIZONTAL_ALIGNMENT_RIGHT, 40, UiTheme.F_META, UiTheme.MUTED)

class DrawerHead extends Control:
	signal toggled
	var title := ""
	var opened := true

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			toggled.emit()

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.BOARD_SUNK, true)
		draw_rect(Rect2(0, size.y - 1, size.x, 1), UiTheme.LINE, true)
		var f := UiTheme.cjk_font()
		draw_string(f, Vector2(16, 36), title, HORIZONTAL_ALIGNMENT_LEFT, 260, UiTheme.F_H3, UiTheme.CHALK_BRIGHT)
		# 展开/收起只画三角，不写 verb。
		var cx := size.x - 26.0
		var cy := size.y * 0.5
		var dir := 1.0 if opened else -1.0
		var pts := PackedVector2Array([
			Vector2(cx - 7, cy - 4 * dir), Vector2(cx + 7, cy - 4 * dir), Vector2(cx, cy + 5 * dir),
		])
		draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), UiTheme.CHALK, 1.6)

class CraftRow extends Control:
	signal acted(row: Dictionary)
	signal picked(row: Dictionary)
	var row: Dictionary = {}
	var active := false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if Rect2(size.x - 108, 10, 84, 36).has_point((event as InputEventMouseButton).position):
				acted.emit(row)
			else:
				picked.emit(row)

	func _draw() -> void:
		var st := _state()
		var bg := UiTheme.alpha(UiTheme.CHALK, 0.08) if st == "ok" else UiTheme.alpha(UiTheme.CHALK, 0.02)
		draw_rect(Rect2(Vector2.ZERO, size), bg, true)
		if st == "locked":
			LabDraw.hatch(self, Rect2(Vector2.ZERO, size), UiTheme.alpha(UiTheme.GRAYBLUE, 0.16), 12.0)
		draw_rect(Rect2(Vector2.ZERO, size), UiTheme.alpha(UiTheme.CHALK, 0.32) if active else UiTheme.LINE, false, 1.0)
		var bar := UiTheme.alpha(UiTheme.CHALK, 0.90) if st == "ok" else (UiTheme.alpha(UiTheme.CHALK, 0.20) if st == "short" else UiTheme.alpha(UiTheme.GRAYBLUE, 0.35))
		draw_rect(Rect2(0, 0, 3, size.y), bar, true)
		var f := UiTheme.cjk_font()
		var name_color := UiTheme.CHALK_BRIGHT if st == "ok" else (UiTheme.CHALK if st == "short" else Color("#9AA9A0"))
		draw_string(f, Vector2(14, 34), str(row.get("name", "")), HORIZONTAL_ALIGNMENT_LEFT, 186, UiTheme.F_LABEL, name_color)
		_draw_materials()
		_draw_meta()
		if st != "locked":
			var times := LabCraft.max_times(row)
			var badge := Rect2(size.x - 202, 10, 34, 20)
			draw_rect(badge, UiTheme.alpha(UiTheme.CHALK, 0.06), true)
			draw_rect(badge, UiTheme.LINE, false, 1.0)
			draw_string(UiTheme.mono_font(), badge.position + Vector2(0, 15), str(times),
				HORIZONTAL_ALIGNMENT_CENTER, badge.size.x, UiTheme.F_META, UiTheme.MUTED)
		_draw_button(st)

	func _state() -> String:
		return LabCraft.state_of(row)

	func _draw_materials() -> void:
		var rec: Dictionary = DataDB.catalog.recipe(str(row.get("rid", "")))
		var inputs: Dictionary = rec.get("inputs", {})
		var keys: Array = inputs.keys()
		var p = GameState.player
		var x := 200.0
		for i in mini(keys.size(), 4):
			var iid := str(keys[i])
			var need := int(inputs[iid])
			var have := 0 if p == null else p.item_count(iid)
			var ir := Rect2(x, 19, 18, 18)
			LabDraw.item_icon(self, ir, iid, str(DataDB.catalog.item(iid).get("layer", "L0")), UiTheme.CHALK)
			var col := UiTheme.MUTED
			if have < need:
				LabDraw.cross(self, Vector2(ir.end.x - 1, ir.position.y + 1), UiTheme.DANGER, 6.0)
				col = UiTheme.DANGER
			draw_string(UiTheme.mono_font(), Vector2(x + 21, 33), "%d/%d" % [have, need],
				HORIZONTAL_ALIGNMENT_LEFT, 30, UiTheme.F_META, col)
			x += 50.0

	func _draw_meta() -> void:
		var rec: Dictionary = DataDB.catalog.recipe(str(row.get("rid", "")))
		var parts := []
		if str(row.get("kind", "")) == "buy":
			var price := Economy.price_of(str(row.get("id", "")))
			if price > 0:
				parts.append("%dg" % price)
		else:
			parts.append("%dg" % EconomyCore.craft_cash(rec, 1))
			parts.append("%dop" % int(rec.get("ops", 0)))
		draw_string(UiTheme.mono_font(), Vector2(404, 33), " ".join(parts),
			HORIZONTAL_ALIGNMENT_LEFT, 78, UiTheme.F_META, UiTheme.MUTED)

	func _draw_button(st: String) -> void:
		var b := Rect2(size.x - 108, 10, 84, 36)
		var enabled := st == "ok"
		var bg := UiTheme.CHALK if enabled else UiTheme.BOARD_SUNK
		draw_rect(b, bg, true)
		draw_rect(b, UiTheme.alpha(UiTheme.CHALK, 0.5) if enabled else UiTheme.LINE, false, 1.0)
		var label := "购买" if str(row.get("kind", "")) == "buy" else "制作"
		if st == "locked":
			label = ""
			var token := _skill_token()
			LabDraw.prereq_node(self, Rect2(b.position, Vector2(34, 18)), token, UiTheme.GRAYBLUE)
		draw_string(UiTheme.cjk_font(), b.position + Vector2(0, 24), label,
			HORIZONTAL_ALIGNMENT_CENTER, b.size.x, UiTheme.F_BODY, UiTheme.INK if enabled else UiTheme.MUTED)

	func _skill_token() -> String:
		var rec: Dictionary = DataDB.catalog.recipe(str(row.get("rid", "")))
		var raw: Variant = rec.get("requires_skill", rec.get("unlock_skill", ""))
		return "" if raw == null else str(raw).substr(0, 3).to_upper()

class InspectView extends Control:
	signal acted
	var row: Dictionary = {}

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_STOP

	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
				and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			if LabCraft.inspector_button_rect().has_point((event as InputEventMouseButton).position):
				acted.emit()

	func _draw() -> void:
		var f := UiTheme.cjk_font()
		if row.is_empty():
			LabDraw.dash_rect(self, Rect2(26, 150, 184, 184), UiTheme.alpha(UiTheme.MUTED, 0.35))
			return
		var iid := str(row.get("id", ""))
		var layer := str(row.get("layer", "L0"))
		var icon := Rect2(86, 16, 64, 64)
		draw_rect(icon, UiTheme.alpha(UiTheme.CHALK, 0.06), true)
		LabDraw.item_icon(self, Rect2(98, 28, 40, 40), iid, layer, UiTheme.CHALK)
		draw_string(f, Vector2(14, 116), str(row.get("name", "")),
			HORIZONTAL_ALIGNMENT_LEFT, 208, UiTheme.F_H3, UiTheme.CHALK_BRIGHT)
		var rec: Dictionary = DataDB.catalog.recipe(str(row.get("rid", "")))
		draw_string(UiTheme.mono_font(), Vector2(14, 140), iid,
			HORIZONTAL_ALIGNMENT_LEFT, 208, UiTheme.F_META, UiTheme.MUTED)
		var inputs: Dictionary = rec.get("inputs", {})
		var p = GameState.player
		var y := 170.0
		var keys: Array = inputs.keys()
		for i in mini(keys.size(), 6):
			var mid := str(keys[i])
			var need := int(inputs[mid])
			var have := 0 if p == null else p.item_count(mid)
			LabDraw.item_icon(self, Rect2(14, y - 14, 18, 18), mid,
				str(DataDB.catalog.item(mid).get("layer", "L0")), UiTheme.CHALK)
			draw_string(UiTheme.mono_font(), Vector2(38, y), "%s  %d/%d" % [mid, have, need],
				HORIZONTAL_ALIGNMENT_LEFT, 170, UiTheme.F_META, UiTheme.DANGER if have < need else UiTheme.MUTED)
			y += 30.0
		if str(row.get("kind", "")) != "buy":
			var cash := EconomyCore.craft_cash(rec, 1)
			var ops := int(rec.get("ops", 0))
			draw_string(UiTheme.mono_font(), Vector2(14, 282), "cash %d" % cash,
				HORIZONTAL_ALIGNMENT_LEFT, 208, UiTheme.F_META, UiTheme.CHALK)
			draw_string(UiTheme.mono_font(), Vector2(14, 306), "ops  %d" % ops,
				HORIZONTAL_ALIGNMENT_LEFT, 208, UiTheme.F_META, UiTheme.CHALK)
		var b := LabCraft.inspector_button_rect()
		var st := LabCraft.state_of(row)
		var enabled := st == "ok"
		draw_rect(b, UiTheme.CHALK if enabled else UiTheme.BOARD_SUNK, true)
		draw_rect(b, UiTheme.alpha(UiTheme.CHALK, 0.5) if enabled else UiTheme.LINE, false, 1.0)
		var label := "购买" if str(row.get("kind", "")) == "buy" else "制作"
		draw_string(f, b.position + Vector2(0, 28), label,
			HORIZONTAL_ALIGNMENT_CENTER, b.size.x, UiTheme.F_BODY, UiTheme.INK if enabled else UiTheme.MUTED)
