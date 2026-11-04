extends RefCounted

## CH08 三节（15 段）结构 + 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按数据现算。
## 8.1 的字段位宽 field_spec 未定 → T8.1-3 挂 pending；其余 gate 一律给正解与反例。
## 所有判据断言都给反例：断言必须能红，不是恒真。

const LABS := ["protocol_editor", "handshake", "capture"]
const SECTION_COUNTS := {"protocol_editor": 5, "handshake": 5, "capture": 5}
const TOTAL_SECTIONS := 15
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260

const Ch08 = preload("res://src/core/ch08_checks.gd")
const Teach = preload("res://src/ui/teaching.gd")

const EXPECT := 157
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 3, "section_count": 3, "total_sections": 1,
	"order": 15, "after_unlock": 15, "after_bound": 15, "text_nonempty": 15, "text_cap": 15,
	"screen_sum": 12, "last_after": 3, "after_required": 3, "fallback": 6,
	"denominator": 3, "gate_ids": 3, "gate_count": 3, "required_count": 3, "gate_codes": 3,
	"practice": 6, "p1_field": 3, "pending_declared": 2,
	"judge_protocol": 8, "judge_handshake": 8, "judge_capture": 8,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch08_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 段数与课文一致（各 5 段）",
	"total_sections": "全篇 15 段",
	"order": "每 lab 内 order 连续",
	"after_unlock": "首段 after=0、其余单调不减",
	"after_bound": "每段 after ≤ required−1",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（左栏口径，去半角空格）",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"last_after": "末段 after = required−1",
	"after_required": "最大 after 落在 required−1",
	"fallback": "删掉 sections 的副本退回 body",
	"denominator": "进分母 gate 数按 required 去 pending 现算",
	"gate_ids": "gate id 按 T8.x-n 顺序且与课文提案一致",
	"gate_count": "每节 gate 条数 4",
	"required_count": "每节 required gate 数为 4",
	"gate_codes": "gate 失败码只用白名单 3/5/7/8/9/10/13/14/15/27",
	"practice": "每节有实践表且每行 id/level/produce/judge 齐全",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"pending_declared": "8.1 字段位宽未定，T8.1-3 挂 pending 且不进分母",
	"judge_protocol": "8.1 回放/三层字段/P07 正解判绿；跳层/缺层/改字段/缺步骤/选择题给反例",
	"judge_handshake": "8.2 正常握手与丢包重发正解判绿；假成功/漏事件/状态错/帧号错/无丢包/路径错给反例",
	"judge_capture": "8.3 三份快照正解判绿；单点/缺帧/缺层/字段错/报告缺项/起始位错给反例",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch08_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch08_labs 可读", not labs.is_empty(), str(labs.size()))

	var total := 0
	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var secs: Array = cfg.get("sections", [])
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not secs.is_empty(), str(secs.size()))
		ctx.begin_group("section_count")
		ctx.eq("%s 段数" % id, secs.size(), int(SECTION_COUNTS[id]))
		_structural(ctx, id, cfg, secs)
		total += secs.size()
		_contract(ctx, id, cfg)
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	_judge_protocol(ctx, labs.get("protocol_editor", {}))
	_judge_handshake(ctx, labs.get("handshake", {}))
	_judge_capture(ctx, labs.get("capture", {}))

func _structural(ctx: TestContext, id: String, cfg: Dictionary, secs: Array) -> void:
	var req := _required_count(cfg)
	var prev_after := -1
	var max_after := -1
	var screen := {}
	for i in secs.size():
		var s: Dictionary = secs[i]
		var order := int(s.get("order", -1))
		var after := int(s.get("after", -1))
		var text := str(s.get("text", ""))
		var text_len := text.replace(" ", "").length()
		ctx.begin_group("order")
		ctx.eq("%s[%d] order 连续" % [id, i + 1], order, i + 1)
		ctx.begin_group("after_unlock")
		if i == 0:
			ctx.eq("%s 首段 after=0" % id, after, 0)
		else:
			ctx.check("%s[%d] after 单调不减" % [id, i + 1], after >= prev_after,
				"%d < %d" % [after, prev_after])
		ctx.begin_group("after_bound")
		ctx.check("%s[%d] after ≤ required−1" % [id, i + 1], after <= req - 1,
			"after=%d required=%d" % [after, req])
		ctx.begin_group("text_nonempty")
		ctx.check("%s[%d] text 非空" % [id, i + 1], not text.strip_edges().is_empty())
		ctx.begin_group("text_cap")
		ctx.check("%s[%d] text ≤150 字" % [id, i + 1], text_len <= LEFT_LIMIT, str(text_len))
		screen[after] = int(screen.get(after, 0)) + text_len
		max_after = maxi(max_after, after)
		prev_after = after
	var last_after := int((secs[secs.size() - 1] as Dictionary).get("after", -1))
	ctx.begin_group("last_after")
	ctx.check("%s 末段 after = required−1" % id, last_after == req - 1,
		"last=%d required=%d" % [last_after, req])
	ctx.begin_group("after_required")
	ctx.check("%s 最大 after = required−1" % id, max_after == req - 1,
		"max=%d required=%d" % [max_after, req])
	ctx.begin_group("screen_sum")
	for after in screen.keys():
		ctx.check("%s after=%d 同屏合计 ≤260" % [id, int(after)], int(screen[after]) <= SCREEN_LIMIT,
			str(screen[after]))
	ctx.begin_group("fallback")
	var copy: Dictionary = JSON.parse_string(JSON.stringify(cfg))
	copy.erase("sections")
	ctx.check("%s 无 sections 时 body 非空" % id, not str(copy.get("body", "")).strip_edges().is_empty())
	ctx.check("%s 无 sections 时退回 body" % id, Teach.has_teaching(copy), Teach.teaching_text(copy))

func _contract(ctx: TestContext, id: String, cfg: Dictionary) -> void:
	var req := _required_count(cfg)
	var cases: Array = cfg.get("gate_cases", [])
	var d: Dictionary = Ch08.deferred_gates(cfg)
	ctx.begin_group("denominator")
	ctx.eq("%s 进分母 gate 数" % id, int(d["counted"]), 3 if id == "protocol_editor" else 4)
	ctx.begin_group("gate_count")
	ctx.eq("%s gate 条数" % id, cases.size(), 4)
	ctx.begin_group("required_count")
	ctx.eq("%s required 数" % id, req, 4)
	ctx.begin_group("gate_ids")
	var ids := []
	for raw in cases:
		ids.append(str((raw as Dictionary).get("id", "")))
	ctx.check("%s gate id 顺序与课文提案一致" % id, _ids_ok(id, ids), str(ids))
	ctx.begin_group("gate_codes")
	var bad := []
	var codes := []
	for raw in cases:
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for raw in (cfg.get("practice", []) as Array):
		for code in (raw as Dictionary).get("codes", []):
			codes.append(str(code))
	for s in codes:
		var num := _code_num(str(s))
		if num < 0 or not LabGateKit.ALLOWED_CODES.has(num):
			bad.append(str(s))
	ctx.check("%s 失败码形如 E_NAME(n) 且在白名单（无 26/28）" % id, bad.is_empty(), str(bad))
	ctx.begin_group("practice")
	var practice: Array = cfg.get("practice", [])
	ctx.check("%s 有实践表" % id, not practice.is_empty(), str(practice.size()))
	var incomplete := []
	for raw in practice:
		var row: Dictionary = raw
		for key in ["id", "level", "produce", "judge"]:
			if str(row.get(key, "")).strip_edges().is_empty():
				incomplete.append("%s.%s" % [str(row.get("id", "?")), key])
	ctx.check("%s 实践表字段齐全" % id, incomplete.is_empty(), str(incomplete))
	ctx.begin_group("p1_field")
	var p1 := str(cfg.get("p1", ""))
	var p1_gates: Array = cfg.get("p1_gates", [])
	ctx.check("%s 有 P1 文本与 p1_gates" % id, not p1.strip_edges().is_empty() and not p1_gates.is_empty(), p1)

func _judge_protocol(ctx: TestContext, cfg: Dictionary) -> void:
	var layer_fields := {
		"physical": {"start": 0, "data": "1010", "parity": 0, "stop": 1},
		"address": {"from": "node1", "to": "node2"},
		"application": {"payload": "hello"},
	}
	var snapshots := {
		"sender": layer_fields,
		"forward": layer_fields.duplicate(true),
		"receiver": layer_fields.duplicate(true),
	}
	var good := {
		"T8.1-1": {
			"steps": [
				{"layer": "physical", "action": "encap", "fields": layer_fields["physical"]},
				{"layer": "address", "action": "forward", "fields": layer_fields["address"]},
				{"layer": "application", "action": "decap", "fields": layer_fields["application"]},
			],
			"snapshots": snapshots,
			"p07": true,
		},
		"T8.1-2": {"encap_layers": ["physical", "application"], "addressing_missing": true,
			"forward_ok": false, "failed_node": "middle"},
		"T8.1-4": 0,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	var pend: Array = result.get("pending", [])
	ctx.begin_group("judge_protocol")
	ctx.check("8.1 可判项全过（字段位宽项 pending）", rep.all_required_passed(), str(rep.failure_codes()))
	ctx.check("8.1 跳层封装却仍报转发成功 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T8.1-2", {"encap_layers": ["physical", "address", "application"],
			"addressing_missing": false, "forward_ok": true, "failed_node": "none"})), "T8.1-2") == 10)
	var miss_layer := snapshots.duplicate(true)
	(miss_layer["forward"] as Dictionary).erase("address")
	ctx.check("8.1 转发快照缺寻址层 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T8.1-1", {
			"steps": (good["T8.1-1"] as Dictionary)["steps"],
			"snapshots": miss_layer, "p07": true})), "T8.1-1") == 13)
	var changed := snapshots.duplicate(true)
	changed["forward"] = changed["forward"].duplicate(true)
	(changed["forward"]["application"] as Dictionary)["payload"] = "hell0"
	ctx.check("8.1 转发改了应用载荷 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T8.1-1", {
			"steps": (good["T8.1-1"] as Dictionary)["steps"],
			"snapshots": changed, "p07": true})), "T8.1-1") == 10)
	ctx.check("8.1 少解封装步骤 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T8.1-1", {
			"steps": [{"layer": "physical", "action": "encap", "fields": layer_fields["physical"]}],
			"snapshots": snapshots, "p07": true})), "T8.1-1") == 13)
	ctx.check("8.1 P07 未入库 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T8.1-1", {
			"steps": (good["T8.1-1"] as Dictionary)["steps"],
			"snapshots": snapshots, "p07": false})), "T8.1-1") == 13)
	ctx.check("8.1 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T8.1-4", 1)),
		"T8.1-4") == 14)
	ctx.check("8.1 未接协议编辑器 → 红 E_UNCONNECTED", _case_code(_run(cfg, _with(good, "T8.1-1", {})),
		"T8.1-1") == 3)
	ctx.begin_group("pending_declared")
	ctx.check("8.1 仅 T8.1-3 挂 pending（field_spec 未定）",
		pend.size() == 1 and str((pend[0] as Dictionary).get("id", "")) == "T8.1-3", str(pend))
	var g := _gate(cfg, "T8.1-3")
	var spec: Dictionary = (g.get("thresholds", {}) as Dictionary).get("field_spec", {})
	ctx.check("8.1 字段位宽标 pending，不猜起始位真值",
		str(spec.get("status", "")) == "pending", str(spec))

func _judge_handshake(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T8.2-1": {
			"transitions": [
				{"from": "idle", "event": "send", "to": "sent"},
				{"from": "sent", "event": "ack", "to": "confirmed"},
				{"from": "sent", "event": "timeout", "to": "sent"},
			],
			"drop_frame": 1, "state_after_drop": "sent", "resend_frame": 1, "delivered": true,
		},
		"T8.2-2": {"resent": false, "state": "sent", "delivered": false},
		"T8.2-3": {"path": ["send", "wait_ack", "timeout", "resend", "ack", "idle"]},
		"T8.2-4": 0,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_handshake")
	ctx.check("8.2 四条全过", rep.all_required_passed(), str(rep.failure_codes()))
	ctx.check("8.2 超时未重发却回空闲并报送达 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T8.2-2", {"resent": false, "state": "idle",
			"delivered": true})), "T8.2-2") == 10)
	ctx.check("8.2 转移表漏超时事件 → 红 E_TABLE_CELL",
		_case_code(_run(cfg, _with(good, "T8.2-1", {
			"transitions": [{"from": "idle", "event": "send", "to": "sent"},
				{"from": "sent", "event": "ack", "to": "confirmed"}],
			"drop_frame": 1, "state_after_drop": "sent", "resend_frame": 1, "delivered": true})),
			"T8.2-1") == 7)
	ctx.check("8.2 丢确认后跳到已确认 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T8.2-1", {
			"transitions": (good["T8.2-1"] as Dictionary)["transitions"],
			"drop_frame": 1, "state_after_drop": "confirmed", "resend_frame": 1, "delivered": true})),
			"T8.2-1") == 10)
	ctx.check("8.2 重发帧号不一致 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T8.2-1", {
			"transitions": (good["T8.2-1"] as Dictionary)["transitions"],
			"drop_frame": 1, "state_after_drop": "sent", "resend_frame": 2, "delivered": true})),
			"T8.2-1") == 10)
	ctx.check("8.2 只跑无丢包路径 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T8.2-1", {
			"transitions": (good["T8.2-1"] as Dictionary)["transitions"],
			"drop_frame": 0, "state_after_drop": "sent", "resend_frame": 1, "delivered": true})),
			"T8.2-1") == 13)
	ctx.check("8.2 自愈路径顺序错 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T8.2-3", {"path": ["send", "wait_ack", "resend",
			"timeout", "ack", "idle"]})), "T8.2-3") == 10)
	ctx.check("8.2 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T8.2-4", 1)),
		"T8.2-4") == 14)

func _judge_capture(ctx: TestContext, cfg: Dictionary) -> void:
	var layers := {
		"physical": {"start": 0, "data": "1010", "parity": 0, "stop": 1},
		"address": {"from": "node1", "to": "node2"},
		"application": {"payload": "hello"},
	}
	var good := {
		"T8.3-1": {
			"frames": [
				{"frame_id": 7, "node": "sender", "layers": layers},
				{"frame_id": 7, "node": "middle", "layers": layers.duplicate(true)},
				{"frame_id": 7, "node": "receiver", "layers": layers.duplicate(true)},
			],
			"report": {"layer": "physical", "field": "start", "sender_value": 0,
				"capture_value": 0},
		},
		"T8.3-2": {"snapshots": 1, "comparable": false,
			"missing_nodes": ["middle", "receiver"]},
		"T8.3-3": {"fields": [
			{"name": "start", "width": 1, "start": 0},
			{"name": "data", "width": 4, "start": 1},
			{"name": "parity", "width": 1, "start": 5},
			{"name": "stop", "width": 1, "start": 6},
		]},
		"T8.3-4": 0,
	}
	var result := _run(cfg, good)
	var rep: GateReport = result.get("report")
	ctx.begin_group("judge_capture")
	ctx.check("8.3 四条全过", rep.all_required_passed(), str(rep.failure_codes()))
	ctx.check("8.3 只抓接收端却自称可对照 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T8.3-2", {"snapshots": 1, "comparable": true,
			"missing_nodes": []})), "T8.3-2") == 13)
	ctx.check("8.3 只抓一帧 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T8.3-1", {
			"frames": [{"frame_id": 7, "node": "sender", "layers": layers}],
			"report": (good["T8.3-1"] as Dictionary)["report"]})), "T8.3-1") == 13)
	var miss_layer := layers.duplicate(true)
	miss_layer.erase("application")
	ctx.check("8.3 三层未展开 → 红 E_COVERAGE",
		_case_code(_run(cfg, _with(good, "T8.3-1", {
			"frames": [
				{"frame_id": 7, "node": "sender", "layers": layers},
				{"frame_id": 7, "node": "middle", "layers": miss_layer},
				{"frame_id": 7, "node": "receiver", "layers": layers},
			], "report": (good["T8.3-1"] as Dictionary)["report"]})), "T8.3-1") == 13)
	var changed := layers.duplicate(true)
	changed["application"] = {"payload": "hell0"}
	ctx.check("8.3 中间节点字段被改 → 红 E_OUTPUT_MISMATCH",
		_case_code(_run(cfg, _with(good, "T8.3-1", {
			"frames": [
				{"frame_id": 7, "node": "sender", "layers": layers},
				{"frame_id": 7, "node": "middle", "layers": changed},
				{"frame_id": 7, "node": "receiver", "layers": layers},
			], "report": (good["T8.3-1"] as Dictionary)["report"]})), "T8.3-1") == 10)
	ctx.check("8.3 报告缺字段名 → 红 E_TABLE_CELL",
		_case_code(_run(cfg, _with(good, "T8.3-1", {
			"frames": (good["T8.3-1"] as Dictionary)["frames"],
			"report": {"layer": "physical", "field": "", "sender_value": 0,
				"capture_value": 0}})), "T8.3-1") == 7)
	ctx.check("8.3 起始位推算与抓包不符 → 红 E_TABLE_CELL",
		_case_code(_run(cfg, _with(good, "T8.3-3", {"fields": [
			{"name": "start", "width": 1, "start": 0},
			{"name": "data", "width": 4, "start": 2},
			{"name": "parity", "width": 1, "start": 5},
			{"name": "stop", "width": 1, "start": 6},
		]})), "T8.3-3") == 7)
	ctx.check("8.3 选择题错 → 红 E_QUIZ", _case_code(_run(cfg, _with(good, "T8.3-4", 1)),
		"T8.3-4") == 14)

# ---------------------------------------------------------------- 工具

func _ids_ok(id: String, ids: Array) -> bool:
	var prefix := ""
	match id:
		"protocol_editor": prefix = "T8.1-"
		"handshake": prefix = "T8.2-"
		"capture": prefix = "T8.3-"
	if ids.size() != 4:
		return false
	for i in 4:
		if str(ids[i]) != "%s%d" % [prefix, i + 1]:
			return false
	return true

func _required_count(cfg: Dictionary) -> int:
	var n := 0
	for raw in cfg.get("gate_cases", []):
		if bool((raw as Dictionary).get("required", false)):
			n += 1
	return n

func _gate(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in cfg.get("gate_cases", []):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

func _code_num(raw: String) -> int:
	var l := raw.find("(")
	var r := raw.find(")")
	if l < 0 or r < 0:
		return -1
	return int(raw.substr(l + 1, r - l - 1))

func _run(cfg: Dictionary, answers: Dictionary) -> Dictionary:
	return Ch08.run(str(cfg.get("id", "")), cfg, {"answers": answers})

func _with(good: Dictionary, cid: String, value: Variant) -> Dictionary:
	var out := good.duplicate(true)
	out[cid] = value
	return out

func _report_of(result: Variant) -> GateReport:
	if result is Dictionary:
		return (result as Dictionary).get("report")
	return result

func _case_ok(result: Variant, cid: String) -> bool:
	var report := _report_of(result)
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return bool(c.get("ok", false))
	return false

func _case_code(result: Variant, cid: String) -> int:
	var report := _report_of(result)
	for c in report.cases:
		if str(c.get("id", "")) == cid:
			return int(c.get("code", GateResult.E_GENERIC))
	return GateResult.E_GENERIC
