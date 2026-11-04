extends RefCounted

## 与仿真组参考向量 `docs/simulation/ref/vectors/l2_vectors.json`（只读）逐行比对。
## 覆盖 7 个模块（HA/FA/ripple8/mux2/mux4/decoder3/comparator4），共 132/140 行；
## `alu4` 8 行不比对：ALU 内部 166 门超 80 硬上限，按接口对齐必须走宏单元（见 PROGRESS 偏差 17）。
## 字段顺序按该 JSON：HA[a,b,s,co] FA[a,b,cin,s,co] ripple8[a,b,cin,sum,cout,note]
## mux2[d0,d1,sel,y] mux4[d(4),s1,s0,y] decoder3[en,a2,a1,a0,y(8)] comparator4[a(4),b(4),eq,gt,lt]。

const VEC_PATH := "res://docs/simulation/ref/vectors/l2_vectors.json"

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 36
const EXPECT_GROUPS := {
	"loadable": 0, "vector_rows": 9, "determinism": 10,
	"delays": 4, "module_vectors": 11, "settle": 2,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "向量文件可读、JSON 可解析：仅在文件缺失或解析失败时才执行的兜底检查",
	"vector_rows": "格式标记与 7 个模块 + alu4 的向量行数（alu4 只登记不比对）",
	"determinism": "determinism.rows 逐键等于实测行数、总行数 140、随机种子",
	"delays": "and/or/not/xor 的延迟表与 SimDelays 同源",
	"module_vectors": "7 个模块逐行比对全过，decoder3/comparator4 门数与预算上限",
	"settle": "decoder3/comparator4 声明 t_settle 与向量生成器实测一致",
}

func run(ctx: TestContext) -> void:
	var f := FileAccess.open(VEC_PATH, FileAccess.READ)
	ctx.begin_group("loadable")
	if f == null:
		ctx.check("L2 参考向量文件存在", false, VEC_PATH)
		return
	var parsed = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		ctx.check("L2 参考向量可解析", false, str(parsed))
		return
	var vec: Dictionary = parsed
	ctx.begin_group("vector_rows")
	ctx.eq("向量格式", str(vec.get("format", "")), "ifz-l2-vectors/1")
	ctx.eq("HA 向量行数", (vec.get("half_adder", []) as Array).size(), 9)
	ctx.eq("FA 向量行数", (vec.get("full_adder", []) as Array).size(), 27)
	ctx.eq("ripple8 向量行数", (vec.get("ripple8", []) as Array).size(), 37)
	ctx.eq("mux2 向量行数", (vec.get("mux2", []) as Array).size(), 27)
	ctx.eq("mux4 向量行数", (vec.get("mux4", []) as Array).size(), 5)
	ctx.eq("decoder3 向量行数", (vec.get("decoder3", []) as Array).size(), 10)
	ctx.eq("comparator4 向量行数", (vec.get("comparator4", []) as Array).size(), 17)
	ctx.eq("alu4 向量行数（宏单元，不比对）", (vec.get("alu4", []) as Array).size(), 8)
	# determinism.rows 与逐键实测行数对账：证明总数 140（不是 143）
	ctx.begin_group("determinism")
	var rows_meta: Dictionary = (vec.get("determinism", {}) as Dictionary).get("rows", {})
	var total_rows := 0
	for k in rows_meta.keys():
		total_rows += int(rows_meta[k])
		ctx.eq("determinism.rows %s" % k, int(rows_meta[k]), (vec.get(k, []) as Array).size())
	ctx.eq("向量总行数", total_rows, 140)
	ctx.eq("随机种子", int((vec.get("determinism", {}) as Dictionary).get("seed", 0)), 539365636)
	# 延迟表必须与向量生成器同源
	ctx.begin_group("delays")
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
	_check_decoder3(ctx, vec.get("decoder3", []))
	_check_comparator4(ctx, vec.get("comparator4", []))

	# 声明延迟必须与向量生成器实测值一致（t_settle 由延迟表推导）
	ctx.begin_group("settle")
	var ts: Dictionary = vec.get("t_settle", {})
	ctx.eq("decoder3 t_settle", SimModule.declared_settle(SimModule.KIND_DECODER3, 3), int(ts.get("decoder3", -1)))
	ctx.eq("comparator4 t_settle", SimModule.declared_settle(SimModule.KIND_COMPARATOR4, 4), int(ts.get("comparator4", -1)))

# ---- 各模块逐行比对 ---------------------------------------------------------

func _check_half_adder(ctx: TestContext, rows: Array) -> void:
	ctx.begin_group("module_vectors")
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
	ctx.begin_group("module_vectors")
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
	ctx.begin_group("module_vectors")
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
	ctx.begin_group("module_vectors")
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
	ctx.begin_group("module_vectors")
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

func _check_decoder3(ctx: TestContext, rows: Array) -> void:
	ctx.begin_group("module_vectors")
	var passed := 0
	for i in rows.size():
		var row: Array = rows[i]
		var c := SimCircuit.new("vec_dec")
		var m := SimModule.create(SimModule.KIND_DECODER3, "u", 3)
		var b := m.build(c)
		if not bool(b.get("ok", false)):
			ctx.check("decoder3 构建 %d" % i, false, str(b.get("error", "")))
			continue
		# JSON 列序 en,a2,a1,a0；模块 inputs = [en, a0, a1, a2]
		c.set_input(m.inputs[0], str(row[0]))
		c.set_input(m.inputs[1], str(row[3]))
		c.set_input(m.inputs[2], str(row[2]))
		c.set_input(m.inputs[3], str(row[1]))
		c.settle()
		var got := ""
		for k in range(7, -1, -1):
			got += c.probe(m.outputs[k])
		var exp := str(row[4])
		if got == exp:
			passed += 1
		else:
			ctx.check("decoder3 向量 %d: 期望 %s 实得 %s" % [i, exp, got], false, str(row))
	ctx.check("decoder3 参考向量 %d/%d" % [passed, rows.size()], passed == rows.size())
	# 宏单元预算：3 not + 8 and = 11 门，≤ 50 默认上限
	var c2 := SimCircuit.new("vec_dec_gates")
	var m2 := SimModule.create(SimModule.KIND_DECODER3, "u", 3)
	var b2 := m2.build(c2)
	if bool(b2.get("ok", false)):
		ctx.eq("decoder3 门数", c2._g_op.size(), 11)
		ctx.check("decoder3 门数 ≤ 交互默认上限", c2._g_op.size() <= SimDelays.gdscript_gate_limit())

func _check_comparator4(ctx: TestContext, rows: Array) -> void:
	ctx.begin_group("module_vectors")
	var passed := 0
	for i in rows.size():
		var row: Array = rows[i]
		var c := SimCircuit.new("vec_cmp")
		var m := SimModule.create(SimModule.KIND_COMPARATOR4, "u", 4)
		var b := m.build(c)
		if not bool(b.get("ok", false)):
			ctx.check("comparator4 构建 %d" % i, false, str(b.get("error", "")))
			continue
		var a := str(row[0])
		var bb := str(row[1])
		for k in 4:
			c.set_input(m.inputs[k], _bit(a, k))
			c.set_input(m.inputs[4 + k], _bit(bb, k))
		c.settle()
		var got := "%s%s%s" % [c.probe(m.outputs[0]), c.probe(m.outputs[1]), c.probe(m.outputs[2])]
		var exp := str(row[2]) + str(row[3]) + str(row[4])
		if got == exp:
			passed += 1
		else:
			ctx.check("comparator4 向量 %d: 期望 %s 实得 %s" % [i, exp, got], false, str(row))
	ctx.check("comparator4 参考向量 %d/%d" % [passed, rows.size()], passed == rows.size())
	var c2 := SimCircuit.new("vec_cmp_gates")
	var m2 := SimModule.create(SimModule.KIND_COMPARATOR4, "u", 4)
	var b2 := m2.build(c2)
	if bool(b2.get("ok", false)):
		ctx.eq("comparator4 门数", c2._g_op.size(), 33)
		ctx.check("comparator4 门数 ≤ 交互默认上限", c2._g_op.size() <= SimDelays.gdscript_gate_limit())

static func _bit(bits: String, i: int) -> String:
	## JSON 位串按 MSB 在前；下标 0 = 最低位。
	var idx := bits.length() - 1 - i
	if idx < 0 or idx >= bits.length():
		return SimValue.X
	return bits.substr(idx, 1)
