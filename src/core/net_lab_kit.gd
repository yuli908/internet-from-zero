extends RefCounted

## CH09–CH12 网络/语言章的通用判据助手。
## 只复用既有 kind 名：table / coverage / port_map / page_map / checksum /
## derived_number / handshake_fsm / timeout_idle / skip_layer / quiz。
## 不新增 kind、不新增失败码；cfg 里声明真值，answers 里取玩家证据。

const Kit := preload("res://src/core/lab_gate_kit.gd")

static func is_pending(c: Dictionary) -> bool:
	return str(c.get("content_status", c.get("status", "ready"))) != "ready"

static func _same(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return absf(float(a) - float(b)) < 1e-9
	# 嵌套形状（token 序列 / AST / 帧表）：逐元素、逐键比；
	# 字典按键集合比，不依赖 JSON 里的键顺序。数组顺序有意义。
	if ta == TYPE_ARRAY and tb == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same((a as Array)[i], (b as Array)[i]):
				return false
		return true
	if ta == TYPE_DICTIONARY and tb == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in (a as Dictionary):
			if not (b as Dictionary).has(k):
				return false
			if not _same((a as Dictionary)[k], (b as Dictionary)[k]):
				return false
		return true
	return str(a) == str(b)

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
		var kind := str(c.get("kind", ""))
		if is_pending(c):
			var reason := str(c.get("pending_reason", "阈值/规格未定，先挂 pending 不进分母"))
			pending.append({"id": cid, "kind": kind, "title": str(c.get("title", "")), "reason": reason})
			Kit.add_pending(rep, c, reason)
			continue
		match kind:
			"table":
				_table(rep, tracker, c, answers)
			"coverage":
				_coverage(rep, tracker, c, answers)
			"port_map":
				_port_map(rep, tracker, c, answers)
			"page_map":
				_page_map(rep, tracker, c, answers)
			"checksum":
				_checksum(rep, tracker, c, answers)
			"derived_number":
				_derived_number(rep, tracker, c, answers)
			"handshake_fsm":
				_handshake_fsm(rep, tracker, c, answers)
			"timeout_idle":
				_timeout_idle(rep, tracker, c, answers)
			"skip_layer":
				_skip_layer(rep, tracker, c, answers)
			"quiz":
				Kit.judge_quiz(rep, tracker, c, answers)
			_:
				Kit.emit(rep, tracker, GateResult.E_UNKNOWN_TARGET, c, false, {"kind": kind},
					"已实现 kind", "unknown",
					"独立检查器不支持 kind=%s（lab=%s）" % [kind, lab_id])
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

## 填表：rows 对 expect_rows，keys 选列；缺件 3、行数 13、某格 7、meta 10。
static func _table(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var rows_v: Variant = got.get("rows", null)
	if not (rows_v is Array):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"rows 数组", "missing", "填表证据未提交：没有 rows")
		return
	var rows: Array = rows_v
	var want: Array = c.get("expect_rows", [])
	var keys: Array = c.get("keys", [])
	if want.is_empty():
		Kit.emit(rep, tracker, GateResult.E_UNKNOWN_TARGET, c, false, got,
			"expect_rows", "missing", "gate 配置缺 expect_rows")
		return
	if keys.is_empty():
		keys = (want[0] as Dictionary).keys()
	if rows.size() != want.size():
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			{"rows": want.size()}, {"rows": rows.size()},
			"表行数不符：交 %d 行，机器要 %d 行" % [rows.size(), want.size()])
		return
	var unique := str(c.get("unique_key", ""))
	if not unique.is_empty():
		var seen := {}
		for raw in rows:
			if not (raw is Dictionary):
				Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, raw,
					"每行为对象", raw, "表行格式错：不是对象")
				return
			var k := str((raw as Dictionary).get(unique, ""))
			if seen.has(k):
				Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got,
					"唯一键 %s" % unique, "重复 %s" % k,
					"表里有重复键 %s：唯一性未成立" % k)
				return
			seen[k] = true
	# 时延越限：cfg 可选 `delay:{key,max}`。只在该列越上限时报 9（语义本就属 E_DELAY_MISMATCH），
	# 值在限内但与机器不符仍归 7。这样 data 里写的 9 是可发射的，不是死判据。
	var delay_cfg: Dictionary = c.get("delay", {})
	var delay_key := str(delay_cfg.get("key", ""))
	var delay_max := float(delay_cfg.get("max", 0.0))
	if not delay_key.is_empty() and delay_max > 0.0:
		for i in range(rows.size()):
			if not (rows[i] is Dictionary):
				continue
			var dr: Dictionary = rows[i]
			var dv: Variant = dr.get(delay_key, null)
			if dv == null or not (typeof(dv) == TYPE_INT or typeof(dv) == TYPE_FLOAT):
				continue
			if float(dv) > delay_max:
				Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, false, dr,
					{str(delay_key): "<= %s" % str(delay_max)},
					{str(delay_key): dv},
					"第 %d 行 %s=%s 超过上限 %s（时延越限）"
						% [i + 1, delay_key, str(dv), str(delay_max)])
				return
	# 时间戳自洽：cfg 可选 `timing:{id,seq,sent,got,latency,gap}`。时延必须由两枚真实时钟事件
	# 现算（latency == got − sent 且 >0），发送时刻必须来自仿真调度（sent = 序号×gap），
	# 请求编号与客户端序号必须按发送顺序绑定。时钟/时延不符 → 9；编号绑错 → 7。
	# 并发请求的完成次序本来就可以乱序，故不校验 got 单调。
	var timing: Dictionary = c.get("timing", {})
	var t_id := str(timing.get("id", ""))
	var t_seq := str(timing.get("seq", ""))
	var t_sent := str(timing.get("sent", ""))
	var t_got := str(timing.get("got", ""))
	var t_lat := str(timing.get("latency", ""))
	var t_gap := int(timing.get("gap", 0))
	if not (t_id.is_empty() or t_seq.is_empty() or t_sent.is_empty()
			or t_got.is_empty() or t_lat.is_empty()):
		for i in range(rows.size()):
			if not (rows[i] is Dictionary):
				continue
			var tr: Dictionary = rows[i]
			if not (tr.has(t_id) and tr.has(t_seq) and tr.has(t_sent)
					and tr.has(t_got) and tr.has(t_lat)):
				continue
			if int(tr[t_id]) != i + 1 or int(tr[t_seq]) != i + 1:
				Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, tr,
					{str(t_id): i + 1, str(t_seq): i + 1},
					{str(t_id): tr[t_id], str(t_seq): tr[t_seq]},
					"第 %d 行请求身份绑错：req_id/client_seq 与发送顺序不符" % (i + 1))
				return
			var sent := int(tr[t_sent])
			var got_t := int(tr[t_got])
			if sent != i * t_gap:
				Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, false, tr,
					{str(t_sent): i * t_gap}, {str(t_sent): sent},
					"第 %d 行发送时刻不是仿真时钟事件：%d ≠ %d" % [i + 1, sent, i * t_gap])
				return
			if got_t <= sent:
				Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, false, tr,
					{str(t_got): "> %d" % sent}, {str(t_got): got_t},
					"第 %d 行到达时刻不在发送之后：got=%d sent=%d" % [i + 1, got_t, sent])
				return
			if int(tr[t_lat]) != got_t - sent or int(tr[t_lat]) <= 0:
				Kit.emit(rep, tracker, GateResult.E_DELAY_MISMATCH, c, false, tr,
					{str(t_lat): got_t - sent}, {str(t_lat): tr[t_lat]},
					"第 %d 行时延不是两枚事件之差：%s ≠ %d−%d"
						% [i + 1, str(tr[t_lat]), got_t, sent])
				return
	for i in range(rows.size()):
		if not (rows[i] is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, rows[i],
				"每行为对象", rows[i], "表行格式错：不是对象")
			return
		var row: Dictionary = rows[i]
		var exp: Dictionary = want[i]
		for key in keys:
			if not _same(row.get(key, ""), exp.get(key, "")):
				Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, row,
					{str(key): exp.get(key, null)}, {str(key): row.get(key, null)},
					"第 %d 行 %s 填错：%s ≠ %s" % [i + 1, str(key),
						str(row.get(key, "?")), str(exp.get(key, "?"))])
				return
	var meta: Dictionary = got.get("meta", {})
	var expect_meta: Dictionary = c.get("expect_meta", {})
	for key in expect_meta:
		if not _same(meta.get(key, ""), expect_meta[key]):
			Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, meta,
				{str(key): expect_meta[key]}, {str(key): meta.get(key, null)},
				"判据 %s 不符：%s ≠ %s" % [str(key), str(meta.get(key, "?")),
					str(expect_meta[key])])
			return
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, true, got,
		"表行逐格一致、判据全真", got, "表与判据全对")

## 覆盖：cases 对 expect_cases；缺项 13、值为假 10。
static func _coverage(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var cases_v: Variant = got.get("cases", null)
	if not (cases_v is Dictionary) or (cases_v as Dictionary).is_empty():
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			"cases 非空", "missing", "覆盖证据未提交：cases 为空")
		return
	var cases: Dictionary = cases_v
	var expect: Dictionary = c.get("expect_cases", {})
	for key in expect:
		if not cases.has(key):
			Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, cases,
				{"case": str(key)}, "missing", "缺覆盖项 %s：只做了一部分" % str(key))
			return
		if str(cases[key]) != str(expect[key]):
			Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, cases,
				{str(key): expect[key]}, {str(key): cases[key]},
				"覆盖项 %s 不成立：%s ≠ %s" % [str(key), str(cases[key]),
					str(expect[key])])
			return
	Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, true, got,
		expect, cases, "覆盖项全部成立")

## 地址→端口/下一跳：rows 对 expect_rows；缺件 3、端口错 7、meta 10。
static func _port_map(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var rows_v: Variant = got.get("rows", null)
	if not (rows_v is Array):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"rows[{addr,port}]", "missing", "映射表未提交：没有 rows")
		return
	var rows: Array = rows_v
	var want: Array = c.get("expect_rows", [])
	if rows.size() != want.size():
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			{"rows": want.size()}, {"rows": rows.size()},
			"映射表行数不符：交 %d 行，机器要 %d 行" % [rows.size(), want.size()])
		return
	for i in range(rows.size()):
		var row: Dictionary = rows[i]
		var exp: Dictionary = want[i]
		if not _same(row.get("addr", ""), exp.get("addr", "")) \
				or not _same(row.get("port", ""), exp.get("port", "")):
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, row,
				exp, row, "第 %d 行地址/端口错：%s→%s ≠ %s→%s" % [i + 1,
					str(row.get("addr", "?")), str(row.get("port", "?")),
					str(exp.get("addr", "?")), str(exp.get("port", "?"))])
			return
	var meta: Dictionary = got.get("meta", {})
	var expect_meta: Dictionary = c.get("expect_meta", {})
	for key in expect_meta:
		if not _same(meta.get(key, ""), expect_meta[key]):
			Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, meta,
				{str(key): expect_meta[key]}, {str(key): meta.get(key, null)},
				"映射判据 %s 不符" % str(key))
			return
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, true, got,
		"地址→端口逐行一致", got, "映射表与判据全对")

## 映射 + 回读：entries/page、written/read_back/mismatches。
static func _page_map(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	for key in ["written", "read_back", "mismatches", "entries"]:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
				"written/read_back/mismatches/entries", "missing",
				"映射证据未提交（缺 %s）" % key)
			return
	var entries: Array = got["entries"]
	var want: Array = c.get("expect_entries", [])
	if entries.is_empty():
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			"entries 非空", "empty", "映射表没有任何行")
		return
	if entries.size() != want.size():
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			{"entries": want.size()}, {"entries": entries.size()},
			"映射行数不符：交 %d，机器要 %d" % [entries.size(), want.size()])
		return
	for i in range(entries.size()):
		var row: Dictionary = entries[i]
		var exp: Dictionary = want[i]
		if not _same(row.get("page", ""), exp.get("page", "")) \
				or not _same(row.get("frame", ""), exp.get("frame", "")):
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, row,
				exp, row, "第 %d 行映射错" % [i + 1])
			return
	if int(got["read_back"]) < int(got["written"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"read_back": int(got["written"])}, {"read_back": int(got["read_back"])},
			"回读少于写入：有行没验")
		return
	if int(got["mismatches"]) > 0:
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"mismatches": 0}, {"mismatches": int(got["mismatches"])},
			"映射回读有 %d 处不一致" % int(got["mismatches"]))
		return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"逐行映射与回读一致", got, "映射与回读全对")

## 1 KB 级传输：bytes/checksum/result_checksum/seq_ok/frames_ok。
static func _checksum(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	for key in ["bytes", "checksum", "result_checksum", "seq_ok", "frames_ok"]:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
				"bytes/checksum/result_checksum/seq_ok/frames_ok", "missing",
				"端到端证据未提交（缺 %s）" % key)
			return
	if int(got["bytes"]) != int(c.get("expect_bytes", 1024)):
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got,
			{"bytes": int(c.get("expect_bytes", 1024))}, {"bytes": int(got["bytes"])},
			"字节数错：%d ≠ %d" % [int(got["bytes"]), int(c.get("expect_bytes", 1024))])
		return
	if int(got["checksum"]) != int(got["result_checksum"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"checksum": int(got["checksum"])}, {"checksum": int(got["result_checksum"])},
			"逐字节校验不一致：内容没拼回")
		return
	if not bool(got["seq_ok"]) or not bool(got["frames_ok"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"seq_ok": true, "frames_ok": true},
			{"seq_ok": bool(got["seq_ok"]), "frames_ok": bool(got["frames_ok"])},
			"序号未连续或有帧缺失：不算送达")
		return
	var meta: Dictionary = got.get("meta", {})
	for key in (c.get("expect_meta", {}) as Dictionary):
		if not _same(meta.get(key, ""), c["expect_meta"][key]):
			Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, meta,
				{str(key): c["expect_meta"][key]}, {str(key): meta.get(key, null)},
				"端到端判据 %s 不符" % str(key))
			return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"1024 字节、校验一致、序号连续", got, "1 KB 端到端全对")

## 数值复算：value 或 values{} 对 expect / expect_values。
static func _derived_number(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var tol := float(c.get("tolerance", 1e-9))
	var expect_values: Dictionary = c.get("expect_values", {})
	if not expect_values.is_empty():
		var values_v: Variant = got.get("values", null)
		if not (values_v is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
				"values", "missing", "复算结果未提交：没有 values")
			return
		var values: Dictionary = values_v
		for key in expect_values:
			if not values.has(key):
				Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, values,
					{str(key): expect_values[key]}, "missing",
					"复算缺项 %s" % str(key))
				return
			if absf(float(values[key]) - float(expect_values[key])) > tol:
				Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, values,
					{str(key): expect_values[key]}, {str(key): values[key]},
					"复算 %s 错：%s ≠ %s" % [str(key), str(values[key]),
						str(expect_values[key])])
				return
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, true, values,
			expect_values, values, "复算各项全对")
		return
	if not got.has("value"):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"value", "missing", "复算结果未提交：没有 value")
		return
	var want := float(c.get("expect", 0.0))
	if absf(float(got["value"]) - want) > tol:
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got,
			{"value": want}, {"value": got["value"]},
			"复算错：%s ≠ %s" % [str(got["value"]), str(want)])
		return
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, true, got,
		{"value": want}, {"value": got["value"]}, "复算正确")

## 确认/重传轨迹：转移表 + 丢包 + 同号重发 + P07 完整版。
static func _handshake_fsm(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var need := ["transitions", "drop_frame", "state_after_drop", "resend_frame",
		"delivered", "p07_full"]
	for key in need:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, need,
				"missing", "ACK 轨迹未提交（缺 %s）" % key)
			return
	var trans: Variant = got["transitions"]
	var events: Array = c.get("events", ["send", "ack", "timeout"])
	var states: Array = c.get("states", ["idle", "waiting", "acked"])
	var seen := {}
	var valid := trans is Array and not (trans as Array).is_empty()
	if valid:
		for raw in (trans as Array):
			if not (raw is Dictionary):
				valid = false
				break
			var t: Dictionary = raw
			if not (t.has("from") and t.has("event") and t.has("to")):
				valid = false
				break
			if str(t["from"]) not in states or str(t["to"]) not in states \
					or str(t["event"]) not in events:
				valid = false
				break
			seen[str(t["event"])] = true
	for e in events:
		if not seen.has(str(e)):
			valid = false
	if not valid:
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got,
			{"events": events, "states": states}, {"transitions": trans},
			"转移表填错：三事件未覆盖或状态不在集合内")
		return
	if int(got["drop_frame"]) <= 0:
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			{"drop_frame": ">=1"}, {"drop_frame": int(got["drop_frame"])},
			"只跑无丢包路径，未注入丢 ACK")
		return
	var want_state := str(c.get("expect_state_after_drop", "waiting"))
	if str(got["state_after_drop"]) != want_state:
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"state_after_drop": want_state}, {"state_after_drop": str(got["state_after_drop"])},
			"丢 ACK 后未停在等待")
		return
	if int(got["resend_frame"]) != int(got["drop_frame"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"resend_frame": int(got["drop_frame"])}, {"resend_frame": int(got["resend_frame"])},
			"超时重发换了序号：接收端会当新数据")
		return
	if not bool(got["delivered"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"delivered": true}, {"delivered": false}, "重发后仍未送达")
		return
	if not bool(got["p07_full"]):
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			{"p07_full": true}, {"p07_full": false}, "P07 完整版未含窗口/重传分支")
		return
	if bool(c.get("expect_repeatable", false)) and not bool(got.get("repeatable", false)):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"repeatable": true}, {"repeatable": got.get("repeatable", false)},
			"同配置第二跑轨迹不一致：重发次数不可复现")
		return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"三状态三事件；丢 ACK 停等、同号重发、送达、P07 完整", got, "ACK 四条全对")

## 超时负例：要么真的重发，要么停在等待且未送达；「回空闲还报送达」判红。
static func _timeout_idle(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("resent") and got.has("state") and got.has("delivered")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"resent/state/delivered", "missing", "超时负例证据未提交")
		return
	var idle := str(c.get("idle_state", "idle"))
	var ok := bool(got["resent"]) or (str(got["state"]) == idle and not bool(got["delivered"]))
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"not_fake": "未重发则停在等待且 delivered=false"}, got,
		"超时未重发却回空闲并自报送达" if not ok else "没有把等待当成已送达")

## 缺阶段负例：必需阶段缺失且下游确实坏 → 绿；下游仍好 → 负例没复现判红。
static func _skip_layer(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("stages") and got.has("missing") and got.has("downstream_ok")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"stages/missing/downstream_ok", "missing", "缺阶段负例证据未提交")
		return
	var missing := str(got["missing"])
	var stages: Variant = got["stages"]
	var ok: bool = not missing.is_empty() and missing in stages and not bool(got["downstream_ok"])
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"missing": str(c.get("stage", "必需阶段")), "downstream_ok": false}, got,
		"缺阶段负例成立：%s 未接，下游确实坏" % missing if ok \
			else "缺阶段负例不成立：%s 未缺或下游仍正常" % missing)
