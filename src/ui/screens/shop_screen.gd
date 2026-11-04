extends GameScreen

## 商店页：元件采购 + 配方合成。全部由代码构建。

const LAYER_KEYS = ["L0a", "L0b", "L0", "L1", "L2", "L3", "L4", "L5", "L6a", "L6b", "L6c", "L7"]

var _gold_value: Label
var _discount_value: Label
var _items_host: VBoxContainer
var _recipes_host: VBoxContainer

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func on_show() -> void:
	_refresh_header()
	_refresh_items()
	_refresh_recipes()

func _build() -> void:
	var page := Ui.vbox(10)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)

	page.add_child(_build_header())

	var body := Ui.hbox(10)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(body)

	var left: Array = _build_column("元件（按层级）", "按层分组；库存为 0 时可直接合成")
	var left_card: PanelContainer = left[0]
	var left_host: VBoxContainer = left[1]
	body.add_child(left_card)
	_items_host = left_host

	var right: Array = _build_column("合成配方", "先看配方再决定要不要直接买")
	var right_card: PanelContainer = right[0]
	var right_host: VBoxContainer = right[1]
	body.add_child(right_card)
	_recipes_host = right_host

func _build_header() -> PanelContainer:
	var card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	var m := Ui.margin4(14, 10, 14, 10)
	card.add_child(m)
	var col := Ui.vbox(5)
	m.add_child(col)

	var row := Ui.hbox(16)
	col.add_child(row)
	row.add_child(Ui.title("商店 · 金币交易", 22))
	row.add_child(Ui.spacer())
	var gold_stat := Ui.stat("金币", "0", UiTheme.AMBER)
	_gold_value = gold_stat.get_child(1) as Label
	row.add_child(gold_stat)
	_discount_value = Ui.label("优惠 0%", 13, UiTheme.OK)
	row.add_child(_discount_value)

	col.add_child(Ui.label("买入价 P，合成成本 0.7P。合成需要材料与配方解锁，但更便宜。", 12, UiTheme.MUTED))
	return card

func _build_column(title_text: String, hint_text: String) -> Array:
	var card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size = Vector2(340, 0)

	var m := Ui.margin4(12, 10, 12, 10)
	card.add_child(m)
	var col := Ui.vbox(6)
	m.add_child(col)

	col.add_child(Ui.label(title_text, 14, UiTheme.ACCENT))
	col.add_child(Ui.label(hint_text, 11, UiTheme.MUTED))
	col.add_child(Ui.hline())

	var scroll := Ui.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	var host := Ui.vbox(6)
	host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(host)
	return [card, host]

func _clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

func _refresh_header() -> void:
	var gold := 0
	if GameState.player != null:
		gold = int(GameState.player.gold)
	if _gold_value != null:
		_gold_value.text = str(gold)
	if _discount_value != null:
		_discount_value.text = "优惠 %d%%" % roundi(Economy.discount() * 100.0)

func _refresh_items() -> void:
	if _items_host == null:
		return
	_clear(_items_host)
	if DataDB.catalog == null:
		_items_host.add_child(Ui.label("数据未就绪：无法读取物品表", 12, UiTheme.DANGER))
		return

	var cat = DataDB.catalog
	var groups: Dictionary = {}
	for raw_id in cat.item_ids_for_sale():
		var iid := str(raw_id)
		var item: Dictionary = cat.item(iid)
		if item.is_empty():
			continue
		if bool(item.get("legacy", false)):
			continue
		if iid == str(cat.currency):
			continue
		var key := _layer_key(item)
		if not groups.has(key):
			groups[key] = []
		var bucket: Array = groups[key]
		bucket.append(iid)

	if groups.is_empty():
		_items_host.add_child(Ui.label("本章暂无可购买的元件", 12, UiTheme.MUTED))
		return

	for key in _ordered_keys(groups.keys()):
		var ids: Array = groups[key]
		var head := Ui.vbox(3)
		head.add_child(Ui.label("%s · %d 项" % [str(key), ids.size()], 11, UiTheme.MUTED))
		head.add_child(Ui.hline())
		_items_host.add_child(head)
		for raw_sid in ids:
			_items_host.add_child(_item_row(str(raw_sid)))

func _item_row(iid: String) -> PanelContainer:
	var cat = DataDB.catalog
	var item: Dictionary = cat.item(iid)
	var price: int = Economy.price_of(iid)
	var base_price: int = cat.buy_price(iid)
	var have := 0
	if GameState.player != null:
		have = GameState.player.item_count(iid)

	var card := Ui.card(UiTheme.PANEL_2, UiTheme.alpha(UiTheme.BORDER, 0.7), 5)
	var m := Ui.margin4(10, 5, 8, 5)
	card.add_child(m)
	var row := Ui.hbox(10)
	m.add_child(row)

	var info := Ui.vbox(1)
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(info)
	var line := Ui.hbox(8)
	info.add_child(line)
	line.add_child(Ui.label(str(item.get("name", iid)), 14, UiTheme.TEXT))
	line.add_child(Ui.label(iid, 10, UiTheme.MUTED))
	var unit := str(item.get("unit", ""))
	if not unit.is_empty():
		line.add_child(Ui.label("单位 %s" % unit, 10, UiTheme.MUTED))

	var price_label := Ui.mono(str(maxi(price, 0)), 16, UiTheme.AMBER)
	if base_price > 0:
		price_label.tooltip_text = "原价 %d 金币" % base_price
	row.add_child(price_label)

	var stock := Ui.label("×%d" % have, 13, UiTheme.TEXT if have > 0 else UiTheme.MUTED)
	stock.custom_minimum_size = Vector2(38, 0)
	stock.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	stock.tooltip_text = "当前库存"
	row.add_child(stock)

	var actions := Ui.hbox(6)
	actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(actions)

	var buy_btn := Ui.button("买 1", _on_buy.bind(iid), true)
	buy_btn.custom_minimum_size = Vector2(62, 28)
	buy_btn.add_theme_font_size_override("font_size", 12)
	buy_btn.tooltip_text = "单价 %d 金币" % maxi(price, 0)
	buy_btn.disabled = price < 0
	actions.add_child(buy_btn)

	if have > 0:
		return card
	var rid := _recipe_for_output(iid)
	if rid.is_empty():
		return card

	var craft_btn := Ui.ghost("合成", _on_craft.bind(rid))
	craft_btn.custom_minimum_size = Vector2(62, 28)
	craft_btn.add_theme_font_size_override("font_size", 12)
	var check: Dictionary = _safe_can_craft(rid)
	var reason := str(check.get("error", ""))
	craft_btn.tooltip_text = "材料齐备，可合成" if reason.is_empty() else reason
	actions.add_child(craft_btn)
	return card

func _refresh_recipes() -> void:
	if _recipes_host == null:
		return
	_clear(_recipes_host)
	if DataDB.catalog == null:
		_recipes_host.add_child(Ui.label("数据未就绪：无法读取配方表", 12, UiTheme.DANGER))
		return

	var cat = DataDB.catalog
	var ids: Array = cat.recipe_ids()
	if ids.is_empty():
		_recipes_host.add_child(Ui.label("本章尚无可用配方", 12, UiTheme.MUTED))
		return
	for raw_rid in ids:
		_recipes_host.add_child(_recipe_row(str(raw_rid)))

func _recipe_row(rid: String) -> PanelContainer:
	var cat = DataDB.catalog
	var r: Dictionary = cat.recipe(rid)

	var card := Ui.card(UiTheme.PANEL_2, UiTheme.alpha(UiTheme.BORDER, 0.7), 5)
	var m := Ui.margin4(10, 6, 8, 6)
	card.add_child(m)
	var col := Ui.vbox(3)
	m.add_child(col)

	var head := Ui.hbox(10)
	col.add_child(head)
	head.add_child(Ui.label(str(r.get("name", rid)), 15, UiTheme.TEXT))
	head.add_child(Ui.label(rid, 10, UiTheme.MUTED))
	head.add_child(Ui.spacer())

	var check: Dictionary = _safe_can_craft(rid)
	var ok := bool(check.get("ok", false))
	var reason := str(check.get("error", ""))
	var craft_btn := Ui.button("合成", _on_craft.bind(rid), ok)
	craft_btn.custom_minimum_size = Vector2(62, 28)
	craft_btn.add_theme_font_size_override("font_size", 12)
	craft_btn.tooltip_text = "材料齐备，可合成" if reason.is_empty() else reason
	head.add_child(craft_btn)

	col.add_child(Ui.wrap("材料：%s" % _format_entries(r, ["inputs", "materials", "key_items"], true), 12, UiTheme.MUTED))
	col.add_child(Ui.wrap("产出：%s" % _format_entries(r, ["outputs", "result", "products"], false), 12, UiTheme.OK))
	if not reason.is_empty():
		col.add_child(Ui.wrap(reason, 11, UiTheme.AMBER))
	return card

func _format_entries(recipe: Dictionary, keys: Array, with_cash: bool) -> String:
	var parts: Array = []
	if not with_cash:
		var out_id := str(recipe.get("output", ""))
		if not out_id.is_empty():
			parts.append("%s ×%d" % [_item_name(out_id), int(recipe.get("output_qty", 1))])
	for key_name in keys:
		var raw: Variant = recipe.get(key_name, null)
		if raw is Dictionary:
			var d: Dictionary = raw
			for k in d.keys():
				var n := int(d[k])
				if n <= 0:
					continue
				parts.append("%s ×%d" % [_item_name(str(k)), n])
	if with_cash:
		var cash := int(recipe.get("cash", 0))
		if cash <= 0:
			cash = int(recipe.get("gold_cost", 0))
		if cash > 0:
			parts.append("%s ×%d" % [_currency_name(), cash])
	if parts.is_empty():
		return "—"
	return " · ".join(PackedStringArray(parts))

func _item_name(iid: String) -> String:
	if DataDB.catalog == null:
		return iid
	var n := str(DataDB.catalog.item_name(iid))
	if n.is_empty():
		return iid
	return n

func _currency_name() -> String:
	var cid := "gold"
	if DataDB.catalog != null:
		cid = str(DataDB.catalog.currency)
	return _item_name(cid)

func _layer_key(item: Dictionary) -> String:
	var raw: Variant = item.get("layer", null)
	if raw == null:
		raw = item.get("tier", null)
	if raw == null:
		return "其他"
	var t := typeof(raw)
	if t == TYPE_INT or t == TYPE_FLOAT:
		return "L%d" % int(raw)
	var s := str(raw)
	if s.is_empty():
		return "其他"
	return s

func _ordered_keys(keys: Array) -> Array:
	var out: Array = []
	for k in LAYER_KEYS:
		if keys.has(k):
			out.append(k)
	for k in keys:
		if not out.has(k):
			out.append(k)
	return out

func _recipe_for_output(iid: String) -> String:
	if DataDB.catalog == null:
		return ""
	return DataDB.catalog.recipe_for_output(iid)

func _safe_can_craft(rid: String) -> Dictionary:
	if GameState.player == null:
		return {"ok": false, "error": "玩家状态未就绪"}
	return Economy.can_craft(rid)

func _on_buy(iid: String) -> void:
	if GameState.player == null:
		EventBus.toast("玩家状态未就绪", "error")
		return
	Economy.buy(iid, 1)
	call_deferred("on_show")

func _on_craft(rid: String) -> void:
	if GameState.player == null:
		EventBus.toast("玩家状态未就绪", "error")
		return
	Economy.craft(rid, 1)
	call_deferred("on_show")
