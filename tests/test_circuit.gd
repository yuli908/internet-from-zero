extends RefCounted

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 33
const EXPECT_GROUPS := {
	"half_adder": 2, "half_adder_rows": 4, "evaluate": 4, "cycle": 2, "unconnected": 1,
	"wire_link": 3, "wire_reject": 3, "gate_removal": 2, "gate_type_validation": 2,
	"limits": 2, "editor_cap": 3, "over_soft_cap": 3, "over_hard_cap": 2,
}
const GROUP_DESCRIPTIONS := {
	"half_adder": "半加器构建校验通过且真值表 4 行",
	"half_adder_rows": "真值表首行与末行的 sum/carry 输出",
	"evaluate": "改输入后求值、输入端子列表",
	"cycle": "环形连线被判为环并报出环",
	"unconnected": "未接线的门报告 2 个未连接端子",
	"wire_link": "连线成功、同槽位替换旧连线并回报被替换者",
	"wire_reject": "连到输入/输出来源、自连均被拒",
	"gate_removal": "删除门后节点消失且相关导线清空",
	"gate_type_validation": "门类型被篡改后校验失败但仍给出 4 行",
	"limits": "门数默认上限 50、绝对上限 80",
	"editor_cap": "编辑器门数上限取自 SimDelays，超硬上限被夹到 80，更严格 lab 上限保留",
	"over_soft_cap": "超过 50 门时提示结构级表示并拒绝构建",
	"over_hard_cap": "超过 80 门时拒绝构建并给出 IFZ_E_SCALE",
}

func run(ctx: TestContext) -> void:
	ctx.begin_group("half_adder")
	var g := HalfAdder.build()
	var res := HalfAdder.validate(g)
	ctx.check("half adder valid", bool(res["ok"]), str(res["issues"]))
	ctx.eq("half adder rows", res["rows"].size(), 4)

	ctx.begin_group("half_adder_rows")
	var row0: Dictionary = res["rows"][0]
	ctx.eq("row 0+0 sum", bool(row0["sum"]), false)
	ctx.eq("row 0+0 carry", bool(row0["carry"]), false)
	var row3: Dictionary = res["rows"][3]
	ctx.eq("row 1+1 sum", bool(row3["sum"]), false)
	ctx.eq("row 1+1 carry", bool(row3["carry"]), true)

	ctx.begin_group("evaluate")
	ctx.eq("query 1+0 sum", bool(HalfAdder.build().evaluate()["values"]["sum"]), false)
	g.set_input_value("a", true)
	g.set_input_value("b", false)
	var ev := g.evaluate()
	ctx.eq("1+0 sum = 1", bool(ev["values"]["sum"]), true)
	ctx.eq("1+0 carry = 0", bool(ev["values"]["carry"]), false)
	ctx.eq("inputs listed", g.input_ids().size(), 2)

	ctx.begin_group("cycle")
	var cyclic := CircuitGraph.new()
	cyclic.add_gate("n1", LogicGates.Type.NOT)
	cyclic.add_gate("n2", LogicGates.Type.NOT)
	cyclic.link("n1", "n2", 0)
	cyclic.link("n2", "n1", 0)
	var cyc := cyclic.evaluate()
	ctx.check("cycle detected", not bool(cyc["ok"]))
	ctx.check("cycle reported", cyc["cycles"].size() > 0)

	ctx.begin_group("unconnected")
	var loose := CircuitGraph.new()
	loose.add_gate("g", LogicGates.Type.AND)
	var lv := loose.evaluate()
	ctx.check("unconnected detected", lv["unconnected"].size() == 2)

	ctx.begin_group("wire_link")
	var wires := CircuitGraph.new()
	wires.add_input("a", "A")
	wires.add_output("o", "O")
	var c1 := wires.link("a", "o", 0)
	ctx.check("connect ok", bool(c1["ok"]))
	wires.add_input("b", "B")
	var c2 := wires.link("b", "o", 0)
	ctx.check("replace ok", bool(c2["ok"]))
	ctx.eq("replaced id", str(c2["replaced"]), "a")

	ctx.begin_group("wire_reject")
	ctx.check("connect to input rejected", not bool(wires.link("a", "b", 0)["ok"]))
	ctx.check("connect from output rejected", not bool(wires.link("o", "a", 0)["ok"]))
	ctx.check("self connect rejected", not bool(wires.link("a", "a", 0)["ok"]))

	ctx.begin_group("gate_removal")
	var rem := HalfAdder.build()
	rem.remove_node("g_xor")
	ctx.check("removed gate", not rem.has_node("g_xor"))
	ctx.eq("wire cleared after removal", str(rem.get_node("sum")["a"]), "")

	ctx.begin_group("gate_type_validation")
	var bad_gate := HalfAdder.build()
	bad_gate.set_gate_type("g_xor", LogicGates.Type.OR)
	var bad := HalfAdder.validate(bad_gate)
	ctx.check("wrong gate rejected", not bool(bad["ok"]))
	ctx.eq("wrong gate rows", bad["rows"].size(), 4)

	# M3-G15：门级交互上限（默认 50 / 绝对上限 80，与 SimDelays 同源）
	ctx.begin_group("limits")
	ctx.check("gdscript gate limit is 50", SimDelays.gdscript_gate_limit() == 50)
	ctx.check("gdscript hard cap is 80", SimDelays.gdscript_gate_hard_cap() == 80)
	ctx.begin_group("editor_cap")
	var ed := CircuitEditor.new()
	ed.setup([{"id": "a", "label": "A"}], [{"id": "out", "label": "O"}], ["and"])
	ctx.eq("editor cap from delays", ed.max_gates, SimDelays.gdscript_gate_limit())
	ed.setup([{"id": "a", "label": "A"}], [{"id": "out", "label": "O"}], ["and"], 500)
	ctx.eq("editor cap clamped to hard cap", ed.max_gates, SimDelays.gdscript_gate_hard_cap())
	ed.setup([{"id": "a", "label": "A"}], [{"id": "out", "label": "O"}], ["and"], 8)
	ctx.eq("editor cap keeps stricter lab limit", ed.max_gates, 8)
	ed.setup([{"id": "a", "label": "A"}], [{"id": "out", "label": "O"}], ["and"])
	ctx.begin_group("over_soft_cap")
	for i in range(SimDelays.gdscript_gate_limit() + 1):
		ed.graph.add_gate("g%d" % i, LogicGates.Type.AND)
	ed._on_left(Vector2(5, 300))
	ctx.check("over cap shows structural hint", ed.last_status.contains("该电路需要结构级表示"), ed.last_status)
	var over := ed.build_sim()
	ctx.check("over cap build rejected", not bool(over.get("ok", true)))
	ctx.eq("over cap error", str(over.get("error", "")), "needs_structural_representation")
	ed.setup([{"id": "a", "label": "A"}], [{"id": "out", "label": "O"}], ["and"], 500)
	ctx.begin_group("over_hard_cap")
	for i in range(SimDelays.gdscript_gate_hard_cap() + 1):
		ed.graph.add_gate("h%d" % i, LogicGates.Type.AND)
	var huge := ed.build_sim()
	ctx.check("hard cap build rejected", not bool(huge.get("ok", true)))
	ctx.eq("hard cap error code", str(huge.get("error", "")), "IFZ_E_SCALE")
	ed.free()
