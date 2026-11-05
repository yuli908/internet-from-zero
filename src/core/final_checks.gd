extends RefCounted

## Final 判据：终章 F1 出网、F2 五子棋、F3 凭证
## 全部复用既有 kind（table / skip_layer / derived_number），未新增 kind。
## 课文：docs/curriculum/31-final-chapter-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")
const Net := preload("res://src/core/net_lab_kit.gd")

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/final_levels.json")


static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	return Net.run(lab_id, cfg, inputs, tracker)
