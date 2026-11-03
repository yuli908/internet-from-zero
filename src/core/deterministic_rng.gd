class_name DeterministicRng
extends RefCounted

## 可存档的确定性随机源。seed + state 都写入存档，保证重放一致。

var seed_value := 1
var _rng := RandomNumberGenerator.new()

func _init(seed_value_in: int = 1) -> void:
	seed_value = seed_value_in
	_rng.seed = seed_value_in

func set_seed(s: int) -> void:
	seed_value = s
	_rng.seed = s

func next_int(from_v: int, to_v: int) -> int:
	return _rng.randi_range(from_v, to_v)

func next_float() -> float:
	return _rng.randf()

func state_value() -> int:
	return int(_rng.state)

func restore_state(s: int) -> void:
	_rng.state = s

func to_dict() -> Dictionary:
	return {"seed": seed_value, "state": str(state_value())}

func from_dict(d: Dictionary) -> void:
	seed_value = int(d.get("seed", 1))
	_rng.seed = seed_value
	if d.has("state"):
		restore_state(int(str(d.get("state", "0"))) if d.get("state") is String else int(d.get("state", 0)))
