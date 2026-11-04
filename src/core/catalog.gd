class_name Catalog
extends RefCounted

## 物品 + 价格 + 配方的运行时索引，由 DataDB 从 JSON 构建。

var items: Dictionary = {}
var buy_prices: Dictionary = {}
var sell_prices: Dictionary = {}
var currency := "gold"
var recipes: Dictionary = {}
var recipe_order: Array = []
var item_order: Array = []

static func from_data(items_doc: Dictionary, prices_doc: Dictionary, recipes_doc: Dictionary) -> Catalog:
	var c := Catalog.new()
	for raw in items_doc.get("items", []):
		if raw is Dictionary:
			var item: Dictionary = raw
			var id := str(item.get("id", ""))
			if not id.is_empty():
				c.items[id] = item
				c.item_order.append(id)
	var buy_doc: Dictionary = prices_doc.get("buy", {})
	for k in buy_doc.keys():
		c.buy_prices[str(k)] = int(buy_doc[k])
	var sell_doc: Dictionary = prices_doc.get("sell", {})
	for k in sell_doc.keys():
		c.sell_prices[str(k)] = int(sell_doc[k])
	c.currency = str(prices_doc.get("currency", "gold"))
	for raw in recipes_doc.get("recipes", []):
		if raw is Dictionary:
			var r: Dictionary = raw
			var id := str(r.get("id", ""))
			if not id.is_empty():
				c.recipes[id] = r
				c.recipe_order.append(id)
	return c

func has_item(id: String) -> bool:
	return items.has(id)

func item(id: String) -> Dictionary:
	return items.get(id, {})

func item_name(id: String) -> String:
	return str(item(id).get("name", id))

func item_desc(id: String) -> String:
	return str(item(id).get("desc", ""))

func is_currency(id: String) -> bool:
	return str(item(id).get("kind", "")) == "currency"

func buy_price(id: String) -> int:
	return int(buy_prices.get(id, -1))

func sell_price(id: String) -> int:
	return int(sell_prices.get(id, 0))

func recipe(id: String) -> Dictionary:
	return recipes.get(id, {})

func recipe_name(id: String) -> String:
	return str(recipe(id).get("name", id))

func item_ids_for_sale() -> Array:
	var out := []
	for id in item_order:
		if buy_price(str(id)) > 0:
			out.append(str(id))
	return out

func recipe_ids() -> Array:
	return recipe_order.duplicate()

func recipe_for_output(id: String) -> String:
	var declared: Variant = item(id).get("recipe", null)
	if declared is String:
		var rid := str(declared)
		if not rid.is_empty() and recipes.has(rid):
			return rid
	if declared is Array:
		for raw in declared:
			var rid := str(raw)
			if not rid.is_empty() and recipes.has(rid):
				return rid
	for raw_rid in recipe_order:
		var r: Dictionary = recipes[raw_rid]
		if str(r.get("output", "")) == id:
			return str(raw_rid)
		var outs: Variant = r.get("outputs", null)
		if outs is Dictionary and (outs as Dictionary).has(id):
			return str(raw_rid)
	return ""
