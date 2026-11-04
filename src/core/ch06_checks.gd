class_name Ch06Checks
extends RefCounted

## CH06（6.1–6.6）gate 判定入口。出口沿用 `GateReport` / `GateResult`，与 CH02 同构。
##
## 已落地 kind：byte_check / range_cell / poll_compare / interrupt_trace / event_coverage /
##              frequency_check / divider_ratio / scale_check / loader_run / checksum /
##              load_address / cache_coverage / cache_avg / page_map / vm_capacity / quiz
## pending kind：cache_hit_rate（6.5）、page_swap_curve（6.6）——阈值未校准，先挂 pending 不进分母。
##
## 机器真值一律从 `inputs` 取（磁带表头、缓存实测、内存规格），玩家只提交结论；
## 缺机器真值判 3（未接线/未采集），不拿手填数字当依据。

const Kit := preload("res://src/core/lab_gate_kit.gd")

const PENDING_REASONS := {
	"cache_hit_rate": "耗时比 ≥2× 与命中率差阈值均为 17 §12-5 初值，待技术侧按实测校准后写进 gate_cases；本项只登记不判定，不进分母",
	"page_swap_curve": "抖动拐点阈值未校准，「曲线随超配上升」不足以下「抖动开始」判定；先挂 pending，不进分母",
}

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch06_levels.json")

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
			"byte_check":
				_byte_check(rep, tracker, c, answers)
			"range_cell":
				_range_cell(rep, tracker, c, answers)
			"poll_compare":
				_poll_compare(rep, tracker, c, answers)
			"interrupt_trace":
				_interrupt_trace(rep, tracker, c, answers, inputs)
			"event_coverage":
				_event_coverage(rep, tracker, c, answers)
			"frequency_check":
				_frequency_check(rep, tracker, c, answers)
			"divider_ratio":
				_divider_ratio(rep, tracker, c, answers)
			"scale_check":
				_scale_check(rep, tracker, c, answers)
			"loader_run":
				_loader_run(rep, tracker, c, answers)
			"checksum":
				_checksum(rep, tracker, c, answers)
			"load_address":
				_load_address(rep, tracker, c, answers, inputs)
			"cache_coverage":
				_cache_coverage(rep, tracker, c, answers)
			"cache_avg":
				_cache_avg(rep, tracker, c, answers, inputs)
			"page_map":
				_page_map(rep, tracker, c, answers)
			"vm_capacity":
				_vm_capacity(rep, tracker, c, answers, inputs)
			"quiz":
				Kit.judge_quiz(rep, tracker, c, answers)
			_:
				rep.add_case(GateResult.E_GENERIC, cid, title, {"kind": kind}, "已知判定 kind",
					kind, [], "未知判定 kind：%s" % kind, bool(c.get("required", true)), 0)
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

# ---------------------------------------------------------------- 6.1 字符集

static func _byte_check(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var text := str(c.get("expect_text", ""))
	var want_bytes := int(c.get("expect_bytes", -1))
	var want_chars := int(c.get("expect_chars", -1))
	var ok := true
	var code := GateResult.OK
	var detail := "字节 %s / 字符 %s / 往返 %s" % [str(got.get("bytes", "?")), str(got.get("chars", "?")),
		str(got.get("roundtrip", "?"))]
	if not got.has("bytes") or not got.has("chars") or not got.has("roundtrip"):
		ok = false
		code = GateResult.E_UNCONNECTED
		detail = "编码器未接线或未提交字节/字符数"
	elif int(got["bytes"]) != want_bytes or int(got["chars"]) != want_chars:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "字节/字符 %d/%d ≠ %d/%d" % [int(got["bytes"]), int(got["chars"]),
			want_bytes, want_chars]
	elif str(got["roundtrip"]) != text:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "解码回不到原文：%s" % str(got["roundtrip"])
	elif bool(c.get("expect_prefix", false)) and not bool(got.get("prefix_ok", false)):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "未按首字节判长度（丢掉长度前缀）"
	Kit.emit(rep, tracker, code, c, ok, got,
		{"bytes": want_bytes, "chars": want_chars, "text": text}, got, detail)

static func _range_cell(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var lo := int(c.get("expect_lo", -1))
	var hi := int(c.get("expect_hi", -1))
	var ok := got.has("lo") and got.has("hi") and int(got["lo"]) == lo and int(got["hi"]) == hi
	var detail := "可打印区间 %s–%s（期望 %d–%d）" % [str(got.get("lo", "?")), str(got.get("hi", "?")), lo, hi]
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, ok, got, {"lo": lo, "hi": hi}, got, detail)

# ---------------------------------------------------------------- 6.2 键盘

static func _poll_compare(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want_key := int(c.get("expect_keycode", -1))
	var max_int_ticks := int(c.get("max_int_ticks", 1))
	var ok := true
	var code := GateResult.OK
	var detail := "键码 轮询 %s / 中断 %s；中断 %s 拍，轮询 %s 圈" % [str(got.get("poll_keycode", "?")),
		str(got.get("int_keycode", "?")), str(got.get("int_ticks", "?")), str(got.get("poll_ticks", "?"))]
	if not got.has("poll_keycode") or not got.has("int_keycode"):
		ok = false
		code = GateResult.E_UNCONNECTED
		detail = "键码未写进显存（驱动未接线）"
	elif int(got["poll_keycode"]) != want_key or int(got["int_keycode"]) != want_key:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "键码不等于 %d（轮询 %d / 中断 %d）" % [want_key, int(got["poll_keycode"]), int(got["int_keycode"])]
	elif int(got.get("int_ticks", 9999)) > max_int_ticks:
		ok = false
		code = GateResult.E_DELAY_EXCEED
		detail = "中断响应 %d 拍 > %d 拍" % [int(got.get("int_ticks", 9999)), max_int_ticks]
	elif int(got.get("poll_ticks", 0)) < 1:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "轮询版未跑（圈数未报）"
	Kit.emit(rep, tracker, code, c, ok, got, {"keycode": want_key, "max_int_ticks": max_int_ticks},
		got, detail)

static func _interrupt_trace(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want_key := int(c.get("expect_keycode", -1))
	var trace: Dictionary = inputs.get("trace", {})
	var ok := true
	var code := GateResult.OK
	var detail := "保存现场 %s/%s，返回 %s，第二键 %s" % [str(got.get("saved_pc", "?")),
		str(got.get("saved_regs", "?")), str(got.get("return_pc", "?")), str(got.get("second_keycode", "?"))]
	if not trace.has("return_pc"):
		ok = false
		code = GateResult.E_UNCONNECTED
		detail = "缺机器返回地址（未采集现场）"
	elif not bool(got.get("saved_pc", false)) or not bool(got.get("saved_regs", false)):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "中断未保存现场，返回地址必错"
	elif int(got.get("return_pc", -1)) != int(trace["return_pc"]):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "返回 %d ≠ 机器 %d（程序跑飞）" % [int(got.get("return_pc", -1)), int(trace["return_pc"])]
	elif int(got.get("second_keycode", -1)) != want_key:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "连按第二次键码错（现场没留全）"
	Kit.emit(rep, tracker, code, c, ok, got, trace, got, detail)

static func _event_coverage(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want := int(c.get("expect_pressed", 2))
	var pressed := int(got.get("pressed", 0))
	var handled := int(got.get("handled", 0))
	var keycodes: Array = got.get("handled_keycodes", [])
	var ok := true
	var code := GateResult.OK
	var detail := "按下 %d / 处理 %d" % [pressed, handled]
	if pressed < want:
		ok = false
		code = GateResult.E_COVERAGE
		detail = "只触发 %d/%d 次按键（没覆盖漏键场景）" % [pressed, want]
	elif handled < pressed:
		ok = false
		code = GateResult.E_COVERAGE
		detail = "漏键：按下 %d 次只处理 %d 次" % [pressed, handled]
	elif keycodes.size() != handled or keycodes.has(-1):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "处理次数对但键码有错/缺"
	Kit.emit(rep, tracker, code, c, ok, got, {"pressed": want, "handled": want}, got, detail)

# ---------------------------------------------------------------- 6.3 声音

static func _frequency_check(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var freqs: Array = got.get("freqs", [])
	var want: Array = c.get("expect_freqs", [440, 660, 880])
	var tol := float(c.get("tolerance", 0.05))
	var ok := true
	var code := GateResult.OK
	var detail := "频率 %s Hz" % str(freqs)
	if freqs.size() != want.size():
		ok = false
		code = GateResult.E_COVERAGE
		detail = "只测 %d/%d 个音" % [freqs.size(), want.size()]
	else:
		for i in want.size():
			var w := float(want[i])
			if absf(float(freqs[i]) - w) > w * tol:
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "第 %d 个音 %.1f Hz ≠ %.1f Hz（±%d%%）" % [i + 1, float(freqs[i]), w, int(tol * 100)]
				break
	Kit.emit(rep, tracker, code, c, ok, got, want, freqs, detail)

static func _divider_ratio(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ns: Array = got.get("n", [])
	var periods: Array = got.get("periods", [])
	var ok := true
	var code := GateResult.OK
	var detail := "周期 %s（应 2N）" % str(periods)
	if ns.size() < 2 or ns.size() != periods.size():
		ok = false
		code = GateResult.E_COVERAGE
		detail = "分频比至少测两组且 N 与周期一一对应"
	else:
		for i in ns.size():
			if absf(float(periods[i]) - 2.0 * float(ns[i])) > 1.0:
				ok = false
				code = GateResult.E_DELAY_EXCEED
				detail = "N=%d 周期 %.1f ≠ 2N（半周期取整丢拍）" % [int(ns[i]), float(periods[i])]
				break
	Kit.emit(rep, tracker, code, c, ok, got, {"periods": "2N"}, periods, detail)

static func _scale_check(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ratio := float(got.get("step_ratio", -1.0))
	var want := float(c.get("expect_ratio", 1.05946))
	var ok := ratio > 0.0 and absf(ratio - want) <= want * 0.01
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got, {"step_ratio": want},
		{"step_ratio": ratio}, "半音比例 %.4f（期望 %.4f，等差即错）" % [ratio, want])

# ---------------------------------------------------------------- 6.4 装入器

static func _loader_run(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var code := GateResult.OK
	var detail := "首次 %s/%s，重载 %s/%s" % [str(got.get("out_a", "?")), str(got.get("out_b", "?")),
		str(got.get("reload_out_a", "?")), str(got.get("reload_out_b", "?"))]
	var need := ["out_a", "out_b", "reload_out_a", "reload_out_b"]
	for key in need:
		if not got.has(key):
			ok = false
			code = GateResult.E_UNCONNECTED
			detail = "装入器未接线或未跑（缺 %s）" % str(key)
			break
	if ok:
		for key in need:
			var want := 8 if str(key).ends_with("a") else 15
			if int(got[key]) != want:
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "%s=%d ≠ %d" % [str(key), int(got[key]), want]
				break
	Kit.emit(rep, tracker, code, c, ok, got, {"a": 8, "b": 15}, got, detail)

static func _checksum(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var code := GateResult.OK
	var detail := "校验和 %s，坏字节拒跑 %s" % [str(got.get("checksum", "?")), str(got.get("corrupt_rejected", "?"))]
	if not got.has("checksum") or not got.has("result_checksum"):
		ok = false
		code = GateResult.E_UNCONNECTED
		detail = "校验器未接线（缺下达/回读校验和）"
	elif int(got["checksum"]) != int(got["result_checksum"]):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "校验和不等：下达 %d / 回读 %d" % [int(got["checksum"]), int(got["result_checksum"])]
	elif not bool(got.get("corrupt_rejected", false)):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "坏字节被照常执行（校验没拦住）"
	Kit.emit(rep, tracker, code, c, ok, got, {"corrupt_rejected": true}, got, detail)

static func _load_address(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var tape: Dictionary = inputs.get("tape", {})
	var ok := true
	var code := GateResult.OK
	var detail := "首地址 %s、长度 %s" % [str(got.get("start_addr", "?")), str(got.get("length", "?"))]
	if not tape.has("start_addr") or not tape.has("length"):
		ok = false
		code = GateResult.E_UNCONNECTED
		detail = "缺磁带表头（未采集首地址/长度）"
	elif int(got.get("start_addr", -1)) != int(tape["start_addr"]):
		ok = false
		code = GateResult.E_UNKNOWN_TARGET
		detail = "首地址 %d ≠ 表头 %d（装错位置）" % [int(got.get("start_addr", -1)), int(tape["start_addr"])]
	elif int(got.get("length", -1)) != int(tape["length"]):
		ok = false
		code = GateResult.E_UNKNOWN_TARGET
		detail = "长度 %d ≠ 表头 %d（装错字节数）" % [int(got.get("length", -1)), int(tape["length"])]
	Kit.emit(rep, tracker, code, c, ok, got, tape, got, detail)

# ---------------------------------------------------------------- 6.5 高速缓存

static func _cache_coverage(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var runs: Array = got.get("runs", [])
	var steps := []
	var ok := true
	var code := GateResult.OK
	var detail := "两组跑量 %s" % str(runs)
	for raw in runs:
		if raw is Dictionary:
			steps.append(int((raw as Dictionary).get("step", -1)))
	if not steps.has(1) or not steps.has(16):
		ok = false
		code = GateResult.E_COVERAGE
		detail = "步长 1 / 16 两组未都跑（实跑 %s）" % str(steps)
	else:
		var a: Dictionary = runs[steps.find(1)]
		var b: Dictionary = runs[steps.find(16)]
		var iterations := int(inputs_iterations(c, a, b))
		if int(a.get("completed", 0)) < iterations or int(b.get("completed", 0)) < iterations:
			ok = false
			code = GateResult.E_COVERAGE
			detail = "跑不满次数：%d/%d、%d/%d" % [int(a.get("completed", 0)), iterations,
				int(b.get("completed", 0)), iterations]
		elif int(a.get("first_addr", -1)) != int(b.get("first_addr", -2)):
			ok = false
			code = GateResult.E_OUTPUT_MISMATCH
			detail = "两段首地址不同（%d / %d）" % [int(a.get("first_addr", -1)), int(b.get("first_addr", -2))]
	Kit.emit(rep, tracker, code, c, ok, got, {"steps": [1, 16]}, steps, detail)

static func inputs_iterations(_c: Dictionary, a: Dictionary, b: Dictionary) -> int:
	## 无机器跑量时退化为「两组一致且非零」，不拿漂亮数字当依据。
	var n := int(a.get("completed", 0))
	if n <= 0 or n != int(b.get("completed", 0)):
		return maxi(n, 1)
	return n

static func _cache_avg(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var cache: Dictionary = inputs.get("cache", {})
	var ok := true
	var code := GateResult.OK
	var detail := "平均访问 %s 拍" % str(got.get("avg_ticks", "?"))
	var want := 0.0
	if not cache.has("hit_ticks") or not cache.has("miss_ticks") or not cache.has("hit_rate"):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "缺命中/未命中拍数与命中率（无法代入）"
	else:
		var rate := float(cache["hit_rate"])
		want = rate * float(cache["hit_ticks"]) + (1.0 - rate) * float(cache["miss_ticks"])
		var stated := float(got.get("avg_ticks", -1.0))
		if absf(stated - want) > want * 0.05:
			ok = false
			code = GateResult.E_OUTPUT_MISMATCH
			detail = "作答 %.2f 拍 ≠ 实算 %.2f 拍（±5%%）" % [stated, want]
	Kit.emit(rep, tracker, code, c, ok, got, {"avg_ticks": want},
		{"avg_ticks": got.get("avg_ticks", null)}, detail)

# ---------------------------------------------------------------- 6.6 虚拟内存

static func _page_map(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var code := GateResult.OK
	var detail := "写 %s / 读回 %s / 不一致 %s" % [str(got.get("written", "?")),
		str(got.get("read_back", "?")), str(got.get("mismatches", "?"))]
	if not got.has("written") or not got.has("read_back"):
		ok = false
		code = GateResult.E_UNCONNECTED
		detail = "页表/内存未接线（缺写入量与读回量）"
	elif int(got.get("mismatches", 1)) != 0:
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "读回不一致 %d 字节（页表映射错）" % int(got.get("mismatches", 1))
	elif int(got["read_back"]) < int(got["written"]):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "只读回 %d/%d 字节" % [int(got["read_back"]), int(got["written"])]
	else:
		var entries: Array = got.get("pt_entries", [])
		if entries.is_empty():
			ok = false
			code = GateResult.E_COVERAGE
			detail = "页表项未逐项核对"
		for raw in entries:
			if raw is Dictionary and not bool((raw as Dictionary).get("ok", true)):
				ok = false
				code = GateResult.E_OUTPUT_MISMATCH
				detail = "页表项错：虚页 %s → 页框 %s" % [str((raw as Dictionary).get("page", "?")),
					str((raw as Dictionary).get("frame", "?"))]
				break
	Kit.emit(rep, tracker, code, c, ok, got, {"mismatches": 0}, got, detail)

static func _vm_capacity(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var mem: Dictionary = inputs.get("memory", {})
	var ok := true
	var code := GateResult.OK
	var detail := "作答容量 %s 字节" % str(got.get("total_bytes", "?"))
	if not mem.has("frames") or not mem.has("page_size") or not mem.has("overcommit"):
		ok = false
		code = GateResult.E_OUTPUT_MISMATCH
		detail = "缺页框数/页大小/超配倍率（无法换算）"
	else:
		var want := float(int(mem["frames"])) * float(int(mem["page_size"])) * float(mem["overcommit"])
		var stated := float(got.get("total_bytes", -1.0))
		if absf(stated - want) > 1.0:
			ok = false
			code = GateResult.E_OUTPUT_MISMATCH
			detail = "作答 %d ≠ 页框×页大小×超配 %d" % [int(stated), int(want)]
	Kit.emit(rep, tracker, code, c, ok, got, {"total_bytes": mem}, got, detail)
