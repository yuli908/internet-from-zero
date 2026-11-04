class_name SimEngine
extends RefCounted

## 确定性离散事件引擎（L0b/L1 接口层）。
## 硬性约束：
##  - 排序键必须是 (tick, seq)，seq 为单线程入队自增序号；
##  - 整数 tick，禁止浮点进入状态；
##  - 单 tick 事件数超限显式失败（SimLimitExceeded），绝不静默丢事件。

var now := 0
var event_count := 0
var last_error := ""
var max_events_per_tick := 20000

var _heap: Array = []
var _seq := 0
var _tick_events := 0
var trace: Array = []

func _init(per_tick_limit: int = -1) -> void:
	if per_tick_limit < 0:
		per_tick_limit = SimDelays.max_events_per_tick()
	max_events_per_tick = per_tick_limit

func pending() -> int:
	return _heap.size()

func next_seq() -> int:
	## 与 schedule() 共用同一个自增源：外部快速队列（如 SimCircuit 的整数门事件）
	## 取到的 seq 与通用事件处于同一全序，保证 (tick, seq) 排序不分裂。
	var s := _seq
	_seq += 1
	return s

func peek() -> Dictionary:
	## 只读堆顶，不弹出；空队列返回空字典（调用方用 is_empty() 判定）。
	return _heap[0] if not _heap.is_empty() else {}

func pop_next() -> Dictionary:
	return _pop()

func advance(t: int) -> Dictionary:
	## 外部快速队列弹出事件时的时间推进与限额记账（语义等同 _pop 的 tick 部分）。
	if t < now:
		last_error = "事件时间倒退，调度器损坏"
		return {"ok": false, "error": last_error}
	if t != now:
		now = t
		_tick_events = 0
	_tick_events += 1
	event_count += 1
	if _tick_events > max_events_per_tick:
		last_error = "tick %d 事件数超过 %d，疑似组合环/零延迟自激" % [now, max_events_per_tick]
		return {"ok": false, "error": last_error}
	return {"ok": true, "error": ""}

func schedule(tick: int, fn: Callable, args: Array = []) -> Dictionary:
	if tick < now:
		return {"ok": false, "error": "不允许调度到过去: %d < %d" % [tick, now]}
	var ev := {"t": tick, "seq": _seq, "fn": fn, "args": args}
	_seq += 1
	_push(ev)
	return {"ok": true, "error": ""}

func schedule_after(delay: int, fn: Callable, args: Array = []) -> Dictionary:
	return schedule(now + maxi(0, delay), fn, args)

func run_until(t_end: int) -> Dictionary:
	var events := 0
	while not _heap.is_empty() and int(_heap[0]["t"]) <= t_end:
		var r := _pop()
		if not bool(r.get("ok", false)):
			return {"ok": false, "error": last_error, "events": events}
		events += 1
		if events > max_events_per_tick * 64:
			last_error = "run_until 事件数异常膨胀，疑似自激"
			return {"ok": false, "error": last_error, "events": events}
	return {"ok": true, "error": "", "events": events}

func run_events() -> Dictionary:
	var budget := max_events_per_tick * 64
	var events := 0
	while not _heap.is_empty():
		var r := _pop()
		if not bool(r.get("ok", false)):
			return {"ok": false, "error": last_error, "events": events}
		events += 1
		if events > budget:
			last_error = "组合逻辑未收敛：事件数超过 %d" % budget
			return {"ok": false, "error": last_error, "events": events}
	return {"ok": true, "error": "", "events": events}

func _pop() -> Dictionary:
	var ev: Dictionary = _heap[0]
	var last: Dictionary = _heap.pop_back()
	if not _heap.is_empty():
		_heap[0] = last
		_sift_down(0)
	var t := int(ev["t"])
	if t < now:
		last_error = "事件时间倒退，调度器损坏"
		return {"ok": false, "error": last_error}
	if t != now:
		now = t
		_tick_events = 0
	_tick_events += 1
	event_count += 1
	if _tick_events > max_events_per_tick:
		last_error = "tick %d 事件数超过 %d，疑似组合环/零延迟自激" % [now, max_events_per_tick]
		return {"ok": false, "error": last_error}
	var fn: Callable = ev["fn"]
	if not fn.is_valid():
		last_error = "无效回调"
		return {"ok": false, "error": last_error}
	fn.callv(ev.get("args", []))
	return {"ok": true, "error": ""}

func _less(a: Dictionary, b: Dictionary) -> bool:
	if int(a["t"]) != int(b["t"]):
		return int(a["t"]) < int(b["t"])
	return int(a["seq"]) < int(b["seq"])

func _push(ev: Dictionary) -> void:
	_heap.append(ev)
	var i := _heap.size() - 1
	while i > 0:
		var p := (i - 1) >> 1
		if not _less(_heap[i], _heap[p]):
			break
		var tmp: Dictionary = _heap[p]
		_heap[p] = _heap[i]
		_heap[i] = tmp
		i = p

func _sift_down(i: int) -> void:
	var n := _heap.size()
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var best := i
		if l < n and _less(_heap[l], _heap[best]):
			best = l
		if r < n and _less(_heap[r], _heap[best]):
			best = r
		if best == i:
			return
		var tmp: Dictionary = _heap[best]
		_heap[best] = _heap[i]
		_heap[i] = tmp
		i = best
