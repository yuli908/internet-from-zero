class_name TraceSink
extends RefCounted

## M3 · 统一事件流（只读观测，不参与求值）。
## 固定 5 字段 schema：`{"tick","layer","kind","subject","payload"}`。
## 排序：只追加，tick 单调不减；同 tick 按写入顺序（仿真侧 seq 保证）。
## 容量：环形缓冲，超限丢最旧并累计 `dropped_old`（导出带计数，不静默截断）。

const FORMAT := "ifz-trace/1"
const LAYERS := ["L0a", "L1", "L2", "L3", "L4", "L5", "L6"]
## M4：7 → 15。新增 8 种 CH02 判定 kind（= `docs/design/11` §3 判定 kind 全大写）；
## `build_area` 是可选语法糖，不产生 trace。schema 与 `digest()` 不变。
const KINDS := [
	"CHANGE", "EDGE", "DROP", "SAMPLE", "METASTABLE", "ERR_ADDR", "ERR_METASTABLE",
	"MOSFET_REGION", "X_PROPAGATION", "STATIC_CURRENT", "RAIL_MARGIN",
	"EQUIV", "AREA_MAX", "POWER_CALC", "POWER_RATIO",
]

## 8 种 CH02 kind 的固定 payload 键与类型。缺键/类型不符按拒绝处理（不静默丢弃）。
## 数值本身来自数据文件，M4 不写入任何阈值。
const REQUIRED_KEYS := {
	"MOSFET_REGION": {"region": TYPE_STRING, "vgs": TYPE_FLOAT, "vds": TYPE_FLOAT, "id_ua": TYPE_FLOAT},
	"X_PROPAGATION": {"expect": TYPE_STRING, "got": TYPE_STRING},
	"STATIC_CURRENT": {"ua": TYPE_FLOAT, "states": TYPE_INT},
	"RAIL_MARGIN": {"v_high": TYPE_FLOAT, "v_low": TYPE_FLOAT},
	"EQUIV": {"ref": TYPE_STRING, "vectors": TYPE_INT, "mismatch": TYPE_INT},
	"AREA_MAX": {"gates": TYPE_INT, "max": TYPE_INT},
	"POWER_CALC": {"mw": TYPE_FLOAT, "expect_mw": TYPE_FLOAT, "tol": TYPE_FLOAT},
	"POWER_RATIO": {"ratio": TYPE_FLOAT, "expect_ratio": TYPE_FLOAT, "tol": TYPE_FLOAT},
}

var max_events := 20000
var dropped_old := 0
var rejected := 0
var last_error := ""

var _buf: Array = []
var _head := 0
var _last_tick := -1073741824

func _init(capacity: int = 20000) -> void:
	max_events = maxi(1, capacity)

func size() -> int:
	return _buf.size() - _head

func entries() -> Array:
	return _buf.slice(_head)

func entry(i: int) -> Dictionary:
	var idx := _head + i
	if idx < _head or idx >= _buf.size():
		return {}
	return _buf[idx]

func record(tick: int, layer: String, kind: String, subject: String, payload: Dictionary) -> bool:
	if not KINDS.has(kind):
		rejected += 1
		last_error = "kind 不在白名单：%s" % kind
		return false
	if not LAYERS.has(layer):
		rejected += 1
		last_error = "layer 不在白名单：%s" % layer
		return false
	if subject.is_empty():
		rejected += 1
		last_error = "subject 不能为空"
		return false
	if tick < _last_tick:
		rejected += 1
		last_error = "tick 回退：%d < %d" % [tick, _last_tick]
		return false
	if not _basic(payload):
		rejected += 1
		last_error = "payload 含非基础类型"
		return false
	if not payload_keys_ok(kind, payload):
		rejected += 1
		last_error = "payload 缺少固定键或类型不符：%s" % kind
		return false
	_last_tick = tick
	_buf.append({"tick": tick, "layer": layer, "kind": kind, "subject": subject,
		"payload": payload.duplicate(true)})
	while _buf.size() - _head > max_events:
		_head += 1
		dropped_old += 1
	if _head > 1024:
		_buf = _buf.slice(_head)
		_head = 0
	return true

func count_kind(kind: String) -> int:
	var n := 0
	for i in range(_head, _buf.size()):
		if str(_buf[i]["kind"]) == kind:
			n += 1
	return n

func count_changes(subject: String) -> int:
	var n := 0
	for i in range(_head, _buf.size()):
		var e: Dictionary = _buf[i]
		if str(e["kind"]) == "CHANGE" and str(e["subject"]) == subject:
			n += 1
	return n

func clear() -> void:
	_buf.clear()
	_head = 0
	dropped_old = 0
	rejected = 0
	last_error = ""
	_last_tick = -1073741824

func digest() -> String:
	## 对 `[tick, layer, kind, subject, canonical(payload)]` 逐条拼接后 SHA-256。
	var lines := PackedStringArray()
	for i in range(_head, _buf.size()):
		var e: Dictionary = _buf[i]
		lines.append("%d|%s|%s|%s|%s" % [int(e["tick"]), e["layer"], e["kind"], e["subject"],
			canonical_payload(e["payload"])])
	return sha256("\n".join(lines))

func export() -> Dictionary:
	return {
		"format": FORMAT,
		"max_events": max_events,
		"dropped_old": dropped_old,
		"rejected": rejected,
		"entries": entries(),
		"digest": digest(),
	}

static func canonical_payload(v: Variant) -> String:
	## 键排序 + 基础类型紧凑序列化；用于跨帧粒度（1 tick/帧 vs 4 tick/帧）逐字节比对。
	match typeof(v):
		TYPE_DICTIONARY:
			var d: Dictionary = v
			var keys := d.keys()
			keys.sort()
			var parts := PackedStringArray()
			for k in keys:
				parts.append("%s:%s" % [JSON.stringify(str(k)), canonical_payload(d[k])])
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var parts := PackedStringArray()
			for x in (v as Array):
				parts.append(canonical_payload(x))
			return "[" + ",".join(parts) + "]"
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return JSON.stringify(v)
		_:
			return JSON.stringify("<unsupported>")

static func sha256(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

static func payload_keys_ok(kind: String, payload: Dictionary) -> bool:
	## 只校验 8 种 CH02 kind；既有 7 种 kind 无固定键约束（保持原行为）。
	var req: Dictionary = REQUIRED_KEYS.get(kind, {})
	for key in req:
		if not payload.has(key):
			return false
		var want := int(req[key])
		var got := typeof(payload[key])
		if want == TYPE_FLOAT:
			if got != TYPE_FLOAT and got != TYPE_INT:
				return false
		elif got != want:
			return false
	return true

static func _basic(v: Variant) -> bool:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in (v as Dictionary):
				if typeof(k) != TYPE_STRING and typeof(k) != TYPE_INT:
					return false
				if not _basic((v as Dictionary)[k]):
					return false
			return true
		TYPE_ARRAY:
			for x in (v as Array):
				if not _basic(x):
					return false
			return true
		TYPE_NIL, TYPE_BOOL, TYPE_INT, TYPE_FLOAT, TYPE_STRING:
			return true
		_:
			return false
