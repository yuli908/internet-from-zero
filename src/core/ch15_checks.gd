extends RefCounted

## CH15 判据：库与 ABI、socket、版本兼容、DNS 解析
## 全部复用既有 kind（table / skip_layer / derived_number / quiz），未新增 kind。
## 课文：docs/curriculum/26-ch15-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")
const Net := preload("res://src/core/net_lab_kit.gd")

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch15_levels.json")

static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	return Net.run(lab_id, cfg, inputs, tracker)
