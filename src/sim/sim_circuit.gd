class_name SimCircuit
extends RefCounted

## L0b/L1 电路容器：线网 + 门 + 确定性事件引擎。
## 语义对齐 docs/simulation/ref/simcore/logic.py：
##  - 每次输入变化按门延迟独立排一次求值（传输延迟）；
##  - 输出值不变则不写线网（自然合并；窄于门延迟的脉冲会被滤除）；
##  - 历史记录 (tick, wire, old, new)，供示波器与回放。

var name := "circuit"
var eng: SimEngine
var wires: Dictionary = {}
var history: Array = []
var glitches: Array = []
var input_names: Array = []
var output_names: Array = []

var _watch: Dictionary = {}

func _init(p_name: String = "circuit", per_tick_limit: int = -1) -> void:
	name = p_name
	eng = SimEngine.new(per_tick_limit)

func add_wire(wire_name: String, init: String = SimValue.X) -> Dictionary:
	if wires.has(wire_name):
		return wires[wire_name]
	var w := {"bits": init, "prev": init, "last_change": -1073741824, "listeners": []}
	wires[wire_name] = w
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
	return eng.pending()

func is_quiescent() -> bool:
	return eng.pending() == 0

func set_input(wire_name: String, bits: String, delay: int = 0) -> void:
	if not wires.has(wire_name):
		add_wire(wire_name, SimValue.X)
	eng.schedule_after(delay, Callable(self, "_drive"), [wire_name, bits])

func _drive(wire_name: String, bits: String) -> void:
	_write(wire_name, bits)

func _write(wire_name: String, bits: String) -> void:
	if not wires.has(wire_name):
		add_wire(wire_name, SimValue.X)
	var w: Dictionary = wires[wire_name]
	if str(w["bits"]) == bits:
		return
	var old := str(w["bits"])
	w["prev"] = old
	w["bits"] = bits
	w["last_change"] = eng.now
	history.append({"t": eng.now, "wire": wire_name, "old": old, "new": bits})
	if _watch.has(wire_name):
		glitches.append({"t": eng.now, "wire": wire_name, "value": bits})
	var listeners: Array = w["listeners"].duplicate()
	for cb in listeners:
		if cb is Callable and cb.is_valid():
			cb.call(old, eng.now)

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
	add_wire(gate_name, SimValue.X)
	var compute := func(_arrive: int) -> void:
		var vals: Array = []
		for src in ins:
			vals.append(probe(str(src)))
		_write(gate_name, SimValue.gate(kind, vals))
	var evaluate := func(_old: String, t: int) -> void:
		eng.schedule(t + d, compute, [t])
	for src in ins:
		add_wire(str(src), SimValue.X)
		var w: Dictionary = wires[str(src)]
		w["listeners"].append(evaluate)
	eng.schedule(eng.now, compute, [eng.now])
	return gate_name

func add_dff(cell_name: String, d_src: String, clk_src: String, delay: int = -1) -> String:
	## D 触发器（上升沿采样）：
	##  - 初值 X；clk 由 0/X→1 时把 d_src 当前值经 clk_to_q 延迟写入 Q（cell_name 本身）；
	##  - 不是门级展开，故不会形成组合环，L3 时序层可直接复用 L1 的确定性调度。
	if wires.has(cell_name) and wires.has(clk_src):
		return ""
	var d := SimDelays.dff_delay() if delay < 0 else delay
	add_wire(cell_name, SimValue.X)
	add_wire(str(d_src), SimValue.X)
	add_wire(clk_src, SimValue.X)
	var on_clk := func(old: String, _t: int) -> void:
		if old == SimValue.ONE:
			return
		if probe(clk_src) != SimValue.ONE:
			return
		eng.schedule_after(d, Callable(self, "_write"), [cell_name, probe(str(d_src))])
	var w: Dictionary = wires[clk_src]
	w["listeners"].append(on_clk)
	return cell_name

func run(ticks: int) -> Dictionary:
	return eng.run_until(eng.now + ticks)

func run_until(t: int) -> Dictionary:
	return eng.run_until(t)

func settle() -> Dictionary:
	return eng.run_events()

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
