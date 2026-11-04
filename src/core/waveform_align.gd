class_name WaveformAlign
extends RefCounted

## CH05 5.1（波形对齐）扩 kind：`waveform_align`。这是扩 kind，不是新失败码。
## 依据 `docs/curriculum/17-ch05-06-lecture-copy.md` §1 判定口径 A：
## 终值、四阶段起止拍、逐拍拍号三样同时成立才算过；「填表式提交」直接拒。
## 失败统一落 `E_OUTPUT_MISMATCH`(10)，`detail` 以「终值 / 阶段 / 拍号」分项，并指到具体阶段与拍号。
##
## 输入：
##   cfg     `.waveform`（逐拍 history：[{"tick", "waves": {信号: 值}}]）
##           `.stage_signals`（四阶段 → 该阶段生效的判据信号，缺省用阶段同名信号）
##           `.final_signal`（终值取波形最后一拍的该信号）
##   answers 玩家标注：`final_value`（终值）、`spans`（起止拍）、`beats`（逐拍拍号）

const KIND := "waveform_align"
const STAGES := ["fetch", "decode", "execute", "writeback"]

## 只从波形历史推导答案，不读玩家任何输入。UI 也可用它画参考标注。
static func expected(cfg: Dictionary) -> Dictionary:
	var hist: Array = cfg.get("waveform", [])
	var sigs: Dictionary = cfg.get("stage_signals", {})
	var beats := {}
	for i in hist.size():
		var row: Dictionary = hist[i]
		var tick := int(row.get("tick", i))
		var waves: Dictionary = row.get("waves", {})
		var label := ""
		# 一拍只允许一个阶段生效；多信号同时为真时按 STAGES 顺序取第一个。
		for s in STAGES:
			if _truthy(waves.get(str(sigs.get(s, s)), 0)):
				label = s
				break
		beats[tick] = label
	var spans := {}
	for s in STAGES:
		var first := -1
		var last := -1
		for raw in beats:
			if str(beats[raw]) != s:
				continue
			var t := int(raw)
			if first < 0 or t < first:
				first = t
			if last < 0 or t > last:
				last = t
		# LDI 的「执行」可以为空：空段的期望起止拍是 -1/-1。
		spans[s] = {"start": first, "end": last}
	var last_tick := -1
	var final_value: Variant = null
	if not hist.is_empty():
		var last_row: Dictionary = hist[hist.size() - 1]
		last_tick = int(last_row.get("tick", hist.size() - 1))
		var fsig := str(cfg.get("final_signal", ""))
		if not fsig.is_empty():
			final_value = (last_row.get("waves", {}) as Dictionary).get(fsig, null)
	return {"stages": spans, "beats": beats, "final_value": final_value, "last_tick": last_tick}

## 校验玩家标注，返回 `{ok, code, input, expected, actual, detail, failures}`。
## 三样都查完再汇总（不 first-fail 短路），`failures` 逐项给出位置。
static func verify(cfg: Dictionary, answers: Dictionary) -> Dictionary:
	var model := expected(cfg)
	var failures := []
	if not _is_annotation(answers):
		failures.append(_failure("填表", "", int(model["last_tick"]),
			"终值 + 起止拍 + 逐拍拍号", answers.duplicate(true),
			"只有阶段顺序，填表不算"))
		return _result(failures, answers, model)
	var got_value: Variant = answers.get("final_value", null)
	if not _same_value(got_value, model["final_value"]):
		failures.append(_failure("终值", "", int(model["last_tick"]),
			model["final_value"], got_value,
			"终值 %s=%s ≠ 波形 %s" % [str(cfg.get("final_signal", "")),
				_s(got_value), _s(model["final_value"])]))
	var got_spans: Dictionary = answers.get("spans", {}) if answers.get("spans", {}) is Dictionary else {}
	for s in STAGES:
		var exp_span: Dictionary = model["stages"][s]
		var got: Dictionary = got_spans.get(s, {}) if got_spans.get(s, {}) is Dictionary else {}
		var g_start := int(got.get("start", -1))
		var g_end := int(got.get("end", -1))
		if g_start != int(exp_span["start"]) or g_end != int(exp_span["end"]):
			failures.append(_failure("阶段", s, g_start,
				"%d-%d" % [int(exp_span["start"]), int(exp_span["end"])],
				"%d-%d" % [g_start, g_end],
				"阶段 %s 起止拍 %d-%d ≠ 波形 %d-%d" % [s, g_start, g_end,
					int(exp_span["start"]), int(exp_span["end"])]))
	var got_beats: Dictionary = answers.get("beats", {}) if answers.get("beats", {}) is Dictionary else {}
	for raw in model["beats"]:
		var t := int(raw)
		var want := str(model["beats"][raw])
		var have := str(got_beats.get(t, "")) if got_beats.has(t) else ""
		if have != want:
			failures.append(_failure("拍号", want, t, want, have,
				"拍号 tick %d 标成 %s ≠ 波形 %s" % [t, have if not have.is_empty() else "（空）", want]))
	return _result(failures, answers, model)

static func _failure(item: String, stage: String, tick: int, expected: Variant, actual: Variant, detail: String) -> Dictionary:
	return {"item": item, "stage": stage, "tick": tick,
		"expected": expected, "actual": actual, "detail": detail}

static func _result(failures: Array, answers: Dictionary, model: Dictionary) -> Dictionary:
	var ok := failures.is_empty()
	var details := PackedStringArray()
	for f in failures:
		details.append(str(f["detail"]))
	return {
		"ok": ok,
		"code": GateResult.OK if ok else GateResult.E_OUTPUT_MISMATCH,
		"input": answers.duplicate(true),
		"expected": {"final_value": model["final_value"], "stages": model["stages"], "beats": model["beats"]},
		"actual": {"final_value": answers.get("final_value", null),
			"stages": answers.get("spans", {}), "beats": answers.get("beats", {})},
		"detail": "；".join(details),
		"failures": failures,
	}

static func _is_annotation(answers: Dictionary) -> bool:
	## 填表式提交只有阶段顺序（`order`/`stages` 列表），没有起止拍、终值、逐拍拍号。
	return answers.has("final_value") or answers.has("spans") or answers.has("beats")

static func _truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return bool(v)
		TYPE_INT:
			return int(v) != 0
		TYPE_FLOAT:
			return float(v) != 0.0
		TYPE_STRING:
			return not str(v).is_empty() and str(v) != "0"
		_:
			return false

static func _same_value(a: Variant, b: Variant) -> bool:
	if a == null or b == null:
		return a == null and b == null
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return absf(float(a) - float(b)) <= 0.000001
	return a == b

static func _s(v: Variant) -> String:
	return "（缺）" if v == null else str(v)
