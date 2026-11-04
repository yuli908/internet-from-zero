class_name GateAttemptTracker
extends RefCounted

## 同一 gate 的连续失败计数（提示阶梯 1/2/3 级切换用）。
## 语义：失败 +1；通过立即清零。只在内存中，不写存档（每节实验重新开始）。
## 键使用 `GateReport` 的 case id（= gate_id），所以同一节内跨重跑仍连续。

var _counts: Dictionary = {}

func record(gate_id: String, ok: bool) -> int:
	if gate_id.is_empty():
		return 0
	if ok:
		_counts.erase(gate_id)
		return 0
	var n := int(_counts.get(gate_id, 0)) + 1
	_counts[gate_id] = n
	return n

func attempts(gate_id: String) -> int:
	return int(_counts.get(gate_id, 0))

func reset(gate_id: String = "") -> void:
	if gate_id.is_empty():
		_counts.clear()
	else:
		_counts.erase(gate_id)

func to_dict() -> Dictionary:
	return {"counts": _counts.duplicate(true)}

static func from_dict(d: Dictionary) -> GateAttemptTracker:
	var t := GateAttemptTracker.new()
	var raw: Variant = d.get("counts", {})
	if raw is Dictionary:
		for k in (raw as Dictionary).keys():
			t._counts[str(k)] = int((raw as Dictionary)[k])
	return t
