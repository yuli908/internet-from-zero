extends RefCounted

## CH08 判据：协议三层与封装回放、握手状态机与丢包、三节点抓包快照。
## 只校验玩家提交的回放/轨迹/快照证据，不碰 UI。field_spec 未定的 gate 走 pending。
## 课文：docs/curriculum/19-ch08-lecture-copy.md。

const Kit := preload("res://src/core/lab_gate_kit.gd")

const PENDING_REASONS := {
	"field_start_spec": "8.1 字段位宽 field_spec 未定，无法给出机器起始位真值；先挂 pending 不进分母，不猜数补 gate。"
}

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
		if PENDING_REASONS.has(kind):
			var reason := str(c.get("pending_reason", PENDING_REASONS[kind]))
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
