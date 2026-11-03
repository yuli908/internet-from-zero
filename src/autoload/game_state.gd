extends Node

## 玩家状态持有者。启动时优先读取槽位 1 存档；--fresh 强制新档。

var player: PlayerState
var booted := false
var seed_value := 20261104

func _ready() -> void:
	player = PlayerState.new(seed_value)

func boot() -> void:
	if booted:
		return
	var fresh := CliArgs.has_flag("fresh") or CliArgs.has_flag("no-save")
	var loaded := false
	if not fresh and SaveManager.has_slot(1):
		var res := SaveManager.load_game(1, true)
		loaded = bool(res.get("ok", false))
		if loaded:
			EventBus.toast("已读取槽位 1 存档", "ok")
	if not loaded:
		new_game(false)
	booted = true
	if player.chapter_id.is_empty():
		player.chapter_id = DataDB.chapter_id()
	EventBus.state_changed.emit()
	EventBus.fire("game_start")
	if loaded:
		EventBus.fire("game_loaded")

func new_game(save_now: bool = true) -> void:
	player = PlayerState.new(seed_value)
	player.chapter_id = DataDB.chapter_id()
	player.scrap = int(DataDB.chapter.start_scrap())
	var start_items: Dictionary = DataDB.chapter.start_items()
	for id in start_items.keys():
		player.add_item(str(id), int(start_items[id]))
	player.stats["saves"] = 0
	player.stats["play_seconds"] = 0.0
	if save_now and SaveManager != null:
		SaveManager.save_game(1, true)
	EventBus.state_changed.emit()

func state() -> PlayerState:
	return player

func set_player(p: PlayerState) -> void:
	player = p

func touch() -> void:
	EventBus.state_changed.emit()

func _process(delta: float) -> void:
	if booted and player != null:
		player.stats["play_seconds"] = float(player.stats.get("play_seconds", 0.0)) + delta
