class_name Ch04Checks
extends RefCounted

## CH04（4.1–4.5）gate 判定入口。出口沿用 `GateReport` / `GateResult`，与 CH02/CH03/CH05 同构。
##
## 已落地 kind：mux_truth / encapsulation / mux_tree / quiz / alu_sweep / opcode_route /
##              control_table / illegal_control / decoder_unique / memory_rw / chip_select /
##              capacity_table / bus_contention / bus_select / port_map
## pending kind：area_check（4.2 只写「≤ 预算」，预算数值未定；不进分母、不判红）。

const Kit := preload("res://src/core/lab_gate_kit.gd")

const PENDING_REASONS := {
	"area_check": "课文只写「展开门数 ≤ 预算」，预算数值未定；未定前只记录门数、不判红",
}

const CONTROL_SIGNALS := ["sel_add", "sel_and", "sel_or", "sel_not", "reg_we"]

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch04_levels.json")

static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	var rep := GateReport.new()
	var pending := []
	var answers: Dictionary = inputs.get("answers", {})
	for raw in cfg.get("gate_cases", []):
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		var title := str(c.get("title", ""))
		var kind := str(c.get("kind", ""))
		if PENDING_REASONS.has(kind):
			var reason := str(c.get("pending_reason", PENDING_REASONS[kind]))
			pending.append({"id": cid, "kind": kind, "title": title, "reason": reason})
			Kit.add_pending(rep, c, reason)
			continue
		match kind:
			"mux_truth":
				_mux_truth(rep, tracker, c, answers)
			"encapsulation":
				_encapsulation(rep, tracker, c, answers)
			"mux_tree":
				_mux_tree(rep, tracker, c, answers)
			"quiz":
				Kit.judge_quiz(rep, tracker, c, answers)
			"alu_sweep":
				_alu_sweep(rep, tracker, c, answers)
			"opcode_route":
				_opcode_route(rep, tracker, c, answers)
			"control_table":
				_control_table(rep, tracker, c, answers)
			"illegal_control":
				_illegal_control(rep, tracker, c, answers)
			"decoder_unique":
				_decoder_unique(rep, tracker, c, answers)
			"memory_rw":
				_memory_rw(rep, tracker, c, answers)
			"chip_select":
				_chip_select(rep, tracker, c, answers)
			"capacity_table":
				_capacity_table(rep, tracker, c, answers)
			"bus_contention":
				_bus_contention(rep, tracker, c, answers)
			"bus_select":
				_bus_select(rep, tracker, c, answers)
			"port_map":
				_port_map(rep, tracker, c, answers)
			_:
				Kit.emit(rep, tracker, GateResult.E_GENERIC, c, false, {"kind": kind},
					"已知判定 kind", kind, "未知判定 kind：%s" % kind)
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

# ---------------------------------------------------------------- 4.1 多路选择

static func _mux_truth(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var rows: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("rows", [])
	var bad := ""
	if rows.size() != int(c.get("rows", 4)):
		bad = "需要 %d 行，实得 %d" % [int(c.get("rows", 4)), rows.size()]
	for raw in rows:
		if not bad.is_empty():
			break
		if not (raw is Dictionary):
			bad = "行不是字典"
			break
		var r: Dictionary = raw
		var s := int(r.get("s", -1))
		var a := int(r.get("a", -1))
		var b := int(r.get("b", -1))
		var y := int(r.get("y", -1))
		if s != 0 and s != 1:
			bad = "S 不是 0/1：%s" % str(r)
			break
		var want := b if s == 1 else a
		if y != want:
			bad = "S=%d 时期望 Y=%d，实得 %d" % [s, want, y]
			break
	var counts := {0: 0, 1: 0}
	for raw in rows:
		if raw is Dictionary:
			var s := int(raw.get("s", -1))
			if counts.has(s):
				counts[s] = int(counts[s]) + 1
	var ok := bad.is_empty() and int(counts[0]) == 2 and int(counts[1]) == 2
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, rows, "4/4", rows,
		bad if not bad.is_empty() else "S=0/1 各两行，4/4")

static func _encapsulation(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ports: Array = got.get("ports", [])
	var want: Array = c.get("ports", [])
	var ok := bool(got.get("encapsulated", false)) and ports == want
	Kit.emit(rep, tracker, GateResult.E_ENCAPSULATION, c, ok, got, want, ports,
		"封装端口 %s，期望 %s" % [str(ports), str(want)])

static func _mux_tree(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var outputs: Array = got.get("outputs", [])
	var n := int(c.get("inputs", 8))
	var bad := ""
	if outputs.size() != n:
		bad = "需要 %d 个选通结果，实得 %d" % [n, outputs.size()]
	for i in outputs.size():
		if not bad.is_empty():
			break
		if int(outputs[i]) != i:
			bad = "选择 %d 期望输入 %d，实得 %d" % [i, i, int(outputs[i])]
			break
	if bad.is_empty() and int(got.get("levels", 0)) != int(c.get("levels", 3)):
		bad = "树深 %s，期望 %d 级（摊成长链是 7 级）" % [str(got.get("levels", "?")), int(c.get("levels", 3))]
	var ok := bad.is_empty()
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, got, {"outputs": n, "levels": 3}, got,
		bad if not bad.is_empty() else "%d 路逐个选通，%d 级树" % [n, int(c.get("levels", 3))])

# ---------------------------------------------------------------- 4.2 ALU-8

static func _alu_sweep(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var results: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("results", [])
	var ops: Array = c.get("ops", [])
	var operands: Array = c.get("operands", [])
	var need := ops.size() * operands.size()
	var bad := ""
	var seen := {}
	for raw in results:
		if not (raw is Dictionary):
			bad = "结果不是字典"
			break
		var r: Dictionary = raw
		var op := str(r.get("op", ""))
		var a := int(r.get("a", -1))
		var b := int(r.get("b", -1))
		var y := int(r.get("y", -1))
		if not ops.has(op):
			bad = "未知操作 %s" % op
			break
		var key := "%s:%d:%d" % [op, a, b]
		if seen.has(key):
			bad = "重复断言 %s" % key
			break
		seen[key] = true
		var want := _alu(op, a, b)
		if y != want:
			bad = "%s(%d,%d) 期望 %d，实得 %d" % [op, a, b, want, y]
			break
	var ok := bad.is_empty() and results.size() >= need and seen.size() == need
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, results.size(), need,
		{"count": results.size(), "bad": bad},
		bad if not bad.is_empty() else "%d/%d 断言通过" % [results.size(), need])

static func _alu(op: String, a: int, b: int) -> int:
	match op:
		"add": return (a + b) & 255
		"sub": return (a - b) & 255
		"and": return a & b
		"or": return a | b
		"xor": return a ^ b
		"not": return (~a) & 255
		"shl": return (a << 1) & 255
		"shr": return a >> 1
	return -1

static func _opcode_route(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var data_ports: Array = got.get("data_ports", [])
	var op_ports: Array = got.get("opcode_ports", [])
	var bad := ""
	if int(op_ports.size()) != int(c.get("opcode_ports", 3)):
		bad = "操作码端口 %d 根，期望 %d" % [op_ports.size(), int(c.get("opcode_ports", 3))]
	for port in op_ports:
		if data_ports.has(port):
			bad = "操作码端口 %s 同时接进数据端" % str(port)
			break
	if bool(got.get("opcode_in_data", true)):
		bad = "操作码接进了数据端"
	var ok := bad.is_empty()
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, got,
		{"opcode_ports": 3, "opcode_in_data": false}, got,
		bad if not bad.is_empty() else "3 根操作码只进选择端")

# ---------------------------------------------------------------- 4.3 控制单元

static func _control_table(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var cells: Dictionary = Kit.answer_dict(answers, str(c.get("id", ""))).get("cells", {})
	var want: Dictionary = c.get("expect", {})
	var bad := ""
	var checked := 0
	for op in want.keys():
		var row: Dictionary = cells.get(str(op), {})
		if row.is_empty():
			bad = "缺操作码 %s 的整行" % str(op)
			break
		for sig in (want[op] as Dictionary).keys():
			if int(row.get(str(sig), -1)) != int((want[op] as Dictionary)[sig]):
				bad = "op=%s %s 期望 %d，实得 %s" % [str(op), str(sig),
					int((want[op] as Dictionary)[sig]), str(row.get(str(sig), "缺"))]
				break
			checked += 1
		if not bad.is_empty():
			break
		for sig in row.keys():
			if not (want[op] as Dictionary).has(str(sig)):
				bad = "op=%s 出现多余信号 %s" % [str(op), str(sig)]
				break
		if not bad.is_empty():
			break
	var ok := bad.is_empty() and cells.size() == want.size() and checked == want.size() * CONTROL_SIGNALS.size()
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, ok, cells, want, cells,
		bad if not bad.is_empty() else "%d 格逐格对上" % checked)

static func _illegal_control(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var rows: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("illegal", [])
	var want_ops := []
	for o in (c.get("illegal_opcodes", []) as Array):
		want_ops.append(int(o))
	var signals: Array = c.get("signals", CONTROL_SIGNALS)
	var bad := ""
	if rows.size() != want_ops.size():
		bad = "非法码 %d 个，期望 %d 个" % [rows.size(), want_ops.size()]
	var seen := {}
	for raw in rows:
		if not bad.is_empty():
			break
		if not (raw is Dictionary):
			bad = "行不是字典"
			break
		var r: Dictionary = raw
		var op := int(r.get("opcode", -1))
		if not want_ops.has(op):
			bad = "非法码 %d 不在清单" % op
			break
		seen[op] = true
		var sigs: Dictionary = r.get("signals", {})
		for sig in signals:
			if int(sigs.get(str(sig), -1)) != 0:
				bad = "非法码 %d 的 %s 仍为 %s（必须全 0）" % [op, str(sig), str(sigs.get(str(sig), "缺"))]
				break
		if not bad.is_empty():
			break
	var ok := bad.is_empty() and seen.size() == want_ops.size()
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, rows, want_ops, rows,
		bad if not bad.is_empty() else "%d 个非法码全 0" % want_ops.size())

static func _decoder_unique(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var rows: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("legal", [])
	var want_ops := []
	for o in (c.get("legal_opcodes", []) as Array):
		want_ops.append(int(o))
	var bad := ""
	if rows.size() != want_ops.size():
		bad = "合法码 %d 个，期望 %d 个" % [rows.size(), want_ops.size()]
	var seen := {}
	for raw in rows:
		if not bad.is_empty():
			break
		if not (raw is Dictionary):
			bad = "行不是字典"
			break
		var r: Dictionary = raw
		var op := int(r.get("opcode", -1))
		if not want_ops.has(op):
			bad = "合法码 %d 不在清单" % op
			break
		seen[op] = true
		if int(r.get("lit", 0)) != 1:
			bad = "合法码 %d 亮的根数 %s，期望恰好 1" % [op, str(r.get("lit", "缺"))]
			break
	var ok := bad.is_empty() and seen.size() == want_ops.size()
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, rows, "恰好 1 根", rows,
		bad if not bad.is_empty() else "%d 个合法码各 1 根" % want_ops.size())

# ---------------------------------------------------------------- 4.4 存储

static func _memory_rw(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var groups: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("groups", [])
	var need := int(c.get("groups", 16))
	var bad := ""
	var seen := {}
	for raw in groups:
		if not (raw is Dictionary):
			bad = "组不是字典"
			break
		var g: Dictionary = raw
		var addr := int(g.get("addr", -1))
		var value := int(g.get("value", -1))
		var back := int(g.get("read", -1))
		if addr < 0 or addr > 255:
			bad = "地址越界 %d" % addr
			break
		if value < 0 or value > 255:
			bad = "写入值越界 %d" % value
			break
		if back != value:
			bad = "地址 %d 写入 %d，读回 %d" % [addr, value, back]
			break
		seen[addr] = true
	var ok := bad.is_empty() and groups.size() >= need and seen.size() == groups.size()
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, groups.size(), need,
		{"count": groups.size(), "bad": bad},
		bad if not bad.is_empty() else "%d/%d 组读写一致" % [groups.size(), need])

static func _chip_select(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var low: Dictionary = got.get("low", {})
	var high: Dictionary = got.get("high", {})
	var bad := ""
	if int(low.get("addr", -1)) != int(c.get("low_addr", 0)):
		bad = "低端地址 %s，期望 %d" % [str(low.get("addr", "?")), int(c.get("low_addr", 0))]
	elif int(high.get("addr", -1)) != int(c.get("high_addr", 511)):
		bad = "高端地址 %s，期望 %d" % [str(high.get("addr", "?")), int(c.get("high_addr", 511))]
	elif int(low.get("value", -1)) < 0 or int(low.get("value", -1)) > 255:
		bad = "低端值越界"
	elif int(high.get("value", -1)) < 0 or int(high.get("value", -1)) > 255:
		bad = "高端值越界"
	elif str(got.get("decode", "")) != "cs":
		bad = "片选译码标记缺失"
	var ok := bad.is_empty()
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, got, "0 与 511 各一组", got,
		bad if not bad.is_empty() else "512 字节两端读写正确")

static func _capacity_table(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var addr_rows: Array = got.get("addr", [])
	var data_rows: Array = got.get("data", [])
	var bad := ""
	var want_addr := [8, 9, 10]
	var want_data := [8, 16]
	if addr_rows.size() != want_addr.size() or data_rows.size() != want_data.size():
		bad = "表格行数不符 addr=%d data=%d" % [addr_rows.size(), data_rows.size()]
	for i in addr_rows.size():
		if not bad.is_empty():
			break
		var r: Dictionary = addr_rows[i]
		var bits := int(r.get("bits", -1))
		if bits != int(want_addr[i]) or int(r.get("slots", -1)) != (1 << bits):
			bad = "地址行 %d：bits=%s slots=%s" % [i, str(r.get("bits", "?")), str(r.get("slots", "?"))]
			break
	for i in data_rows.size():
		if not bad.is_empty():
			break
		var r2: Dictionary = data_rows[i]
		var bits2 := int(r2.get("bits", -1))
		if bits2 != int(want_data[i]) or int(r2.get("width", -1)) != bits2:
			bad = "数据行 %d：bits=%s width=%s" % [i, str(r2.get("bits", "?")),
				str(r2.get("width", "?"))]
	var ok := bad.is_empty()
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, ok, got, {"addr": want_addr, "data": want_data},
		got, bad if not bad.is_empty() else "两列逐格对上")

# ---------------------------------------------------------------- 4.5 总线

static func _bus_contention(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var drivers: Array = got.get("drivers", [])
	var line := str(got.get("line", ""))
	var bad := ""
	var en := 0
	var v1 := 0
	var v0 := 0
	for raw in drivers:
		if raw is Dictionary:
			if int(raw.get("en", 0)) == 1:
				en += 1
				if int(raw.get("v", -1)) == 1:
					v1 += 1
				elif int(raw.get("v", -1)) == 0:
					v0 += 1
	if en < 2:
		bad = "需要至少两个 EN=1 的驱动"
	if bad.is_empty() and (v1 == 0 or v0 == 0):
		bad = "两个驱动必须一个送 1、一个送 0"
	if bad.is_empty() and line != "X":
		bad = "争用时线值必须读回 X，实得 %s" % line
	if bad.is_empty() and not bool(got.get("reported", false)):
		bad = "只读回 X 不够，必须报「争用」"
	var ok := bad.is_empty()
	Kit.emit(rep, tracker, GateResult.E_X_ROW, c, ok, got, {"line": "X", "reported": true}, got,
		bad if not bad.is_empty() else "读回 X 且报争用")

static func _bus_select(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var rows: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("reads", [])
	var n := int(c.get("devices", 8))
	var bad := ""
	var seen := {}
	for raw in rows:
		if not (raw is Dictionary):
			bad = "读点不是字典"
			break
		var r: Dictionary = raw
		var dev := int(r.get("dev", -1))
		var en := int(r.get("en", 0))
		var value := int(r.get("value", -1))
		if dev < 0 or dev >= n:
			bad = "器件号越界 %d" % dev
			break
		if seen.has(dev):
			bad = "器件 %d 重复选中" % dev
			break
		seen[dev] = true
		if en != 1:
			bad = "器件 %d 的 EN 不是 1" % dev
			break
		if value != dev:
			bad = "器件 %d 读回 %d，期望 %d" % [dev, value, dev]
			break
	var ok := bad.is_empty() and rows.size() == n and seen.size() == n
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, rows.size(), n,
		{"count": rows.size(), "bad": bad},
		bad if not bad.is_empty() else "%d 个器件逐个选中，每次仅一个 EN" % n)

static func _port_map(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var rows: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("mappings", [])
	var want: Array = c.get("expect", [])
	var bad := ""
	var seen := {}
	for raw in rows:
		if not (raw is Dictionary):
			bad = "映射不是字典"
			break
		var r: Dictionary = raw
		var addr := int(r.get("addr", -1))
		seen[addr] = {"port": str(r.get("port", "")), "lit": bool(r.get("lit", false))}
	for w in want:
		var addr := int(w.get("addr", -1))
		if not seen.has(addr):
			bad = "缺地址 %d 的映射" % addr
			break
		if str((seen[addr] as Dictionary).get("port", "")) != str(w.get("port", "")):
			bad = "地址 %d 期望端口 %s，实得 %s" % [addr, str(w.get("port", "")),
				str((seen[addr] as Dictionary).get("port", ""))]
			break
		if bool((seen[addr] as Dictionary).get("lit", false)) != bool(w.get("lit", false)):
			bad = "地址 %d 的灯状态不符" % addr
			break
	var ok := bad.is_empty() and rows.size() == want.size()
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, ok, rows, want, rows,
		bad if not bad.is_empty() else "%d 条端口映射逐条对上" % want.size())
