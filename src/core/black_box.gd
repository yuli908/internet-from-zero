class_name BlackBox
extends RefCounted

## 行为黑盒验收：只按"给定输入组合 → 输出位"判断，不匹配拓扑与标准答案。
## 因此同一目标允许多条正确路径（多解），拓扑签名只用于统计"不同结构"。
## 仿真语义复用 SimCircuit（L1 归一化门延迟 + 三值 Kleene），与参考实现一致。

const MAX_SETTLE := 400

static func rows_for(inputs: Array, bits: Array = []) -> Array:
	var use := bits if not bits.is_empty() else ["0", "1"]
	var rows := [{}]
	for id in inputs:
		var next := []
		for r in rows:
			for b in use:
				var nr: Dictionary = (r as Dictionary).duplicate()
				nr[str(id)] = str(b)
				next.append(nr)
		rows = next
	return rows

static func check_outputs(graph: CircuitGraph, input_ids: Array, output_ids: Array, expected: Array, delay_per_gate: int = -1) -> Dictionary:
	if graph == null:
		return _failed("电路为空", GateResult.E_MISSING_GRAPH, null, null, null, expected.size())
	var loose := unconnected(graph)
	if not loose.is_empty():
		return _failed("有输入未连接：%s" % JSON.stringify(loose), GateResult.E_UNCONNECTED,
			{"unconnected": loose}, "所有输入已连接", loose, expected.size())
	var built := SimCircuit.build_graph(graph, delay_per_gate)
	if not bool(built.get("ok", false)):
		return _failed(str(built.get("error", "构建失败")), GateResult.E_BUILD,
			{"graph": "build"}, "可构建", str(built.get("error", "")), expected.size())
	var sim: SimCircuit = built["sim"]
	var map: Dictionary = built.get("output_map", {})
	var results := []
	var issues := []
	var passed := 0
	var first: Dictionary = {}
	for raw in expected:
		var row: Dictionary = raw
		var ins: Dictionary = row.get("inputs", {})
		var exp: Dictionary = row.get("outputs", {})
		for id in ins.keys():
			sim.set_input(str(id), str(ins[id]))
		var rr := sim.settle()
		if not bool(rr.get("ok", false)):
			issues.append("仿真失败：%s" % str(rr.get("error", "")))
			if first.is_empty():
				first = {"code": GateResult.E_BUILD, "gate_id": "", "input": ins,
					"expected": exp, "actual": str(rr.get("error", "")), "error_tags": GateResult.tags_for(GateResult.E_BUILD), "attempt": 0}
			break
		var got := {}
		var ok := true
		for oid in output_ids:
			var wire := str(map.get(str(oid), ""))
			var v := sim.probe(wire) if not wire.is_empty() else SimValue.X
			got[str(oid)] = v
			if exp.has(str(oid)) and str(exp[str(oid)]) != v:
				ok = false
		if ok:
			passed += 1
		else:
			issues.append("输入 %s：期望 %s，实际 %s" % [JSON.stringify(ins), JSON.stringify(exp), JSON.stringify(got)])
			if first.is_empty():
				first = {"code": GateResult.E_TRUTH_ROW, "gate_id": "", "input": ins,
					"expected": exp, "actual": got, "error_tags": GateResult.tags_for(GateResult.E_TRUTH_ROW), "attempt": 0}
		results.append({"inputs": ins, "expected": exp, "got": got, "ok": ok})
		sim = SimCircuit.build_graph(graph, delay_per_gate)["sim"]
		# 每行重建仿真器，避免历史值掩盖 X；重建后重新设置输入
	if not first.is_empty():
		first["code_name"] = GateResult.name_of(int(first["code"]))
	var code := GateResult.E_TRUTH_ROW if not first.is_empty() else GateResult.OK
	return {"ok": passed == expected.size() and issues.is_empty(), "rows": results, "issues": issues,
		"passed": passed, "total": expected.size(), "code": code, "failure": first}

static func _failed(msg: String, code: int, input: Variant, expected: Variant, actual: Variant, total: int) -> Dictionary:
	var f := GateResult.make(code, "", input, expected, actual, 0)
	return {"ok": false, "rows": [], "issues": [msg], "passed": 0, "total": total, "code": code, "failure": f}

static func unconnected(graph: CircuitGraph) -> Array:
	## 哪条线未连接：返回悬空输入节点 id 列表（空 = 全部连接）。
	if graph == null:
		return []
	var r := graph.evaluate()
	var loose: Variant = r.get("unconnected", [])
	return (loose as Array).duplicate() if loose is Array else []


static func check_target(graph: CircuitGraph, target: String, input_ids: Array, output_ids: Array, delay_per_gate: int = -1) -> Dictionary:
	var expected := target_rows(target, input_ids)
	if expected.is_empty():
		return _failed("未知目标函数 %s" % target, GateResult.E_UNKNOWN_TARGET,
			{"target": target}, "已知目标函数", target, 0)
	return check_outputs(graph, input_ids, output_ids, expected, delay_per_gate)

static func target_rows(target: String, input_ids: Array) -> Array:
	if target == "not":
		return [
			{"inputs": {str(input_ids[0]): "0"}, "outputs": {"out": "1"}},
			{"inputs": {str(input_ids[0]): "1"}, "outputs": {"out": "0"}},
		]
	if target == "buf":
		return [
			{"inputs": {str(input_ids[0]): "0"}, "outputs": {"out": "0"}},
			{"inputs": {str(input_ids[0]): "1"}, "outputs": {"out": "1"}},
		]
	var rows := []
	for a in ["0", "1"]:
		for b in ["0", "1"]:
			rows.append({"inputs": {str(input_ids[0]): a, str(input_ids[1]): b}, "outputs": {"out": SimValue.gate(target, [a, b])}})
	return rows

static func half_adder_rows() -> Array:
	var rows := []
	for a in ["0", "1"]:
		for b in ["0", "1"]:
			rows.append({
				"inputs": {"a": a, "b": b},
				"outputs": {"sum": SimValue.gate("xor", [a, b]), "carry": SimValue.gate("and", [a, b])},
			})
	return rows

static func half_adder_tri(a: String, b: String) -> Dictionary:
	var s := SimValue.gate("xor", [a, b])
	var c := SimValue.gate("and", [a, b])
	return {"sum": s, "carry": c}

static func tri_eval(graph: CircuitGraph, values: Dictionary, delay_per_gate: int = -1) -> Dictionary:
	var built := SimCircuit.build_graph(graph, delay_per_gate)
	if not bool(built.get("ok", false)):
		return {"ok": false, "values": {}, "error": str(built.get("error", "")),
			"code": GateResult.E_BUILD, "failure": GateResult.make(GateResult.E_BUILD, "", values, "可构建", str(built.get("error", "")))}
	var sim: SimCircuit = built["sim"]
	var map: Dictionary = built.get("output_map", {})
	for id in values.keys():
		sim.set_input(str(id), str(values[id]))
	var rr := sim.settle()
	if not bool(rr.get("ok", false)):
		return {"ok": false, "values": {}, "error": str(rr.get("error", "")),
			"code": GateResult.E_BUILD, "failure": GateResult.make(GateResult.E_BUILD, "", values, "可仿真", str(rr.get("error", "")))}
	var out := {}
	for oid in map.keys():
		out[str(oid)] = sim.probe(str(map[oid]))
	return {"ok": true, "values": out, "error": "", "code": GateResult.OK, "failure": {}}

static func depth(graph: CircuitGraph) -> int:
	var memo := {}
	var visiting := {}
	var deepest := 0
	for oid in graph.output_ids():
		var n: Dictionary = graph.nodes[oid]
		var src := str(n.get("a", ""))
		if not src.is_empty():
			deepest = maxi(deepest, _walk_depth(graph, src, memo, visiting))
	return deepest

static func _walk_depth(graph: CircuitGraph, id: String, memo: Dictionary, visiting: Dictionary) -> int:
	if memo.has(id):
		return int(memo[id])
	if visiting.has(id):
		return 999
	if not graph.nodes.has(id):
		return 0
	visiting[id] = true
	var n: Dictionary = graph.nodes[id]
	var best := 0
	if str(n["kind"]) == CircuitGraph.KIND_GATE:
		var a := str(n["a"])
		var b := str(n["b"])
		if not a.is_empty():
			best = maxi(best, _walk_depth(graph, a, memo, visiting))
		if not b.is_empty() and LogicGates.arity(int(n["gate"])) > 1:
			best = maxi(best, _walk_depth(graph, b, memo, visiting))
		best += 1
	visiting.erase(id)
	memo[id] = best
	return best

static func signature(graph: CircuitGraph) -> String:
	var parts := []
	var keys := graph.nodes.keys()
	keys.sort()
	for id in keys:
		var n: Dictionary = graph.nodes[id]
		var kind := str(n["kind"])
		if kind == CircuitGraph.KIND_GATE:
			parts.append("G:%s:%s:%s:%s" % [id, str(n["gate"]), str(n["a"]), str(n["b"])])
		elif kind == CircuitGraph.KIND_OUTPUT:
			parts.append("O:%s:%s" % [id, str(n["a"])])
		elif kind == CircuitGraph.KIND_INPUT:
			parts.append("I:%s" % id)
	return "|".join(parts)

static func gate_count(graph: CircuitGraph) -> int:
	return graph.gate_ids().size()

static func estimate_delay(graph: CircuitGraph, delay_per_gate: int = -1) -> int:
	var d := depth(graph)
	if delay_per_gate > 0:
		return d * delay_per_gate
	return d
