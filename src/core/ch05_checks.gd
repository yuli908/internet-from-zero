class_name Ch05Checks
extends RefCounted

## CH05（5.1–5.4）gate 判定入口。出口沿用 `GateReport` / `GateResult`，与 CH02 同构。
##
## 已落地 kind：register_final / control_line_audit / quiz / control_row / isa_sweep /
##              illegal_opcode / program_run / loop_run / loop_boundary / first_fail_tick /
##              retest_after_change / derived_number / timing_calc /
##              waveform_align（5.1 扩 kind，判定在 `WaveformAlign`；只扩 kind、不新开码，落 10）
## 无 pending kind（`waveform_align` 已接入，不再走"人工走查/不进分母"的降级路径）。
##
## 计时两数不从数据里手填：级数取 `inputs.delay_report.stages`（3.2 报告），
## 单级延迟取 `inputs.delay_report.stage_delay_ps`（1.6 实测）；缺报告一律 E_DELAY_MISMATCH(9)。

const Kit := preload("res://src/core/lab_gate_kit.gd")

const PENDING_REASONS := {}

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch05_levels.json")

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
			"register_final":
				_register_final(rep, tracker, c, answers)
			"waveform_align":
				_waveform_align(rep, tracker, c, answers)
			"control_line_audit":
				_control_line_audit(rep, tracker, cfg, c, answers)
			"quiz":
				Kit.judge_quiz(rep, tracker, c, answers)
			"control_row":
				_control_row(rep, tracker, c, answers, inputs)
			"isa_sweep":
				_isa_sweep(rep, tracker, c, answers)
			"illegal_opcode":
				_illegal_opcode(rep, tracker, c, answers)
			"program_run":
				_program_run(rep, tracker, c, answers)
			"loop_run":
				_loop_run(rep, tracker, c, answers)
			"loop_boundary":
				_loop_boundary(rep, tracker, c, answers)
			"first_fail_tick":
				_first_fail_tick(rep, tracker, c, answers, inputs)
			"retest_after_change":
				_retest_after_change(rep, tracker, c, answers, inputs)
			"derived_number":
				_derived_number(rep, tracker, c, answers, inputs)
			"timing_calc":
				_timing_calc(rep, tracker, c, answers, inputs)
			_:
				rep.add_case(GateResult.E_GENERIC, cid, title, {"kind": kind}, "已知判定 kind",
					kind, [], "未知判定 kind：%s" % kind, bool(c.get("required", true)), 0)
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

# ---------------------------------------------------------------- 5.1 数据通路

static func _register_final(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want: Dictionary = c.get("expect", {})
	var regs: Dictionary = got.get("regs", got)
	var ok := true
	var code := GateResult.OK
	var detail := "终值 %s" % str(regs)
	for reg in want.keys():
		var name := str(reg)
		if not regs.has(name):
			ok = false
			code = GateResult.E_OUTPUT_MISMATCH
			detail = "缺寄存器 %s 终值" % name
			break
		if int(regs[name]) != int(want[reg]):
			ok = false
			code = GateResult.E_OUTPUT_MISMATCH
			detail = "%s 期望 %d，实得 %d" % [name, int(want[reg]), int(regs[name])]
			break
	for name in regs.keys():
		if not _known_register(str(name)):
			ok = false
			code = GateResult.E_UNKNOWN_TARGET
			detail = "未知寄存器名 %s" % str(name)
			break
	var max_ticks := int(c.get("max_ticks", -1))
	if ok and max_ticks > 0 and got.has("ticks") and int(got["ticks"]) > max_ticks:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "执行拍数 %d > 应有 %d" % [int(got["ticks"]), max_ticks]
	Kit.emit(rep, tracker, code, c, ok, got, _expect_regs(want, max_ticks), regs, detail)

static func _expect_regs(want: Dictionary, max_ticks: int) -> Dictionary:
	var out := {"regs": want}
	if max_ticks > 0:
		out["max_ticks"] = max_ticks
	return out

static func _known_register(name: String) -> bool:
	## MUD-8 寄存器：设计表 A/B/PC/IR，课文 5.3 用 R1/R2/R3；两者都收，其余判未知。
	return ["A", "B", "PC", "IR", "R1", "R2", "R3", "R4"].has(name)

static func _waveform_align(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	## 5.1 扩 kind：三样（终值/起止拍/逐拍拍号）判定在 `WaveformAlign`，这里只接统一出口。
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var res: Dictionary = WaveformAlign.verify(c, got)
	Kit.emit(rep, tracker, int(res.get("code", GateResult.E_OUTPUT_MISMATCH)), c,
		bool(res.get("ok", false)), res.get("input", null), res.get("expected", null),
		res.get("actual", null), str(res.get("detail", "")))

static func _control_line_audit(rep: GateReport, tracker: GateAttemptTracker, cfg: Dictionary,
		c: Dictionary, answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var lines: Array = got.get("lines", [])
	var want: Array = c.get("expect_lines", [])
	var legal: Array = ((cfg.get("datapath", {}) as Dictionary).get("control_lines", []) as Array)
	var ok := true
	var code := GateResult.OK
	var detail := "翻转线 %s" % str(lines)
	var unknown := []
	for raw in lines:
		if not legal.is_empty() and not legal.has(str(raw)):
			unknown.append(str(raw))
	if not unknown.is_empty():
		ok = false
		code = GateResult.E_UNKNOWN_TARGET
		detail = "未知控制线 %s" % str(unknown)
	else:
		var extra := []
		var missing := []
		for raw in lines:
			if not want.has(str(raw)):
				extra.append(str(raw))
		for raw in want:
			if not lines.has(str(raw)):
				missing.append(str(raw))
		if not extra.is_empty() or not missing.is_empty():
			ok = false
			code = GateResult.E_OUTPUT_MISMATCH
			detail = "多翻转 %s / 少翻转 %s" % [str(extra), str(missing)]
	Kit.emit(rep, tracker, code, c, ok, {"lines": lines}, want, lines, detail)

# ---------------------------------------------------------------- 5.2 指令集

static func _control_row(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want: Dictionary = c.get("expect", {})
	var ok := true
	var code := GateResult.OK
	var detail := "行 %s" % str(got)
	if got.is_empty():
		ok = false
		code = GateResult.E_TABLE_CELL
		detail = "控制表未填写"
	elif int(got.get("opcode", -1)) != int(want.get("opcode", -2)):
		ok = false
		code = GateResult.E_TABLE_CELL
		detail = "操作码 0x%02X ≠ 0x%02X" % [int(got.get("opcode", -1)), int(want.get("opcode", -2))]
	elif str(got.get("mnemonic", "")) != str(want.get("mnemonic", "")):
		ok = false
		code = GateResult.E_TABLE_CELL
		detail = "助记符 %s ≠ %s" % [str(got.get("mnemonic", "")), str(want.get("mnemonic", ""))]
	elif not _same_list(_line_set(got.get("lines", [])), _line_set(want.get("lines", []))):
		ok = false
		code = GateResult.E_TABLE_CELL
		detail = "控制线 %s ≠ %s" % [str(got.get("lines", [])), str(want.get("lines", []))]
	var expect_final: Variant = c.get("expect_final", null)
	if ok and expect_final is Dictionary:
		var regs: Dictionary = got.get("final", {})
		if not _same_dict(regs, expect_final as Dictionary):
			ok = false
			code = GateResult.E_OUTPUT_MISMATCH
			detail = "终值 %s ≠ %s" % [str(regs), str(expect_final)]
	var expect_ticks: Variant = c.get("expect_ticks", null)
	if ok and expect_ticks != null and got.has("ticks") and int(got["ticks"]) != int(expect_ticks):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "拍数 %d ≠ %d" % [int(got["ticks"]), int(expect_ticks)]
	var wave: Dictionary = inputs.get("waveform", {})
	if ok and expect_ticks == null and wave.has("ticks") and got.has("ticks") \
			and int(got["ticks"]) != int(wave["ticks"]):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "拍数 %d 与波形 %d 不符" % [int(got["ticks"]), int(wave["ticks"])]
	Kit.emit(rep, tracker, code, c, ok, got, want, got, detail)

static func _line_set(lines: Variant) -> Array:
	var out := []
	if lines is Array:
		for raw in lines:
			out.append(str(raw))
	out.sort()
	return out

static func _same_list(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in a.size():
		if str(a[i]) != str(b[i]):
			return false
	return true

static func _same_dict(a: Dictionary, b: Dictionary) -> bool:
	if a.size() != b.size():
		return false
	for k in b.keys():
		if not a.has(k) or int(a[k]) != int(b[k]):
			return false
	return true

static func _isa_sweep(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Array = Kit.answer_list(answers, str(c.get("id", "")))
	var isa: Array = c.get("isa", [])
	var ok := true
	var code := GateResult.OK
	var detail := ""
	var seen := {}
	for raw in got:
		if raw is Dictionary:
			var oc := int((raw as Dictionary).get("opcode", -1))
			if seen.has(oc):
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "操作码 0x%02X 重复单步" % oc
				break
			seen[oc] = raw
	if ok:
		for i in isa.size():
			var item: Dictionary = isa[i]
			var oc := int(item.get("opcode", -1))
			if not seen.has(oc):
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "第 %d 条（0x%02X）未单步" % [i + 1, oc]
				break
			var entry: Dictionary = seen[oc]
			if str(entry.get("mnemonic", "")) != str(item.get("mnemonic", "")):
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "第 %d 条（0x%02X）·助记符 %s ≠ %s" % [i + 1, oc,
					str(entry.get("mnemonic", "")), str(item.get("mnemonic", ""))]
				break
			var bad_tick := int(entry.get("bad_tick", 0))
			if bad_tick > 0:
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "第 %d 条（0x%02X）·第 %d 拍" % [i + 1, oc, bad_tick]
				break
			if not entry.has("ticks"):
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "第 %d 条（0x%02X）·未报到拍" % [i + 1, oc]
				break
	if detail.is_empty():
		detail = "%d/%d 条已单步" % [seen.size(), isa.size()]
	Kit.emit(rep, tracker, code, c, ok, {"step": got.size()}, "%d 条全单步" % isa.size(),
		"%d 条" % seen.size(), detail)

static func _illegal_opcode(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var expect: Array = c.get("expect_opcodes", [])
	var tested: Array = got.get("tested", [])
	var rejected: Array = got.get("rejected", [])
	var reported: Array = got.get("reported", [])
	var ok := true
	var code := GateResult.OK
	var detail := ""
	var missing_test := []
	for raw in expect:
		if not tested.has(int(raw)):
			missing_test.append(int(raw))
	if not missing_test.is_empty():
		ok = false
		code = GateResult.E_COVERAGE
		detail = "空码只测 %d/%d：缺 %s" % [expect.size() - missing_test.size(), expect.size(), str(missing_test)]
	else:
		for raw in expect:
			if not rejected.has(int(raw)):
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "空码未拒：0x%02X" % int(raw)
				break
		if ok:
			for raw in expect:
				if not reported.has(int(raw)):
					ok = false
					code = GateResult.E_OUTPUT_MISMATCH
					detail = "未回报操作码：0x%02X" % int(raw)
					break
	if detail.is_empty():
		detail = "空码 %d/%d 全部被拒并回报" % [expect.size(), expect.size()]
	Kit.emit(rep, tracker, code, c, ok, got, {"rejected": expect}, {"rejected": rejected}, detail)

# ---------------------------------------------------------------- 5.3 程序

static func _program_run(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want_out := int(c.get("expect_out", 8))
	var want_regs: Dictionary = c.get("expect_regs", {})
	var max_ticks := int(c.get("max_ticks", -1))
	var ok := true
	var code := GateResult.OK
	var detail := "输出 %s，终值 %s" % [str(got.get("out", "?")), str(got.get("regs", {}))]
	if got.is_empty() or not got.has("out"):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "未提交程序输出"
	elif int(got["out"]) != want_out:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "输出 %d ≠ %d" % [int(got["out"]), want_out]
	if ok and not want_regs.is_empty():
		var regs: Dictionary = got.get("regs", {})
		for reg in want_regs.keys():
			if not regs.has(reg) or int(regs[reg]) != int(want_regs[reg]):
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "%s 终值不等（期望 %d）" % [str(reg), int(want_regs[reg])]
				break
		if ok:
			for reg in regs.keys():
				if not _known_register(str(reg)):
					ok = false
					code = GateResult.E_UNKNOWN_TARGET
					detail = "未知寄存器名 %s" % str(reg)
					break
	if ok and max_ticks > 0 and got.has("ticks") and int(got["ticks"]) > max_ticks:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "执行拍数 %d > 应有 %d" % [int(got["ticks"]), max_ticks]
	Kit.emit(rep, tracker, code, c, ok, got, {"out": want_out, "regs": want_regs}, got, detail)

static func _loop_run(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want_out := int(c.get("expect_out", 15))
	var want_jumps := int(c.get("expect_jumps", 5))
	var ok := true
	var code := GateResult.OK
	var detail := "输出 %s，回跳 %s，停机 %s" % [str(got.get("out", "?")), str(got.get("back_jumps", "?")),
		str(got.get("halted", "?"))]
	if got.is_empty():
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "未提交循环结果"
	elif not bool(got.get("halted", false)):
		ok = false
		code = GateResult.E_TARGET_UNREACHED
		detail = "未停机（撞拍数上限）"
	elif int(got.get("out", -1)) != want_out:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "输出 %d ≠ %d" % [int(got.get("out", -1)), want_out]
	elif int(got.get("back_jumps", -1)) != want_jumps:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "回跳 %d ≠ %d" % [int(got.get("back_jumps", -1)), want_jumps]
	Kit.emit(rep, tracker, code, c, ok, got, {"out": want_out, "back_jumps": want_jumps, "halted": true},
		got, detail)

static func _loop_boundary(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := not got.is_empty() and int(got.get("out", -1)) == 0 and int(got.get("back_jumps", -1)) == 0
	var detail := "上限改 0：输出 %s，回跳 %s" % [str(got.get("out", "?")), str(got.get("back_jumps", "?"))]
	if not ok:
		detail += "（边界未测或一次未进）"
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"out": 0, "back_jumps": 0}, got, detail)

# ---------------------------------------------------------------- 5.4 时钟上限

static func _first_fail_tick(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var report: Dictionary = inputs.get("delay_report", {})
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var code := GateResult.OK
	var detail := "首个失败拍 %s，线 %s，余量 %s ps" % [str(got.get("tick", "?")),
		str(got.get("line", "?")), str(got.get("margin_ps", "?"))]
	if not _has_timing(report) or not report.has("clock_period_ps"):
		ok = false
		code = GateResult.E_DELAY_MISMATCH
		detail = "手填：缺 3.2 级数 / 1.6 单级延迟 / 时钟周期报告"
	elif int(got.get("tick", -1)) != int(report.get("fail_tick", -2)):
		ok = false
		code = GateResult.E_DELAY_MISMATCH
		detail = "拍号 %d 与报告 %d 不符（手填）" % [int(got.get("tick", -1)), int(report.get("fail_tick", -2))]
	elif str(got.get("line", "")) != str(report.get("fail_line", "")):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "失败线 %s ≠ 报告 %s" % [str(got.get("line", "")), str(report.get("fail_line", ""))]
	else:
		var margin := _margin_ps(report)
		if margin <= 0:
			ok = false
			code = GateResult.E_TIMING_MARGIN
			detail = "余量 %.1f ps ≤ 0（建立/保持已破）" % margin
		elif absf(float(got.get("margin_ps", 1e18)) - margin) > absf(margin) * 0.05:
			ok = false
			code = GateResult.E_DELAY_MISMATCH
			detail = "余量 %.1f ps 与报告实算 %.1f ps 不符（手填）" % [float(got.get("margin_ps", 1e18)), margin]
	Kit.emit(rep, tracker, code, c, ok, got, {"tick": report.get("fail_tick", null)},
		{"tick": got.get("tick", null), "margin_ps": _margin_ps(report)}, detail)

static func _retest_after_change(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var report: Dictionary = inputs.get("delay_report", {})
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var code := GateResult.OK
	var detail := "改后级数 %s（改前 %s），同频复测 %s" % [str(got.get("stages_after", "?")),
		str(report.get("stages", "?")), str(got.get("retest_pass", "?"))]
	if not _has_timing(report):
		ok = false
		code = GateResult.E_DELAY_MISMATCH
		detail = "缺 3.2 级数报告，无法判「改后级数下降」"
	elif not bool(got.get("same_freq", false)):
		ok = false
		code = GateResult.E_DELAY_EXCEED
		detail = "未在原先崩的那档频率复测（调低频率属回避）"
	elif int(got.get("stages_after", 999)) >= int(report.get("stages", 0)):
		ok = false
		code = GateResult.E_DELAY_EXCEED
		detail = "级数未下降（%d ≥ %d，未改结构）" % [int(got.get("stages_after", 999)),
			int(report.get("stages", 0))]
	elif not bool(got.get("retest_pass", false)):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "同频复测仍错"
	elif got.has("margin_ps") and float(got["margin_ps"]) <= 0.0:
		ok = false
		code = GateResult.E_TIMING_MARGIN
		detail = "余量 %.1f ps ≤ 0" % float(got["margin_ps"])
	Kit.emit(rep, tracker, code, c, ok, got, {"stages_before": report.get("stages", null)},
		{"stages_after": got.get("stages_after", null)}, detail)

static func _derived_number(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var report: Dictionary = inputs.get("delay_report", {})
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var code := GateResult.OK
	var detail := "周期 %s ps" % str(got.get("clock_period_ps", "?"))
	if not _has_timing(report):
		ok = false
		code = GateResult.E_DELAY_MISMATCH
		detail = "手填：缺 3.2 级数 / 1.6 单级延迟报告"
	else:
		var derived := _period_ps(report)
		var stated := float(got.get("clock_period_ps", -1.0))
		if absf(stated - derived) > absf(derived) * 0.05:
			ok = false
			code = GateResult.E_DELAY_MISMATCH
			detail = "手填 %d ps ≠ 级数×单级延迟 %d ps" % [int(stated), int(derived)]
	Kit.emit(rep, tracker, code, c, ok, got,
		{"clock_period_ps": _period_ps(report)}, {"clock_period_ps": got.get("clock_period_ps", null)},
		detail)

static func _timing_calc(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var report: Dictionary = inputs.get("delay_report", {})
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var code := GateResult.OK
	var detail := "作答 %s ps" % str(got.get("clock_period_ps", "?"))
	if not _has_timing(report):
		ok = false
		code = GateResult.E_DELAY_MISMATCH
		detail = "代入量缺失（需 9 级与实测单级延迟）"
	else:
		var derived := _period_ps(report)
		var stated := float(got.get("clock_period_ps", -1.0))
		if absf(stated - derived) > absf(derived) * 0.05:
			ok = false
			code = GateResult.E_DELAY_MISMATCH
			detail = "作答 %d ps，实测比值 %d ps（±5%%）" % [int(stated), int(derived)]
	Kit.emit(rep, tracker, code, c, ok, got, {"clock_period_ps": _period_ps(report)},
		{"clock_period_ps": got.get("clock_period_ps", null)}, detail)

static func _has_timing(report: Dictionary) -> bool:
	return int(report.get("stages", 0)) > 0 and float(report.get("stage_delay_ps", 0.0)) > 0.0

static func _period_ps(report: Dictionary) -> float:
	return float(int(report.get("stages", 0))) * float(report.get("stage_delay_ps", 0.0))

static func _margin_ps(report: Dictionary) -> float:
	return float(report.get("clock_period_ps", 0.0)) - _period_ps(report) \
		- float(report.get("setup_ps", 0.0)) - float(report.get("hold_ps", 0.0))
