extends RefCounted

## CH06 六节（30 段）结构 + P1 判据校验。
## 分母口径：required 且非 pending 的 gate 数，按数据现算（6.5/6.6 各有一条阈值 pending，降为 3）。
## 所有判据断言都给反例：断言必须能红，不是恒真。

const LABS := ["charset", "keyboard", "sound", "loader", "cache", "vm"]
const SECTION_COUNTS := {"charset": 5, "keyboard": 5, "sound": 5, "loader": 5, "cache": 5, "vm": 5}
const TOTAL_SECTIONS := 30
const LEFT_LIMIT := 150
const SCREEN_LIMIT := 260

const Ch06 = preload("res://src/core/ch06_checks.gd")
const Teach = preload("res://src/ui/teaching.gd")

const EXPECT := 307
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 6, "section_count": 6, "total_sections": 1,
	"order": 30, "after_unlock": 30, "after_bound": 30, "text_nonempty": 30, "text_cap": 30,
	"screen_sum": 24, "last_after": 6, "after_required": 6, "fallback": 12,
	"denominator": 6, "gate_ids": 6, "gate_count": 6, "required_count": 6, "gate_codes": 6,
	"practice": 12, "p1_field": 6, "pending_declared": 4,
	"judge_charset": 8, "judge_keyboard": 8, "judge_sound": 7, "judge_loader": 7,
	"judge_cache": 6, "judge_vm": 7,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch06_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 段数为 5",
	"total_sections": "全篇段数 30",
	"order": "每 lab 内 order 连续",
	"after_unlock": "首段 after=0、其余单调不减",
	"after_bound": "每段 after ≤ required−1",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（左栏口径，去半角空格）",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"last_after": "末段 after = required−1",
	"after_required": "最大 after 落在 required−1",
	"fallback": "删掉 sections 的副本退回 body",
	"denominator": "进分母 gate 数按 required 去 pending 现算（6.5/6.6=3）",
	"gate_ids": "gate id 按 T6.x-n 顺序且与课文提案一致",
	"gate_count": "每节 4 条 gate",
	"required_count": "每节 required gate 数为 4",
	"gate_codes": "gate 失败码只用白名单 3/5/7/8/9/10/13/14/15/27",
	"practice": "每节有实践表且每行 id/level/produce/judge 齐全",
	"p1_field": "每节有 P1 文本与 p1_gates",
	"pending_declared": "6.5/6.6 的阈值 gate 均带 pending_reason 且未拍数值",
	"judge_charset": "6.1 P1：字节/字符/往返/区间判绿与反例",
	"judge_keyboard": "6.2 P1：两版键码/中断拍数/现场/漏键判绿与反例",
	"judge_sound": "6.3 P1：三音频率/2N 周期/等比音阶判绿与反例",
	"judge_loader": "6.4 P1：装入/重载/校验/首地址判绿与反例",
	"judge_cache": "6.5 P1：两组跑满/对齐/平均访问判绿与反例；阈值项为 pending",
	"judge_vm": "6.6 P1：全写全读回/页表项/容量判绿与反例；曲线项为 pending",
}

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch06_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch06_labs 可读", not labs.is_empty(), str(labs.size()))

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
		_contract(ctx, id, cfg, labs)
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

	_judge_charset(ctx, labs.get("charset", {}))
	_judge_keyboard(ctx, labs.get("keyboard", {}))
	_judge_sound(ctx, labs.get("sound", {}))
	_judge_loader(ctx, labs.get("loader", {}))
	_judge_cache(ctx, labs.get("cache", {}))
	_judge_vm(ctx, labs.get("vm", {}))

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

func _contract(ctx: TestContext, id: String, cfg: Dictionary, labs: Dictionary) -> void:
	var req := _required_count(cfg)
	var cases: Array = cfg.get("gate_cases", [])
	var d: Dictionary = Ch06.deferred_gates(cfg)
	var expect_counted := req
	for raw in cases:
		if bool((raw as Dictionary).get("required", false)) \
				and Ch06.PENDING_REASONS.has(str((raw as Dictionary).get("kind", ""))):
			expect_counted -= 1
	ctx.begin_group("denominator")
	ctx.eq("%s 进分母 gate 数" % id, int(d["counted"]), expect_counted)
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
	if id == "cache" or id == "vm":
		var pc := _gate(cfg, "T6.5-2" if id == "cache" else "T6.6-2")
		ctx.begin_group("pending_declared")
		ctx.check("%s 阈值 gate status=pending 且有 rationale" % id,
			str(pc.get("status", "")) == "pending" and not str(pc.get("pending_reason", "")).strip_edges().is_empty(),
			str(pc.get("pending_reason", "")))
		var th: Dictionary = pc.get("thresholds", {})
		ctx.check("%s 阈值未拍数值（全为 null 或标 pending）" % id, _thresholds_unset(th),
			str(th))

func _ids_ok(id: String, ids: Array) -> bool:
	var prefix := ""
	match id:
		"charset": prefix = "T6.1-"
		"keyboard": prefix = "T6.2-"
		"sound": prefix = "T6.3-"
		"loader": prefix = "T6.4-"
		"cache": prefix = "T6.5-"
		"vm": prefix = "T6.6-"
	if ids.size() != 4:
		return false
	for i in 4:
		if str(ids[i]) != "%s%d" % [prefix, i + 1]:
			return false
	return true

func _thresholds_unset(th: Dictionary) -> bool:
	for key in th.keys():
		var raw: Variant = th[key]
		if raw == null:
			continue
		if raw is Dictionary:
			if (raw as Dictionary).get("initial", 0) != null and str((raw as Dictionary).get("status", "")) != "pending":
				return false
			continue
		return false
	return true

func _required_count(cfg: Dictionary) -> int:
	var req := 0
	for raw in cfg.get("gate_cases", []):
		if bool((raw as Dictionary).get("required", false)):
			req += 1
	return req

func _gate(cfg: Dictionary, cid: String) -> Dictionary:
	for raw in cfg.get("gate_cases", []):
		if str((raw as Dictionary).get("id", "")) == cid:
			return raw
	return {}

func _run(cfg: Dictionary, answers: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var inputs := {"answers": answers}
	for k in extra:
		inputs[k] = extra[k]
	return Ch06.run(str(cfg.get("id", "")), cfg, inputs)

func _codes(rep: GateReport) -> Array:
	## 只取 required 失败码：6.5/6.6 各有一条 pending gate（E_PENDING，required=false），
	## 它是「暂不判定」标记而不是玩家失败，混进来会把真正的首条失败码顶掉。
	var out := []
	for c in rep.cases:
		if not bool(c.get("ok", false)) and bool(c.get("required", true)):
			out.append(int(c.get("code", GateResult.E_GENERIC)))
	return out

## 白名单口径：一条码必须是完整的 `E_NAME(n)`，名字与 `GateResult` 注册名一致。
func _code_num(s: String) -> int:
	var re := RegEx.new()
	re.compile(r"^E_[A-Z_]+\((\d+)\)$")
	var m := re.search(s)
	if m == null:
		return -1
	var num := int(m.get_string(1))
	if s.get_slice("(", 0) != GateResult.name_of(num):
		return -1
	return num

# ---------------------------------------------------------------- 6.1

func _judge_charset(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T6.1-1": {"bytes": 9, "chars": 9, "roundtrip": "hi, human"},
		"T6.1-2": {"bytes": 6, "chars": 2, "roundtrip": "你好", "prefix_ok": true},
		"T6.1-3": {"lo": 32, "hi": 126},
		"T6.1-4": 0,
	}
	ctx.begin_group("judge_charset")
	ctx.check("6.1 往返一致判绿", bool(_run(cfg, good)["ok"]))
	var wrong_bytes: Dictionary = good.duplicate(true)
	wrong_bytes["T6.1-1"] = {"bytes": 8, "chars": 9, "roundtrip": "hi, human"}
	var r1 := _run(cfg, wrong_bytes)
	ctx.check("6.1 字节数错判红", not bool(r1["ok"]))
	ctx.eq("6.1 字节数错落 10", _codes(r1["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var no_prefix: Dictionary = good.duplicate(true)
	no_prefix["T6.1-2"] = {"bytes": 6, "chars": 2, "roundtrip": "你好", "prefix_ok": false}
	var r2 := _run(cfg, no_prefix)
	ctx.check("6.1 不读长度前缀判红", not bool(r2["ok"]))
	ctx.eq("6.1 长度前缀错落 10", _codes(r2["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var bad_range: Dictionary = good.duplicate(true)
	bad_range["T6.1-3"] = {"lo": 0, "hi": 127}
	ctx.eq("6.1 区间错落 7", _codes(_run(cfg, bad_range)["report"])[0], GateResult.E_TABLE_CELL)
	var quiz: Dictionary = good.duplicate(true)
	quiz["T6.1-4"] = 1
	ctx.eq("6.1 quiz 错落 14", _codes(_run(cfg, quiz)["report"])[0], GateResult.E_QUIZ)
	var unwired: Dictionary = good.duplicate(true)
	unwired["T6.1-1"] = {"chars": 9, "roundtrip": "hi, human"}
	ctx.eq("6.1 未接线落 3", _codes(_run(cfg, unwired)["report"])[0], GateResult.E_UNCONNECTED)

# ---------------------------------------------------------------- 6.2

func _judge_keyboard(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T6.2-1": {"poll_keycode": 65, "int_keycode": 65, "int_ticks": 1, "poll_ticks": 7},
		"T6.2-2": {"saved_pc": true, "saved_regs": true, "return_pc": 3, "second_keycode": 65},
		"T6.2-3": {"pressed": 2, "handled": 2, "handled_keycodes": [65, 65]},
		"T6.2-4": 0,
	}
	ctx.begin_group("judge_keyboard")
	ctx.check("6.2 两版都判绿", bool(_run(cfg, good, {"trace": {"return_pc": 3}})["ok"]))
	var bad_key: Dictionary = good.duplicate(true)
	bad_key["T6.2-1"] = {"poll_keycode": 66, "int_keycode": 66, "int_ticks": 1, "poll_ticks": 7}
	var r1 := _run(cfg, bad_key, {"trace": {"return_pc": 3}})
	ctx.check("6.2 键码错判红", not bool(r1["ok"]))
	ctx.eq("6.2 键码错落 10", _codes(r1["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var slow: Dictionary = good.duplicate(true)
	slow["T6.2-1"] = {"poll_keycode": 65, "int_keycode": 65, "int_ticks": 3, "poll_ticks": 7}
	ctx.eq("6.2 中断响应超拍落 8", _codes(_run(cfg, slow, {"trace": {"return_pc": 3}})["report"])[0],
		GateResult.E_DELAY_EXCEED)
	var no_save: Dictionary = good.duplicate(true)
	no_save["T6.2-2"] = {"saved_pc": false, "saved_regs": false, "return_pc": 3, "second_keycode": 65}
	ctx.eq("6.2 未存现场落 10", _codes(_run(cfg, no_save, {"trace": {"return_pc": 3}})["report"])[0],
		GateResult.E_OUTPUT_MISMATCH)
	var no_trace := _run(cfg, good, {})
	ctx.eq("6.2 缺现场采集落 3", _codes(no_trace["report"])[0], GateResult.E_UNCONNECTED)
	var drop: Dictionary = good.duplicate(true)
	drop["T6.2-3"] = {"pressed": 2, "handled": 1, "handled_keycodes": [65]}
	ctx.eq("6.2 漏键落 13", _codes(_run(cfg, drop, {"trace": {"return_pc": 3}})["report"])[0],
		GateResult.E_COVERAGE)
	var quiz: Dictionary = good.duplicate(true)
	quiz["T6.2-4"] = 1
	ctx.eq("6.2 quiz 错落 14", _codes(_run(cfg, quiz, {"trace": {"return_pc": 3}})["report"])[0],
		GateResult.E_QUIZ)

# ---------------------------------------------------------------- 6.3

func _judge_sound(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T6.3-1": {"freqs": [440, 660, 880]},
		"T6.3-2": {"n": [100, 200, 400], "periods": [200, 400, 800]},
		"T6.3-3": {"step_ratio": 1.059},
		"T6.3-4": 0,
	}
	ctx.begin_group("judge_sound")
	ctx.check("6.3 三音全对判绿", bool(_run(cfg, good)["ok"]))
	var off: Dictionary = good.duplicate(true)
	off["T6.3-1"] = {"freqs": [440, 660, 990]}
	var r1 := _run(cfg, off)
	ctx.check("6.3 频率偏判红", not bool(r1["ok"]))
	ctx.eq("6.3 频率偏落 10", _codes(r1["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var short: Dictionary = good.duplicate(true)
	short["T6.3-1"] = {"freqs": [440, 660]}
	ctx.eq("6.3 只测两音落 13", _codes(_run(cfg, short)["report"])[0], GateResult.E_COVERAGE)
	var bad_ratio: Dictionary = good.duplicate(true)
	bad_ratio["T6.3-2"] = {"n": [100, 200, 400], "periods": [200, 200, 200]}
	ctx.eq("6.3 半周期丢拍落 8", _codes(_run(cfg, bad_ratio)["report"])[0], GateResult.E_DELAY_EXCEED)
	var equal_step: Dictionary = good.duplicate(true)
	## 加常数（440→450）在低音区的实际比值 1.0227，偏离 1.05946 3.4%（>±1% 公差）；
	## 1.07 只差 1.0%，落在公差内，作反例判不红。
	equal_step["T6.3-3"] = {"step_ratio": 1.0227}
	ctx.eq("6.3 等差音阶落 10", _codes(_run(cfg, equal_step)["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var quiz: Dictionary = good.duplicate(true)
	quiz["T6.3-4"] = 1
	ctx.eq("6.3 quiz 错落 14", _codes(_run(cfg, quiz)["report"])[0], GateResult.E_QUIZ)

# ---------------------------------------------------------------- 6.4

func _judge_loader(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T6.4-1": {"out_a": 8, "out_b": 15, "reload_out_a": 8, "reload_out_b": 15},
		"T6.4-2": {"checksum": 42, "result_checksum": 42, "corrupt_rejected": true},
		"T6.4-3": {"start_addr": 16, "length": 8},
		"T6.4-4": 0,
	}
	var tape := {"tape": {"start_addr": 16, "length": 8}}
	ctx.begin_group("judge_loader")
	ctx.check("6.4 装入/重载/校验全对判绿", bool(_run(cfg, good, tape)["ok"]))
	var bad_run: Dictionary = good.duplicate(true)
	bad_run["T6.4-1"] = {"out_a": 7, "out_b": 15, "reload_out_a": 7, "reload_out_b": 15}
	var r1 := _run(cfg, bad_run, tape)
	ctx.check("6.4 装入后输出错判红", not bool(r1["ok"]))
	ctx.eq("6.4 装入错落 10", _codes(r1["report"])[0], GateResult.E_OUTPUT_MISMATCH)
	var dirty: Dictionary = good.duplicate(true)
	dirty["T6.4-2"] = {"checksum": 42, "result_checksum": 42, "corrupt_rejected": false}
	ctx.eq("6.4 坏字节照跑落 10", _codes(_run(cfg, dirty, tape)["report"])[0],
		GateResult.E_OUTPUT_MISMATCH)
	var addr: Dictionary = good.duplicate(true)
	addr["T6.4-3"] = {"start_addr": 15, "length": 8}
	ctx.eq("6.4 首地址错落 5", _codes(_run(cfg, addr, tape)["report"])[0], GateResult.E_UNKNOWN_TARGET)
	var no_tape := _run(cfg, good, {})
	ctx.eq("6.4 缺磁带表头落 3", _codes(no_tape["report"])[0], GateResult.E_UNCONNECTED)
	var quiz: Dictionary = good.duplicate(true)
	quiz["T6.4-4"] = 2
	ctx.eq("6.4 quiz 错落 14", _codes(_run(cfg, quiz, tape)["report"])[0], GateResult.E_QUIZ)

# ---------------------------------------------------------------- 6.5

func _judge_cache(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T6.5-1": {"runs": [{"step": 1, "completed": 64, "first_addr": 0},
			{"step": 16, "completed": 64, "first_addr": 0}]},
		"T6.5-3": {"avg_ticks": 4.9},
		"T6.5-4": 0,
	}
	var cache := {"cache": {"hit_ticks": 1.0, "miss_ticks": 40.0, "hit_rate": 0.9}}
	ctx.begin_group("judge_cache")
	var pass_rep: Dictionary = _run(cfg, good, cache)
	ctx.check("6.5 可判项全对判绿（阈值项 pending 不影响）", bool(pass_rep["ok"]))
	ctx.eq("6.5 pending 一条（cache_hit_rate）", (pass_rep["pending"] as Array).size(), 1)
	var one_group: Dictionary = good.duplicate(true)
	one_group["T6.5-1"] = {"runs": [{"step": 1, "completed": 64, "first_addr": 0}]}
	ctx.eq("6.5 只跑一组落 13", _codes(_run(cfg, one_group, cache)["report"])[0],
		GateResult.E_COVERAGE)
	var unaligned: Dictionary = good.duplicate(true)
	unaligned["T6.5-1"] = {"runs": [{"step": 1, "completed": 64, "first_addr": 0},
		{"step": 16, "completed": 64, "first_addr": 15}]}
	ctx.eq("6.5 首地址不对齐落 10", _codes(_run(cfg, unaligned, cache)["report"])[0],
		GateResult.E_OUTPUT_MISMATCH)
	var avg: Dictionary = good.duplicate(true)
	avg["T6.5-3"] = {"avg_ticks": 2.0}
	ctx.eq("6.5 平均访问算错落 10", _codes(_run(cfg, avg, cache)["report"])[0],
		GateResult.E_OUTPUT_MISMATCH)
	var quiz: Dictionary = good.duplicate(true)
	quiz["T6.5-4"] = 1
	ctx.eq("6.5 quiz 错落 14", _codes(_run(cfg, quiz, cache)["report"])[0], GateResult.E_QUIZ)

# ---------------------------------------------------------------- 6.6

func _judge_vm(ctx: TestContext, cfg: Dictionary) -> void:
	var good := {
		"T6.6-1": {"written": 1536, "read_back": 1536, "mismatches": 0,
			"pt_entries": [{"page": 0, "frame": 0, "ok": true}, {"page": 1, "frame": 1, "ok": true}]},
		"T6.6-3": {"total_bytes": 1536},
		"T6.6-4": 0,
	}
	var mem := {"memory": {"frames": 16, "page_size": 64, "overcommit": 1.5}}
	ctx.begin_group("judge_vm")
	var pass_rep: Dictionary = _run(cfg, good, mem)
	ctx.check("6.6 可判项全对判绿（曲线项 pending 不影响）", bool(pass_rep["ok"]))
	ctx.eq("6.6 pending 一条（page_swap_curve）", (pass_rep["pending"] as Array).size(), 1)
	var lost: Dictionary = good.duplicate(true)
	lost["T6.6-1"] = {"written": 1536, "read_back": 1535, "mismatches": 1,
		"pt_entries": [{"page": 0, "frame": 0, "ok": true}]}
	ctx.eq("6.6 读回不一致落 10", _codes(_run(cfg, lost, mem)["report"])[0],
		GateResult.E_OUTPUT_MISMATCH)
	var bad_pt: Dictionary = good.duplicate(true)
	bad_pt["T6.6-1"] = {"written": 1536, "read_back": 1536, "mismatches": 0,
		"pt_entries": [{"page": 0, "frame": 0, "ok": true}, {"page": 1, "frame": 2, "ok": false}]}
	ctx.eq("6.6 页表项错落 10", _codes(_run(cfg, bad_pt, mem)["report"])[0],
		GateResult.E_OUTPUT_MISMATCH)
	var no_pt: Dictionary = good.duplicate(true)
	no_pt["T6.6-1"] = {"written": 1536, "read_back": 1536, "mismatches": 0, "pt_entries": []}
	ctx.eq("6.6 页表项未核对落 13", _codes(_run(cfg, no_pt, mem)["report"])[0],
		GateResult.E_COVERAGE)
	var cap: Dictionary = good.duplicate(true)
	cap["T6.6-3"] = {"total_bytes": 1024}
	ctx.eq("6.6 容量换算错落 10", _codes(_run(cfg, cap, mem)["report"])[0],
		GateResult.E_OUTPUT_MISMATCH)
	var quiz: Dictionary = good.duplicate(true)
	quiz["T6.6-4"] = 1
	ctx.eq("6.6 quiz 错落 14", _codes(_run(cfg, quiz, mem)["report"])[0], GateResult.E_QUIZ)
