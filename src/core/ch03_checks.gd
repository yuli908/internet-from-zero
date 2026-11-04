class_name Ch03Checks
extends RefCounted

## CH03（3.1–3.4）gate 判定入口。出口沿用 `GateReport` / `GateResult`，与 CH02/CH05 同构。
##
## 已落地 kind：fa_truth / part_count / delay_positive / quiz / same_part_array /
##              adder_sweep / carry_out / stage_report / clock_sample / timing_derived /
##              sample_mode / feedback_structure / hold_ticks / register_hold / setup_hold
## 无 pending kind。3.1 延迟上限、3.2 进位链上限未由技术侧定数，故这两条只判「报告有值 / 级数=8」，
## 不拍绝对 tick 阈值；3.3 起才用「短 T 必须红」判 E_DELAY_EXCEED。

const Kit := preload("res://src/core/lab_gate_kit.gd")

const PENDING_REASONS := {}

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch03_levels.json")

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
			"fa_truth":
				_fa_truth(rep, tracker, c, answers)
			"part_count":
				_part_count(rep, tracker, c, answers)
			"delay_positive":
				_delay_positive(rep, tracker, c, answers)
			"quiz":
				Kit.judge_quiz(rep, tracker, c, answers)
			"same_part_array":
				_same_part_array(rep, tracker, c, answers)
			"adder_sweep":
				_adder_sweep(rep, tracker, c, answers)
			"carry_out":
				_carry_out(rep, tracker, c, answers)
			"stage_report":
				_stage_report(rep, tracker, c, answers)
			"clock_sample":
				_clock_sample(rep, tracker, c, answers)
			"timing_derived":
				_timing_derived(rep, tracker, c, answers, inputs)
			"sample_mode":
				_sample_mode(rep, tracker, c, answers)
			"feedback_structure":
				_feedback_structure(rep, tracker, c, answers)
			"hold_ticks":
				_hold_ticks(rep, tracker, c, answers)
			"register_hold":
				_register_hold(rep, tracker, c, answers)
			"setup_hold":
				_setup_hold(rep, tracker, c, answers)
			_:
				Kit.emit(rep, tracker, GateResult.E_GENERIC, c, false, {"kind": kind},
					"已知判定 kind", kind, "未知判定 kind：%s" % kind)
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

# ---------------------------------------------------------------- 3.1 全加器

static func _fa_truth(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var rows: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("rows", [])
	var want := {}
	for a in 2:
		for b in 2:
			for cin in 2:
				var s := a ^ b ^ cin
				var cout := (a & b) | (a & cin) | (b & cin)
				want[_combo(a, b, cin)] = {"sum": s, "cout": cout}
	if rows.size() != 8:
		Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, false, rows.size(), 8, rows.size(),
			"需要 8 行（含 Cin=1 的四行），实得 %d 行" % rows.size())
		return
	var seen := {}
	for raw in rows:
		if not (raw is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, false, raw, want, "非字典行", "行不是字典")
			return
		var r: Dictionary = raw
		var key := _combo(int(r.get("a", -1)), int(r.get("b", -1)), int(r.get("cin", -1)))
		if not want.has(key):
			Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, false, r, want, "非法输入组合",
				"行输入不在 0/1 组合内：%s" % str(r))
			return
		if seen.has(key):
			Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, false, r, want, "重复行",
				"重复行：%s" % key)
			return
		seen[key] = true
		var w: Dictionary = want[key]
		if int(r.get("sum", -1)) != int(w["sum"]) or int(r.get("cout", -1)) != int(w["cout"]):
			Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, false, r,
				{"sum": int(w["sum"]), "cout": int(w["cout"])},
				{"sum": int(r.get("sum", -1)), "cout": int(r.get("cout", -1))},
				"%s 期望 SUM=%d Cout=%d" % [key, int(w["sum"]), int(w["cout"])])
			return
	Kit.emit(rep, tracker, GateResult.OK, c, true, {"rows": 8}, {"rows": 8}, {"rows": 8},
		"8/8 真值全过")

static func _combo(a: int, b: int, cin: int) -> String:
	return "%d%d%d" % [a, b, cin]

static func _part_count(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var parts: Dictionary = got.get("parts", {})
	if parts.is_empty():
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, c.get("expect", {}),
			"无零件计数", "没有接线或没有使用已封装零件")
		return
	var want: Dictionary = c.get("expect", {})
	var ok := true
	for key in want.keys():
		if int(parts.get(str(key), 0)) != int(want[key]):
			ok = false
			break
	for key in parts.keys():
		if not want.has(str(key)) and int(parts[key]) != 0:
			ok = false
			break
	Kit.emit(rep, tracker, GateResult.E_ENCAPSULATION, c, ok, parts, want, parts,
		"零件计数 %s，期望 %s" % [str(parts), str(want)])

# ---------------------------------------------------------------- 3.2 八位加法器

static func _delay_positive(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ticks := int(got.get("delay_ticks", 0))
	var ok := ticks > 0
	Kit.emit(rep, tracker, GateResult.E_DELAY_EXCEED, c, ok, got, "> 0", ticks,
		"延迟报告 %d tick（上限待技术侧定，只报级数）" % ticks)

static func _same_part_array(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := true
	var detail := ""
	if str(got.get("part", "")) != str(c.get("part", "full_adder")):
		ok = false
		detail = "整列不是同一封装件：%s" % str(got.get("part", ""))
	elif not bool(got.get("same_part", false)):
		ok = false
		detail = "8 个实例不是同一封装件（手画 8 份不算）"
	elif int(got.get("instances", 0)) != int(c.get("instances", 8)):
		ok = false
		detail = "实例数 %d，期望 %d" % [int(got.get("instances", 0)), int(c.get("instances", 8))]
	Kit.emit(rep, tracker, GateResult.E_ENCAPSULATION, c, ok, got, c.get("instances", 8), got, detail)

static func _adder_sweep(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var groups: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("groups", [])
	var need := int(c.get("random_count", 16)) + (c.get("boundary", []) as Array).size()
	var bad := ""
	for raw in groups:
		if not (raw is Dictionary):
			bad = "组不是字典"
			break
		var g: Dictionary = raw
		var a := int(g.get("a", -1))
		var b := int(g.get("b", -1))
		var total := a + b
		if a < 0 or a > 255 or b < 0 or b > 255:
			bad = "操作数越界 a=%d b=%d" % [a, b]
			break
		if int(g.get("sum", -1)) != total % 256 or int(g.get("c8", -1)) != int(total > 255):
			bad = "%d+%d 期望 S=%d C8=%d，实得 S=%s C8=%s" % [a, b, total % 256,
				int(total > 255), str(g.get("sum", "?")), str(g.get("c8", "?"))]
			break
	var seen := {}
	for raw in groups:
		if raw is Dictionary:
			seen["%d:%d" % [int(raw.get("a", -1)), int(raw.get("b", -1))]] = true
	var missing := []
	for pair in c.get("boundary", []):
		if not seen.has("%d:%d" % [int(pair[0]), int(pair[1])]):
			missing.append(pair)
	var ok := groups.size() >= need and bad.is_empty() and missing.is_empty()
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, groups.size(), need,
		{"count": groups.size(), "missing": missing, "bad": bad},
		bad if not bad.is_empty() else ("缺边界组 %s" % str(missing) if not missing.is_empty()
			else "%d/%d 组通过" % [groups.size(), need]))

static func _carry_out(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var want := {"sum": int(c.get("sum", 0)), "c8": int(c.get("c8", 1))}
	var ok := int(got.get("sum", -1)) == int(want["sum"]) and int(got.get("c8", -1)) == int(want["c8"])
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, got, want,
		{"sum": int(got.get("sum", -1)), "c8": int(got.get("c8", -1))},
		"255+1 期望 C8=1、S=0；实得 C8=%s、S=%s" % [str(got.get("c8", "?")), str(got.get("sum", "?"))])

static func _stage_report(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var stages := int(got.get("stages", 0))
	var ok := stages == int(c.get("stages", 8))
	Kit.emit(rep, tracker, GateResult.E_DELAY_EXCEED, c, ok, got, int(c.get("stages", 8)), stages,
		"进位链级数 %d，期望 %d" % [stages, int(c.get("stages", 8))])

# ---------------------------------------------------------------- 3.3 时钟与边沿

static func _clock_sample(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var pl := int(got.get("period_long", 0))
	var ps := int(got.get("period_short", 0))
	var long_sample := int(got.get("long_sample", -1))
	var short_sample := int(got.get("short_sample", -1))
	var want := int(c.get("expect_sum", 8))
	var ok := pl > ps and ps > 0 and long_sample == want and short_sample != want
	var code := GateResult.E_TRUTH_ROW
	var detail := ""
	if pl <= ps or ps <= 0:
		code = GateResult.E_DELAY_EXCEED
		detail = "需要两档 T 且长 T > 短 T；实得 %d / %d" % [pl, ps]
	elif long_sample != want:
		detail = "长 T 采样 %d，期望和 %d" % [long_sample, want]
	elif short_sample == want:
		detail = "短 T 采样仍等于期望和 %d：沿没有替你走完组合路径，必须能红" % want
	else:
		detail = "长 T=%d 采到 %d，短 T=%d 采到 %d（≠%d）" % [pl, long_sample, ps, short_sample, want]
	Kit.emit(rep, tracker, code, c, ok, got, want,
		{"long": long_sample, "short": short_sample}, detail)

static func _timing_derived(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, inputs: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var delay: Dictionary = inputs.get("delay_report", {})
	if not delay.has("stages") or not delay.has("stage_delay_ticks"):
		Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, false, got, "delay_report",
			delay, "缺 3.2 的 delay_report（stages / stage_delay_ticks），不允许重填")
		return
	var stages := int(delay.get("stages", 0)) + int(c.get("extra_stages", 1))
	var unit := int(delay.get("stage_delay_ticks", 0))
	var used := int(got.get("stages_used", 0))
	var period := int(got.get("period_ticks", 0))
	var need := stages * unit
	var ok := used == stages and period >= need
	Kit.emit(rep, tracker, GateResult.E_TIMING_MARGIN, c, ok, got, {"stages": stages, "min_period": need},
		{"stages": used, "period": period},
		"级数 %d（含采样 1 级），T=%d ≥ %d×%d=%d" % [stages, period, stages, unit, need])

static func _sample_mode(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var mode := str(got.get("mode", ""))
	var ok := mode == str(c.get("expect_mode", "edge"))
	Kit.emit(rep, tracker, GateResult.E_TRUTH_ROW, c, ok, {"mode": mode},
		str(c.get("expect_mode", "edge")), mode,
		"采样模式必须是沿采样；实得 %s" % (mode if not mode.is_empty() else "未作答"))

# ---------------------------------------------------------------- 3.4 双稳态与寄存器

static func _feedback_structure(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var ok := int(got.get("inverters", 0)) == int(c.get("inverters", 2)) \
		and bool(got.get("cross_coupled", false))
	Kit.emit(rep, tracker, GateResult.E_HOLD_TICKS, c, ok, got,
		{"inverters": 2, "cross_coupled": true}, got,
		"需要 2 只反相器首尾相接成环（交叉耦合）")

static func _hold_ticks(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var runs: Array = Kit.answer_dict(answers, str(c.get("id", ""))).get("runs", [])
	var want_states := []
	for s in (c.get("states", [0, 1]) as Array):
		want_states.append(int(s))
	var ticks := int(c.get("ticks", 10))
	var ok := runs.size() == want_states.size()
	var detail := ""
	if not ok:
		detail = "需要两个稳定态各测一次，实得 %d 组" % runs.size()
	for raw in runs:
		if not ok:
			break
		if not (raw is Dictionary):
			ok = false
			detail = "组不是字典"
			break
		var r: Dictionary = raw
		var state := int(r.get("state", -1))
		var readings: Array = r.get("readings", [])
		if not want_states.has(state):
			ok = false
			detail = "稳定态 %d 不在 %s" % [state, str(want_states)]
			break
		if readings.size() != ticks:
			ok = false
			detail = "稳定态 %d 只有 %d 个读数，期望 %d tick" % [state, readings.size(), ticks]
			break
		for v in readings:
			if int(v) != state:
				ok = false
				detail = "稳定态 %d 中途翻到 %d（保持失败）" % [state, int(v)]
				break
		if not detail.is_empty():
			break
	Kit.emit(rep, tracker, GateResult.E_HOLD_TICKS, c, ok, runs, {"states": want_states, "ticks": ticks},
		runs, detail if not ok else "两态各保持 %d tick 不变" % ticks)

static func _register_hold(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var width := int(c.get("width", 8))
	var write: Array = got.get("write", [])
	var back: Array = got.get("read_back", [])
	var before: Array = got.get("read_before", [])
	var ok := int(got.get("width", 0)) == width and write.size() == width and back.size() == width
	var code := GateResult.E_HOLD_TICKS
	var detail := ""
	if not ok:
		code = GateResult.E_TRUTH_ROW
		detail = "位宽/数组长度不符：width=%s write=%d read_back=%d" % [str(got.get("width", "?")),
			write.size(), back.size()]
	elif write != back:
		ok = false
		detail = "WE=0 后读回 %s，写入的是 %s（保持失败）" % [str(back), str(write)]
	elif before.size() != width:
		code = GateResult.E_TRUTH_ROW
		ok = false
		detail = "缺写入前读回（证明保留的是上一次值）"
	elif before == write:
		code = GateResult.E_TRUTH_ROW
		ok = false
		detail = "写入前读回与写入值相同，无法证明改写与保持"
	else:
		detail = "WE=1 写 %s，WE=0 读回一致；写入前读回 %s" % [str(back), str(before)]
	Kit.emit(rep, tracker, code, c, ok, got, {"width": width, "write": write}, got, detail)

static func _setup_hold(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got: Dictionary = Kit.answer_dict(answers, str(c.get("id", "")))
	var setup := int(got.get("setup", -1))
	var hold := int(got.get("hold", -1))
	var need_setup := int(c.get("setup_required", 1))
	var need_hold := int(c.get("hold_required", 1))
	var ok := setup >= need_setup and hold >= need_hold
	Kit.emit(rep, tracker, GateResult.E_TIMING_MARGIN, c, ok, got,
		{"setup": need_setup, "hold": need_hold}, {"setup": setup, "hold": hold},
		"建立 %d ≥ %d、保持 %d ≥ %d" % [setup, need_setup, hold, need_hold])
