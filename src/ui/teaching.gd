extends RefCounted

## 教学 / 提示 / 误区三类数据字段的统一读取与分级（UI 与测试共用，保证「渲染的」就是「断言的」）。
##
## 与 53 条删除划清：
##   删的是状态噪音 ——「进行中 / 已完成 / 点击这里 / 按右侧按钮运行」；
##   加的是教学内容 ——「为什么需要进位 / 德摩根为什么成立 / 0.2V 为什么算线性区」。
##   判据：「你现在在哪」→ 视觉；「这件事为什么是这样」→ 文字。
##   每个接入字段都要能回答「它教了什么」，答不上来就是状态噪音，不许接。

## 教学层：正文 + rules 逐行拼接，常驻正文区（左栏讲解位 / 画布下方讲解带）。
static func teaching_text(cfg: Dictionary) -> String:
	var parts: Array = []
	var body := str(cfg.get("body", "")).strip_edges()
	if not body.is_empty():
		parts.append(body)
	var rules: Variant = cfg.get("rules", [])
	if rules is Array:
		for raw in rules:
			var line := str(raw).strip_edges()
			if not line.is_empty():
				parts.append(line)
	return "\n".join(PackedStringArray(parts))

static func has_teaching(cfg: Dictionary) -> bool:
	return not teaching_text(cfg).is_empty()

## 提示层：把单条 hint 按句读切成阶梯（。；;!? 为界），逐级累积。
## 数据侧若只给两句，则 L1 = 第一句、L2/L3 = 全文——文案粒度由数据侧后续补齐，这里只负责分级显示。
static func hint_sentences(cfg: Dictionary) -> Array:
	var raw := str(cfg.get("hint", "")).strip_edges()
	var out: Array = []
	if raw.is_empty():
		return out
	var buf := ""
	for i in raw.length():
		var ch := raw[i]
		buf += ch
		if ch in ["。", "；", ";", "！", "!", "？", "?"]:
			var seg := buf.strip_edges()
			if not seg.is_empty():
				out.append(seg)
			buf = ""
	var tail := buf.strip_edges()
	if not tail.is_empty():
		out.append(tail)
	return out

## attempt <= 0（还没跑过）不出提示；1 出 L1、2 出 L2、>=3 出 L3（不足三级时用全文兜底）。
static func hint_for_attempt(cfg: Dictionary, attempt: int) -> String:
	if attempt <= 0:
		return ""
	var segs := hint_sentences(cfg)
	if segs.is_empty():
		return ""
	var take := mini(clampi(attempt, 1, 3), segs.size())
	return "".join(PackedStringArray(segs.slice(0, take)))

## 误区层：只在 required 用例失败时出 1 条（成功不显示）。
## 每个 lab 只有一条 misconception，错因匹配 = 该 lab 本轮存在 required 失败。
static func misconception_text(cfg: Dictionary) -> String:
	return str(cfg.get("misconception", "")).strip_edges()

static func misconception_on_report(cfg: Dictionary, report: GateReport) -> String:
	if report == null:
		return ""
	for raw in report.cases:
		var c: Dictionary = raw
		if not bool(c.get("ok", false)) and bool(c.get("required", true)):
			return misconception_text(cfg)
	return ""

## 分段课文：sections = [{order, after, title, text}]，按 order 升序。
## 缺失 sections 时退回 body(+rules) 单段，老数据不炸。
static func section_list(cfg: Dictionary) -> Array:
	var raw: Variant = cfg.get("sections", [])
	var out: Array = []
	if raw is Array:
		for item in raw:
			if not item is Dictionary:
				continue
			var d: Dictionary = item
			var text := str(d.get("text", "")).strip_edges()
			if text.is_empty():
				continue
			out.append({
				"order": int(d.get("order", out.size() + 1)),
				"after": maxi(0, int(d.get("after", 0))),
				"title": str(d.get("title", "")).strip_edges(),
				"text": text,
			})
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a["order"]) < int(b["order"]))
	if out.is_empty():
		var body := teaching_text(cfg)
		if not body.is_empty():
			out.append({"order": 1, "after": 0, "title": "", "text": body})
	return out

static func has_sections(cfg: Dictionary) -> bool:
	var raw: Variant = cfg.get("sections", [])
	return raw is Array and not (raw as Array).is_empty()

## rules 是阈值速查表。有 sections 时一律不渲染（正文已讲同一件事，避免两处重复）；
## 只有 sections 缺失时才随 body 一起兜底成单段，保证信息不丢。
static func rules_note(cfg: Dictionary) -> String:
	var raw: Variant = cfg.get("rules", [])
	var lines := PackedStringArray()
	if raw is Array:
		for r in raw:
			var s := str(r).strip_edges()
			if not s.is_empty():
				lines.append(s)
	return "\n".join(lines)

## 课文卡附注：唯一定义「rules 何时出现」的地方，UI 与断言共用。
static func fallback_note(cfg: Dictionary) -> String:
	return "" if has_sections(cfg) else rules_note(cfg)

## 已完成 done 个 required gate 时解锁的段数（after ≤ done）。
static func unlocked_count_sections(secs: Array, done: int) -> int:
	var n := 0
	for raw in secs:
		if int((raw as Dictionary).get("after", 0)) <= done:
			n += 1
	return n

## 当前段下标：已解锁段的最后一段；某档无段自然回落到前一档最后一段（空档保护）。
## back 为翻页回看的步数（0 = 最新解锁段）。
static func current_section_index(secs: Array, done: int, back: int = 0) -> int:
	var unlocked := unlocked_count_sections(secs, done)
	return maxi(0, unlocked - 1 - maxi(0, back))

static func current_section(secs: Array, done: int, back: int = 0) -> Dictionary:
	if secs.is_empty():
		return {}
	return secs[current_section_index(secs, done, back)]

## 翻页标签：i/n，n = 已解锁段数（未解锁段不可达，分母随之增长）。
static func pager_label(index: int, unlocked: int) -> String:
	return "%d/%d" % [index + 1, maxi(1, unlocked)]
