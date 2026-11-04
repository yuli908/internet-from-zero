extends RefCounted

## CH07 判据：串行位宽/采样、7 位帧、UART 30% 偏移、双机互通。
## 只校验玩家提交的实测/回放证据，不触碰 UI。缺可判口径的 gate 走 pending，不猜数。
## 课文：docs/curriculum/18-ch07-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")

const PENDING_REASONS := {
	"sample_phase": "采样相位判据需扩接口（位窗口 + 采样 tick）；±10% 位宽容差为 18 §6-4 初值，未校准。先挂 pending 不进分母，不以初值冒充定稿。"
}

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch07_levels.json")

static func run(lab_id: String, cfg: Dictionary, inputs: Dictionary = {},
		tracker: GateAttemptTracker = null) -> Dictionary:
	var rep := GateReport.new()
	var pending := []
	var answers: Dictionary = inputs.get("answers", {})
	var gate_cases: Array = cfg.get("gate_cases", [])
	for raw in gate_cases:
		if not (raw is Dictionary):
			continue
		var c: Dictionary = raw
		var cid := str(c.get("id", ""))
		var kind := str(c.get("kind", ""))
		if PENDING_REASONS.has(kind):
			var reason := str(c.get("pending_reason", PENDING_REASONS[kind]))
			pending.append({"id": cid, "kind": kind, "title": str(c.get("title", "")), "reason": reason})
			Kit.add_pending(rep, c, reason)
			continue
		match kind:
			"edge_sample":
				_edge_sample(rep, tracker, c, answers)
			"period_calc":
				_period_calc(rep, tracker, c, answers)
			"frame_fields":
				_frame_fields(rep, tracker, c, answers)
			"stop_low":
				_stop_low(rep, tracker, c, answers)
			"parity_calc":
				_parity_calc(rep, tracker, c, answers)
			"uart_offset":
				_uart_offset(rep, tracker, c, answers)
			"single_point_shift":
				_single_point_shift(rep, tracker, c, answers)
			"offset_calc":
				_offset_calc(rep, tracker, c, answers)
			"two_machine":
				_two_machine(rep, tracker, c, answers)
			"baud_mismatch":
				_baud_mismatch(rep, tracker, c, answers)
			"no_checksum":
				_no_checksum(rep, tracker, c, answers)
			"quiz":
				Kit.judge_quiz(rep, tracker, c, answers)
			_:
				Kit.emit(rep, tracker, GateResult.E_UNKNOWN_TARGET, c, false, {"kind": kind},
					"已实现 kind", "unknown", "独立检查器不支持 kind=%s（lab=%s）" % [kind, lab_id])
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

static func _edge_sample(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var readings: Variant = got.get("readings", null)
	if not (readings is Array) or (readings as Array).size() < 2:
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, "重复读数 ≥2", "missing",
			"采样探针未接或只读一次，无法复现沿上抖动")
		return
	var arr: Array = readings
	var all_same := true
	for i in range(1, arr.size()):
		if str(arr[i]) != str(arr[0]):
			all_same = false
			break
	var inverted := bool(got.get("inverted", false))
	var ok := not all_same or inverted
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		"多次读数不一致或读成反值", {"readings": arr, "inverted": inverted},
		"采样点落在跳变沿：读数不一致/读成反值" if ok else "采样点落在跳变沿：多次读数仍一致且无反值")

static func _period_calc(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("bit_us") and got.has("half_us")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, "bit_us/half_us", "missing",
			"位宽换算未提交（bit_us 或 half_us 缺）")
		return
	var want_bit := float(c.get("expect_bit_us", 104.1667))
	var want_half := float(c.get("expect_half_us", 52.0833))
	var tol := float(c.get("tolerance", 0.05))
	var got_bit := float(got["bit_us"])
	var got_half := float(got["half_us"])
	var ok := (absf(got_bit - want_bit) <= want_bit * tol
		and absf(got_half - want_half) <= want_half * tol)
	Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, ok, got,
		{"bit_us": want_bit, "half_us": want_half, "tolerance": tol},
		{"bit_us": got_bit, "half_us": got_half},
		"位宽换算对（±5%）" if ok else "位宽换算错：一位 %.2f µs / 半位 %.2f µs 与机器值不符" % [got_bit, got_half])

static func _frame_fields(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var got_fields: Variant = got.get("fields", null)
	var exp_fields: Array = c.get("fields", [])
	if not (got_fields is Array) or (got_fields as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, exp_fields, "missing",
			"字段表未提交（帧检查器未接）")
		return
	var fields: Array = got_fields
	var fields_ok := fields.size() == exp_fields.size()
	if fields_ok:
		for i in range(exp_fields.size()):
			var e: Dictionary = exp_fields[i]
			var g: Dictionary = fields[i]
			if (str(g.get("name", "")) != str(e.get("name", ""))
				or int(g.get("start", -1)) != int(e.get("start", 0))
				or int(g.get("width", -1)) != int(e.get("width", 0))):
				fields_ok = false
				break
	if not fields_ok:
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got, exp_fields, got_fields,
			"字段表起始位或位宽错：7 位帧应为 start[0,1]+data[1,4]+parity[5,1]+stop[6,1]")
		return
	var vectors: Variant = got.get("vectors", null)
	if not (vectors is Array) or (vectors as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, ["normal", "parity", "stop"],
			"missing", "只测正常帧，未提交坏帧向量，测不出拒收")
		return
	var vmap := {}
	for raw in (vectors as Array):
		if raw is Dictionary:
			vmap[str((raw as Dictionary).get("id", ""))] = raw
	for vid in ["normal", "parity", "stop"]:
		if not vmap.has(vid):
			Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, ["normal", "parity", "stop"],
				vmap.keys(), "缺 %s 向量，未覆盖该过/该拒两态" % vid)
			return
	var normal: Dictionary = vmap["normal"]
	if not bool(normal.get("passed", false)) or bool(normal.get("rejected", false)):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, normal,
			"正常帧通过", normal, "该过未过：正常帧被拒")
		return
	var parity: Dictionary = vmap["parity"]
	if not bool(parity.get("rejected", false)) or _field_name(parity.get("field", "")) != "parity":
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, parity,
			{"rejected": true, "field": "parity"}, parity, "校验翻位未被拒，或拒收原因未落到「校验」字段")
		return
	var stop: Dictionary = vmap["stop"]
	if not bool(stop.get("rejected", false)) or _field_name(stop.get("field", "")) != "stop":
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, stop,
			{"rejected": true, "field": "stop"}, stop, "缺停止位未被拒，或拒收原因未落到「停止」字段")
		return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"正常过、校验翻拒、缺停止拒", got, "字段表与三向量全对")

static func _stop_low(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("stop_level") and got.has("single_frame_ok") and got.has("frames_merged")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"stop_level/single_frame_ok/frames_merged", "missing", "停止位负例证据未提交")
		return
	var ok := int(got.get("stop_level", 1)) == 0 \
		and bool(got.get("single_frame_ok", false)) \
		and bool(got.get("frames_merged", false))
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"stop_level": 0, "single_frame_ok": true, "frames_merged": true}, got,
		"停止位缺失：单帧看似对，下一帧粘连" if ok else "停止位负例未复现：停止电平/单帧/粘连三项不符")

static func _parity_calc(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var results: Variant = got.get("results", null)
	var vectors: Array = c.get("vectors", [])
	if not (results is Array) or (results as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, "3 组校验结果", "missing",
			"未提交 3 组数据位的校验结果")
		return
	var rmap := {}
	for raw in (results as Array):
		if raw is Dictionary:
			rmap[str((raw as Dictionary).get("id", ""))] = raw
	for raw in vectors:
		var v: Dictionary = raw
		var vid := str(v.get("id", ""))
		if not rmap.has(vid):
			Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, "全部 3 组", rmap.keys(),
				"缺 %s 的校验结果" % vid)
			return
		var want := 0
		for b in (v.get("data", []) as Array):
			want ^= int(b)
		var r: Dictionary = rmap[vid]
		if not r.has("parity") or int(r.get("parity", -1)) != want:
			Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, r,
				{"id": vid, "parity": want}, r, "校验位算错：%s 期望 %d" % [vid, want])
			return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got, "3/3 异或", got,
		"3 组数据位的异或校验全部一致")

static func _uart_offset(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var need := ["offset_ratio", "same_freq_byte", "offset_byte", "first_bad_bit", "fixed_byte"]
	for key in need:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, need, "missing",
				"UART 复现/修正证据未提交（缺 %s）" % key)
			return
	var cfg_byte := int(c.get("byte", 165))
	var cfg_ratio := float(c.get("offset_ratio", 1.3))
	var ratio := float(got["offset_ratio"])
	if absf(ratio - cfg_ratio) > float(c.get("ratio_tolerance", 0.01)):
		Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, false, got,
			{"offset_ratio": cfg_ratio}, {"offset_ratio": ratio},
			"位周期偏移量与实测不符：应报 %.2f×" % cfg_ratio)
		return
	var want_offset_byte := _offset_byte(cfg_byte, cfg_ratio)
	var want_first := _first_bad_bit(cfg_byte, cfg_ratio)
	var ok := int(got["same_freq_byte"]) == cfg_byte \
		and int(got["offset_byte"]) == want_offset_byte \
		and int(got["first_bad_bit"]) == want_first \
		and int(got["fixed_byte"]) == cfg_byte
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"same_freq_byte": cfg_byte, "offset_byte": want_offset_byte,
		 "first_bad_bit": want_first, "fixed_byte": cfg_byte},
		{"same_freq_byte": int(got["same_freq_byte"]), "offset_byte": int(got["offset_byte"]),
		 "first_bad_bit": int(got["first_bad_bit"]), "fixed_byte": int(got["fixed_byte"])},
		"1.3× 复现误码并报首个错位，改回同频一致" if ok else "字节错或首个错位位号与机器不一致")

static func _single_point_shift(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("last_sample_shifted") and got.has("byte_before")
			and got.has("byte_after") and got.has("reproduced")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"last_sample_shifted/byte_before/byte_after/reproduced", "missing",
			"只挪点位负例证据未提交")
		return
	var cfg_byte := int(c.get("byte", 165))
	var ok := bool(got.get("last_sample_shifted", false)) \
		and int(got.get("byte_before", -1)) == cfg_byte \
		and int(got.get("byte_after", -1)) == cfg_byte \
		and not bool(got.get("reproduced", true))
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"last_sample_shifted": true, "byte_before": cfg_byte, "byte_after": cfg_byte,
		 "reproduced": false},
		got, "只挪点位未改位周期：单字节仍全对，未复现误码" if ok else "只挪点位负例不成立：字节变了或自称复现误码")

static func _offset_calc(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var need := ["bit_us", "offset_us", "accum_bits"]
	for key in need:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, need, "missing",
				"偏移累计未提交（缺 %s）" % key)
			return
	var want_bit := float(c.get("expect_bit_us", 104.1667))
	var want_off := float(c.get("expect_offset_us", 31.25))
	var want_acc := float(c.get("expect_accum_bits", 2.1))
	var tol := float(c.get("tolerance", 0.05))
	var ok := absf(float(got["bit_us"]) - want_bit) <= want_bit * tol \
		and absf(float(got["offset_us"]) - want_off) <= want_off * tol \
		and absf(float(got["accum_bits"]) - want_acc) <= want_acc * tol
	Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, ok, got,
		{"bit_us": want_bit, "offset_us": want_off, "accum_bits": want_acc},
		{"bit_us": float(got["bit_us"]), "offset_us": float(got["offset_us"]),
		 "accum_bits": float(got["accum_bits"])},
		"30% 偏移累计对（±5%）" if ok else "偏移累计算错：104/31/2.1 与提交值不符")

static func _two_machine(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var need := ["width_tx", "width_rx", "tx_bytes", "rx_bytes", "rejected_frame", "resent_ok"]
	for key in need:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, need, "missing",
				"双机证据未提交（缺 %s）" % key)
			return
	var tx: Variant = got["tx_bytes"]
	var rx: Variant = got["rx_bytes"]
	if (not (tx is Array) or not (rx is Array)
			or (tx as Array).size() != 2 or (rx as Array).size() != 2):
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, "双向各 2 帧", 
			{"tx": tx, "rx": rx}, "只跑单向或只跑一帧，未覆盖双向字节")
		return
	var a := int(c.get("byte_a", 165))
	var b := int(c.get("byte_b", 60))
	var width_a := float(got["width_tx"])
	var width_b := float(got["width_rx"])
	if width_a <= 0.0 or absf(width_a - width_b) > 0.0001:
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"width_tx": width_a, "width_rx": width_a}, 
			{"width_tx": width_a, "width_rx": width_b}, "两端实测位宽不一致")
		return
	if int((tx as Array)[0]) != a or int((tx as Array)[1]) != b \
			or int((rx as Array)[0]) != a or int((rx as Array)[1]) != b:
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"tx_bytes": [a, b], "rx_bytes": [a, b]}, {"tx_bytes": tx, "rx_bytes": rx},
			"双向拼回字节逐位不一致")
		return
	var rejected := int(got["rejected_frame"])
	if rejected <= 0:
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"rejected_frame": ">=1"}, {"rejected_frame": rejected},
			"坏帧未被拒或未报帧号")
		return
	if not bool(got["resent_ok"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"resent_ok": true}, {"resent_ok": false}, "坏帧拒收后重发未送达")
		return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"位宽一致、双向字节一致、拒收并重发送达", got, "双机端到端四条全对")

static func _baud_mismatch(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("width_a") and got.has("width_b") and got.has("frames")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"width_a/width_b/frames", "missing", "两端分频不一致负例证据未提交")
		return
	var wa := float(got["width_a"])
	var wb := float(got["width_b"])
	var want_ratio := float(c.get("ratio", 1.3))
	var tol := float(c.get("ratio_tolerance", 0.05))
	if wa <= 0.0 or absf((wb / wa) - want_ratio) > tol:
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"ratio": want_ratio}, {"ratio": wb / wa if wa > 0.0 else -1.0},
			"两端位宽不一致：应是一端 1.3×")
		return
	var frames: Array = got["frames"]
	var fmap := {}
	for raw in frames:
		if raw is Dictionary:
			fmap[int((raw as Dictionary).get("index", -1))] = raw
	if (not fmap.has(1) or not fmap.has(2)
			or not bool((fmap[1] as Dictionary).get("ok", false))
			or bool((fmap[2] as Dictionary).get("ok", true))):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"frames": [{"index": 1, "ok": true}, {"index": 2, "ok": false}]}, got,
			"两端位宽不一致：应单帧偶对、第二帧开始错位")
		return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"单帧偶对、第二帧错位", got, "两端分频不一致负例复现")

static func _no_checksum(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var need := ["checksum_checked", "corrupted_accepted", "corrupted_byte", "clean_byte"]
	for key in need:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, need, "missing",
				"不校验负例证据未提交（缺 %s）" % key)
			return
	var cfg_byte := int(c.get("byte", 165))
	var flip_bit := int(c.get("flip_bit", 0))
	var want_corrupt := cfg_byte ^ (1 << flip_bit)
	var ok := (not bool(got["checksum_checked"]) and bool(got["corrupted_accepted"])
		and int(got["corrupted_byte"]) == want_corrupt and int(got["clean_byte"]) == cfg_byte)
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"checksum_checked": false, "corrupted_accepted": true,
		 "corrupted_byte": want_corrupt, "clean_byte": cfg_byte}, got,
		"坏帧未拒收：拼出错误字节" if ok else "不校验负例不成立：校验仍开或坏帧未拼错")

static func _field_name(raw: Variant) -> String:
	var s := str(raw)
	if s == "parity" or s == "校验":
		return "parity"
	if s == "stop" or s == "停止":
		return "stop"
	return s

static func _sample_index(bit_index: int, ratio: float) -> int:
	## 接收端按自己的位周期 ratio×发送位宽：半位采样起点 0.5×ratio，之后每 ratio 一位。
	return int(floor(0.5 * ratio + float(bit_index) * ratio))

static func _bit_at(value: int, index: int) -> int:
	if index < 0 or index >= 8:
		return 0
	return (value >> index) & 1

static func _offset_byte(value: int, ratio: float) -> int:
	var out := 0
	for i in range(8):
		var src := _sample_index(i, ratio)
		if _bit_at(value, src) == 1:
			out |= (1 << i)
	return out

static func _first_bad_bit(value: int, ratio: float) -> int:
	for i in range(8):
		var src := _sample_index(i, ratio)
		if _bit_at(value, src) != _bit_at(value, i):
			return i
	return -1
