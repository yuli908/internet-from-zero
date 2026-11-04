extends RefCounted

## CH14 判据：解释器、动态类型、脚本自动化
## 全部复用既有 kind（table / skip_layer / derived_number / quiz），未新增 kind。
## 课文：docs/curriculum/25-ch14-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")
const Net := preload("res://src/core/net_lab_kit.gd")

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch14_levels.json")

static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	return Net.run(lab_id, cfg, inputs, tracker)
