extends RefCounted

## CH11 判据：汇编表、跳转循环、栈调用、调试定位。
## 全部复用既有 kind（table/derived_number/skip_layer/quiz），未新增 kind。
## 课文：docs/curriculum/22-ch11-lecture-copy.md；操作码取 ch05 MUD-8 表。

const Net := preload("res://src/core/net_lab_kit.gd")
const Kit := preload("res://src/core/lab_gate_kit.gd")

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch11_levels.json")

static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	return Net.run(lab_id, cfg, inputs, tracker)
