extends RefCounted

## CH10 判据：序号重排、ACK/重传、滑动窗口、1 KB 可靠通道。
## 全部复用既有 kind（table/coverage/checksum/derived_number/handshake_fsm/
## timeout_idle/skip_layer/quiz），未新增 kind。
## 课文：docs/curriculum/21-ch10-lecture-copy.md。

const Net := preload("res://src/core/net_lab_kit.gd")
const Kit := preload("res://src/core/lab_gate_kit.gd")

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch10_levels.json")

static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	return Net.run(lab_id, cfg, inputs, tracker)
