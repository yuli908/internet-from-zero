extends GameScreen

## 商店页：左售出区（双抽屉）+ 右背包列表。全部代码构建、绝对定位，无 .tscn。
## 本屏 local (0,0) 对应绝对 (24,92)，两栏均以 local y=612 为底边。

## 抽屉头的三角指示：收起朝下、展开朝上，颜色是 chalk 白。
class ArrowGlyph extends Control:
	var open := false
	var tint := Color("#E8E4D6")

	func _draw() -> void:
		var w := size.x
		var h := size.y
		var pts: PackedVector2Array
		if open:
			pts = PackedVector2Array([
				Vector2(w * 0.50, h * 0.30),
				Vector2(w * 0.20, h * 0.68),
				Vector2(w * 0.80, h * 0.68),
			])
		else:
			pts = PackedVector2Array([
				Vector2(w * 0.20, h * 0.32),
				Vector2(w * 0.80, h * 0.32),
				Vector2(w * 0.50, h * 0.68),
			])
		draw_colored_polygon(pts, tint)

## BOUND 行的 45° 斜纹：线宽 2 px、间隔 8 px。
class StripeField extends Control:
	var stripe := Color(1.0, 1.0, 1.0, 0.12)

	func _draw() -> void:
		var step := 8.0
		var width := 2.0
		var h := size.y
		var x := -h
		while x < size.x:
			draw_line(Vector2(x, h), Vector2(x + h, 0.0), stripe, width)
			x += step

# ---------- 几何常量（1280×720 逻辑像素，local 坐标） ----------
const W_TOTAL := 1232.0
const W_SELL := 730.0
const GUTTER := 18.0
const W_BAG := 484.0
const H_CONTENT := 612.0

const HEADER_Y := -62.0
const HEADER_H := 44.0

const DRAWER_HEAD_H := 56.0
const DRAWER_OPEN_H := 520.0
const DRAWER2_Y_COLLAPSED := 64.0
const DRAWER2_Y_UNDER_OPEN1 := 528.0

const MENU_X := 20.0
const MENU_Y := 64.0
const MENU_W := 690.0
const MENU_H := 448.0

const ROW_W := 690.0
const ROW_H := 56.0
const ROW_GAP := 8.0
const LAYER_HEAD_H := 28.0

const BAG_HEAD_H := 40.0
const BAG_LIST_Y := 48.0
const BAG_LIST_H := 564.0
const BAG_ROW_W := 484.0
const BAG_ROW_H := 56.0

const ANIM_OPEN := 0.200
const ANIM_CLOSE := 0.140
const ANIM_HOVER := 0.090

# ---------- 色值 ----------
const C_READY_BG := Color("#1A342D")
const C_POOR_BG := Color("#12261F")
const C_OWNED_BG := Color("#16302A")
const C_CHALK := Color("#E8E4D6")
const C_BRIGHT := Color("#FFFDF5")
const C_GOLD := Color("#D8A24A")
const C_RUST := Color("#B8452F")
const C_MUTED := Color("#7F9189")
const C_GRAYBLUE := Color("#8FA3B8")
const C_BOUND_NAME := Color("#9AA9A0")
const C_HEAD_BG := Color("#1A342D")
const C_BAG_ROW_BG := Color("#16302A")

const LAYER_ORDER := ["L0", "L1", "L2", "L3", "L4", "L5", "CUR"]
const LAYER_COLORS := {
	"L0": Color("#E8E4D6"),
	"L1": Color("#D8A24A"),
	"L2": Color("#7FC7CF"),
	"L3": Color("#8FA3B8"),
	"L4": Color("#B9A8D8"),
	"L5": Color("#A8C28B"),
}

var _page: Control
var _gold_value: Label
var _discount_value: Label

var _drawers: Array[Control] = []
var _views: Array[ScrollContainer] = []
var _boxes: Array[VBoxContainer] = []
var _arrows: Array[ArrowGlyph] = []
var _counts: Array[Label] = []
var _active_tweens: Dictionary = {}
var _open_drawer := -1

var _bag_total: Label
var _bag_scroll: ScrollContainer
var _bag_box: VBoxContainer

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func on_show() -> void:
	var items_pos := 0
	var recipes_pos := 0
	var bag_pos := 0
	if _views.size() == 2:
		items_pos = _views[0].scroll_vertical
		recipes_pos = _views[1].scroll_vertical
	if _bag_scroll != null:
		bag_pos = _bag_scroll.scroll_vertical
	_refresh_header()
	_rebuild_items()
	_rebuild_recipes()
	_rebuild_bag()
	_sync_drawers()
	call_deferred("_restore_scrolls", items_pos, recipes_pos, bag_pos)

func _build() -> void:
	_page = Control.new()
	_page.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_page)
	_build_header()
	_build_sell()
	_build_bag()
	_sync_drawers()

# ---------------------------------------------------------------- 抬头

func _build_header() -> void:
	var header := Control.new()
	header.position = Vector2(0.0, HEADER_Y)
	header.size = Vector2(W_TOTAL, HEADER_H)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_page.add_child(header)

	var discount := Ui.mono("−0%", UiTheme.F_BODY, UiTheme.CYAN)
	discount.position = Vector2(1136.0, 0.0)
	discount.size = Vector2(80.0, HEADER_H)
	discount.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	discount.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	discount.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(discount)
	_discount_value = discount

	var gold := Ui.mono("0", UiTheme.F_BODY, C_GOLD)
	gold.position = Vector2(1024.0, 0.0)
	gold.size = Vector2(100.0, HEADER_H)
	gold.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	gold.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(gold)
	_gold_value = gold

	var caption := Ui.label("金币", UiTheme.F_META, C_MUTED)
	caption.position = Vector2(960.0, 0.0)
	caption.size = Vector2(56.0, HEADER_H)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(caption)

func _refresh_header() -> void:
	var gold := 0
	if GameState.player != null:
		gold = int(GameState.player.gold)
	_gold_value.text = str(gold)
	var pct := 0
	if GameState.player != null:
		pct = roundi(Economy.discount() * 100.0)
	_discount_value.text = "−%d%%" % pct

# ---------------------------------------------------------------- 左售出区

func _build_sell() -> void:
	var col := Control.new()
	col.position = Vector2.ZERO
	col.size = Vector2(W_SELL, H_CONTENT)
	col.clip_contents = true
	col.mouse_filter = Control.MOUSE_FILTER_PASS
	_page.add_child(col)
	_build_drawer(0, col, "元件", "项")
	_build_drawer(1, col, "合成配方", "条")

func _build_drawer(idx: int, parent: Control, title_text: String, unit_text: String) -> void:
	var drawer := Panel.new()
	drawer.add_theme_stylebox_override("panel", UiTheme.flat_tight(C_POOR_BG, UiTheme.LINE, 1))
	drawer.position = Vector2(0.0, DRAWER2_Y_COLLAPSED if idx == 1 else 0.0)
	drawer.size = Vector2(W_SELL, DRAWER_HEAD_H)
	drawer.clip_contents = true
	drawer.mouse_filter = Control.MOUSE_FILTER_PASS
	parent.add_child(drawer)
	_drawers.append(drawer)

	var head := Panel.new()
	head.position = Vector2.ZERO
	head.size = Vector2(W_SELL, DRAWER_HEAD_H)
	head.mouse_filter = Control.MOUSE_FILTER_STOP
	head.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	head.add_theme_stylebox_override("panel", UiTheme.flat_tight(C_HEAD_BG, UiTheme.LINE, 1))
	head.gui_input.connect(_on_head_gui_input.bind(idx))
	drawer.add_child(head)

	var title := Ui.label(title_text, UiTheme.F_BODY, C_BRIGHT)
	title.position = Vector2(18.0, 12.0)
	title.size = Vector2(260.0, 32.0)
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(title)

	var arrow := ArrowGlyph.new()
	arrow.position = Vector2(586.0, 16.0)
	arrow.size = Vector2(24.0, 24.0)
	arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(arrow)
	_arrows.append(arrow)

	var count := Ui.label("0 %s" % unit_text, UiTheme.F_META, C_MUTED)
	count.position = Vector2(618.0, 0.0)
	count.size = Vector2(94.0, DRAWER_HEAD_H)
	count.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	count.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	count.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(count)
	_counts.append(count)

	var view := ScrollContainer.new()
	view.position = Vector2(MENU_X, MENU_Y)
	view.size = Vector2(MENU_W, MENU_H)
	view.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	view.visible = false
	drawer.add_child(view)
	_views.append(view)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", int(ROW_GAP))
	box.custom_minimum_size = Vector2(ROW_W, 0.0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	view.add_child(box)
	_boxes.append(box)

func _on_head_gui_input(event: InputEvent, idx: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
		return
	_toggle_drawer(idx)

func _toggle_drawer(idx: int) -> void:
	var prev := _open_drawer
	if prev == idx:
		_open_drawer = -1
		_apply_drawer_positions()
		_collapse(idx)
	else:
		_open_drawer = idx
		_apply_drawer_positions()
		if prev >= 0:
			_collapse(prev)
		_expand(idx)
	for i in 2:
		_arrows[i].open = _open_drawer == i
		_arrows[i].queue_redraw()

func _apply_drawer_positions() -> void:
	_drawers[0].position = Vector2(0.0, 0.0)
	var y2 := DRAWER2_Y_UNDER_OPEN1 if _open_drawer == 0 else DRAWER2_Y_COLLAPSED
	_drawers[1].position = Vector2(0.0, y2)

func _sync_drawers() -> void:
	for i in 2:
		_kill_tween(i)
		var h := DRAWER_OPEN_H if _open_drawer == i else DRAWER_HEAD_H
		_drawers[i].size = Vector2(W_SELL, h)
		_views[i].visible = _open_drawer == i
		_arrows[i].open = _open_drawer == i
		_arrows[i].queue_redraw()
	_apply_drawer_positions()

func _expand(idx: int) -> void:
	_kill_tween(idx)
	var drawer: Control = _drawers[idx]
	var view := _views[idx]
	if not UiTheme.motion:
		view.visible = true
		drawer.size = Vector2(W_SELL, DRAWER_OPEN_H)
		return
	view.visible = false
	var tw := create_tween()
	tw.tween_property(drawer, "size:y", DRAWER_OPEN_H, ANIM_OPEN).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_callback(func(): view.visible = true)
	_active_tweens[idx] = tw

func _collapse(idx: int) -> void:
	_kill_tween(idx)
	var drawer: Control = _drawers[idx]
	var view := _views[idx]
	view.visible = false
	if not UiTheme.motion:
		drawer.size = Vector2(W_SELL, DRAWER_HEAD_H)
		return
	var tw := create_tween()
	tw.tween_property(drawer, "size:y", DRAWER_HEAD_H, ANIM_CLOSE).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_active_tweens[idx] = tw

func _kill_tween(idx: int) -> void:
	if not _active_tweens.has(idx):
		return
	var tw := _active_tweens[idx] as Tween
	if tw != null:
		tw.kill()
	_active_tweens.erase(idx)

func _restore_scrolls(items_pos: int, recipes_pos: int, bag_pos: int) -> void:
	if _views.size() == 2:
		_views[0].scroll_vertical = items_pos
		_views[1].scroll_vertical = recipes_pos
	if _bag_scroll != null:
		_bag_scroll.scroll_vertical = bag_pos

# ---------------------------------------------------------------- 左：元件菜单

func _rebuild_items() -> void:
	var box: VBoxContainer = _boxes[0]
	_clear_children(box)
	var total := 0
	if DataDB.catalog != null:
		var cat: Catalog = DataDB.catalog
		var groups: Dictionary = {}
		for raw in cat.item_ids_for_sale():
			var iid := str(raw)
			var item: Dictionary = cat.item(iid)
			if item.is_empty():
				continue
			if bool(item.get("legacy", false)):
				continue
			if iid == str(cat.currency):
				continue
			var layer := str(item.get("layer", ""))
			if not groups.has(layer):
				groups[layer] = []
			(groups[layer] as Array).append(iid)
		for layer in _ordered_layers(groups.keys()):
			var ids: Array = groups[layer]
			ids.sort()
			box.add_child(_layer_head(str(layer), ids.size()))
			for raw_id in ids:
				box.add_child(_item_row(str(raw_id)))
				total += 1
	_counts[0].text = "%d 项" % total

func _ordered_layers(keys: Array) -> Array:
	var out: Array = []
	for k in LAYER_ORDER:
		if keys.has(k):
			out.append(k)
	var rest: Array = []
	for k in keys:
		if not out.has(k):
			rest.append(str(k))
	rest.sort()
	out.append_array(rest)
	return out

func _layer_head(layer: String, n: int) -> Control:
	var head := Control.new()
	head.custom_minimum_size = Vector2(ROW_W, LAYER_HEAD_H)
	head.size = Vector2(ROW_W, LAYER_HEAD_H)
	head.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var text := Ui.label("%s · %d 项" % [layer, n], UiTheme.F_META, C_MUTED)
	text.position = Vector2(14.0, 2.0)
	text.size = Vector2(400.0, 24.0)
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(text)

	var line := ColorRect.new()
	line.color = UiTheme.LINE
	line.position = Vector2(0.0, LAYER_HEAD_H - 1.0)
	line.size = Vector2(ROW_W, 1.0)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(line)
	return head

func _item_row(iid: String) -> Control:
	var cat: Catalog = DataDB.catalog
	var item: Dictionary = cat.item(iid)
	var price: int = Economy.price_of(iid)
	var have := 0
	var gold := 0
	if GameState.player != null:
		have = GameState.player.item_count(iid)
		gold = int(GameState.player.gold)
	var state := _item_state(item, have, price, gold)

	var row := _new_row(ROW_W, ROW_H)
	_row_bg(row, _state_bg(state), ROW_W, ROW_H)
	if state == "BOUND":
		var stripes := StripeField.new()
		stripes.position = Vector2.ZERO
		stripes.size = Vector2(ROW_W, ROW_H)
		stripes.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(stripes)
		row.tooltip_text = "教学件 · 首件绑定，不可交易"
	_color_rect(row, Vector2(0.0, 0.0), Vector2(3.0, ROW_H), _state_bar(state))

	var name_l := Ui.label(str(item.get("name", iid)), UiTheme.F_BODY, _state_name(state))
	name_l.position = Vector2(14.0, 6.0)
	name_l.size = Vector2(300.0, 22.0)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)

	var layer := str(item.get("layer", ""))
	var sub_text := iid if layer.is_empty() else "%s · %s" % [iid, layer]
	var sub_l := Ui.label(sub_text, UiTheme.F_META, C_MUTED)
	sub_l.position = Vector2(14.0, 30.0)
	sub_l.size = Vector2(200.0, 18.0)
	sub_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_l.clip_text = true
	sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sub_l)

	if state != "BOUND":
		var price_l := Ui.mono(str(maxi(price, 0)), UiTheme.F_BODY, _state_price(state))
		price_l.position = Vector2(310.0, 18.0)
		price_l.size = Vector2(90.0, 20.0)
		price_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		price_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		price_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(price_l)

	row.add_child(_stock_badge(state, have))

	if state == "BOUND":
		var row_lock := Ui.glyph("lock", C_GRAYBLUE, 24)
		row_lock.position = Vector2(640.0, 16.0)
		row.add_child(row_lock)

	if state != "BOUND":
		var buy_btn: Button
		if state == "OWNED":
			buy_btn = Ui.ghost("买", _on_buy.bind(iid))
		else:
			buy_btn = Ui.button("买", _on_buy.bind(iid), true)
		if state == "POOR":
			buy_btn.disabled = true
		_place_button(buy_btn, Vector2(470.0, 10.0), Vector2(84.0, 36.0), state != "OWNED")
		row.add_child(buy_btn)

	if state == "READY" or state == "POOR":
		var rid := str(cat.recipe_for_output(iid))
		var craft_btn := Ui.ghost("合成", _on_craft.bind(rid))
		_place_button(craft_btn, Vector2(562.0, 10.0), Vector2(84.0, 36.0), false)
		row.add_child(craft_btn)

	_attach_hover(row, ROW_W, ROW_H)
	return row

func _item_state(item: Dictionary, have: int, price: int, gold: int) -> String:
	if bool(item.get("bound_first", false)) and have > 0:
		return "BOUND"
	if have > 0:
		return "OWNED"
	if price < 0 or gold < price:
		return "POOR"
	return "READY"

func _state_bg(state: String) -> Color:
	match state:
		"READY":
			return C_READY_BG
		"OWNED":
			return C_OWNED_BG
		_:
			return C_POOR_BG

func _state_name(state: String) -> Color:
	match state:
		"POOR":
			return C_CHALK
		"BOUND":
			return C_BOUND_NAME
		_:
			return C_BRIGHT

func _state_bar(state: String) -> Color:
	match state:
		"POOR":
			return UiTheme.alpha(C_BRIGHT, 0.16)
		"OWNED":
			return UiTheme.alpha(C_BRIGHT, 0.90)
		"BOUND":
			return C_GRAYBLUE
		_:
			return C_CHALK

func _state_price(state: String) -> Color:
	match state:
		"POOR":
			return C_RUST
		"BOUND":
			return C_GRAYBLUE
		_:
			return C_GOLD

func _stock_badge(state: String, n: int) -> Panel:
	var bg := UiTheme.BOARD_SUNK
	var fg := C_MUTED
	var border := UiTheme.LINE
	if state == "OWNED":
		bg = C_BRIGHT
		fg = UiTheme.INK
		border = C_BRIGHT
	elif state == "BOUND":
		bg = UiTheme.alpha(C_GRAYBLUE, 0.30)
		fg = C_BRIGHT
		border = UiTheme.alpha(C_GRAYBLUE, 0.55)
	return _badge("×%d" % n, Vector2(412.0, 18.0), Vector2(34.0, 20.0), bg, fg, border)

# ---------------------------------------------------------------- 左：配方菜单

func _rebuild_recipes() -> void:
	var box: VBoxContainer = _boxes[1]
	_clear_children(box)
	var total := 0
	if DataDB.catalog != null:
		var cat: Catalog = DataDB.catalog
		for raw in cat.recipe_ids():
			var rid := str(raw)
			var r: Dictionary = cat.recipe(rid)
			if r.is_empty():
				continue
			box.add_child(_recipe_row(rid))
			total += 1
	_counts[1].text = "%d 条" % total

func _recipe_row(rid: String) -> Control:
	var r: Dictionary = DataDB.catalog.recipe(rid)
	var row := _new_row(ROW_W, ROW_H)
	_row_bg(row, C_READY_BG, ROW_W, ROW_H)
	_color_rect(row, Vector2(0.0, 0.0), Vector2(3.0, ROW_H), C_GOLD)

	var name_l := Ui.label(str(r.get("name", rid)), UiTheme.F_BODY, C_BRIGHT)
	name_l.position = Vector2(14.0, 6.0)
	name_l.size = Vector2(320.0, 22.0)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)

	var sub_l := Ui.label(_recipe_summary(r), UiTheme.F_META, C_MUTED)
	sub_l.position = Vector2(14.0, 30.0)
	sub_l.size = Vector2(220.0, 18.0)
	sub_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	sub_l.clip_text = true
	sub_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(sub_l)

	var cash_l := Ui.mono(str(maxi(int(r.get("cash", 0)), 0)), UiTheme.F_BODY, C_GOLD)
	cash_l.position = Vector2(310.0, 18.0)
	cash_l.size = Vector2(90.0, 20.0)
	cash_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cash_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	cash_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(cash_l)

	var check := _can_craft(rid)
	var craft_btn := Ui.ghost("合成", _on_craft.bind(rid))
	_place_button(craft_btn, Vector2(562.0, 10.0), Vector2(84.0, 36.0), false)
	if not bool(check.get("ok", false)):
		craft_btn.disabled = true
		var reason := str(check.get("error", ""))
		if not reason.is_empty():
			craft_btn.tooltip_text = reason
	row.add_child(craft_btn)

	_attach_hover(row, ROW_W, ROW_H)
	return row

func _recipe_summary(r: Dictionary) -> String:
	var parts: Array = []
	_append_materials(parts, r.get("inputs", {}))
	_append_materials(parts, r.get("key_items", {}))
	# 现金已单独落在价格列（310..400），副行不再重复，避免同值出现两次。
	if parts.is_empty():
		return ""
	return " · ".join(PackedStringArray(parts))

func _append_materials(parts: Array, raw: Variant) -> void:
	if not (raw is Dictionary):
		return
	for k in (raw as Dictionary).keys():
		var n := int((raw as Dictionary)[k])
		if n <= 0:
			continue
		parts.append("%s ×%d" % [_item_name(str(k)), n])

func _item_name(iid: String) -> String:
	if DataDB.catalog == null:
		return iid
	var n := str(DataDB.catalog.item_name(iid))
	if n.is_empty():
		return iid
	return n

func _can_craft(rid: String) -> Dictionary:
	if GameState.player == null or DataDB.catalog == null:
		return {"ok": false, "error": ""}
	return EconomyCore.can_craft(GameState.player, DataDB.catalog, rid)

# ---------------------------------------------------------------- 右背包

func _build_bag() -> void:
	var panel := Panel.new()
	panel.position = Vector2(W_SELL + GUTTER, 0.0)
	panel.size = Vector2(W_BAG, H_CONTENT)
	panel.add_theme_stylebox_override("panel", UiTheme.flat(C_POOR_BG, UiTheme.LINE, 6, 1))
	panel.mouse_filter = Control.MOUSE_FILTER_PASS
	_page.add_child(panel)

	var header := Control.new()
	header.position = Vector2.ZERO
	header.size = Vector2(W_BAG, BAG_HEAD_H)
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(header)

	var hbg := ColorRect.new()
	hbg.color = C_HEAD_BG
	hbg.position = Vector2.ZERO
	hbg.size = Vector2(W_BAG, BAG_HEAD_H)
	hbg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(hbg)

	var hline := ColorRect.new()
	hline.color = UiTheme.LINE
	hline.position = Vector2(0.0, BAG_HEAD_H - 1.0)
	hline.size = Vector2(W_BAG, 1.0)
	hline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(hline)

	var caption := Ui.label("物品", UiTheme.F_META, C_MUTED)
	caption.position = Vector2(14.0, 0.0)
	caption.size = Vector2(200.0, BAG_HEAD_H)
	caption.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(caption)

	var total_l := Ui.mono("0", UiTheme.F_META, C_MUTED)
	total_l.position = Vector2(320.0, 0.0)
	total_l.size = Vector2(150.0, BAG_HEAD_H)
	total_l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	total_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(total_l)
	_bag_total = total_l

	_bag_scroll = ScrollContainer.new()
	_bag_scroll.position = Vector2(0.0, BAG_LIST_Y)
	_bag_scroll.size = Vector2(W_BAG, BAG_LIST_H)
	_bag_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(_bag_scroll)

	_bag_box = VBoxContainer.new()
	_bag_box.add_theme_constant_override("separation", 0)
	_bag_box.custom_minimum_size = Vector2(BAG_ROW_W, 0.0)
	_bag_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_bag_scroll.add_child(_bag_box)

func _rebuild_bag() -> void:
	_clear_children(_bag_box)
	var total := 0
	if GameState.player != null:
		for raw in GameState.player.inventory.keys():
			total += int(GameState.player.inventory[raw])
	_bag_total.text = str(total)
	if DataDB.catalog == null or GameState.player == null:
		return
	var cat: Catalog = DataDB.catalog
	var ids: Array = []
	for raw in GameState.player.inventory.keys():
		var iid := str(raw)
		if GameState.player.item_count(iid) <= 0:
			continue
		if iid == str(cat.currency):
			continue
		var item: Dictionary = cat.item(iid)
		if item.is_empty():
			continue
		if bool(item.get("legacy", false)):
			continue
		ids.append(iid)
	ids.sort_custom(_bag_less)
	for i in ids.size():
		if i > 0:
			var sep := ColorRect.new()
			sep.color = UiTheme.LINE
			sep.custom_minimum_size = Vector2(BAG_ROW_W, 1.0)
			sep.size = Vector2(BAG_ROW_W, 1.0)
			sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_bag_box.add_child(sep)
		_bag_box.add_child(_bag_row(str(ids[i])))

func _bag_less(a: String, b: String) -> bool:
	var ra := _layer_rank(_layer_of(a))
	var rb := _layer_rank(_layer_of(b))
	if ra != rb:
		return ra < rb
	return a < b

func _layer_of(iid: String) -> String:
	if DataDB.catalog == null:
		return ""
	return str(DataDB.catalog.item(iid).get("layer", ""))

func _layer_rank(layer: String) -> int:
	var i := LAYER_ORDER.find(layer)
	if i < 0:
		return 90
	return i

func _layer_color(layer: String) -> Color:
	if LAYER_COLORS.has(layer):
		var c: Color = LAYER_COLORS[layer]
		return c
	return C_MUTED

func _bag_row(iid: String) -> Control:
	var cat: Catalog = DataDB.catalog
	var item: Dictionary = cat.item(iid)
	var cnt := GameState.player.item_count(iid)
	var row := _new_row(BAG_ROW_W, BAG_ROW_H)
	_row_bg(row, C_BAG_ROW_BG, BAG_ROW_W, BAG_ROW_H)
	_color_rect(row, Vector2(0.0, 0.0), Vector2(3.0, BAG_ROW_H), _layer_color(str(item.get("layer", ""))))

	var name_l := Ui.label(str(item.get("name", iid)), UiTheme.F_BODY, C_BRIGHT)
	name_l.position = Vector2(14.0, 6.0)
	name_l.size = Vector2(250.0, 22.0)
	name_l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_l.clip_text = true
	name_l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_l)

	row.add_child(_badge("×%d" % cnt, Vector2(372.0, 18.0), Vector2(34.0, 20.0), UiTheme.alpha(C_CHALK, 0.12), C_BRIGHT, UiTheme.LINE))

	if bool(item.get("bound_first", false)) and cnt > 0:
		var lock := Ui.glyph("lock", C_GRAYBLUE, 24)
		lock.position = Vector2(424.0, 16.0)
		row.add_child(lock)

	_attach_hover(row, BAG_ROW_W, BAG_ROW_H)
	return row

# ---------------------------------------------------------------- 行与控件工具

func _new_row(w: float, h: float) -> Control:
	var row := Control.new()
	row.custom_minimum_size = Vector2(w, h)
	row.size = Vector2(w, h)
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	return row

func _row_bg(row: Control, color: Color, w: float, h: float) -> void:
	var bg := ColorRect.new()
	bg.color = color
	bg.position = Vector2.ZERO
	bg.size = Vector2(w, h)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bg)

func _color_rect(row: Control, pos: Vector2, sz: Vector2, color: Color) -> void:
	var bar := ColorRect.new()
	bar.color = color
	bar.position = pos
	bar.size = sz
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(bar)

func _badge(text: String, pos: Vector2, sz: Vector2, bg: Color, fg: Color, border: Color) -> Panel:
	var panel := Panel.new()
	panel.position = pos
	panel.size = sz
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", UiTheme.flat_tight(bg, border, 1))
	var label := Ui.label(text, UiTheme.F_META, fg)
	label.position = Vector2.ZERO
	label.size = sz
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(label)
	return panel

func _place_button(button: Button, pos: Vector2, sz: Vector2, primary: bool) -> void:
	button.position = pos
	button.size = sz
	button.custom_minimum_size = sz
	button.add_theme_font_size_override("font_size", UiTheme.F_LABEL)
	if primary:
		_style_button(button, "normal", UiTheme.CHALK, UiTheme.CHALK)
		_style_button(button, "hover", UiTheme.CHALK_BRIGHT, UiTheme.CHALK_BRIGHT)
		_style_button(button, "pressed", UiTheme.MUTED, UiTheme.MUTED)
	else:
		_style_button(button, "normal", Color(0.0, 0.0, 0.0, 0.0), UiTheme.LINE)
		_style_button(button, "hover", UiTheme.alpha(UiTheme.CHALK, 0.10), UiTheme.CHALK)
		_style_button(button, "pressed", UiTheme.alpha(UiTheme.CHALK, 0.16), UiTheme.CHALK)
	_style_button(button, "disabled", UiTheme.BOARD_SUNK, UiTheme.alpha(UiTheme.LINE, 0.10))

func _style_button(button: Button, key: String, bg: Color, border: Color) -> void:
	var sb := UiTheme.flat(bg, border)
	_tight_margins(sb)
	button.add_theme_stylebox_override(key, sb)

func _tight_margins(sb: StyleBoxFlat) -> void:
	sb.content_margin_left = 6
	sb.content_margin_right = 6
	sb.content_margin_top = 2
	sb.content_margin_bottom = 2

func _attach_hover(row: Control, w: float, h: float) -> void:
	var tint := ColorRect.new()
	tint.color = Color(1.0, 1.0, 1.0, 0.0)
	tint.position = Vector2.ZERO
	tint.size = Vector2(w, h)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(tint)

	var frame := Panel.new()
	frame.add_theme_stylebox_override("panel", UiTheme.flat_tight(Color(0.0, 0.0, 0.0, 0.0), UiTheme.alpha(UiTheme.CHALK_BRIGHT, 0.32), 1))
	frame.modulate.a = 0.0
	frame.position = Vector2.ZERO
	frame.size = Vector2(w, h)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(frame)

	row.mouse_entered.connect(_set_row_hover.bind(row, tint, frame, true))
	row.mouse_exited.connect(_set_row_hover.bind(row, tint, frame, false))

func _set_row_hover(row: Control, tint: ColorRect, frame: Panel, hot: bool) -> void:
	var old := row.get_meta("hover_tween", null) as Tween
	if old != null:
		old.kill()
	if not UiTheme.motion:
		tint.color = Color(1.0, 1.0, 1.0, 0.06 if hot else 0.0)
		frame.modulate.a = 1.0 if hot else 0.0
		return
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(tint, "color:a", 0.06 if hot else 0.0, ANIM_HOVER)
	tw.tween_property(frame, "modulate:a", 1.0 if hot else 0.0, ANIM_HOVER)
	row.set_meta("hover_tween", tw)

func _clear_children(container: Node) -> void:
	for c in container.get_children():
		if c is Control:
			var tw := (c as Control).get_meta("hover_tween", null) as Tween
			if tw != null:
				tw.kill()
		container.remove_child(c)
		c.queue_free()

# ---------------------------------------------------------------- 动作

func _on_buy(iid: String) -> void:
	if GameState.player == null or DataDB.catalog == null:
		return
	var r := EconomyCore.buy(GameState.player, DataDB.catalog, DataDB.skill_nodes(), iid, 1)
	if bool(r.get("ok", false)):
		EventBus.economy_changed.emit()
		EventBus.state_changed.emit()
		call_deferred("on_show")
	else:
		EventBus.toast("购买失败：%s" % str(r.get("error", "")), "error")

func _on_craft(rid: String) -> void:
	if rid.is_empty() or GameState.player == null or DataDB.catalog == null:
		return
	var r := EconomyCore.craft(GameState.player, DataDB.catalog, rid, 1)
	if bool(r.get("ok", false)):
		EventBus.economy_changed.emit()
		EventBus.state_changed.emit()
		call_deferred("on_show")
	else:
		EventBus.toast("合成失败：%s" % str(r.get("error", "")), "error")
