extends RefCounted

## CH08 判据：协议三层与封装回放、握手状态机与丢包、三节点抓包快照。
## 只校验玩家提交的回放/轨迹/快照证据，不碰 UI。field_spec 未定的 gate 走 pending。
## 课文：docs/curriculum/19-ch08-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")

## 8.1 字段位宽已定稿：真值在 labs.protocol_editor.field_spec。
## 缺真值才挂 pending（不再按 kind 短路），有真值就必须真判。

static func deferred_gates(cfg: Dictionary) -> Dictionary:
	return Kit.deferred_gates(cfg, "res://data/chapters/ch08_levels.json")

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
		if kind == "field_start_spec":
			var spec_v: Variant = cfg.get("field_spec", null)
			if not (spec_v is Dictionary) or (spec_v as Dictionary).is_empty():
				var reason := "8.1 缺 field_spec 真值：无法给出字段起始位，不猜数补 gate"
				pending.append({"id": cid, "kind": kind, "title": str(c.get("title", "")), "reason": reason})
				Kit.add_pending(rep, c, reason)
				continue
		match kind:
			"protocol_replay":
				_protocol_replay(rep, tracker, c, answers)
			"skip_layer":
				_skip_layer(rep, tracker, c, answers)
			"handshake_fsm":
				_handshake_fsm(rep, tracker, c, answers)
			"timeout_idle":
				_timeout_idle(rep, tracker, c, answers)
			"self_heal_path":
				_self_heal_path(rep, tracker, c, answers)
			"capture_layers":
				_capture_layers(rep, tracker, c, answers)
			"single_snapshot":
				_single_snapshot(rep, tracker, c, answers)
			"capture_start":
				_capture_start(rep, tracker, c, answers)
			"field_start_spec":
				_field_start_spec(rep, tracker, c, answers, cfg)
			"quiz":
				Kit.judge_quiz(rep, tracker, c, answers)
			_:
				Kit.emit(rep, tracker, GateResult.E_UNKNOWN_TARGET, c, false, {"kind": kind},
					"已实现 kind", "unknown", "独立检查器不支持 kind=%s（lab=%s）" % [kind, lab_id])
	return {"ok": rep.all_required_passed(), "report": rep, "pending": pending}

static func _protocol_replay(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var steps: Variant = got.get("steps", null)
	var snaps: Variant = got.get("snapshots", null)
	var layers: Array = c.get("layers", [])
	if not (steps is Array) or not (snaps is Dictionary):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"steps + snapshots", "missing", "封装回放未提交：没有步骤或三节点快照")
		return
	var actions: Array = c.get("actions", [])
	var step_arr: Array = steps
	var steps_ok := step_arr.size() == actions.size()
	if steps_ok:
		for i in range(actions.size()):
			var st: Variant = step_arr[i]
			if not (st is Dictionary):
				steps_ok = false
				break
			var sd: Dictionary = st
			if not (sd.has("layer") and sd.has("action") and sd.has("fields")):
				steps_ok = false
				break
			if str(sd.get("layer", "")) not in layers or str(sd.get("action", "")) != str(actions[i]):
				steps_ok = false
				break
			if not (sd.get("fields") is Dictionary) or (sd["fields"] as Dictionary).is_empty():
				steps_ok = false
				break
	if not steps_ok:
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			{"actions": actions}, {"steps": step_arr}, "封装/解封装步骤不可回放：序列或每步 layer/action/fields 缺失")
		return
	var s: Dictionary = snaps
	for key in ["sender", "forward", "receiver"]:
		if not s.has(key) or not (s[key] is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
				["sender", "forward", "receiver"], s.keys(), "只测两端：缺 %s 快照" % key)
			return
	for layer in layers:
		if (not _layers_ok(s["sender"], layers) or not _layers_ok(s["forward"], layers)
				or not _layers_ok(s["receiver"], layers)):
			Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
				{"layers": layers, "each": "非空字段"}, {"snapshots": s},
				"三层未全部展开：%s 层缺字段或为空" % layer)
			return
		for node in ["forward", "receiver"]:
			if not _dict_equal((s["sender"] as Dictionary)[layer], (s[node] as Dictionary)[layer]):
				Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false,
					{"sender": s["sender"], "node": s[node]},
					"转发前后字段一致", {"layer": layer, "node": node},
					"转发后字段被改：%s 层 %s 与发送端不一致" % [layer, node])
				return
	if not bool(got.get("p07", false)):
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, {"p07": true},
			{"p07": false}, "P07 初版未入库，四条验收缺一件")
		return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"回放步骤一致、三层字段不坏、P07 入库", got, "包的一生四条全对")

static func _skip_layer(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("encap_layers") and got.has("addressing_missing") \
			and got.has("forward_ok") and got.has("failed_node")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"encap_layers/addressing_missing/forward_ok/failed_node", "missing",
			"跳层封装负例证据未提交")
		return
	var enc: Variant = got["encap_layers"]
	var ok := ((not (enc is Array) or "address" not in (enc as Array))
		and bool(got["addressing_missing"]) and not bool(got["forward_ok"]))
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"encap_layers": ["physical", "application"], "addressing_missing": true, "forward_ok": false},
		got, "跳层封装，缺寻址字段：中间节点读不到去向" if ok else "跳层负例不成立：寻址层仍在或转发仍成功")

static func _handshake_fsm(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var need := ["transitions", "drop_frame", "state_after_drop", "resend_frame", "delivered"]
	for key in need:
		if not got.has(key):
			Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, need, "missing",
				"握手状态机证据未提交（缺 %s）" % key)
			return
	var trans: Variant = got["transitions"]
	if not (trans is Array) or (trans as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got, "转移表非空", "missing",
			"转移表未填")
		return
	var events: Array = c.get("events", ["send", "ack", "timeout"])
	var states: Array = c.get("states", ["idle", "sent", "confirmed"])
	var seen := {}
	var valid := true
	for raw in (trans as Array):
		if not (raw is Dictionary):
			valid = false
			break
		var t: Dictionary = raw
		if not (t.has("from") and t.has("event") and t.has("to")):
			valid = false
			break
		if (str(t.get("from", "")) not in states or str(t.get("to", "")) not in states
				or str(t.get("event", "")) not in events):
			valid = false
			break
		seen[str(t.get("event", ""))] = true
	for e in events:
		if not seen.has(str(e)):
			valid = false
	if not valid:
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got,
			{"events": events, "states": states}, {"transitions": trans},
			"转移表填错：每条边要有事件与目标状态，三条事件都要覆盖")
		return
	if int(got["drop_frame"]) <= 0:
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			{"drop_frame": ">=1"}, {"drop_frame": int(got["drop_frame"])},
			"只跑无丢包路径，未覆盖注入丢包")
		return
	if str(got["state_after_drop"]) != "sent":
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"state_after_drop": "sent"}, {"state_after_drop": str(got["state_after_drop"])},
			"丢确认后未停在已发送")
		return
	if int(got["resend_frame"]) != int(got["drop_frame"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"resend_frame": int(got["drop_frame"])}, {"resend_frame": int(got["resend_frame"])},
			"超时后重发的帧号与丢失帧不一致")
		return
	if not bool(got["delivered"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			{"delivered": true}, {"delivered": false}, "重发后收到确认仍未送达")
		return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"三状态三事件；丢包停等、重发同帧号、送达", got, "握手四条全对")

static func _timeout_idle(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("resent") and got.has("state") and got.has("delivered")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"resent/state/delivered", "missing", "超时回空闲负例证据未提交")
		return
	var ok := bool(got["resent"]) or (str(got["state"]) == "sent" and not bool(got["delivered"]))
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got,
		{"not_fake": "未重发则停在 sent 且 delivered=false"}, got,
		"超时未重发就回空闲并自称成功" if not ok else "没有把等待当成已送达")

static func _self_heal_path(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var path: Variant = got.get("path", null)
	if not (path is Array) or (path as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, "path", "missing",
			"自愈路径未提交")
		return
	var want: Array = c.get("expected_path", [])
	var got_path: Array = path
	var ok := got_path.size() == want.size()
	if ok:
		for i in range(want.size()):
			if str(got_path[i]) != str(want[i]):
				ok = false
				break
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, ok, got, want, got_path,
		"自愈路径与机器序列一致" if ok else "自愈路径步骤或顺序错")

static func _capture_layers(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var frames: Variant = got.get("frames", null)
	var report: Variant = got.get("report", null)
	var layers: Array = c.get("layers", [])
	if not (frames is Array) or (frames as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, "frames", "missing",
			"未抓到帧：快照为空")
		return
	var arr: Array = frames
	var min_frames := int(c.get("min_frames", 3))
	if arr.size() < min_frames:
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, {"frames": min_frames},
			{"frames": arr.size()}, "只抓单点，无转发对照")
		return
	var nodes := {}
	var frame_ids := {}
	var sender_fields := {}
	var first_id: Variant = null
	for raw in arr:
		if not (raw is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, "帧快照", raw,
				"快照格式错：每份需 {frame_id,node,layers}")
			return
		var f: Dictionary = raw
		if not (f.has("frame_id") and f.has("node") and f.get("layers") is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got, "帧快照", f,
				"快照缺 frame_id/node/layers")
			return
		var nid := str(f["node"])
		nodes[nid] = true
		frame_ids[str(f["frame_id"])] = true
		if first_id == null:
			first_id = f["frame_id"]
		var lm: Dictionary = f["layers"]
		for layer in layers:
			if not lm.has(layer) or not (lm[layer] is Dictionary) or (lm[layer] as Dictionary).is_empty():
				Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
					{"layers": layers}, {"node": nid, "layers": lm.keys()},
					"三层未全部展开：%s 节点缺 %s 层或为空" % [nid, layer])
				return
		if nid == "sender":
			sender_fields = lm
	if frame_ids.size() != 1:
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, got,
			"三份同一帧号", frame_ids.keys(), "三份快照未对齐同一帧号")
		return
	if not (nodes.has("sender") and nodes.has("middle") and nodes.has("receiver")):
		Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, false, got,
			["sender", "middle", "receiver"], nodes.keys(), "只抓单点，缺中间节点对照")
		return
	for raw in arr:
		var f: Dictionary = raw
		if str(f["node"]) == "sender":
			continue
		var lm: Dictionary = f["layers"]
		for layer in layers:
			if not _dict_equal(sender_fields[layer], lm[layer]):
				Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false,
					{"sender": sender_fields[layer], "capture": lm[layer]},
					"与发送端逐字段一致", {"node": str(f["node"]), "layer": layer},
					"字段与发送端不一致：%s 节点 %s 层" % [str(f["node"]), layer])
				return
	if not (report is Dictionary):
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, got,
			"report{layer,field,sender_value,capture_value}", "missing", "报告只抄字节，未填层名/字段名")
		return
	var rd: Dictionary = report
	for key in ["layer", "field", "sender_value", "capture_value"]:
		if not rd.has(key) or str(rd[key]).is_empty():
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, rd,
				"report{layer,field,sender_value,capture_value}", rd,
				"报告字段填错：缺 %s" % key)
			return
	Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, true, got,
		"三份同帧号、三层字段一致、报告两边值", got, "抓包四条全对")

static func _single_snapshot(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	if not (got.has("snapshots") and got.has("comparable") and got.has("missing_nodes")):
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got,
			"snapshots/comparable/missing_nodes", "missing", "单点抓包负例证据未提交")
		return
	var count := int(got["snapshots"])
	var missing: Variant = got["missing_nodes"]
	var ok := (count < 2 and not bool(got["comparable"])
		and (missing is Array) and (missing as Array).size() > 0)
	Kit.emit(rep, tracker, GateResult.E_COVERAGE, c, ok, got,
		{"snapshots": 1, "comparable": false, "missing_nodes": ["middle", "receiver"]}, got,
		"只抓单点，无转发对照" if ok else "单点负例不成立：仍自称可对照或缺缺失节点清单")

static func _capture_start(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary) -> void:
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var fields: Variant = got.get("fields", null)
	if not (fields is Array) or (fields as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, "fields", "missing",
			"未提交抓包字段表")
		return
	var arr: Array = fields
	var cursor := 0
	for raw in arr:
		if not (raw is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, raw, "字段 {name,width,start}",
				raw, "字段格式错")
			return
		var f: Dictionary = raw
		var width := int(f.get("width", 0))
		if width <= 0 or not f.has("start") or int(f.get("start", -1)) != cursor:
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, f,
				{"start": cursor}, {"start": int(f.get("start", -1)), "width": width},
				"起始位推算与抓包不符：%s 应为 %d（前面位宽之和）" % [str(f.get("name", "")), cursor])
			return
		cursor += width
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, true, got,
		"各字段 start = 前面位宽之和", got, "起始位复算与抓包字段表一致")

## 8.1 字段起始位：与 cfg 的 field_spec 逐字段比（字段名、位宽、起始位、保留位），
## 不是只验「start = 前面位宽之和」的自洽——后者会让自洽但位宽错的表蒙过关。
static func _field_start_spec(rep: GateReport, tracker: GateAttemptTracker, c: Dictionary,
		answers: Dictionary, cfg: Dictionary) -> void:
	var spec: Dictionary = cfg.get("field_spec", {})
	var truth := _spec_truth(spec)
	if not bool(truth["ok"]):
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, spec, "field_spec 自洽",
			truth["detail"], str(truth["detail"]))
		return
	var cross := _ch17_spec_agrees(spec)
	if not bool(cross["ok"]):
		Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, spec, "与 17.1 一致",
			cross["detail"], str(cross["detail"]))
		return
	var got := Kit.answer_dict(answers, str(c.get("id", "")))
	var rows_v: Variant = got.get("fields", null)
	if not (rows_v is Array) or (rows_v as Array).is_empty():
		Kit.emit(rep, tracker, GateResult.E_UNCONNECTED, c, false, got, "fields 8 行", "missing",
			"未提交字段起始位表")
		return
	var rows: Array = rows_v
	var fields: Array = (spec.get("packet", {}) as Dictionary).get("fields", [])
	if rows.size() != fields.size():
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, {"rows": rows.size()},
			{"rows": fields.size()}, {"rows": rows.size()},
			"字段行数不符：应为 %d 行，交 %d 行" % [fields.size(), rows.size()])
		return
	for i in fields.size():
		var f: Dictionary = fields[i]
		var rv: Variant = rows[i]
		if not (rv is Dictionary):
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, rv,
				"字段行 {layer,field,start_bit,width_bit}", "missing", "第 %d 行不是对象" % (i + 1))
			return
		var r: Dictionary = rv
		var col := ""
		if str(r.get("layer", "")) != str(f.get("layer", "")):
			col = "layer"
		elif str(r.get("field", "")) != str(f.get("field", "")):
			col = "field"
		elif str(r.get("start_bit", "")) != str(f.get("start_bit", "")):
			col = "start_bit"
		elif not _width_eq(r.get("width_bit", null), f.get("width_bit", null)):
			col = "width_bit"
		if col != "":
			Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false,
				{"row": i + 1, "field": str(f.get("field", ""))},
				{"column": col, "expect": f.get(col, null)}, {"column": col, "actual": r.get(col, null)},
				"第 %d 行（%s）%s 与 field_spec 不符：应为 %s，交 %s" % [i + 1, str(f.get("field", "")), col,
					str(f.get(col, null)), str(r.get(col, null))])
			return
	var samples: Array = spec.get("samples", [])
	if samples.is_empty():
		Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, false, spec, "samples 非空", "empty",
			"field_spec 缺样例")
		return
	for raw in samples:
		var s: Dictionary = raw
		var dec := _decode_sample(str(s.get("hex", "")), spec)
		if bool(s.get("accepted", false)) != bool(dec["accepted"]) \
				or str(s.get("reason", "")) != str(dec["reason"]):
			Kit.emit(rep, tracker, GateResult.E_OUTPUT_MISMATCH, c, false, s,
				{"accepted": dec["accepted"], "reason": dec["reason"]},
				{"accepted": bool(s.get("accepted", false)), "reason": str(s.get("reason", ""))},
				"样例 %s 结论与解码不符：应为 accepted=%s reason=%s，写 accepted=%s reason=%s" % [
					str(s.get("id", "")), str(dec["accepted"]), str(dec["reason"]),
					str(s.get("accepted", false)), str(s.get("reason", ""))])
			return
	Kit.emit(rep, tracker, GateResult.E_TABLE_CELL, c, true, got,
		"字段名/位宽/起始位逐格与 field_spec 相同；样例解码结论一致", got,
		"%d 行逐字段一致；%d 条样例结论一致" % [rows.size(), samples.size()])

static func _spec_truth(spec: Dictionary) -> Dictionary:
	if str(spec.get("unit", "")) != "bit":
		return {"ok": false, "detail": "field_spec.unit 必须是 bit（位宽口径，不是字节）"}
	if str(spec.get("byte_order", "")) != "big_endian":
		return {"ok": false, "detail": "多字节必须大端：byte_order=big_endian"}
	var fr: Dictionary = spec.get("frame", {})
	var ff: Array = fr.get("fields", [])
	if ff.size() != 4:
		return {"ok": false, "detail": "物理帧字段应为 4 个，数据 %d 个" % ff.size()}
	var cursor := 0
	for raw in ff:
		var x: Dictionary = raw
		if int(x.get("start", -1)) != cursor:
			return {"ok": false, "detail": "物理帧 %s 起始位应为 %d" % [str(x.get("name", "")), cursor]}
		var w := int(x.get("width", 0))
		if w <= 0:
			return {"ok": false, "detail": "物理帧 %s 位宽必须为正" % str(x.get("name", ""))}
		cursor += w
	if cursor != 7 or int(fr.get("bits", 0)) != 7:
		return {"ok": false, "detail": "物理帧应为 7 bit（4 数据位 + 1 校验 + 起止各 1），数据合计 %d" % cursor}
	if int(fr.get("frames_per_byte", 0)) != 2:
		return {"ok": false, "detail": "4 数据位口径下每字节 2 帧，数据写 %s" % str(fr.get("frames_per_byte", 0))}
	var f0: Dictionary = ff[0]
	var f1: Dictionary = ff[1]
	var f2: Dictionary = ff[2]
	var f3: Dictionary = ff[3]
	if int(f0.get("must", -1)) != 0 or int(f3.get("must", -1)) != 1:
		return {"ok": false, "detail": "起始位必须为 0、停止位必须为 1"}
	if str(f2.get("rule", "")) != "xor(data)" or str(f1.get("order", "")) != "lsb_first":
		return {"ok": false, "detail": "校验规则应为 xor(data)、数据低位先发"}
	var pk: Dictionary = spec.get("packet", {})
	var pf: Array = pk.get("fields", [])
	if pf.size() != 8:
		return {"ok": false, "detail": "包字段应为 8 个（dst/rsv/src/rsv/type/len/ts/payload），数据 %d 个" % pf.size()}
	var by := _field_by_name(pf)
	for nm in ["dst_node", "dst_rsv", "src_node", "src_rsv", "type", "len", "ts", "payload"]:
		if not by.has(nm):
			return {"ok": false, "detail": "包字段缺 %s" % nm}
	var pos := 0
	for raw in pf:
		var x: Dictionary = raw
		if int(x.get("start_bit", -1)) != pos:
			return {"ok": false, "detail": "包字段 %s 起始位应为 %d（前缀和）" % [str(x.get("field", "")), pos]}
		var wv: Variant = x.get("width_bit", null)
		if wv is String:
			if str(wv) != "8*len" or str(x.get("field", "")) != "payload":
				return {"ok": false, "detail": "只有 payload 可以是可变位宽 8*len"}
		else:
			pos += int(wv)
	if pos != 64:
		return {"ok": false, "detail": "头 8 B 的固定位宽之和应为 64 bit，数据 %d" % pos}
	if int(pk.get("header_bytes", 0)) != 8 or int(pk.get("header_bytes", 0)) * 8 != pos:
		return {"ok": false, "detail": "header_bytes 应与固定位宽之和一致（8 B = 64 bit）"}
	if int(pk.get("max_payload", 0)) != 256:
		return {"ok": false, "detail": "负载上限应为 256 B"}
	if int(pk.get("max_packet_bytes", 0)) != 264 \
			or int(pk.get("max_packet_bytes", 0)) != int(pk.get("header_bytes", 0)) + int(pk.get("max_payload", 0)):
		return {"ok": false, "detail": "整包上限应为 8 + 256 = 264 B"}
	var dst: Dictionary = by["dst_node"]
	var src: Dictionary = by["src_node"]
	var dr: Dictionary = by["dst_rsv"]
	var sr: Dictionary = by["src_rsv"]
	if int(dst.get("width_bit", 0)) != 2 or int(src.get("width_bit", 0)) != 2:
		return {"ok": false, "detail": "dst_node/src_node 位宽应为 2"}
	if int(dr.get("width_bit", 0)) != 6 or int(dr.get("must", -1)) != 0 \
			or int(sr.get("width_bit", 0)) != 6 or int(sr.get("must", -1)) != 0:
		return {"ok": false, "detail": "保留位应为 6 bit 且必须为 0"}
	var ty: Dictionary = by["type"]
	var ln: Dictionary = by["len"]
	var ts: Dictionary = by["ts"]
	var pl: Dictionary = by["payload"]
	if int(ty.get("width_bit", 0)) != 8 or int(ln.get("width_bit", 0)) != 16 or int(ts.get("width_bit", 0)) != 24:
		return {"ok": false, "detail": "应用头应为 type 8 / len 16 / ts 24"}
	if int(ty.get("start_bit", -1)) != 16 or int(ln.get("start_bit", -1)) != 24 \
			or int(ts.get("start_bit", -1)) != 40 or int(pl.get("start_bit", -1)) != 64:
		return {"ok": false, "detail": "起始位应为 type 16 / len 24 / ts 40 / payload 64"}
	if str(pl.get("width_bit", "")) != "8*len":
		return {"ok": false, "detail": "payload 位宽应为 8*len"}
	return {"ok": true, "detail": ""}

## 跨文件：8.1 应用头必须沿用 17.1 的 type/len/ts 与负载上限，不另造一套。
static func _ch17_spec_agrees(spec: Dictionary) -> Dictionary:
	var raw := FileAccess.get_file_as_string("res://data/labs/ch17_labs.json")
	if raw.is_empty():
		return {"ok": false, "detail": "读不到 17.1 数据：res://data/labs/ch17_labs.json"}
	var d: Variant = JSON.parse_string(raw)
	if not (d is Dictionary):
		return {"ok": false, "detail": "17.1 数据不是对象"}
	var labs: Dictionary = (d as Dictionary).get("labs", {})
	var msg: Dictionary = labs.get("msg_format", {})
	var gs: Array = msg.get("gate_cases", [])
	var f17 := {}
	for rawg in gs:
		var g: Dictionary = rawg
		if (g.get("fields") is Dictionary) and not (g.get("fields") as Dictionary).is_empty():
			f17 = g["fields"]
			break
	if f17.is_empty():
		return {"ok": false, "detail": "17.1 没有 fields 真值块"}
	var by := _field_by_name((spec.get("packet", {}) as Dictionary).get("fields", []))
	var ty: Dictionary = by.get("type", {})
	var ln: Dictionary = by.get("len", {})
	var ts: Dictionary = by.get("ts", {})
	var tdom: Array = ty.get("domain", [])
	var allowed: Array = f17.get("allowed_types", [])
	if allowed.size() != tdom.size():
		return {"ok": false, "detail": "type 取值域与 17.1 allowed_types 不一致"}
	for i in allowed.size():
		if int(allowed[i]) != int(tdom[i]):
			return {"ok": false, "detail": "type 取值域与 17.1 allowed_types 不一致"}
	if int(f17.get("len_bits", 0)) != int(ln.get("width_bit", 0)) \
			or int(f17.get("ts_bits", 0)) != int(ts.get("width_bit", 0)):
		return {"ok": false, "detail": "len/ts 位宽与 17.1 不一致（8.1 必须沿用 17.1）"}
	if int(f17.get("max_payload", 0)) != int((spec.get("packet", {}) as Dictionary).get("max_payload", 0)):
		return {"ok": false, "detail": "负载上限与 17.1 不一致"}
	return {"ok": true, "detail": ""}

## 样例按 field_spec 解码：保留位优先，再看节点号、类型、长度上限与长度自洽。
static func _decode_sample(hex: String, spec: Dictionary) -> Dictionary:
	var bytes := hex.hex_decode()
	var total := bytes.size()
	if total < 8:
		return {"accepted": false, "reason": "bad_length"}
	var b0 := int(bytes[0])
	var b1 := int(bytes[1])
	if (b0 >> 2) != 0 or (b1 >> 2) != 0:
		return {"accepted": false, "reason": "bad_reserved"}
	if (b0 & 3) < 1 or (b0 & 3) > 3 or (b1 & 3) < 1 or (b1 & 3) > 3:
		return {"accepted": false, "reason": "bad_addr"}
	var by := _field_by_name((spec.get("packet", {}) as Dictionary).get("fields", []))
	var ty: Dictionary = by.get("type", {})
	var tdom: Array = ty.get("domain", [])
	var t := int(bytes[2])
	if not _in_domain(t, tdom):
		return {"accepted": false, "reason": "bad_type"}
	var ln := (int(bytes[3]) << 8) | int(bytes[4])
	var cap := int((spec.get("packet", {}) as Dictionary).get("max_payload", 0))
	if ln > cap:
		return {"accepted": false, "reason": "too_long"}
	if total - 8 != ln:
		return {"accepted": false, "reason": "bad_length"}
	return {"accepted": true, "reason": ""}

static func _field_by_name(fields: Array) -> Dictionary:
	var out := {}
	for raw in fields:
		if raw is Dictionary:
			out[str((raw as Dictionary).get("field", ""))] = raw
	return out

static func _in_domain(v: int, domain: Array) -> bool:
	for a in domain:
		if int(a) == v:
			return true
	return false

static func _width_eq(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return false
	if (a is String) or (b is String):
		return str(a).strip_edges() == str(b).strip_edges()
	return float(a) == float(b)

static func _layers_ok(snapshot: Variant, layers: Array) -> bool:
	if not (snapshot is Dictionary):
		return false
	var d: Dictionary = snapshot
	for layer in layers:
		if not d.has(layer) or not (d[layer] is Dictionary) or (d[layer] as Dictionary).is_empty():
			return false
	return true

static func _dict_equal(a: Variant, b: Variant) -> bool:
	if not (a is Dictionary) or not (b is Dictionary):
		return false
	var da: Dictionary = a
	var db: Dictionary = b
	if da.size() != db.size():
		return false
	for key in da.keys():
		if not db.has(key):
			return false
		if str(da[key]) != str(db[key]):
			return false
	return true
