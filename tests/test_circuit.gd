extends RefCounted

func run(ctx: TestContext) -> void:
	var g := HalfAdder.build()
	var res := HalfAdder.validate(g)
	ctx.check("half adder valid", bool(res["ok"]), str(res["issues"]))
	ctx.eq("half adder rows", res["rows"].size(), 4)

	var row0: Dictionary = res["rows"][0]
	ctx.eq("row 0+0 sum", bool(row0["sum"]), false)
	ctx.eq("row 0+0 carry", bool(row0["carry"]), false)
	var row3: Dictionary = res["rows"][3]
	ctx.eq("row 1+1 sum", bool(row3["sum"]), false)
	ctx.eq("row 1+1 carry", bool(row3["carry"]), true)

	ctx.eq("query 1+0 sum", bool(HalfAdder.build().evaluate()["values"]["sum"]), false)
	g.set_input_value("a", true)
	g.set_input_value("b", false)
	var ev := g.evaluate()
	ctx.eq("1+0 sum = 1", bool(ev["values"]["sum"]), true)
	ctx.eq("1+0 carry = 0", bool(ev["values"]["carry"]), false)
	ctx.eq("inputs listed", g.input_ids().size(), 2)

	var cyclic := CircuitGraph.new()
	cyclic.add_gate("n1", LogicGates.Type.NOT)
	cyclic.add_gate("n2", LogicGates.Type.NOT)
	cyclic.link("n1", "n2", 0)
	cyclic.link("n2", "n1", 0)
	var cyc := cyclic.evaluate()
	ctx.check("cycle detected", not bool(cyc["ok"]))
	ctx.check("cycle reported", cyc["cycles"].size() > 0)

	var loose := CircuitGraph.new()
	loose.add_gate("g", LogicGates.Type.AND)
	var lv := loose.evaluate()
	ctx.check("unconnected detected", lv["unconnected"].size() == 2)

	var wires := CircuitGraph.new()
	wires.add_input("a", "A")
	wires.add_output("o", "O")
	var c1 := wires.link("a", "o", 0)
	ctx.check("connect ok", bool(c1["ok"]))
	wires.add_input("b", "B")
	var c2 := wires.link("b", "o", 0)
	ctx.check("replace ok", bool(c2["ok"]))
	ctx.eq("replaced id", str(c2["replaced"]), "a")

	ctx.check("connect to input rejected", not bool(wires.link("a", "b", 0)["ok"]))
	ctx.check("connect from output rejected", not bool(wires.link("o", "a", 0)["ok"]))
	ctx.check("self connect rejected", not bool(wires.link("a", "a", 0)["ok"]))

	var rem := HalfAdder.build()
	rem.remove_node("g_xor")
	ctx.check("removed gate", not rem.has_node("g_xor"))
	ctx.eq("wire cleared after removal", str(rem.get_node("sum")["a"]), "")

	var bad_gate := HalfAdder.build()
	bad_gate.set_gate_type("g_xor", LogicGates.Type.OR)
	var bad := HalfAdder.validate(bad_gate)
	ctx.check("wrong gate rejected", not bool(bad["ok"]))
	ctx.eq("wrong gate rows", bad["rows"].size(), 4)
