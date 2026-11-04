class_name EconomyCore
extends RefCounted

## 商店与经济规则。所有操作先校验再扣减，失败不留半成品。
## 配方兼容两种写法：
##  - 新表：output/output_qty/cash/inputs/key_items/requires_skill
##  - 旧表：outputs{cash?}/inputs/unlock_skill

static func discount_for(state: PlayerState, node_map: Dictionary) -> float:
	var total := 0.0
	for id in state.knowledge.keys():
		var node: Dictionary = node_map.get(str(id), {})
		if node.has("effects") and node["effects"] is Dictionary:
			total += float(node["effects"].get("price_discount", 0.0))
	return clampf(total, 0.0, 0.5)

static func effective_price(base: int, discount: float) -> int:
	if base <= 0:
		return -1
	return maxi(1, roundi(float(base) * (1.0 - discount)))

static func buy(state: PlayerState, catalog: Catalog, node_map: Dictionary, item_id: String, qty: int = 1) -> Dictionary:
	if qty <= 0:
		return {"ok": false, "error": "数量必须大于 0", "cost": 0}
	var base := catalog.buy_price(item_id)
	if base < 0:
		return {"ok": false, "error": "商店不出售该物品", "cost": 0}
	var cost := effective_price(base, discount_for(state, node_map)) * qty
	if state.gold < cost:
		return {"ok": false, "error": "金币不足：需要 %d，现有 %d" % [cost, state.gold], "cost": cost}
	if not state.spend_gold(cost):
		return {"ok": false, "error": "扣款失败", "cost": cost}
	state.add_item(item_id, qty)
	return {"ok": true, "error": "", "cost": cost}

static func sell(state: PlayerState, catalog: Catalog, item_id: String, qty: int = 1) -> Dictionary:
	if qty <= 0:
		return {"ok": false, "error": "数量必须大于 0", "gain": 0}
	if catalog.is_currency(item_id):
		return {"ok": false, "error": "金币本身不能出售", "gain": 0}
	var price := catalog.sell_price(item_id)
	if price <= 0:
		return {"ok": false, "error": "该物品无法出售", "gain": 0}
	if state.item_count(item_id) < qty:
		return {"ok": false, "error": "持有数量不足", "gain": 0}
	state.remove_item(item_id, qty)
	state.add_gold(price * qty)
	return {"ok": true, "error": "", "gain": price * qty}

static func can_craft(state: PlayerState, catalog: Catalog, recipe_id: String, times: int = 1) -> Dictionary:
	var recipe := catalog.recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "error": "配方不存在", "missing": []}
	var unlock_raw: Variant = recipe.get("requires_skill", recipe.get("unlock_skill", ""))
	var unlock_skill := "" if unlock_raw == null else str(unlock_raw)
	if not unlock_skill.is_empty() and not state.has_knowledge(unlock_skill):
		return {"ok": false, "error": "配方未解锁：需要技能「%s」" % unlock_skill, "missing": []}
	if times <= 0:
		return {"ok": false, "error": "次数必须大于 0", "missing": []}
	var missing := []
	var inputs: Dictionary = recipe.get("inputs", {})
	for k in inputs.keys():
		var need := int(inputs[k]) * times
		var have := _have(state, catalog, str(k))
		if have < need:
			missing.append({"id": str(k), "need": need, "have": have, "kind": "input"})
	var key_items: Dictionary = recipe.get("key_items", {})
	for k in key_items.keys():
		var need2 := int(key_items[k]) * times
		var have2 := _have(state, catalog, str(k))
		if have2 < need2:
			missing.append({"id": str(k), "need": need2, "have": have2, "kind": "key"})
	var cash := craft_cash(recipe, times)
	if state.gold < cash:
		missing.append({"id": catalog.currency, "need": cash, "have": state.gold, "kind": "cash"})
	if not missing.is_empty():
		return {"ok": false, "error": "材料或金币不足", "missing": missing}
	return {"ok": true, "error": "", "missing": []}

static func craft(state: PlayerState, catalog: Catalog, recipe_id: String, times: int = 1) -> Dictionary:
	if times <= 0:
		return {"ok": false, "error": "次数必须大于 0"}
	var check := can_craft(state, catalog, recipe_id, times)
	if not bool(check.ok):
		return check
	var recipe := catalog.recipe(recipe_id)
	var inputs: Dictionary = recipe.get("inputs", {})
	for k in inputs.keys():
		var need := int(inputs[k]) * times
		if str(k) == catalog.currency:
			state.spend_gold(need)
		else:
			state.remove_item(str(k), need)
	var cash := craft_cash(recipe, times)
	if cash > 0:
		state.spend_gold(cash)
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.is_empty() and str(recipe.get("output", "")).length() > 0:
		outputs[str(recipe["output"])] = int(recipe.get("output_qty", 1))
	for k in outputs.keys():
		var amount := int(outputs[k]) * times
		if str(k) == catalog.currency:
			state.add_gold(amount)
		else:
			state.add_item(str(k), amount)
	return {"ok": true, "error": "", "recipe": recipe_id}

static func craft_cash(recipe: Dictionary, times: int = 1) -> int:
	if recipe.has("cash"):
		return maxi(0, int(recipe.get("cash", 0)) * times)
	var outputs: Dictionary = recipe.get("outputs", {})
	if outputs.has("cash"):
		return maxi(0, int(outputs["cash"]) * times)
	return 0

static func _have(state: PlayerState, catalog: Catalog, id: String) -> int:
	return state.gold if id == catalog.currency else state.item_count(id)
