class_name CircuitGraph
extends RefCounted

## 组合逻辑电路图：节点 + 连线 + 拓扑求值。
## 只做纯逻辑，不依赖渲染；UI 层只负责坐标与交互。

const KIND_INPUT := "input"
const KIND_GATE := "gate"
const KIND_OUTPUT := "output"

var nodes: Dictionary = {}

func clear() -> void:
	nodes.clear()

func add_input(id: String, label: String = "", pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var node := {"id": id, "kind": KIND_INPUT, "gate": -1, "label": label, "pos": pos, "a": "", "b": "", "value": false}
	nodes[id] = node
	return node

func add_gate(id: String, gate_type: int, label: String = "", pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var node := {"id": id, "kind": KIND_GATE, "gate": gate_type, "label": label, "pos": pos, "a": "", "b": "", "value": false}
	nodes[id] = node
	return node

func add_output(id: String, label: String = "", pos: Vector2 = Vector2.ZERO) -> Dictionary:
	var node := {"id": id, "kind": KIND_OUTPUT, "gate": -1, "label": label, "pos": pos, "a": "", "b": "", "value": false}
	nodes[id] = node
	return node

func has_node(id: String) -> bool:
	return nodes.has(id)

func get_node(id: String) -> Dictionary:
	return nodes.get(id, {})

func remove_node(id: String) -> void:
	if not nodes.has(id):
		return
	nodes.erase(id)
	for other_id in nodes.keys():
		var n: Dictionary = nodes[other_id]
		if str(n.a) == id:
			n.a = ""
		if str(n.b) == id:
			n.b = ""

func set_input_value(id: String, v: bool) -> bool:
	if not nodes.has(id) or str(nodes[id].kind) != KIND_INPUT:
		return false
	nodes[id].value = v
	return true

func get_input_value(id: String) -> bool:
	if not nodes.has(id):
		return false
	return bool(nodes[id].value)

func set_gate_type(id: String, gate_type: int) -> bool:
	if not nodes.has(id) or str(nodes[id].kind) != KIND_GATE:
		return false
	nodes[id].gate = gate_type
	return true

func gate_type(id: String) -> int:
	if not nodes.has(id):
		return -1
	return int(nodes[id].gate)

func link(from_id: String, to_id: String, port: int) -> Dictionary:
	if not nodes.has(from_id) or not nodes.has(to_id):
		return {"ok": false, "error": "节点不存在", "replaced": ""}
	var src: Dictionary = nodes[from_id]
	var dst: Dictionary = nodes[to_id]
	if from_id == to_id:
		return {"ok": false, "error": "不能把节点接到自己", "replaced": ""}
	if str(src.kind) == KIND_OUTPUT:
		return {"ok": false, "error": "输出节点只能作为终点", "replaced": ""}
	if str(dst.kind) == KIND_INPUT:
		return {"ok": false, "error": "输入节点只能作为起点", "replaced": ""}
	if str(dst.kind) == KIND_OUTPUT and port != 0:
		return {"ok": false, "error": "灯只有一个输入端口", "replaced": ""}
	if str(dst.kind) == KIND_GATE and (port < 0 or port > 1):
		return {"ok": false, "error": "门电路端口必须是 0 或 1", "replaced": ""}
	var old := ""
	if port == 0:
		old = str(dst.a)
		dst.a = from_id
	else:
		old = str(dst.b)
		dst.b = from_id
	return {"ok": true, "error": "", "replaced": old}

func unlink(to_id: String, port: int) -> bool:
	if not nodes.has(to_id):
		return false
	var dst: Dictionary = nodes[to_id]
	if port == 0:
		if str(dst.a).is_empty():
			return false
		dst.a = ""
		return true
	if port == 1:
		if str(dst.b).is_empty():
			return false
		dst.b = ""
		return true
	return false

func evaluate() -> Dictionary:
	var values := {}
	var cycles := []
	var loose := []
	var visiting := {}
	for id in nodes.keys():
		_evaluate_node(str(id), values, visiting, cycles, loose)
	return {"ok": cycles.is_empty(), "values": values, "cycles": cycles, "unconnected": loose}

func _evaluate_node(id: String, values: Dictionary, visiting: Dictionary, cycles: Array, loose: Array) -> bool:
	if values.has(id):
		return true
	if visiting.has(id):
		cycles.append(id)
		return false
	if not nodes.has(id):
		return false
	visiting[id] = true
	var n: Dictionary = nodes[id]
	var v := false
	match str(n.kind):
		KIND_INPUT:
			v = bool(n.value)
		KIND_OUTPUT:
			var src := str(n.a)
			if src.is_empty():
				loose.append("%s.in" % id)
			else:
				_evaluate_node(src, values, visiting, cycles, loose)
				v = bool(values.get(src, false))
		KIND_GATE:
			var ga := str(n.a)
			var gb := str(n.b)
			var va := false
			var vb := false
			if ga.is_empty():
				loose.append("%s.a" % id)
			else:
				_evaluate_node(ga, values, visiting, cycles, loose)
				va = bool(values.get(ga, false))
			if LogicGates.arity(int(n.gate)) > 1:
				if gb.is_empty():
					loose.append("%s.b" % id)
				else:
					_evaluate_node(gb, values, visiting, cycles, loose)
					vb = bool(values.get(gb, false))
			v = LogicGates.evaluate(int(n.gate), va, vb)
	visiting.erase(id)
	values[id] = v
	return true

func outputs() -> Dictionary:
	var out := {}
	for id in nodes.keys():
		if str(nodes[id].kind) == KIND_OUTPUT:
			out[str(id)] = bool(nodes[id].value)
	return out

func input_ids() -> Array:
	var out := []
	for id in nodes.keys():
		if str(nodes[id].kind) == KIND_INPUT:
			out.append(str(id))
	return out
