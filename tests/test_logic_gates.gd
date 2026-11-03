extends RefCounted

func run(ctx: TestContext) -> void:
	ctx.eq("AND signature", LogicGates.signature(LogicGates.Type.AND), "0001")
	ctx.eq("OR signature", LogicGates.signature(LogicGates.Type.OR), "0111")
	ctx.eq("XOR signature", LogicGates.signature(LogicGates.Type.XOR), "0110")
	ctx.eq("NAND signature", LogicGates.signature(LogicGates.Type.NAND), "1110")
	ctx.eq("NOR signature", LogicGates.signature(LogicGates.Type.NOR), "1000")
	ctx.eq("XNOR signature", LogicGates.signature(LogicGates.Type.XNOR), "1001")

	ctx.check("NOT false->true", LogicGates.evaluate(LogicGates.Type.NOT, false))
	ctx.check("NOT true->false", not LogicGates.evaluate(LogicGates.Type.NOT, true))
	ctx.check("AND 1 1", LogicGates.evaluate(LogicGates.Type.AND, true, true))
	ctx.check("AND 1 0", not LogicGates.evaluate(LogicGates.Type.AND, true, false))
	ctx.check("OR 0 1", LogicGates.evaluate(LogicGates.Type.OR, false, true))
	ctx.check("XOR 1 1 false", not LogicGates.evaluate(LogicGates.Type.XOR, true, true))

	ctx.eq("arity NOT", LogicGates.arity(LogicGates.Type.NOT), 1)
	ctx.eq("arity AND", LogicGates.arity(LogicGates.Type.AND), 2)
	ctx.eq("NOT table rows", LogicGates.truth_table(LogicGates.Type.NOT).size(), 2)
	ctx.eq("AND table rows", LogicGates.truth_table(LogicGates.Type.AND).size(), 4)
	ctx.eq("AND first row false", bool(LogicGates.truth_table(LogicGates.Type.AND)[0]["out"]), false)
	ctx.eq("AND last row true", bool(LogicGates.truth_table(LogicGates.Type.AND)[3]["out"]), true)

	ctx.eq("from_string and", LogicGates.from_string("and"), LogicGates.Type.AND)
	ctx.eq("from_string XOR", LogicGates.from_string("XOR"), LogicGates.Type.XOR)
	ctx.eq("from_string bad", LogicGates.from_string("nope"), -1)
	ctx.eq("gate key", LogicGates.gate_key(LogicGates.Type.XOR), "XOR")
	ctx.eq("display name", LogicGates.display_name(LogicGates.Type.AND), "与门")
	ctx.eq("symbol name", LogicGates.display_name(LogicGates.Type.XOR), "异或门")
