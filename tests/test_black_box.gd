extends RefCounted

## 行为黑盒：多解、错误拓扑、签名、半加器三值。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 18
const EXPECT_GROUPS := {
	"structure": 2, "check_target": 5, "multi_solution": 5,
	"half_adder": 2, "tri_eval": 4,
}
const GROUP_DESCRIPTIONS := {
	"structure": "AND 图的 gate_count 与 depth 各为 1",
	"check_target": "and/or/not 三种目标判定通过、AND 行数 4、以 AND 冒充 XOR 的错误拓扑被拒",
	"multi_solution": "两种 XOR 接线都判过、A 版行数 4、两解签名互异、B 版恰 4 门",
	"half_adder": "半加器 4 行真值表全过与 passed 计数",
	"tri_eval": "含 X 的三值求值：1,X 与 0,X 下 sum/carry 均为 X",
}

func run(ctx: TestContext) -> void:
	var and_g := _and_graph()
	var or_g := _or_graph()
	var not_g := _not_graph()
	var bad := _xor_bad_graph()
	ctx.begin_group("structure")
	ctx.eq("gate count and", BlackBox.gate_count(and_g), 1)
	ctx.eq("depth and", BlackBox.depth(and_g), 1)

	ctx.begin_group("check_target")
	var r_and := BlackBox.check_target(and_g, "and", ["a", "b"], ["out"])
	ctx.check("and target pass", bool(r_and.get("ok", false)), str(r_and.get("issues", "")))
	ctx.eq("and rows", int(r_and.get("passed", 0)), 4)
	var r_or := BlackBox.check_target(or_g, "or", ["a", "b"], ["out"])
	ctx.check("or target pass", bool(r_or.get("ok", false)))
	var r_not := BlackBox.check_target(not_g, "not", ["a"], ["out"])
	ctx.check("not target pass", bool(r_not.get("ok", false)))
	var r_bad := BlackBox.check_target(bad, "xor", ["a", "b"], ["out"])
	ctx.check("wrong topology fails", not bool(r_bad.get("ok", false)))

	ctx.begin_group("multi_solution")
	var x1 := _xor_graph_a()
	var x2 := _xor_graph_b()
	var r1 := BlackBox.check_target(x1, "xor", ["a", "b"], ["out"])
	var r2 := BlackBox.check_target(x2, "xor", ["a", "b"], ["out"])
	ctx.check("xor solution A", bool(r1.get("ok", false)), str(r1.get("issues", "")))
	ctx.check("xor solution B", bool(r2.get("ok", false)), str(r2.get("issues", "")))
	ctx.eq("xor A rows", int(r1.get("passed", 0)), 4)
	ctx.ne("solutions differ", BlackBox.signature(x1), BlackBox.signature(x2))
	ctx.check("xor B has 4 gates", BlackBox.gate_count(x2) == 4)

	ctx.begin_group("half_adder")
	var ha := _half_adder_graph()
	var ha_rows := BlackBox.check_outputs(ha, ["a", "b"], ["sum", "carry"], BlackBox.half_adder_rows())
	ctx.check("half adder 4 rows", bool(ha_rows.get("ok", false)))
	ctx.eq("half adder total rows", int(ha_rows.get("total", 0)), 4)
	ctx.begin_group("tri_eval")
	var tri := BlackBox.tri_eval(ha, {"a": "1", "b": "X"})
	ctx.check("tri eval ok", bool(tri.get("ok", false)))
	ctx.eq("xor 1,X", str(tri.get("values", {}).get("sum", "")), "X")
	ctx.eq("and 1,X", str(tri.get("values", {}).get("carry", "")), "X")
	var tri0 := BlackBox.tri_eval(ha, {"a": "0", "b": "X"})
	ctx.eq("xor 0,X", str(tri0.get("values", {}).get("sum", "")), "X")

func _base_graph() -> CircuitGraph:
	return CircuitGraph.new()

func _and_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _or_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("or"), "OR", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _not_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_gate("g1", LogicGates.from_string("not"), "NOT", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _xor_bad_graph() -> CircuitGraph:
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(120, 20))
	g.link("a", "g1", 0)
	g.link("b", "g1", 1)
	g.add_output("out", "OUT", Vector2(240, 20))
	g.link("g1", "out", 0)
	return g

func _xor_graph_a() -> CircuitGraph:
	## (a ∧ ¬b) ∨ (¬a ∧ b)
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("na", LogicGates.from_string("not"), "NOT", Vector2(90, -20))
	g.add_gate("nb", LogicGates.from_string("not"), "NOT", Vector2(90, 80))
	g.add_gate("p1", LogicGates.from_string("and"), "AND", Vector2(200, 0))
	g.add_gate("p2", LogicGates.from_string("and"), "AND", Vector2(200, 100))
	g.add_gate("o1", LogicGates.from_string("or"), "OR", Vector2(320, 40))
	g.link("a", "na", 0)
	g.link("b", "nb", 0)
	g.link("a", "p1", 0)
	g.link("nb", "p1", 1)
	g.link("na", "p2", 0)
	g.link("b", "p2", 1)
	g.link("p1", "o1", 0)
	g.link("p2", "o1", 1)
	g.add_output("out", "OUT", Vector2(440, 40))
	g.link("o1", "out", 0)
	return g

func _xor_graph_b() -> CircuitGraph:
	## (a ∨ b) ∧ ¬(a ∧ b)
	var g := _base_graph()
	g.add_input("a", "A", Vector2(0, 0))
	g.add_input("b", "B", Vector2(0, 60))
	g.add_gate("n1", LogicGates.from_string("and"), "AND", Vector2(90, 10))
	g.add_gate("n2", LogicGates.from_string("not"), "NOT", Vector2(200, 10))
	g.add_gate("o1", LogicGates.from_string("or"), "OR", Vector2(90, 100))
	g.add_gate("g1", LogicGates.from_string("and"), "AND", Vector2(320, 40))
	g.link("a", "n1", 0)
	g.link("b", "n1", 1)
	g.link("n1", "n2", 0)
	g.link("a", "o1", 0)
	g.link("b", "o1", 1)
	g.link("o1", "g1", 0)
	g.link("n2", "g1", 1)
	g.add_output("out", "OUT", Vector2(440, 40))
	g.link("g1", "out", 0)
	return g

func _half_adder_graph() -> CircuitGraph:
	var g := _xor_graph_b()
	g.add_gate("g_carry", LogicGates.from_string("and"), "AND", Vector2(320, 140))
	g.link("a", "g_carry", 0)
	g.link("b", "g_carry", 1)
	g.add_output("sum", "SUM", Vector2(440, 40))
	g.link("g1", "sum", 0)
	g.add_output("carry", "CARRY", Vector2(440, 140))
	g.link("g_carry", "carry", 0)
	return g
