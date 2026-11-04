extends RefCounted

## CH02 五节 sections（25 段）结构校验。
## 分母口径：**required 且非 pending** 的 gate 数（读数据现算，不写死 4）。
## inverter / replace 各留一个恒 pending 的 static_current，进分母为 3；其余为 4。
## 末段 after 口径：= 名义 required − 1（五节均为 3）。pending 项在段落阶梯上仍占一格、
## 显示为「暂缓」，所以不按「分母 − 1」算；inverter/replace 的 3 同时等于各自分母（可判项全过即显示）。
## 结构断言：order 连续、after 单调不减、每段 ≤150、同 after 档 ≤260、缺 sections 退回 body。

const LABS := ["transistor", "inverter", "nand", "replace", "power"]
const TOTAL_SECTIONS := 25
const LEFT_LIMIT := 150

## 本套件自报期望数：EXPECT = 各组之和，runner 逐组比对实际计数。
const EXPECT := 180
const EXPECT_GROUPS := {
	"loadable": 1, "sections_present": 5, "section_count": 5, "denominator": 5,
	"denominator_lock": 1, "order": 25, "after_unlock": 25, "after_bound": 25,
	"text_nonempty": 25, "text_cap": 25, "last_after": 5, "pending_display": 2,
	"screen_sum": 20, "fallback": 10, "total_sections": 1,
}
const GROUP_DESCRIPTIONS := {
	"loadable": "ch02_labs 数据文件可读",
	"sections_present": "每 lab 必有非空 sections",
	"section_count": "每 lab 恰好 5 段",
	"denominator": "进分母 gate 数 = required − pending（读数据现算）",
	"denominator_lock": "inverter/replace 各因 pending 降为 3，防写死 4",
	"order": "每段 order 在 lab 内连续 1..5",
	"after_unlock": "首段 after=0、其余单调不减",
	"after_bound": "每段 after ≤ required−1",
	"text_nonempty": "每段 text 非空",
	"text_cap": "每段 ≤150 字（左栏口径，去半角空格）",
	"last_after": "末段与最大 after = required−1",
	"pending_display": "含 pending 的节：末段 after = 可判项数",
	"screen_sum": "同一 after 档同屏合计 ≤260",
	"fallback": "删掉 sections 后退回 body",
	"total_sections": "全篇段数 25",
}

const Teach = preload("res://src/ui/teaching.gd")

func run(ctx: TestContext) -> void:
	var cfg_all: Dictionary = TestUtil.read_json("res://data/labs/ch02_labs.json")
	var labs: Dictionary = cfg_all.get("labs", {})
	ctx.begin_group("loadable")
	ctx.check("ch02_labs 可读", not labs.is_empty(), str(labs.size()))

	var total := 0
	for id in LABS:
		var cfg: Dictionary = labs.get(id, {})
		var secs: Array = cfg.get("sections", [])
		var counts := _gate_counts(cfg)
		var req: int = int(counts["req"])
		var denom: int = int(counts["denom"])
		var pending: int = int(counts["pending"])
		ctx.begin_group("sections_present")
		ctx.check("%s 有 sections" % id, not secs.is_empty(), str(secs.size()))
		ctx.begin_group("section_count")
		ctx.eq("%s 段数" % id, secs.size(), 5)
		ctx.begin_group("denominator")
		ctx.eq("%s 进分母 gate 数（required 去 pending）" % id, denom,
			int(counts["req"]) - int(counts["pending"]))
		var max_after := -1
		var prev_after := -1
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
			ctx.check("%s[%d] text ≤150 字（左栏）" % [id, i + 1], text_len <= LEFT_LIMIT, str(text_len))
			screen[after] = int(screen.get(after, 0)) + text_len
			max_after = maxi(max_after, after)
			prev_after = after
		total += secs.size()
		var last_after := int((secs[secs.size() - 1] as Dictionary).get("after", -1))
		ctx.begin_group("last_after")
		ctx.check("%s 末段/最大 after = required−1（分母 %d，pending %d）" % [id, denom, pending],
			last_after == req - 1 and max_after == req - 1,
			"last=%d max=%d required=%d" % [last_after, max_after, req])
		if pending > 0:
			ctx.begin_group("pending_display")
			ctx.check("%s 末段 after = 可判项数（pending 项全过即显示）" % id, last_after == denom,
				"last=%d denom=%d" % [last_after, denom])
		ctx.begin_group("screen_sum")
		for after in screen.keys():
			ctx.check("%s after=%d 同屏合计 ≤260" % [id, int(after)],
				int(screen[after]) <= 260, str(screen[after]))
		ctx.begin_group("fallback")
		_fallback_check(ctx, str(id), cfg)
	ctx.begin_group("total_sections")
	ctx.eq("全文段数", total, TOTAL_SECTIONS)
	# 锁住「分母不是硬编码 4」：至少两节因 pending 被扣到 3。
	var inv := _gate_counts(labs.get("inverter", {}))
	var rep := _gate_counts(labs.get("replace", {}))
	ctx.begin_group("denominator_lock")
	ctx.check("inverter/replace 分母均因 pending 降为 3",
		int(inv["denom"]) == 3 and int(rep["denom"]) == 3 and int(inv["pending"]) == 1
		and int(rep["pending"]) == 1,
		"inverter=%s replace=%s" % [str(inv), str(rep)])

func _gate_counts(cfg: Dictionary) -> Dictionary:
	var req := 0
	var pending := 0
	for raw in cfg.get("gate_cases", []):
		var c: Dictionary = raw
		if not bool(c.get("required", false)):
			continue
		req += 1
		if str(c.get("status", "")) == "pending":
			pending += 1
	return {"req": req, "pending": pending, "denom": req - pending}

## 反向验证：删掉 sections 的副本仍能退回 body。
func _fallback_check(ctx: TestContext, id: String, cfg: Dictionary) -> void:
	var copy: Dictionary = JSON.parse_string(JSON.stringify(cfg))
	copy.erase("sections")
	var body := str(copy.get("body", "")).strip_edges()
	ctx.check("%s 无 sections 时 body 非空" % id, not body.is_empty(), body)
	ctx.check("%s 无 sections 时退回 body" % id, Teach.has_teaching(copy), Teach.teaching_text(copy))
