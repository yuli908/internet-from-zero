class_name PlayerState
extends RefCounted

## 玩家全部可存档状态。不依赖场景树与 autoload，测试可直接构造。

const SAVE_VERSION := 3
const XP_LEVELS := [0, 60, 160, 300, 520, 800]

var save_version := SAVE_VERSION
var slot := 1
var created_at := ""
var updated_at := ""
var chapter_id := "ch01"
var gold := 20
var xp := 0
var inventory: Dictionary = {}
var knowledge: Dictionary = {}
var objectives: Dictionary = {}
var labs_completed: Dictionary = {}
var flags: Dictionary = {}
var tutorial_done: Dictionary = {}
var stats: Dictionary = {"saves": 0, "play_seconds": 0.0, "ticks": 0}
var rng_seed := 1
var _rng := DeterministicRng.new(1)

func _init(seed_value_in: int = 1) -> void:
	var now := Time.get_datetime_string_from_system()
	created_at = now
	updated_at = now
	rng_seed = seed_value_in
	_rng = DeterministicRng.new(seed_value_in)

func add_gold(n: int) -> void:
	gold = maxi(0, gold + n)

func spend_gold(n: int) -> bool:
	if n < 0 or gold < n:
		return false
	gold -= n
	return true

func add_xp(n: int) -> void:
	xp = maxi(0, xp + n)

func spend_xp(n: int) -> bool:
	if n < 0 or xp < n:
		return false
	xp -= n
	return true

func level() -> int:
	var lv := 1
	for i in XP_LEVELS.size():
		if xp >= int(XP_LEVELS[i]):
			lv = i + 1
	return lv

func xp_into_level() -> int:
	var lv := level()
	var base := int(XP_LEVELS[lv - 1])
	return xp - base

func xp_for_next_level() -> int:
	var lv := level()
	if lv >= XP_LEVELS.size():
		return 0
	return int(XP_LEVELS[lv]) - int(XP_LEVELS[lv - 1])

func add_item(id: String, n: int = 1) -> void:
	if n <= 0:
		return
	inventory[id] = item_count(id) + n

func remove_item(id: String, n: int = 1) -> bool:
	if n <= 0 or item_count(id) < n:
		return false
	var left := item_count(id) - n
	if left <= 0:
		inventory.erase(id)
	else:
		inventory[id] = left
	return true

func item_count(id: String) -> int:
	return int(inventory.get(id, 0))

func grant_knowledge(id: String) -> bool:
	if knowledge.has(id):
		return false
	knowledge[id] = true
	return true

func has_knowledge(id: String) -> bool:
	return knowledge.has(id)

func complete_objective(id: String) -> bool:
	if objectives.has(id):
		return false
	objectives[id] = true
	return true

func is_objective_done(id: String) -> bool:
	return objectives.has(id)

func mark_lab_completed(id: String) -> void:
	labs_completed[id] = true

func is_lab_completed(id: String) -> bool:
	return labs_completed.has(id)

func set_flag(key: String, value: Variant) -> void:
	flags[key] = value

func get_flag(key: String, fallback: Variant = null) -> Variant:
	return flags.get(key, fallback)

func has_flag(key: String) -> bool:
	return flags.has(key)

func mark_tutorial_done(id: String) -> void:
	tutorial_done[id] = true

func is_tutorial_done(id: String) -> bool:
	return tutorial_done.has(id)

func rng() -> DeterministicRng:
	return _rng

func roll(from_v: int, to_v: int) -> int:
	return _rng.next_int(from_v, to_v)

func to_dict() -> Dictionary:
	updated_at = Time.get_datetime_string_from_system()
	return {
		"version": SAVE_VERSION,
		"slot": slot,
		"created_at": created_at,
		"updated_at": updated_at,
		"chapter_id": chapter_id,
		"gold": gold,
		"xp": xp,
		"inventory": inventory.duplicate(true),
		"knowledge": knowledge.duplicate(true),
		"objectives": objectives.duplicate(true),
		"labs_completed": labs_completed.duplicate(true),
		"flags": flags.duplicate(true),
		"tutorial_done": tutorial_done.duplicate(true),
		"stats": stats.duplicate(true),
		"rng": _rng.to_dict(),
	}

static func from_dict(d: Dictionary) -> PlayerState:
	var s := PlayerState.new(int(d.get("rng", {}).get("seed", 1)))
	s.save_version = int(d.get("version", 1))
	s.slot = int(d.get("slot", 1))
	s.created_at = str(d.get("created_at", ""))
	s.updated_at = str(d.get("updated_at", ""))
	s.chapter_id = str(d.get("chapter_id", "ch01"))
	var raw_gold: Variant = d.get("gold", d.get("scrap", 0))
	s.gold = int(raw_gold)
	s.xp = int(d.get("xp", 0))
	s.inventory = _copy_int_dict(d.get("inventory", {}))
	s.knowledge = _copy_bool_dict(d.get("knowledge", {}))
	s.objectives = _copy_bool_dict(d.get("objectives", {}))
	s.labs_completed = _copy_bool_dict(d.get("labs_completed", {}))
	s.flags = _copy_dict(d.get("flags", {}))
	s.tutorial_done = _copy_bool_dict(d.get("tutorial_done", {}))
	s.stats = _copy_dict(d.get("stats", {"saves": 0, "play_seconds": 0.0, "ticks": 0}))
	if d.has("rng") and d["rng"] is Dictionary:
		s._rng.from_dict(d["rng"])
	return s

static func _copy_int_dict(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k in src.keys():
			out[str(k)] = int(src[k])
	return out

static func _copy_bool_dict(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k in src.keys():
			out[str(k)] = bool(src[k])
	return out

static func _copy_dict(src: Variant) -> Dictionary:
	var out := {}
	if src is Dictionary:
		for k in src.keys():
			out[str(k)] = src[k]
	return out
