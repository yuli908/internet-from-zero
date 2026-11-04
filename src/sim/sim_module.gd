class_name SimModule
extends RefCounted

## L2 组合层：把 L1 的门封装成可复用模块（半加器 → 全加器 → 8 位行波加法器 → 多路选择器）。
## 契约：
##  - `name` / `inputs` / `outputs` / `t_settle` 是模块对外的全部声明；
##  - `build(circuit)` 把模块展开成 L1 门（子模块继续递归展开），返回 {ok, error}；
##  - `t_settle` 是**输入变化到所有输出最后稳定**的 tick 上界，由 `SimDelays` 的延迟表推导，
##    不写死数字；测试用 `SimCircuit.measure_settle` 实测并断言不超界。
## 位序约定：下标 0 = 最低位（与 docs/simulation/ref/simcore/logic.py 一致）。

const KIND_HALF_ADDER := "half_adder"
const KIND_FULL_ADDER := "full_adder"
const KIND_RIPPLE := "ripple"
const KIND_MUX2 := "mux2"
const KIND_MUX4 := "mux4"

var name := "module"
var kind := KIND_HALF_ADDER
var width := 1
var t_settle := 0
var inputs: Array = []
var outputs: Array = []
var built := false

static func create(p_kind: String, p_name: String, p_width: int = 8) -> SimModule:
	var m := SimModule.new()
	m.kind = p_kind
	m.name = p_name if not p_name.is_empty() else p_kind
	m.width = maxi(1, p_width)
	m.t_settle = declared_settle(p_kind, m.width)
	return m

static func declared_settle(p_kind: String, p_width: int) -> int:
	## 由延迟表推导的上界（tick）。任一输入变化 → 所有输出稳定的最坏情形。
	var d_xor := SimDelays.delay("xor")
	var d_and := SimDelays.delay("and")
	var d_or := SimDelays.delay("or")
	var d_not := SimDelays.delay("not")
	var and_or := d_and + d_or
	var w := maxi(1, p_width)
	match p_kind:
		"half_adder":
			return maxi(d_xor, d_and)
		"full_adder":
			# sum = 2 级 xor；cout = xor(生成 s1) + and + or
			return maxi(d_xor + d_xor, d_xor + and_or)
		"ripple":
			# 进位链每级 and+or；最坏路径 = 第 0 位经 s1 生成进位，再穿 width-1 级
			return d_xor + and_or + (w - 1) * and_or
		"mux2":
			# 选择端最坏：not + and + or
			return d_not + and_or
		"mux4":
			# 第一级 mux2 的选择路径 + 第二级的数据路径
			return d_not + and_or + d_and + d_or
	return 0

func build(c: SimCircuit) -> Dictionary:
	if built:
		return {"ok": false, "error": "模块 %s 已构建，不能重复展开" % name}
	var p := name
	var r: Dictionary = {}
	match kind:
		"half_adder":
			r = _build_half_adder(c, p)
		"full_adder":
			r = _build_full_adder(c, p)
		"ripple":
			r = _build_ripple(c, p)
		"mux2":
			r = _build_mux2(c, p)
		"mux4":
			r = _build_mux4(c, p)
		_:
			return {"ok": false, "error": "未知模块类型 %s" % kind}
	if not bool(r.get("ok", false)):
		return r
	built = true
	return r

func summary() -> String:
	return "%s(%s) in=%d out=%d t_settle=%d" % [name, kind, inputs.size(), outputs.size(), t_settle]

# ---- 各模块展开 -------------------------------------------------------------

func _build_half_adder(c: SimCircuit, p: String) -> Dictionary:
	var a := p + ".a"
	var b := p + ".b"
	var r := _half_adder_at(c, p, a, b)
	if not bool(r.get("ok", false)):
		return r
	inputs = [a, b]
	outputs = [str(r["sum"]), str(r["carry"])]
	return {"ok": true, "error": ""}

func _build_full_adder(c: SimCircuit, p: String) -> Dictionary:
	var a := p + ".a"
	var b := p + ".b"
	var cin := p + ".cin"
	var r := _full_adder_at(c, p, a, b, cin)
	if not bool(r.get("ok", false)):
		return r
	inputs = [a, b, cin]
	outputs = [str(r["sum"]), str(r["cout"])]
	return {"ok": true, "error": ""}

func _build_ripple(c: SimCircuit, p: String) -> Dictionary:
	var a_bits: Array = []
	var b_bits: Array = []
	for i in width:
		var aw := "%s.a%d" % [p, i]
		var bw := "%s.b%d" % [p, i]
		c.add_wire(aw, SimValue.X)
		c.add_wire(bw, SimValue.X)
		a_bits.append(aw)
		b_bits.append(bw)
	var cin := p + ".cin"
	c.add_wire(cin, SimValue.X)
	var carry := cin
	var sums: Array = []
	for i in width:
		var r := _full_adder_at(c, "%s.fa%d" % [p, i], str(a_bits[i]), str(b_bits[i]), carry)
		if not bool(r.get("ok", false)):
			return r
		sums.append(str(r["sum"]))
		carry = str(r["cout"])
	inputs = a_bits + b_bits + [cin]
	outputs = sums + [carry]
	return {"ok": true, "error": ""}

func _build_mux2(c: SimCircuit, p: String) -> Dictionary:
	var d0 := p + ".d0"
	var d1 := p + ".d1"
	var sel := p + ".sel"
	var r := _mux2_at(c, p, d0, d1, sel)
	if not bool(r.get("ok", false)):
		return r
	inputs = [d0, d1, sel]
	outputs = [str(r["y"])]
	return {"ok": true, "error": ""}

func _build_mux4(c: SimCircuit, p: String) -> Dictionary:
	var d0 := p + ".d0"
	var d1 := p + ".d1"
	var d2 := p + ".d2"
	var d3 := p + ".d3"
	var s0 := p + ".s0"
	var s1 := p + ".s1"
	for w in [d0, d1, d2, d3, s0, s1]:
		c.add_wire(str(w), SimValue.X)
	var m0 := _mux2_at(c, p + ".m0", d0, d1, s0)
	if not bool(m0.get("ok", false)):
		return m0
	var m1 := _mux2_at(c, p + ".m1", d2, d3, s0)
	if not bool(m1.get("ok", false)):
		return m1
	var m2 := _mux2_at(c, p + ".m2", str(m0["y"]), str(m1["y"]), s1)
	if not bool(m2.get("ok", false)):
		return m2
	inputs = [d0, d1, d2, d3, s0, s1]
	outputs = [str(m2["y"])]
	return {"ok": true, "error": ""}

# ---- 结构化展开（可被上層模块复用） -----------------------------------------

static func _half_adder_at(c: SimCircuit, p: String, a: String, b: String) -> Dictionary:
	c.add_wire(a, SimValue.X)
	c.add_wire(b, SimValue.X)
	var sum := p + ".sum"
	var carry := p + ".carry"
	if c.add_gate(sum, "xor", [a, b]).is_empty():
		return {"ok": false, "error": "半加器 xor 门创建失败"}
	if c.add_gate(carry, "and", [a, b]).is_empty():
		return {"ok": false, "error": "半加器 and 门创建失败"}
	return {"ok": true, "error": "", "sum": sum, "carry": carry}

static func _full_adder_at(c: SimCircuit, p: String, a: String, b: String, cin: String) -> Dictionary:
	c.add_wire(a, SimValue.X)
	c.add_wire(b, SimValue.X)
	c.add_wire(cin, SimValue.X)
	var ha1 := _half_adder_at(c, p + ".ha1", a, b)
	if not bool(ha1.get("ok", false)):
		return ha1
	var ha2 := _half_adder_at(c, p + ".ha2", str(ha1["sum"]), cin)
	if not bool(ha2.get("ok", false)):
		return ha2
	var cout := p + ".cout"
	if c.add_gate(cout, "or", [str(ha1["carry"]), str(ha2["carry"])]).is_empty():
		return {"ok": false, "error": "全加器 or 门创建失败"}
	return {"ok": true, "error": "", "sum": str(ha2["sum"]), "cout": cout}

static func _mux2_at(c: SimCircuit, p: String, d0: String, d1: String, sel: String) -> Dictionary:
	for w in [d0, d1, sel]:
		c.add_wire(str(w), SimValue.X)
	var nsel := p + ".nsel"
	var a := p + ".a"
	var b := p + ".b"
	var y := p + ".y"
	if c.add_gate(nsel, "not", [sel]).is_empty():
		return {"ok": false, "error": "选择器 not 门创建失败"}
	if c.add_gate(a, "and", [d0, nsel]).is_empty():
		return {"ok": false, "error": "选择器 and 门创建失败"}
	if c.add_gate(b, "and", [d1, sel]).is_empty():
		return {"ok": false, "error": "选择器 and 门创建失败"}
	if c.add_gate(y, "or", [a, b]).is_empty():
		return {"ok": false, "error": "选择器 or 门创建失败"}
	return {"ok": true, "error": "", "y": y}
