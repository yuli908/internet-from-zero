class_name HalfAdder
extends RefCounted

## 半加器：SUM = A XOR B, CARRY = A AND B。
## 既提供标准实现，也提供对玩家电路的判定。

const NODE_A := "a"
const NODE_B := "b"
const NODE_SUM := "sum"
const NODE_CARRY := "carry"

static func build() -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input(NODE_A, "A")
	g.add_input(NODE_B, "B")
	g.add_gate("g_xor", LogicGates.Type.XOR, "XOR")
	g.add_gate("g_and", LogicGates.Type.AND, "AND")
	g.add_output(NODE_SUM, "SUM")
	g.add_output(NODE_CARRY, "CARRY")
	g.link(NODE_A, "g_xor", 0)
	g.link(NODE_B, "g_xor", 1)
	g.link(NODE_A, "g_and", 0)
	g.link(NODE_B, "g_and", 1)
	g.link("g_xor", NODE_SUM, 0)
	g.link("g_and", NODE_CARRY, 0)
	return g

static func expected_sum(a: bool, b: bool) -> bool:
	return a != b

static func expected_carry(a: bool, b: bool) -> bool:
	return a and b

static func truth_table() -> Array:
	var rows := []
	for a in [false, true]:
		for b in [false, true]:
			rows.append({
				"a": a,
				"b": b,
				"sum": expected_sum(a, b),
				"carry": expected_carry(a, b),
			})
	return rows

static func validate(graph: CircuitGraph, a_id: String = NODE_A, b_id: String = NODE_B, sum_id: String = NODE_SUM, carry_id: String = NODE_CARRY) -> Dictionary:
	var rows := []
	var ok := true
	var issues := []
	for id in [a_id, b_id, sum_id, carry_id]:
		if not graph.has_node(id):
			issues.append("缺少节点 %s" % id)
			return {"ok": false, "rows": [], "issues": issues}
	for a in [false, true]:
		for b in [false, true]:
			graph.set_input_value(a_id, a)
			graph.set_input_value(b_id, b)
			var ev := graph.evaluate()
			var sum := bool(ev.values.get(sum_id, false))
			var carry := bool(ev.values.get(carry_id, false))
			var want_sum := expected_sum(a, b)
			var want_carry := expected_carry(a, b)
			rows.append({
				"a": a, "b": b, "sum": sum, "carry": carry,
				"want_sum": want_sum, "want_carry": want_carry,
				"pass": sum == want_sum and carry == want_carry,
			})
			if sum != want_sum or carry != want_carry:
				ok = false
	if not ok:
		issues.append("输出不符合半加器真值表")
	if not ev_has_no_cycles(graph):
		issues.append("电路存在反馈回路")
		ok = false
	graph.set_input_value(a_id, false)
	graph.set_input_value(b_id, false)
	return {"ok": ok, "rows": rows, "issues": issues}

static func ev_has_no_cycles(graph: CircuitGraph) -> bool:
	var ev := graph.evaluate()
	return bool(ev.ok)
