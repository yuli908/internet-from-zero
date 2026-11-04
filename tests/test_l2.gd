extends RefCounted

## L2 组合层：半加器 → 全加器 → 8 位行波进位加法器 → 多路选择器。
## 每一级都验证三件事：
##  1. 结构展开成功、对外声明（inputs/outputs/t_settle）完整；
##  2. 对参考真值表逐向量等价（半加器直接用 ref_vectors.json；全加器/选择器用
##     docs/simulation/ref/simcore/components.py 同构的三值公式）；
##  3. `t_settle` 是实测最坏稳定时间的上界，关键模块给出精确值。
## 另验证 L1 门与 L2 模块在同一张网表里混合仿真。

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 430
const EXPECT_GROUPS := {
	"declared": 8, "half_adder": 15, "full_adder": 40,
	"ripple8_decl": 3, "ripple8_sweep_a0_127": 128, "ripple8_sweep_a128_255": 129,
	"ripple8_random": 33, "ripple8_carry": 4, "mux2": 40, "mux4": 21, "mixed": 9,
}
const GROUP_DESCRIPTIONS := {
	"declared": "五个模块的 t_settle 声明值，且必须由延迟表推导",
	"half_adder": "半加器构建、端口数、9 行参考向量、实测最坏稳定时间与声明上界",
	"full_adder": "全加器构建、端口数、8 行二进制真值表、27 组三值向量、最坏稳定时间与关键路径 10",
	"ripple8_decl": "8 位行波加法器构建与输入 17 / 输出 9 端口",
	"ripple8_sweep_a0_127": "a=0..127、b=0x5A、cin 随奇偶的穷举扫描（前半）",
	"ripple8_sweep_a128_255": "a=128..255 的穷举扫描（后半）与整体失败计数",
	"ripple8_random": "固定种子 32 条随机向量及其失败计数",
	"ripple8_carry": "最坏进位链 0xFE+0x00+1 的 52 tick 延迟、声明上界、进位与和",
	"mux2": "二选一构建、端口数、8 组二进制与 27 组三值向量、选择端延迟 7",
	"mux4": "四选一构建、端口数、4×4 组数据/选择组合、s0 延迟 13",
	"mixed": "L1 门读 L2 输出再喂 L2 选择器的混合仿真与选择端切换",
}

func run(ctx: TestContext) -> void:
	_declared(ctx)
	_half_adder(ctx)
	_full_adder(ctx)
	_ripple8(ctx)
	_mux(ctx)
	_mixed(ctx)

# ---- 声明 -------------------------------------------------------------------

func _declared(ctx: TestContext) -> void:
	ctx.begin_group("declared")
	var ha := SimModule.create("half_adder", "ha")
	var fa := SimModule.create("full_adder", "fa")
	var add8 := SimModule.create("ripple", "add8", 8)
	var mux2 := SimModule.create("mux2", "mux2")
	var mux4 := SimModule.create("mux4", "mux4")
	ctx.eq("HA t_settle", ha.t_settle, 4)
	ctx.eq("FA t_settle", fa.t_settle, 10)
	ctx.eq("ripple8 t_settle", add8.t_settle, 52)
	ctx.eq("mux2 t_settle", mux2.t_settle, 7)
	ctx.eq("mux4 t_settle", mux4.t_settle, 13)
	# 声明值必须由延迟表推导，而不是写死：重设延迟表后应随之变化。
	var xor_d := SimDelays.delay("xor")
	var and_d := SimDelays.delay("and")
	var or_d := SimDelays.delay("or")
	ctx.eq("HA derived", ha.t_settle, maxi(xor_d, and_d))
	ctx.eq("FA derived", fa.t_settle, maxi(xor_d + xor_d, xor_d + and_d + or_d))
	ctx.eq("ripple8 derived", add8.t_settle, xor_d + and_d + or_d + 7 * (and_d + or_d))

# ---- 半加器 -----------------------------------------------------------------

func _half_adder(ctx: TestContext) -> void:
	ctx.begin_group("half_adder")
	var b := _build("half_adder", "ha")
	ctx.check("HA build", bool(b.get("ok", false)), str(b.get("error", "")))
	if not bool(b.get("ok", false)):
		return
	var c: SimCircuit = b["c"]
	var m: SimModule = b["m"]
	ctx.eq("HA inputs", m.inputs.size(), 2)
	ctx.eq("HA outputs", m.outputs.size(), 2)

	var ref: Array = TestUtil.read_json("res://tests/data/ref_vectors.json").get("half_adder", [])
	var rows := 0
	for raw in ref:
		var row: Array = raw
		_drive(c, m.inputs, [str(row[0]), str(row[1])])
		var s: Dictionary = c.settle()
		var got := _probe_values(c, m.outputs)
		ctx.check("HA ref(%s,%s)" % [str(row[0]), str(row[1])],
			bool(s.get("ok", false)) and got[0] == str(row[2]) and got[1] == str(row[3]),
			"sum=%s carry=%s 期望 %s/%s" % [got[0], got[1], row[2], row[3]])
		rows += 1
	ctx.eq("HA ref rows", rows, 9)

	var worst := _worst_settle(c, m, _patterns(2))
	ctx.eq("HA measured worst", worst, 4)
	ctx.check("HA within declared", worst <= m.t_settle, "%d > %d" % [worst, m.t_settle])

# ---- 全加器 -----------------------------------------------------------------

func _full_adder(ctx: TestContext) -> void:
	ctx.begin_group("full_adder")
	var b := _build("full_adder", "fa")
	ctx.check("FA build", bool(b.get("ok", false)), str(b.get("error", "")))
	if not bool(b.get("ok", false)):
		return
	var c: SimCircuit = b["c"]
	var m: SimModule = b["m"]
	ctx.eq("FA inputs", m.inputs.size(), 3)
	ctx.eq("FA outputs", m.outputs.size(), 2)

	# 二进制真值表：输出必须等于整数加法的和与进位。
	for raw in _patterns(3):
		var p: Array = raw
		_drive(c, m.inputs, p)
		c.settle()
		var x := int(str(p[0]))
		var y := int(str(p[1]))
		var ci := int(str(p[2]))
		var total := x + y + ci
		var got := _probe_values(c, m.outputs)
		ctx.check("FA(%d,%d,%d)" % [x, y, ci],
			got[0] == str(total & 1) and got[1] == str((total >> 1) & 1),
			"sum=%s cout=%s 期望 %d/%d" % [got[0], got[1], total & 1, (total >> 1) & 1])

	# 三值（含 X）逐向量：与参考实现同构的 s1/c1/s/c2/cout 公式比对。
	for a in ["0", "1", "X"]:
		for bb in ["0", "1", "X"]:
			for ci in ["0", "1", "X"]:
				_drive(c, m.inputs, [a, bb, ci])
				c.settle()
				var want := _fa_ref(str(a), str(bb), str(ci))
				var got := _probe_values(c, m.outputs)
				ctx.check("FA tri(%s,%s,%s)" % [a, bb, ci],
					got[0] == str(want["sum"]) and got[1] == str(want["cout"]),
					"sum=%s cout=%s 期望 %s/%s" % [got[0], got[1], want["sum"], want["cout"]])

	var worst := _worst_settle(c, m, _patterns(3))
	ctx.check("FA within declared", worst >= 0 and worst <= m.t_settle, "%d > %d" % [worst, m.t_settle])
	# 关键路径：只改 a（b=0, cin=1），进位经 s1→c2→cout = 4+3+3 = 10。
	_drive(c, m.inputs, ["0", "0", "1"])
	c.settle()
	var t0 := c.now()
	c.set_input(str(m.inputs[0]), "1")
	var d := c.measure_settle(m.outputs, t0)
	ctx.eq("FA worst path a->cout", d, 10)

# ---- 8 位行波进位加法器 -----------------------------------------------------

func _ripple8(ctx: TestContext) -> void:
	ctx.begin_group("ripple8_decl")
	var b := _build("ripple", "add8", 8)
	ctx.check("ripple8 build", bool(b.get("ok", false)), str(b.get("error", "")))
	if not bool(b.get("ok", false)):
		return
	var c: SimCircuit = b["c"]
	var m: SimModule = b["m"]
	ctx.eq("ripple8 inputs", m.inputs.size(), 17)
	ctx.eq("ripple8 outputs", m.outputs.size(), 9)

	# 8 位穷举的一侧：a 取 0..255，b 固定 0x5A，cin 随 a 奇偶交替。
	var failures := 0
	ctx.begin_group("ripple8_sweep_a0_127")
	for a_val in 256:
		var b_val := 0x5A
		var ci := a_val & 1
		_drive_byte(c, "add8", "a", a_val)
		_drive_byte(c, "add8", "b", b_val)
		c.set_input("add8.cin", str(ci))
		c.settle()
		var got := _sum_value(c, m, 8)
		var cout := c.probe(str(m.outputs[8]))
		var expect := a_val + b_val + ci
		var ok := got == (expect & 0xFF) and cout == str(expect >> 8)
		if not ok:
			failures += 1
		if a_val == 128:
			ctx.begin_group("ripple8_sweep_a128_255")
		ctx.check("ripple8 0x%02X+0x%02X+%d" % [a_val, b_val, ci], ok,
			"和=%d 进位=%s 期望 %d/%d" % [got, cout, expect & 0xFF, expect >> 8])
	ctx.check("ripple8 sweep failures", failures == 0, str(failures))

	# 固定种子的随机向量（可复现）。
	ctx.begin_group("ripple8_random")
	var rng := DeterministicRng.new(7)
	var rand_fail := 0
	for _i in 32:
		var x := rng.next_int(0, 255)
		var y := rng.next_int(0, 255)
		var ci := rng.next_int(0, 1)
		_drive_byte(c, "add8", "a", x)
		_drive_byte(c, "add8", "b", y)
		c.set_input("add8.cin", str(ci))
		c.settle()
		var expect := x + y + ci
		var ok := _sum_value(c, m, 8) == (expect & 0xFF) and c.probe(str(m.outputs[8])) == str(expect >> 8)
		if not ok:
			rand_fail += 1
		ctx.check("ripple8 rnd %d+%d+%d" % [x, y, ci], ok)
	ctx.check("ripple8 random failures", rand_fail == 0, str(rand_fail))

	# 最坏进位链：0xFE+0x00+1 → a0 由 0→1，进位穿过全部 8 级。
	ctx.begin_group("ripple8_carry")
	_drive_byte(c, "add8", "a", 0xFE)
	_drive_byte(c, "add8", "b", 0x00)
	c.set_input("add8.cin", "1")
	c.settle()
	var t0 := c.now()
	c.set_input("add8.a0", "1")
	var d := c.measure_settle(m.outputs, t0)
	ctx.eq("ripple8 carry chain", d, 52)
	ctx.check("ripple8 within declared", d >= 0 and d <= m.t_settle, "%d > %d" % [d, m.t_settle])
	ctx.eq("ripple8 carry out", c.probe(str(m.outputs[8])), "1")
	ctx.eq("ripple8 sum low", _sum_value(c, m, 8), 0)

# ---- 多路选择器 -------------------------------------------------------------

func _mux(ctx: TestContext) -> void:
	ctx.begin_group("mux2")
	var b := _build("mux2", "mux2")
	ctx.check("mux2 build", bool(b.get("ok", false)), str(b.get("error", "")))
	if bool(b.get("ok", false)):
		var c: SimCircuit = b["c"]
		var m: SimModule = b["m"]
		ctx.eq("mux2 inputs", m.inputs.size(), 3)
		ctx.eq("mux2 outputs", m.outputs.size(), 1)
		for raw in _patterns(3):
			var p: Array = raw
			_drive(c, m.inputs, p)
			c.settle()
			var want: String = str(p[1]) if str(p[2]) == "1" else str(p[0])
			ctx.eq("mux2 sel=%s d=%s,%s" % [str(p[2]), str(p[0]), str(p[1])], c.probe(str(m.outputs[0])), want)
		for a in ["0", "1", "X"]:
			for bb in ["0", "1", "X"]:
				for tri_sel in ["0", "1", "X"]:
					_drive(c, m.inputs, [a, bb, tri_sel])
					c.settle()
					ctx.eq("mux2 tri(%s,%s,%s)" % [a, bb, tri_sel], c.probe(str(m.outputs[0])), _mux_ref(str(a), str(bb), str(tri_sel)))
		# 选择端变化是最坏路径：not + and + or = 7。
		_drive(c, m.inputs, ["1", "0", "0"])
		c.settle()
		var t0 := c.now()
		c.set_input(str(m.inputs[2]), "1")
		var d := c.measure_settle(m.outputs, t0)
		ctx.eq("mux2 select delay", d, 7)
		ctx.check("mux2 within declared", d >= 0 and d <= m.t_settle, "%d > %d" % [d, m.t_settle])

	ctx.begin_group("mux4")
	var b4 := _build("mux4", "mux4")
	ctx.check("mux4 build", bool(b4.get("ok", false)), str(b4.get("error", "")))
	if not bool(b4.get("ok", false)):
		return
	var c4: SimCircuit = b4["c"]
	var m4: SimModule = b4["m"]
	ctx.eq("mux4 inputs", m4.inputs.size(), 6)
	ctx.eq("mux4 outputs", m4.outputs.size(), 1)
	var data_patterns := [[0, 0, 0, 0], [1, 0, 1, 0], [0, 1, 1, 0], [1, 1, 0, 1]]
	for raw_dp in data_patterns:
		var dp: Array = raw_dp
		for sel_i in 4:
			_drive(c4, m4.inputs, [
				str(dp[0]), str(dp[1]), str(dp[2]), str(dp[3]),
				str(sel_i & 1), str((sel_i >> 1) & 1),
			])
			c4.settle()
			ctx.eq("mux4 sel=%d" % sel_i, c4.probe(str(m4.outputs[0])), str(dp[sel_i]))
	# s0 变化经两级选择器：not + (and+or) + (and+or) = 13。
	_drive(c4, m4.inputs, ["1", "0", "0", "0", "0", "0"])
	c4.settle()
	var t4 := c4.now()
	c4.set_input(str(m4.inputs[4]), "1")
	var d4 := c4.measure_settle(m4.outputs, t4)
	ctx.eq("mux4 select delay", d4, 13)
	ctx.check("mux4 within declared", d4 >= 0 and d4 <= m4.t_settle, "%d > %d" % [d4, m4.t_settle])

# ---- L1 门与 L2 模块混合 -----------------------------------------------------

func _mixed(ctx: TestContext) -> void:
	ctx.begin_group("mixed")
	var c := SimCircuit.new("mixed")
	var ha := SimModule.create("half_adder", "ha")
	var mux := SimModule.create("mux2", "mux")
	ctx.check("mixed HA build", bool(ha.build(c).get("ok", false)))
	ctx.check("mixed mux build", bool(mux.build(c).get("ok", false)))
	# L1 门读取 L2 输出（ha.sum ^ ha.carry = a|b），再经 0 延迟连线喂给 L2 选择器。
	var mix := "mix_xor"
	c.add_gate(mix, "xor", [str(ha.outputs[0]), str(ha.outputs[1])])
	c.bind(mix, str(mux.inputs[0]), 0)
	c.set_input(str(mux.inputs[1]), "1")
	c.set_input(str(mux.inputs[2]), "0")
	var r := c.settle()
	ctx.check("mixed initial settle", bool(r.get("ok", false)), str(r.get("error", "")))
	for raw in _patterns(2):
		var p: Array = raw
		c.set_input(str(ha.inputs[0]), str(p[0]))
		c.set_input(str(ha.inputs[1]), str(p[1]))
		c.settle()
		var want := int(str(p[0])) | int(str(p[1]))
		ctx.eq("mixed L1+L2 (%s,%s)" % [str(p[0]), str(p[1])], c.probe(str(mux.outputs[0])), str(want))
	# 选择端切到 d1=1：无论 a/b 如何，输出恒 1。
	c.set_input(str(mux.inputs[2]), "1")
	var s := c.settle()
	ctx.check("mixed select settle", bool(s.get("ok", false)))
	ctx.eq("mixed select d1", c.probe(str(mux.outputs[0])), "1")

# ---- 工具 -------------------------------------------------------------------

func _build(kind: String, mod_name: String, width: int = 8) -> Dictionary:
	var c := SimCircuit.new(mod_name)
	var m := SimModule.create(kind, mod_name, width)
	var r: Dictionary = m.build(c)
	return {"ok": bool(r.get("ok", false)), "error": str(r.get("error", "")), "c": c, "m": m}

func _drive(c: SimCircuit, wires: Array, values: Array) -> void:
	for i in wires.size():
		c.set_input(str(wires[i]), str(values[i]))

func _probe_values(c: SimCircuit, wires: Array) -> Array:
	var out: Array = []
	for w in wires:
		out.append(c.probe(str(w)))
	return out

func _worst_settle(c: SimCircuit, m: SimModule, patterns: Array) -> int:
	var worst := 0
	var first := true
	for raw in patterns:
		var p: Array = raw
		var t0 := c.now()
		_drive(c, m.inputs, p)
		if first:
			var r: Dictionary = c.settle()
			if not bool(r.get("ok", false)):
				return -1
			first = false
		else:
			var d := c.measure_settle(m.outputs, t0)
			if d < 0:
				return -1
			worst = maxi(worst, d)
	return worst

func _patterns(n: int) -> Array:
	var out: Array = [[]]
	for _i in n:
		var next: Array = []
		for row in out:
			for bit in ["0", "1"]:
				var nr: Array = (row as Array).duplicate()
				nr.append(bit)
				next.append(nr)
		out = next
	return out

func _drive_byte(c: SimCircuit, prefix: String, letter: String, value: int) -> void:
	for i in 8:
		c.set_input("%s.%s%d" % [prefix, letter, i], "1" if ((value >> i) & 1) == 1 else "0")

func _sum_value(c: SimCircuit, m: SimModule, width: int) -> int:
	var bits := ""
	for i in width:
		bits = c.probe(str(m.outputs[i])) + bits
	return SimValue.value_of(bits)

func _fa_ref(a: String, b: String, cin: String) -> Dictionary:
	## 与 docs/simulation/ref/simcore/components.py 的 full_adder 结构同构。
	var s1 := SimValue.bin3("xor", a, b)
	var c1 := SimValue.bin3("and", a, b)
	var s := SimValue.bin3("xor", s1, cin)
	var c2 := SimValue.bin3("and", s1, cin)
	return {"sum": s, "cout": SimValue.bin3("or", c1, c2)}

func _mux_ref(d0: String, d1: String, sel: String) -> String:
	var nsel := SimValue.not3(sel)
	return SimValue.bin3("or", SimValue.bin3("and", d0, nsel), SimValue.bin3("and", d1, sel))
