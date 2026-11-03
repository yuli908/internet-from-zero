extends Node

## 商店与经济服务：统一处理折扣、交易、合成与提示。

func discount() -> float:
	if GameState.player == null:
		return 0.0
	return EconomyCore.discount_for(GameState.player, DataDB.skill_nodes())

func price_of(item_id: String) -> int:
	var base := DataDB.catalog.buy_price(item_id)
	if base < 0:
		return -1
	return EconomyCore.effective_price(base, discount())

func buy(item_id: String, qty: int = 1) -> Dictionary:
	var res := EconomyCore.buy(GameState.player, DataDB.catalog, DataDB.skill_nodes(), item_id, qty)
	if bool(res.get("ok", false)):
		EventBus.toast("购买 %s ×%d（-%d 废铁）" % [DataDB.catalog.item_name(item_id), qty, int(res.get("cost", 0))], "ok")
		EventBus.economy_changed.emit()
		EventBus.state_changed.emit()
	else:
		EventBus.toast("购买失败：%s" % str(res.get("error", "未知错误")), "error")
	return res

func sell(item_id: String, qty: int = 1) -> Dictionary:
	var res := EconomyCore.sell(GameState.player, DataDB.catalog, item_id, qty)
	if bool(res.get("ok", false)):
		EventBus.toast("出售 %s ×%d（+%d 废铁）" % [DataDB.catalog.item_name(item_id), qty, int(res.get("gain", 0))], "ok")
		EventBus.economy_changed.emit()
		EventBus.state_changed.emit()
	else:
		EventBus.toast("出售失败：%s" % str(res.get("error", "未知错误")), "error")
	return res

func craft(recipe_id: String, times: int = 1) -> Dictionary:
	var res := EconomyCore.craft(GameState.player, DataDB.catalog, recipe_id, times)
	if bool(res.get("ok", false)):
		EventBus.toast("合成完成：%s" % DataDB.catalog.recipe_name(recipe_id), "ok")
		EventBus.economy_changed.emit()
		EventBus.state_changed.emit()
	else:
		EventBus.toast("合成失败：%s" % str(res.get("error", "未知错误")), "error")
	return res

func can_craft(recipe_id: String) -> Dictionary:
	return EconomyCore.can_craft(GameState.player, DataDB.catalog, recipe_id)
