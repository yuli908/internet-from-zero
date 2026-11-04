extends RefCounted

## 与仿真组参考向量 `docs/simulation/ref/vectors/l2_vectors.json`（只读）逐行比对。
## 覆盖现有 5 个 L2 模块（HA/FA/ripple8/mux2/mux4）；decoder/comparator/ALU 属 L3+，M3 不做。
## 字段顺序按该 JSON：HA[a,b,s,co] FA[a,b,cin,s,co] ripple8[a,b,cin,sum,cout,note]
## mux2[d0,d1,sel,y] mux4[d(4),s1,s0,y]。

const VEC_PATH := "res://docs/simulation/ref/vectors/l2_vectors.json"

func run(ctx: TestContext) -> void:
	var f := FileAccess.open(VEC_PATH, FileAccess.READ)
	if f == null:
		ctx.check("L2 参考向量文件存在", false, VEC_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		ctx.check("L2 参考向量可解析", false, str(parsed))
		return
	var vec: Dictionary = parsed
	ctx.eq("向量格式", str(vec.get("format", "")), "ifz-l2-vectors/1")
	ctx.eq("HA 向量行数", (vec.get("half_adder", []) as Array).size(), 9)
	ctx.eq("FA 向量行数", (vec.get("full_adder", []) as Array).size(), 27)
	ctx.eq("ripple8 向量行数", (vec.get("ripple8", []) as Array).size(), 37)
	ctx.eq("mux2 向量行数", (vec.get("mux2", []) as Array).size(), 27)
	ctx.eq("mux4 向量行数", (vec.get("mux4", []) as Array).size(), 5)
	# 延迟表必须与向量生成器同源
	var gd: Dictionary = vec.get("gate_delay", {})
	ctx.eq("延迟表 and", int(gd.get("and", 0)), SimDelays.delay("and"))
	ctx.eq("延迟表 or", int(gd.get("or", 0)), SimDelays.delay("or"))
	ctx.eq("延迟表 not", int(gd.get("not", 0)), SimDelays.delay("not"))
	ctx.eq("延迟表 xor", int(gd.get("xor", 0)), SimDelays.delay("xor"))

	_check_half_adder(ctx, vec.get("half_adder", []))
	_check_full_adder(ctx, vec.get("full_adder", []))
	_check_ripple8(ctx, vec.get("ripple8", []))
	_check_mux2(ctx, vec.get("mux2", []))
	_check_mux4(ctx, vec.get("mux4", []))

# ---- 各模块逐行比对 ---------------------------------------------------------

func _check_half_adder(ctx: TestContext, rows: Array) -> void:
	var passed := 0
	for i in rows.size():
		var row: Array = rows[i]
		var c := SimCircuit.new("vec_ha")
		var m := SimModule.create(SimModule.KIND_HALF_ADDER, "u")
		var b := m.build(c)
		if not bool(b.get("ok", false)):
			ctx.check("HA 构建 %d" % i, false, str(b.get("error", "")))
			continue
		c.set_input(m.inputs[0], str(row[0]))
		c.set_input(m.inputs[1], str(row[1]))
		c.settle()
		var got := "%s%s" % [c.probe(m.outputs[0]), c.probe(m.outputs[1])]
		var exp := "%s%s" % [str(row[2]), str(row[3])]
		if got == exp:
			passed += 1
		else:
			ctx.check("HA 向量 %d: 期望 %s 实得 %s" % [i, exp, got], false, str(row))
	ctx.check("HA 参考向量 %d/%d" % [passed, rows.size()], passed == rows.size())

func _check_full_adder(ctx: TestContext, rows: Array) -> void:
	var passed := 0
	for i in rows.size():
		var row: Array = rows[i]
		var c := SimCircuit.new("vec_fa")
		var m := SimModule.create(SimModule.KIND_FULL_ADDER, "u")
		var b := m.build(c)
		if not bool(b.get("ok", false)):
			ctx.check("FA 构建 %d" % i, false, str(b.get("error", "")))
			continue
		for k in 3:
			c.set_input(m.inputs[k], str(row[k]))
		c.settle()
		var got := "%s%s" % [c.probe(m.outputs[0]), c.probe(m.outputs[1])]
		var exp := "%s%s" % [str(row[3]), str(row[4])]
		if got == exp:
			passed += 1
		else:
			ctx.check("FA 向量 %d: 期望 %s 实得 %s" % [i, exp, got], false, str(row))
	ctx.check("FA 参考向量 %d/%d" % [passed, rows.size()], passed == rows.size())

func _check_ripple8(ctx: TestContext, rows: Array) -> void:
	var passed := 0
	for i in rows.size():
		var row: Array = rows[i]
		var c := SimCircuit.new("vec_rip")
		var m := SimModule.create(SimModule.KIND_RIPPLE, "u", 8)
		var b := m.build(c)
		if not bool(b.get("ok", false)):
			ctx.check("ripple 构建 %d" % i, false, str(b.get("error", "")))
			continue
		var a := str(row[0])
		var bb := str(row[1])
		for k in 8:
			c.set_input(m.inputs[k], _bit(a, k))
			c.set_input(m.inputs[8 + k], _bit(bb, k))
		c.set_input(m.inputs[16], str(row[2]))
		c.settle()
		var got := ""
		for k in range(7, -1, -1):
			got += c.probe(m.outputs[k])
		got += c.probe(m.outputs[8])
		var exp := str(row[3]) + str(row[4])
		if got == exp:
			passed += 1
		else:
			ctx.check("ripple8 向量 %d: 期望 %s 实得 %s" % [i, exp, got], false, str(row))
	ctx.check("ripple8 参考向量 %d/%d" % [passed, rows.size()], passed == rows.size())

func _check_mux2(ctx: TestContext, rows: Array) -> void:
	var passed := 0
	for i in rows.size():
		var row: Array = rows[i]
		var c := SimCircuit.new("vec_mux2")
		var m := SimModule.create(SimModule.KIND_MUX2, "u")
		var b := m.build(c)
		if not bool(b.get("ok", false)):
			ctx.check("mux2 构建 %d" % i, false, str(b.get("error", "")))
			continue
		for k in 3:
			c.set_input(m.inputs[k], str(row[k]))
		c.settle()
		var got := c.probe(m.outputs[0])
		if got == str(row[3]):
			passed += 1
		else:
			ctx.check("mux2 向量 %d: 期望 %s 实得 %s" % [i, str(row[3]), got], false, str(row))
	ctx.check("mux2 参考向量 %d/%d" % [passed, rows.size()], passed == rows.size())

func _check_mux4(ctx: TestContext, rows: Array) -> void:
	var passed := 0
	for i in rows.size():
		var row: Array = rows[i]
		var c := SimCircuit.new("vec_mux4")
		var m := SimModule.create(SimModule.KIND_MUX4, "u")
		var b := m.build(c)
		if not bool(b.get("ok", false)):
			ctx.check("mux4 构建 %d" % i, false, str(b.get("error", "")))
			continue
		var d := str(row[0])
		for k in 4:
			c.set_input(m.inputs[k], _bit(d, k))
		c.set_input(m.inputs[4], str(row[2]))  # s0
		c.set_input(m.inputs[5], str(row[1]))  # s1
		c.settle()
		var got := c.probe(m.outputs[0])
		if got == str(row[3]):
			passed += 1
		else:
			ctx.check("mux4 向量 %d: 期望 %s 实得 %s" % [i, str(row[3]), got], false, str(row))
	ctx.check("mux4 参考向量 %d/%d" % [passed, rows.size()], passed == rows.size())

static func _bit(bits: String, i: int) -> String:
	## JSON 位串按 MSB 在前；下标 0 = 最低位。
	var idx := bits.length() - 1 - i
	if idx < 0 or idx >= bits.length():
		return SimValue.X
	return bits.substr(idx, 1)
