class_name SimSequential
extends RefCounted

## L3 时序层器件（结构级，不是玩家门级电路）：寄存器 / 计数器 / 移位寄存器。
## 契约：
##  - 位序 index 0 = 最低位；
##  - 每个器件展开成 `SimDff` + 少量组合门（计数器自增链），对外只声明 Q 线网；
##  - 初值 0；RESET 异步高有效（在上升沿优先于采样）；
##  - 计数器周期必须为偶数，最小周期由 `measure_counter_period()` 实测确定（见 M3 spec）。

static func create_register(sim: SimCircuit, p: String, width: int, clk: String,
		reset: String = "", en: String = "") -> Dictionary:
	var w := maxi(1, width)
	var q: Array = []
	var ins: Array = []
	for i in w:
		var qw := "%s.q%d" % [p, i]
		var dw := "%s.d%d" % [p, i]
		sim.add_wire(dw, SimValue.ZERO)
		var dsrc := dw
		if not en.is_empty():
			# EN=0 保持（选 Q）、EN=1 装载（选 D）、EN=X → X
			var mw := "%s.m%d" % [p, i]
			if sim.add_gate(mw, "mux", [en, qw, dw]).is_empty():
				return {"ok": false, "error": "寄存器 mux 门创建失败", "q": q, "inputs": ins}
			dsrc = mw
		sim.dffs.append(SimDff.attach(sim, qw, dsrc, clk, reset, SimDff.SETUP, SimDff.HOLD,
			SimDff.CLK_TO_Q, SimValue.ZERO))
		q.append(qw)
		ins.append(dw)
	return {"ok": true, "error": "", "q": q, "inputs": ins}

static func create_counter(sim: SimCircuit, p: String, width: int, clk: String,
		reset: String = "", en: String = "", load: String = "", load_srcs: Array = []) -> Dictionary:
	## 计数器 = 寄存器 + 自增链：q0' = !q0；qi' = qi ^ (q0 & ... & qi-1)。
	var w := maxi(1, width)
	if not load.is_empty() and load_srcs.size() != w:
		return {"ok": false, "error": "load_srcs 数量必须等于位宽", "q": []}
	var q: Array = []
	for i in w:
		q.append("%s.q%d" % [p, i])
		sim.add_wire(str(q[i]), SimValue.ZERO)
	var carry := ""
	var next: Array = []
	for i in w:
		if i == 0:
			var n0 := "%s.n0" % p
			if sim.add_gate(n0, "not", [str(q[0])]).is_empty():
				return {"ok": false, "error": "计数器 not 门创建失败", "q": q}
			next.append(n0)
			carry = str(q[0])
		else:
			var nn := "%s.n%d" % [p, i]
			if sim.add_gate(nn, "xor", [str(q[i]), carry]).is_empty():
				return {"ok": false, "error": "计数器 xor 门创建失败", "q": q}
			next.append(nn)
			if i < w - 1:
				var nc := "%s.c%d" % [p, i]
				if sim.add_gate(nc, "and", [str(q[i]), carry]).is_empty():
					return {"ok": false, "error": "计数器 and 门创建失败", "q": q}
				carry = nc
	for i in w:
		var dsrc := str(next[i])
		if not en.is_empty():
			var me := "%s.e%d" % [p, i]
			if sim.add_gate(me, "mux", [en, str(q[i]), dsrc]).is_empty():
				return {"ok": false, "error": "计数器 EN mux 创建失败", "q": q}
			dsrc = me
		if not load.is_empty():
			var ml := "%s.l%d" % [p, i]
			if sim.add_gate(ml, "mux", [load, dsrc, str(load_srcs[i])]).is_empty():
				return {"ok": false, "error": "计数器 LOAD mux 创建失败", "q": q}
			dsrc = ml
		sim.dffs.append(SimDff.attach(sim, str(q[i]), dsrc, clk, reset,
			SimDff.SETUP, SimDff.HOLD, SimDff.CLK_TO_Q, SimValue.ZERO))
	return {"ok": true, "error": "", "q": q}

static func create_shift_register(sim: SimCircuit, p: String, width: int, din: String,
		clk: String, reset: String = "", en: String = "") -> Dictionary:
	var w := maxi(1, width)
	var q: Array = []
	var prev := din
	for i in w:
		var qw := "%s.q%d" % [p, i]
		var dsrc := prev
		if not en.is_empty():
			var mw := "%s.m%d" % [p, i]
			if sim.add_gate(mw, "mux", [en, qw, prev]).is_empty():
				return {"ok": false, "error": "移位寄存器 mux 门创建失败", "q": q}
			dsrc = mw
		sim.dffs.append(SimDff.attach(sim, qw, dsrc, clk, reset, SimDff.SETUP, SimDff.HOLD,
			SimDff.CLK_TO_Q, SimValue.ZERO))
		q.append(qw)
		prev = qw
	return {"ok": true, "error": "", "q": q, "inputs": [din]}

static func drive_clock(sim: SimCircuit, wire: String, period: int, cycles: int,
		high_ticks: int = -1, start_tick: int = -1) -> void:
	## 生成 cycles 个完整周期；period 必须为偶数（M3 契约）。
	## start_tick 用绝对 tick（默认从当前 tick 起），避免 now 停在最后一个事件处导致相位偏移。
	var p := maxi(2, period)
	if p % 2 == 1:
		p += 1
	var high := p / 2 if high_ticks < 0 else mini(p - 1, maxi(1, high_ticks))
	var base := sim.now() if start_tick < 0 else start_tick
	for i in cycles:
		sim.set_input(wire, SimValue.ONE, maxi(0, base + i * p - sim.now()))
		sim.set_input(wire, SimValue.ZERO, maxi(1, base + i * p + high - sim.now()))

static func read_value(sim: SimCircuit, q: Array) -> int:
	var bits := ""
	for i in range(q.size() - 1, -1, -1):
		bits += sim.probe(str(q[i]))
	return SimValue.value_of(bits)

static func measure_counter_period(width: int, max_period: int = 120) -> Dictionary:
	## 实测最小稳定周期：偶数 + 无 METASTABLE + 连续两个完整周期输出正确。
	## 做法：先在 rst=1 的沿上清零，释放复位后第 k 个沿的稳定值应为 k（满 2^width 回绕）；
	## 扫描覆盖两个完整计数周期（含最高位翻转与进位链最长路径）。
	var w := maxi(1, width)
	var mod := 1 << w
	var edges := 2 * mod + 2
	for p in range(4, max_period + 1, 2):
		var c := SimCircuit.new("period_probe")
		c.add_wire("clk", SimValue.ZERO)
		c.add_wire("rst", SimValue.ZERO)
		var r := create_counter(c, "cnt", w, "clk", "rst")
		if not bool(r.get("ok", false)):
			return {"ok": false, "error": str(r.get("error", ""))}
		var q: Array = r["q"]
		c.set_input("rst", SimValue.ONE, 0)
		c.set_input("rst", SimValue.ZERO, 1)
		for k in range(1, edges + 1):
			c.set_input("clk", SimValue.ONE, k * p)
			c.set_input("clk", SimValue.ZERO, k * p + p / 2)
		var ok := true
		# 第 k 个沿的 Q 在 k*p+2 才更新；在下一个沿前的 (k+1)*p-1 采样已稳定。
		for k in range(1, edges):
			c.run_until((k + 1) * p - 1)
			var v := read_value(c, q)
			if v != (k % mod):
				ok = false
				break
		if ok and c.metastable.is_empty():
			return {"ok": true, "error": "", "period": p, "edges_checked": edges}
	return {"ok": false, "error": "在 %d tick 内未找到稳定周期" % max_period}
