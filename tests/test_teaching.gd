extends RefCounted

## 教学字段接通验收：用真实 data/labs/ch01_labs.json 断言「写进去的文案确实会被渲染」。
## 渲染路径：LabBase._add_teaching → teaching_text；_apply_hint → hint_for_attempt；误区 → misconception_on_report。

const Teach = preload("res://src/ui/teaching.gd")
const LabBaseGd = preload("res://src/ui/screens/lab_base.gd")
const LABS := ["level", "binary", "boolean", "gate", "signal", "half_adder"]

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 50
const EXPECT_GROUPS := {
	"teaching_nonempty": 6, "rules_in_body": 4, "legacy_no_sections": 4, "gate_body": 5, "hint_ladder": 9,
	"hint_sentences": 15, "misconception": 4, "misconception_codes": 2,
	"optional_no_misconception": 1,
}
const GROUP_DESCRIPTIONS := {
	"teaching_nonempty": "六个 lab 的教学正文都非空（rules 也走同一通道）",
	"rules_in_body": "level.rules 存在且逐行进入正文",
	"legacy_no_sections": "没有 sections 的老数据真的走兜底：section_list 合成单段、fallback_note 出 rules；有 sections 时仍短路",
	"gate_body": "gate.body 非空、进正文、长度 ≥20，并出现在讲解位实际文本里",
	"hint_ladder": "attempt=0 无提示、1 出 L1、1 不得等于 L3",
	"hint_sentences": "attempt=2 不短于 L1、attempt=3 为全文、hint 可切 ≥2 句且 L1/L2 各取半",
	"misconception": "成功不出误区；required 失败且错因匹配时出数据里那一条、单行显示",
	"misconception_codes": "E_TARGET_UNREACHED / E_ENCAPSULATION 两种失败码都出同一条误区",
	"optional_no_misconception": "optional 失败不算错因、不出误区",
}

func run(ctx: TestContext) -> void:
	var db := TestUtil.data_db()
	var cfg := {}
	for id in LABS:
		cfg[id] = db.lab_data(id)

	# ---- 教学层：六个 lab 正文区都非空（rules 也走同一通道）----
	for id in LABS:
		ctx.begin_group("teaching_nonempty")
		ctx.check("教学层 %s 正文非空" % id, Teach.has_teaching(cfg[id]), Teach.teaching_text(cfg[id]))

	# ---- rules 逐行进正文（1.1 是唯一带 rules 的 lab）----
	var lv: Dictionary = cfg["level"]
	var tt := Teach.teaching_text(lv)
	var rules: Array = lv.get("rules", [])
	ctx.begin_group("rules_in_body")
	ctx.check("level.rules 存在", rules.size() > 0, str(rules.size()))
	for i in rules.size():
		ctx.check("level.rules[%d] 进入正文" % i, tt.contains(str(rules[i])), str(rules[i]))

	# ---- 老数据兜底：没有 sections 时必须真的走到 fallback_note，而不是永远短路 ----
	var legacy := {"id": "legacy", "body": "兜底正文", "rules": ["规则甲", "规则乙"]}
	var legacy_secs := Teach.section_list(legacy)
	var legacy_note := Teach.fallback_note(legacy)
	ctx.begin_group("legacy_no_sections")
	ctx.check("无 sections 时 section_list 兜底成单段", legacy_secs.size() == 1, str(legacy_secs.size()))
	ctx.check("兜底段落包含 body 与 rules", str((legacy_secs[0] as Dictionary).get("text", "")).contains("兜底正文")
		and str((legacy_secs[0] as Dictionary).get("text", "")).contains("规则乙"),
		str(legacy_secs[0]))
	ctx.check("无 sections 时 fallback_note 出 rules", not legacy_note.is_empty() and legacy_note == Teach.rules_note(legacy), legacy_note)
	ctx.check("有 sections 时 fallback_note 仍短路为空", Teach.fallback_note(lv).is_empty())

	# ---- gate.body：1.4 此前整段不显示，现在必须进正文且来自数据字段 ----
	var gt: Dictionary = cfg["gate"]
	var gbody := str(gt.get("body", ""))
	ctx.begin_group("gate_body")
	ctx.check("gate.body 非空", gbody.length() > 0, str(gbody.length()))
	ctx.check("gate 正文取自 gate.body", Teach.teaching_text(gt).contains(gbody), gbody)
	ctx.check("gate.body 长度 ≥ 20", gbody.length() >= 20, str(gbody.length()))
	# 讲解位实际文本（_add_teaching 写入 Label 的同一函数）：非空且含 gate.body。
	var g_rendered: String = LabBaseGd._flow(Teach.teaching_text(gt), 36)
	ctx.check("gate 讲解位文本非空", g_rendered.length() > 0, str(g_rendered.length()))
	ctx.check("gate 讲解位含 gate.body", LabBaseGd.flat_text(g_rendered).contains(LabBaseGd.flat_text(gbody)), gbody)

	# ---- 提示阶梯：attempt 0 不显示；1→L1；2→L2；3→全文；L1 不得等于 L3 ----
	for id in ["binary", "gate", "signal"]:
		var c: Dictionary = cfg[id]
		var l1 := Teach.hint_for_attempt(c, 1)
		var l2 := Teach.hint_for_attempt(c, 2)
		var l3 := Teach.hint_for_attempt(c, 3)
		var full := str(c.get("hint", "")).strip_edges()
		ctx.begin_group("hint_ladder")
		ctx.check("%s attempt=0 无提示" % id, Teach.hint_for_attempt(c, 0).is_empty())
		ctx.check("%s attempt=1 有 L1" % id, not l1.is_empty(), l1)
		ctx.check("%s attempt=1 不出现 L3" % id, l1 != l3, "L1=%s" % l1)
		ctx.begin_group("hint_sentences")
		ctx.check("%s attempt=2 不短于 L1" % id, l2.length() >= l1.length(), "L2=%d/L1=%d" % [l2.length(), l1.length()])
		ctx.check("%s attempt=3 为全文" % id, l3 == full, l3)
		# 真实数据每条 hint 均为两句：attempt=1 只能等于首句；attempt=2 必须带上第二句。
		var segs := Teach.hint_sentences(c)
		ctx.check("%s hint 可分级（≥2 句）" % id, segs.size() >= 2, str(segs.size()))
		ctx.check("%s attempt=1 只出首句 L1" % id, l1 == str(segs[0]), l1)
		ctx.check("%s attempt=2 含第二句 L2" % id, l2.contains(str(segs[1])), l2)

	# ---- 误区层：成功为空；required 失败且错因匹配（本 lab 的 code）才出 1 条 ----
	var d: Dictionary = cfg["gate"]
	var ok_rep := GateReport.new()
	ok_rep.add("T1.4-1", "ok", true, "")
	ctx.begin_group("misconception")
	ctx.check("成功时误区为空", Teach.misconception_on_report(d, ok_rep).is_empty())
	var fail_rep := GateReport.new()
	fail_rep.add_case(GateResult.E_GENERIC, "T1.4-1", "fail", null, null, null, [], "未通过", true, 1)
	var mis := Teach.misconception_on_report(d, fail_rep)
	ctx.check("T1.4-1 失败时出误区", not mis.is_empty(), mis)
	ctx.check("误区文案取自 misconception", mis == str(d.get("misconception", "")).strip_edges(), mis)
	ctx.check("误区单条显示（不含换行）", not mis.contains("\n"), mis)
	# 特定失败 code：目标未达成 / 未封装，都要出本 lab 对应那一条误区。
	for code in [GateResult.E_TARGET_UNREACHED, GateResult.E_ENCAPSULATION]:
		var rep := GateReport.new()
		rep.add_case(int(code), "T1.4-x", "fail", null, null, null, [], "未通过", true, 2)
		ctx.begin_group("misconception_codes")
		ctx.check("失败 code %d 出对应误区" % int(code),
			Teach.misconception_on_report(d, rep) == mis, str(code))
	# optional 失败不算错因，不出误区。
	var opt_rep := GateReport.new()
	opt_rep.add_case(GateResult.E_TARGET_UNREACHED, "T1.4-opt", "fail", null, null, null, [], "未通过", false, 1)
	ctx.begin_group("optional_no_misconception")
	ctx.check("optional 失败不出误区", Teach.misconception_on_report(d, opt_rep).is_empty())
