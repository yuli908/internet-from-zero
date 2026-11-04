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
