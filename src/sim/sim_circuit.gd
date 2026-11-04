class_name SimCircuit
extends RefCounted

## L0b/L1 电路容器：线网 + 门 + 确定性事件引擎。
## 语义对齐 docs/simulation/ref/simcore/logic.py：
##  - 每次输入变化按门延迟独立排一次求值（传输延迟）；
##  - 输出值不变则不写线网（自然合并；窄于门延迟的脉冲会被滤除）；
##  - 历史记录 (tick, wire, old, new)，供示波器与回放。
##
## 实现层（M3-OPT）：热路径数据化，语义不变。
##  - 线网/门用整数 id（`PackedInt32Array`/`PackedByteArray`），字符串只在公开 API 边界转换；
##  - fanout 邻接表在 add_gate 时预计算，不再为每门每输入挂闭包；
##  - 门求值走整数三值表，不再每事件建 Array/Dictionary；
##  - 门事件与 DFF 写事件进入整数堆，与通用事件按 (tick, seq) 合并出队。
## 顺序约定：同一 tick 内，fanout 表按"建门顺序"订阅，与旧实现"listeners 追加顺序"一致；
## 通用 closure listeners（bind/外部）在 fanout 之后调用。

var name := "circuit"
var eng: SimEngine
var wires: Dictionary = {}
var history: Array = []
var glitches: Array = []
var input_names: Array = []
var output_names: Array = []

var _watch: Dictionary = {}

# ---- 整数线网表 -------------------------------------------------------------
# _wval 编码：0 = X，1 = "0"，2 = "1"（非 0/1 的字符串按 X 参与求值，与 SimValue.gate 一致）
var _wname := PackedStringArray()
var _widx: Dictionary = {}
var _wval := PackedByteArray()
var _wlast := PackedInt32Array()
var _fan: Array = []

# ---- 整数门表 ---------------------------------------------------------------
# op：0 buf / 1 not / 2 and / 3 or / 4 xor / 5 nand / 6 nor / 7 xnor
var _g_op := PackedInt32Array()
var _g_delay := PackedInt32Array()
var _g_out := PackedInt32Array()
var _g_in0 := PackedInt32Array()
var _g_in1 := PackedInt32Array()          # -1 = 一元
var _g_extra: Array = []                  # >2 输入时的额外线网 id（PackedInt32Array）

# ---- DFF 表（T1 会扩展 RESET/setup/hold；此处保持 M2 行为） -----------------
var _d_q := PackedInt32Array()
var _d_d := PackedInt32Array()
var _d_clk := PackedInt32Array()
var _d_delay := PackedInt32Array()

# ---- 合并事件堆（type：0 = 门求值，1 = 线网写入） ---------------------------
var _ev_t := PackedInt32Array()
var _ev_seq := PackedInt32Array()
var _ev_type := PackedByteArray()
var _ev_a := PackedInt32Array()
var _ev_b := PackedInt32Array()

const _T_NOT := [0, 2, 1]
# 三值真值表，下标 a*3+b，a/b 取 0=X,1="0",2="1"
const _T_AND := [0, 1, 0, 1, 1, 1, 0, 1, 2]
const _T_OR := [0, 0, 2, 0, 1, 2, 2, 2, 2]
const _T_XOR := [0, 0, 0, 0, 1, 2, 0, 2, 1]

func _init(p_name: String = "circuit", per_tick_limit: int = -1) -> void:
	name = p_name
	eng = SimEngine.new(per_tick_limit)

func add_wire(wire_name: String, init: String = SimValue.X) -> Dictionary:
	if wires.has(wire_name):
		return wires[wire_name]
	var w := {"bits": init, "prev": init, "last_change": -1073741824, "listeners": []}
	wires[wire_name] = w
	var wid := _wname.size()
	_wname.append(wire_name)
	_widx[wire_name] = wid
	_wval.append(_enc(init))
	_wlast.append(-1073741824)
	_fan.append(PackedInt32Array())
	return w

func has_wire(wire_name: String) -> bool:
	return wires.has(wire_name)

func probe(wire_name: String) -> String:
	if not wires.has(wire_name):
		return SimValue.X
	return str(wires[wire_name]["bits"])

func now() -> int:
	return eng.now

func pending() -> int:
	return eng.pending() + _ev_t.size()

func is_quiescent() -> bool:
	return pending() == 0

func set_input(wire_name: String, bits: String, delay: int = 0) -> void:
	if not wires.has(wire_name):
		add_wire(wire_name, SimValue.X)
	eng.schedule_after(delay, Callable(self, "_drive"), [wire_name, bits])

func _drive(wire_name: String, bits: String) -> void:
	_write(wire_name, bits)

func _write(wire_name: String, bits: String) -> void:
	var wid := _wire_id(wire_name)
	_write_id(wid, _enc(bits), bits)

func _write_id(wid: int, val: int, bits: String = "") -> void:
	if _wval[wid] == val:
		return
	var w: Dictionary = wires[_wname[wid]]
	var old := str(w["bits"])
	var next_bits := bits if not bits.is_empty() else _dec(val)
	w["prev"] = old
	w["bits"] = next_bits
	w["last_change"] = eng.now
	_wval[wid] = val
	_wlast[wid] = eng.now
	history.append({"t": eng.now, "wire": _wname[wid], "old": old, "new": next_bits})
	if _watch.has(_wname[wid]):
		glitches.append({"t": eng.now, "wire": _wname[wid], "value": next_bits})
	# fanout：门事件与 DFF 事件按订阅顺序入堆
	var fan: PackedInt32Array = _fan[wid]
	var t_now := eng.now
	for e in fan:
		if e >= 0:
			_ev_push(t_now + _g_delay[e], eng.next_seq(), 0, e, 0)
		elif val == 2:
			var did := -(e + 1)
			_ev_push(t_now + _d_delay[did], eng.next_seq(), 1, _d_q[did], _wval[_d_d[did]])
	# 通用 closure listeners（bind/外部），保持旧语义
	var listeners: Array = w["listeners"]
	if not listeners.is_empty():
		var copy := listeners.duplicate()
		for cb in copy:
			if cb is Callable and cb.is_valid():
				cb.call(old, t_now)

func watch_glitch(wire_name: String) -> void:
	_watch[wire_name] = true

func bind(src: String, dst: String, delay: int = 0) -> void:
	add_wire(src, SimValue.X)
	add_wire(dst, SimValue.X)
	var w: Dictionary = wires[src]
	var cb := func(_old: String, t: int) -> void:
		eng.schedule(t + delay, Callable(self, "_write"), [dst, probe(src)])
	w["listeners"].append(cb)
	eng.schedule(eng.now, Callable(self, "_write"), [dst, probe(src)])

func add_gate(gate_name: String, kind: String, ins: Array, delay: int = -1) -> String:
	if not SimValue.GATE_DELAY.has(kind) and kind != "buf":
		return ""
	if kind == "not" and ins.size() != 1:
		return ""
	var d := SimDelays.delay(kind) if delay < 0 else delay
	var out_wid := _wire_id(gate_name)
	var op := _op_of(kind)
	var gid := _g_op.size()
	_g_op.append(op)
	_g_delay.append(d)
	_g_out.append(out_wid)
	var in0 := -1
	var in1 := -1
	var extra := PackedInt32Array()
	for i in ins.size():
		var wid := _wire_id(str(ins[i]))
		if i == 0:
			in0 = wid
		elif i == 1:
			in1 = wid
		else:
			extra.append(wid)
		var f: PackedInt32Array = _fan[wid]
		f.append(gid)
		_fan[wid] = f
	_g_in0.append(in0)
	_g_in1.append(in1)
	_g_extra.append(extra)
	_ev_push(eng.now, eng.next_seq(), 0, gid, 0)
	return gate_name

func add_dff(cell_name: String, d_src: String, clk_src: String, delay: int = -1) -> String:
	## D 触发器（上升沿采样）：
	##  - 初值 X；clk 由 0/X→1 时把 d_src 当前值经 clk_to_q 延迟写入 Q（cell_name 本身）；
	##  - 不是门级展开，故不会形成组合环，L3 时序层可直接复用 L1 的确定性调度。
	##  - RESET/setup/hold/METASTABLE 属 T1（`SimDff`），本函数保持 M2 行为。
	if wires.has(cell_name) and wires.has(clk_src):
		return ""
	var d := SimDelays.dff_delay() if delay < 0 else delay
	var q_wid := _wire_id(cell_name)
	var dd_wid := _wire_id(str(d_src))
	var clk_wid := _wire_id(clk_src)
	var did := _d_q.size()
	_d_q.append(q_wid)
	_d_d.append(dd_wid)
	_d_clk.append(clk_wid)
	_d_delay.append(d)
	var f: PackedInt32Array = _fan[clk_wid]
	f.append(-(did + 1))
	_fan[clk_wid] = f
	return cell_name

func run(ticks: int) -> Dictionary:
	return run_until(eng.now + ticks)

func run_until(t: int) -> Dictionary:
	return _pump(t, false)

func settle() -> Dictionary:
	return _pump(0, true)

func measure_settle(outputs: Array, from_tick: int) -> int:
	var r := settle()
	if not bool(r.get("ok", false)):
		return -1
	var last := from_tick
	for o in outputs:
		if wires.has(str(o)):
			last = maxi(last, int(wires[str(o)]["last_change"]))
	return last - from_tick

func snapshot() -> Dictionary:
	## 只允许在队列为空时快照（静止 tick），否则拒绝，避免存档后的波形不同。
	if not is_quiescent():
		return {"ok": false, "error": "队列非空（%d 事件），拒绝存档" % pending()}
	var sorted_wires := {}
	var keys := wires.keys()
	keys.sort()
	for key in keys:
		sorted_wires[str(key)] = str(wires[key]["bits"])
	var canonical := JSON.stringify({"format": "ifz-circuit/1", "name": name, "tick": eng.now, "wires": sorted_wires})
	return {
		"ok": true,
		"error": "",
		"format": "ifz-circuit/1",
		"tick": eng.now,
		"wires": sorted_wires,
		"digest": digest(canonical),
		"canonical": canonical,
	}

func restore(snap: Dictionary) -> Dictionary:
	if str(snap.get("format", "")) != "ifz-circuit/1":
		return {"ok": false, "error": "存档格式不兼容"}
	if not is_quiescent():
		return {"ok": false, "error": "恢复前必须清空队列"}
	var w: Dictionary = snap.get("wires", {})
	var keys := w.keys()
	keys.sort()
	var snap_tick := int(snap.get("tick", 0))
	for key in keys:
		if not wires.has(str(key)):
			continue
		var wd: Dictionary = wires[str(key)]
		var bits := str(w[key])
		if str(wd["bits"]) == bits:
			continue
		var old := str(wd["bits"])
		# 状态移植：直接写入，不触发监听者，否则会产生新事件、破坏"恢复后队列为空"。
		wd["prev"] = old
		wd["bits"] = bits
		wd["last_change"] = snap_tick
		var wid := int(_widx[str(key)])
		_wval[wid] = _enc(bits)
		_wlast[wid] = snap_tick
		history.append({"t": snap_tick, "wire": str(key), "old": old, "new": bits})
	eng.now = snap_tick
	return {"ok": true, "error": ""}

func state_digest() -> String:
	var sorted_wires := {}
	var keys := wires.keys()
	keys.sort()
	for key in keys:
		sorted_wires[str(key)] = probe(str(key))
	return digest(JSON.stringify({"tick": eng.now, "wires": sorted_wires}))

static func digest(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()

static func build_graph(graph: CircuitGraph, delay_per_gate: int = -1) -> Dictionary:
	## 从 CircuitGraph 构建可仿真网表。返回 {ok, sim, inputs, outputs, error}。
	var sim := SimCircuit.new("graph", -1)
	var inputs: Array = []
	var outputs: Array = []
	for raw_id in graph.nodes.keys():
		var id := str(raw_id)
		var n: Dictionary = graph.nodes[raw_id]
		if str(n["kind"]) == CircuitGraph.KIND_INPUT:
			sim.add_wire(id, SimValue.X)
			inputs.append(id)
	for raw_id in graph.nodes.keys():
		var id := str(raw_id)
		var n: Dictionary = graph.nodes[raw_id]
		if str(n["kind"]) != CircuitGraph.KIND_GATE:
			continue
		var in_list: Array = []
		var a := str(n["a"])
		var b := str(n["b"])
		if a.is_empty():
			in_list.append("__nc_%s_a" % id)
		else:
			in_list.append(a)
		if LogicGates.arity(int(n["gate"])) > 1:
			if b.is_empty():
				in_list.append("__nc_%s_b" % id)
			else:
				in_list.append(b)
		var kind: String = LogicGates.key_for(int(n["gate"]))
		if kind.is_empty() or sim.add_gate(id, kind, in_list, delay_per_gate).is_empty():
			return {"ok": false, "sim": null, "inputs": inputs, "outputs": outputs, "error": "非法门节点 %s" % id}
	outputs = []
	var output_map := {}
	for raw_id in graph.nodes.keys():
		var id := str(raw_id)
		var n: Dictionary = graph.nodes[raw_id]
		if str(n["kind"]) != CircuitGraph.KIND_OUTPUT:
			continue
		var src := str(n["a"])
		var out_name := "__out_%s" % id
		sim.add_wire(out_name, SimValue.X)
		if not src.is_empty():
			sim.bind(src, out_name, 0)
		outputs.append(out_name)
		output_map[id] = out_name
	sim.input_names = inputs
	sim.output_names = outputs
	return {"ok": true, "sim": sim, "inputs": inputs, "outputs": outputs, "output_map": output_map, "error": ""}

# ---- 整数表辅助 -------------------------------------------------------------

func _wire_id(wire_name: String, init: String = SimValue.X) -> int:
	var wid: int = _widx.get(wire_name, -1)
	if wid >= 0:
		return wid
	add_wire(wire_name, init)
	return int(_widx[wire_name])

static func _enc(bits: String) -> int:
	if bits == SimValue.ONE:
		return 2
	if bits == SimValue.ZERO:
		return 1
	return 0

static func _dec(val: int) -> String:
	if val == 2:
		return SimValue.ONE
	if val == 1:
		return SimValue.ZERO
	return SimValue.X

static func _op_of(kind: String) -> int:
	match kind:
		"buf":
			return 0
		"not":
			return 1
		"and":
			return 2
		"or":
			return 3
		"xor":
			return 4
		"nand":
			return 5
		"nor":
			return 6
		_:
			return 7

func _eval_gate(gid: int) -> void:
	var op := _g_op[gid]
	var in0 := _g_in0[gid]
	var in1 := _g_in1[gid]
	var v := 0
	if in1 < 0:
		var src := _wval[in0]
		v = _T_NOT[src] if op == 1 else src
	else:
		v = _bin(op, _wval[in0], _wval[in1])
		var extra: PackedInt32Array = _g_extra[gid]
		for i in extra.size():
			v = _bin(op, v, _wval[extra[i]])
	_write_id(_g_out[gid], v)

func _bin(op: int, a: int, b: int) -> int:
	var idx := a * 3 + b
	match op:
		2:
			return _T_AND[idx]
		3:
			return _T_OR[idx]
		4:
			return _T_XOR[idx]
		5:
			return _T_NOT[_T_AND[idx]]
		6:
			return _T_NOT[_T_OR[idx]]
		_:
			return _T_NOT[_T_XOR[idx]]

# ---- 合并事件循环 -----------------------------------------------------------

func _pump(t_end: int, to_empty: bool) -> Dictionary:
	var events := 0
	var budget := eng.max_events_per_tick * 64
	while true:
		var hd: Dictionary = eng.peek()
		var has_generic := not hd.is_empty() and (to_empty or int(hd["t"]) <= t_end)
		var has_fast := _ev_t.size() > 0 and (to_empty or _ev_t[0] <= t_end)
		if not has_generic and not has_fast:
			break
		var take_fast := has_fast
		if has_fast and has_generic:
			var ft := _ev_t[0]
			var gt := int(hd["t"])
			take_fast = ft < gt or (ft == gt and _ev_seq[0] < int(hd["seq"]))
		if take_fast:
			var nt := _ev_t[0]
			var typ := _ev_type[0]
			var ea := _ev_a[0]
			var eb := _ev_b[0]
			_ev_pop()
			var ar := eng.advance(nt)
			if not bool(ar.get("ok", false)):
				return {"ok": false, "error": eng.last_error, "events": events}
			if typ == 0:
				_eval_gate(ea)
			else:
				_write_id(ea, eb)
		else:
			var r := eng.pop_next()
			if not bool(r.get("ok", false)):
				return {"ok": false, "error": eng.last_error, "events": events}
		events += 1
		if events > budget:
			var msg := "组合逻辑未收敛：事件数超过 %d" % budget
			if not to_empty:
				msg = "run_until 事件数异常膨胀，疑似自激"
			return {"ok": false, "error": msg, "events": events}
	return {"ok": true, "error": "", "events": events}

func _ev_push(t: int, seq: int, typ: int, a: int, b: int) -> void:
	var i := _ev_t.size()
	_ev_t.append(t)
	_ev_seq.append(seq)
	_ev_type.append(typ)
	_ev_a.append(a)
	_ev_b.append(b)
	while i > 0:
		var p := (i - 1) >> 1
		var pt := _ev_t[p]
		var ps := _ev_seq[p]
		if pt < t or (pt == t and ps <= seq):
			break
		_ev_t[i] = pt
		_ev_seq[i] = ps
		_ev_type[i] = _ev_type[p]
		_ev_a[i] = _ev_a[p]
		_ev_b[i] = _ev_b[p]
		_ev_t[p] = t
		_ev_seq[p] = seq
		_ev_type[p] = typ
		_ev_a[p] = a
		_ev_b[p] = b
		i = p

func _ev_pop() -> void:
	var n := _ev_t.size() - 1
	if n <= 0:
		_ev_t.clear()
		_ev_seq.clear()
		_ev_type.clear()
		_ev_a.clear()
		_ev_b.clear()
		return
	var t := _ev_t[n]
	var s := _ev_seq[n]
	var ty := _ev_type[n]
	var a := _ev_a[n]
	var b := _ev_b[n]
	_ev_t.resize(n)
	_ev_seq.resize(n)
	_ev_type.resize(n)
	_ev_a.resize(n)
	_ev_b.resize(n)
	if n == 0:
		return
	_ev_t[0] = t
	_ev_seq[0] = s
	_ev_type[0] = ty
	_ev_a[0] = a
	_ev_b[0] = b
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var best := i
		if l < n:
			var lt := _ev_t[l]
			var lbt := _ev_t[best]
			if lt < lbt or (lt == lbt and _ev_seq[l] < _ev_seq[best]):
				best = l
		if r < n:
			var rt := _ev_t[r]
			var rbt := _ev_t[best]
			if rt < rbt or (rt == rbt and _ev_seq[r] < _ev_seq[best]):
				best = r
		if best == i:
			return
		var tt := _ev_t[best]
		var ss := _ev_seq[best]
		var tyy := _ev_type[best]
		var aa := _ev_a[best]
		var bb := _ev_b[best]
		_ev_t[best] = _ev_t[i]
		_ev_seq[best] = _ev_seq[i]
		_ev_type[best] = _ev_type[i]
		_ev_a[best] = _ev_a[i]
		_ev_b[best] = _ev_b[i]
		_ev_t[i] = tt
		_ev_seq[i] = ss
		_ev_type[i] = tyy
		_ev_a[i] = aa
		_ev_b[i] = bb
		i = best
