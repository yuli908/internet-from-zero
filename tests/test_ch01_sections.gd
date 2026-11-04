extends RefCounted

## CH01 六节 sections 数据落地校验（结构断言，不写死字数——文案会继续改）。
## 口径：order 为 lab 内从 1 起；after = 已完成 required gate 数；
## 每节最后一段必须落在 after = required gate 数 − 1；body 保留为兜底路径。
## 字数口径：去半角空格后的字符数；单段 ≤260，同一 after 档同屏合计 ≤260。

const LABS := ["level", "binary", "boolean", "gate", "signal", "half_adder"]
const TOTAL_SECTIONS := 33

const Teach = preload("res://src/ui/teaching.gd")

func run(ctx: TestContext) -> void:
	var db := TestUtil.data_db()
	ctx.check("数据层 loader 无错误", db.errors.is_empty(), str(db.errors))
	var labs_doc := TestUtil.labs_doc()
	var chapter_doc := TestUtil.chapter_doc()
	var req_by_lab := _required_by_lab(ctx, chapter_doc, labs_doc)

	var total := 0
	for id in LABS:
		var cfg: Dictionary = db.lab_data(str(id))
		var secs: Array = cfg.get("sections", [])
		var req: int = int(req_by_lab.get(id, -1))
		ctx.check("%s 有 sections" % id, not secs.is_empty(), str(secs.size()))
		var max_after := -1
		var prev_after := -1
		var screen := {}
		for i in secs.size():
			var s: Dictionary = secs[i]
			var order := int(s.get("order", -1))
			var after := int(s.get("after", -1))
			var text := str(s.get("text", ""))
			var text_len := text.replace(" ", "").length()
			ctx.eq("%s[%d] order 连续" % [id, i + 1], order, i + 1)
			if i == 0:
				ctx.eq("%s 首段 after=0" % id, after, 0)
			else:
				ctx.check("%s[%d] after 单调不减" % [id, i + 1], after >= prev_after,
					"%d < %d" % [after, prev_after])
			ctx.check("%s[%d] after ≤ required−1" % [id, i + 1], after <= req - 1,
				"after=%d required=%d" % [after, req])
			ctx.check("%s[%d] text 非空" % [id, i + 1], not text.strip_edges().is_empty())
			ctx.check("%s[%d] text ≤260 字" % [id, i + 1], text_len <= 260, str(text_len))
			screen[after] = int(screen.get(after, 0)) + text_len
			max_after = maxi(max_after, after)
			prev_after = after
		total += secs.size()
		var last_after := int((secs[secs.size() - 1] as Dictionary).get("after", -1))
		ctx.check("%s 末段/最大 after = required−1" % id,
			last_after == req - 1 and max_after == req - 1,
			"last=%d max=%d required=%d" % [last_after, max_after, req])
		# 同屏约束：同一 after 档一次显示的全部段落合计 ≤260。
		for after in screen.keys():
			ctx.check("%s after=%d 同屏合计 ≤260" % [id, int(after)],
				int(screen[after]) <= 260, str(screen[after]))
		_fallback_check(ctx, str(id), cfg)
	ctx.eq("全文段数", total, TOTAL_SECTIONS)

## required gate 数：章节 gate_ids 与 labs gate_cases 里 required=true 的条数必须一致。
func _required_by_lab(ctx: TestContext, chapter_doc: Dictionary, labs_doc: Dictionary) -> Dictionary:
	var out := {}
	var labs: Dictionary = labs_doc.get("labs", {})
	for raw in chapter_doc.get("labs", []):
		var lab: Dictionary = raw
		var key := str(lab.get("data_key", ""))
		var gate_ids: Array = lab.get("gate_ids", [])
		var cfg: Dictionary = labs.get(key, {})
		var req := 0
		for raw_case in cfg.get("gate_cases", []):
			if bool((raw_case as Dictionary).get("required", false)):
				req += 1
		ctx.eq("%s required gate 数与章节对齐" % key, req, gate_ids.size())
		out[key] = req
	return out

## 反向验证：删掉 sections 的副本仍能退回 body（老数据兜底路径不断）。
func _fallback_check(ctx: TestContext, id: String, cfg: Dictionary) -> void:
	var copy: Dictionary = JSON.parse_string(JSON.stringify(cfg))
	copy.erase("sections")
	var body := str(copy.get("body", "")).strip_edges()
	ctx.check("%s 无 sections 时 body 非空" % id, not body.is_empty(), body)
	ctx.check("%s 无 sections 时退回 body" % id, Teach.has_teaching(copy), Teach.teaching_text(copy))
