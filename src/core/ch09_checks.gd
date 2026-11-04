extends RefCounted

## CH09 判据：编址、ARP、交换机、路由、环路恢复。
## 全部复用既有 kind（table / coverage / port_map / page_map / checksum /
## derived_number / handshake_fsm / timeout_idle / skip_layer / quiz），未新增 kind。
## 课文：docs/curriculum/20-ch09-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")
const Net := preload("res://src/core/net_lab_kit.gd")

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch09_levels.json")

static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	return Net.run(lab_id, cfg, inputs, tracker)
