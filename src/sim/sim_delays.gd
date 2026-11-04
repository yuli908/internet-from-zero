class_name SimDelays
extends RefCounted

## 延迟与预算的唯一运行时来源。启动时由 DataDB 读取 data/sim/delays.json 调用 configure()。
## 缺省值与 docs/simulation/ref/simcore/logic.py 保持一致，避免未加载数据时语义漂移。

const DEFAULT_GATE := {
	"buf": 1, "not": 1,
	"nand": 2, "nor": 2,
	"and": 3, "or": 3,
	"xor": 4, "xnor": 5,
}
const DEFAULT_DFF := {"setup": 2, "hold": 1, "clk_to_q": 2}
const DEFAULT_FRAME := {"render_fps": 60, "budget_ms": 5, "ticks_per_frame": 4}
const DEFAULT_LIMITS := {
	"max_events_per_tick": 20000,
	"gdscript_gates": 100,
	"gdscript_dff": 100,
	"require_gdextension_above": 100,
}

static var gate_table: Dictionary = DEFAULT_GATE.duplicate()
static var dff_table: Dictionary = DEFAULT_DFF.duplicate()
static var frame_table: Dictionary = DEFAULT_FRAME.duplicate()
static var limits_table: Dictionary = DEFAULT_LIMITS.duplicate()
static var relay_delay := 3
static var loaded := false

static func configure(doc: Dictionary) -> void:
	if doc.is_empty():
		return
	var gates: Dictionary = doc.get("gate_delay", {})
	for key in gates.keys():
		gate_table[str(key)] = int(gates[key])
	var dff: Dictionary = doc.get("dff", {})
	for key in dff.keys():
		dff_table[str(key)] = int(dff[key])
	var frame: Dictionary = doc.get("frame", {})
	for key in frame.keys():
		frame_table[str(key)] = int(frame[key])
	var limits: Dictionary = doc.get("limits", {})
	for key in limits.keys():
		limits_table[str(key)] = int(limits[key])
	var relay: Dictionary = doc.get("relay", {})
	relay_delay = int(relay.get("delay_per_stage_ticks", relay_delay))
	loaded = true

static func delay(kind: String, fallback: int = 3) -> int:
	return int(gate_table.get(kind, fallback))

static func dff_delay() -> int:
	## clk→Q 传播延迟（tick）。setup/hold 由 L3 时序层使用，M2 只用到这一项。
	return int(dff_table.get("clk_to_q", 2))

static func max_events_per_tick() -> int:
	return int(limits_table.get("max_events_per_tick", 20000))

static func ticks_per_frame() -> int:
	return int(frame_table.get("ticks_per_frame", 4))

static func budget_ms() -> int:
	return int(frame_table.get("budget_ms", 5))

static func gdscript_gate_limit() -> int:
	## 玩家可搭建的门级电路上限（内容侧与编辑器共用的单一来源）。
	## 实测来源：`scripts/bench.ps1 -Sizes "50,80,100"` 三档各 3 次，100 档 p95 ≤5 ms 后定为 100。
	return int(limits_table.get("gdscript_gates", 100))

static func gate_table_snapshot() -> Dictionary:
	return gate_table.duplicate()
