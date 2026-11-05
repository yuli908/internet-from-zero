extends RefCounted

## Ch19 判据：共享介质、嵌入式预算、传感闭环、固件回滚、多终端告警
## 全部复用既有 kind（table / skip_layer / derived_number / quiz），未新增 kind。
## 课文：docs/curriculum/30-ch19-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")
const Net := preload("res://src/core/net_lab_kit.gd")

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch19_levels.json")


static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	return Net.run(lab_id, cfg, inputs, tracker)
