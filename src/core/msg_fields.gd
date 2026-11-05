extends RefCounted

## 17.1 消息字段边界（19 §2.7）：四字段 + 超长拒绝，按 §2.3 从左到右首错即止。
##
## 为什么单独成模块：`table` 的逐格比对只能比「填得对不对」，比不了「为什么拒」。
## 若把 `len=65536` 的 `reason` 判成 `too_long`，逐格比对只会报普通填错(7)，看不出
## 「位宽判定被排到上限之后」这个语义错。故由本模块先按公式现算真值，再与提交对照；
## 期望表只做第二道对照，不反过来当判定输入。不新增 kind、不新增失败码。
##
## 判定顺序（§2.3，固定，不可由数据翻转）：
##   type 合法 → len 16 位装得下 → len ≤ 协议上限 → 负载字节数与 len 相符 → ts 24 位装得下。

const E_TABLE_CELL := 7
const E_OUTPUT_MISMATCH := 10

const REASON_ENUM := ["", "too_long", "bad_length", "bad_type", "bad_ts"]

## 单行判定：返回 {accepted, reason, detail}。第一处不满足的条件即返回，不继续往后判。
static func evaluate(row: Dictionary, spec: Dictionary) -> Dictionary:
	var allowed: Array = spec.get("allowed_types", [1, 2, 3])
	var len_max: int = (1 << int(spec.get("len_bits", 16))) - 1
	var ts_max: int = (1 << int(spec.get("ts_bits", 24))) - 1
	var max_payload: int = int(spec.get("max_payload", 256))

	var t_v: Variant = row.get("type", null)
	var type_ok := false
	if _is_num(t_v):
		for a in allowed:
			if _is_num(a) and int(a) == int(t_v):
				type_ok = true
	if not type_ok:
		return _fail("bad_type", "type_not_in_set")
	var ln: int = int(row.get("len", -1))
	if ln < 0 or ln > len_max:
		return _fail("bad_length", "len_out_of_field")
	if ln > max_payload:
		return _fail("too_long", "over_protocol_limit")
	var pb: Variant = _payload_bytes(row)
	if pb == null:
		return _fail("bad_length", "payload_absent")
	if int(pb) != ln:
		return _fail("bad_length", "len_payload_mismatch")
	var ts: int = int(row.get("ts", -1))
	if ts < 0 or ts > ts_max:
		return _fail("bad_ts", "ts_out_of_field")
	return {"accepted": true, "reason": "", "detail": ""}

## 网关级校验（`net_lab_kit.gd::_table` 在逐格比对之前调用）。
static func validate_gate(got: Dictionary, c: Dictionary) -> Dictionary:
	var spec: Dictionary = c.get("fields", {})
	var expect: Array = c.get("expect_rows", [])
	var rows_v: Variant = got.get("rows", [])
	var rows: Array = rows_v if (rows_v is Array) else []

	# 0) 期望表自身先过公式：数据不能一边写「首错即止」一边把 S5 标成 too_long。
	for i in range(expect.size()):
		if not (expect[i] is Dictionary):
			continue
		var er: Dictionary = expect[i]
		var et := evaluate(er, spec)
		if bool(er.get("accepted", false)) != bool(et["accepted"]) \
				or str(er.get("reason", "__missing__")) != str(et["reason"]):
			return _bad(E_TABLE_CELL, {"expect_row": i + 1, "msg": er.get("msg", "")},
				{"accepted": et["accepted"], "reason": et["reason"], "detail": et["detail"]},
				{"accepted": er.get("accepted", null), "reason": er.get("reason", null)},
				"期望表第 %d 行（%s）与边界公式不符：应为 reason=%s（%s），写 reason=%s"
					% [i + 1, str(er.get("msg", "")), str(et["reason"]),
						str(et["detail"]), str(er.get("reason", ""))])

	# 1) 逐行首错即止：accepted/reason 必须等于公式现算值（顺序错会在这里暴露）。
	for i in range(rows.size()):
		if not (rows[i] is Dictionary):
			return _bad(E_TABLE_CELL, {"row": i + 1}, "每行为对象", rows[i],
				"表行格式错：第 %d 行不是对象" % (i + 1))
		var r: Dictionary = rows[i]
		var rt := evaluate(r, spec)
		if bool(r.get("accepted", false)) != bool(rt["accepted"]) \
				or str(r.get("reason", "__missing__")) != str(rt["reason"]):
			return _bad(E_TABLE_CELL,
				{"row": i + 1, "msg": r.get("msg", ""), "type": r.get("type", null),
					"len": r.get("len", null), "ts": r.get("ts", null)},
				{"accepted": rt["accepted"], "reason": rt["reason"], "detail": rt["detail"]},
				{"accepted": r.get("accepted", null), "reason": r.get("reason", null)},
				"第 %d 行（%s）首错即止：应为 accepted=%s reason=%s（%s），写 accepted=%s reason=%s"
					% [i + 1, str(r.get("msg", "")), str(rt["accepted"]), str(rt["reason"]),
						str(rt["detail"]), str(r.get("accepted", null)),
						str(r.get("reason", null))])

	# 2) 四字段逐字段：提交的原始字段必须与期望行一致（不能只对 accepted/reason）。
	var keys: Array = c.get("keys", [])
	for i in range(rows.size()):
		if not (rows[i] is Dictionary) or i >= expect.size():
			continue
		var r2: Dictionary = rows[i]
		var e2: Dictionary = expect[i]
		for raw_key in keys:
			var key := str(raw_key)
			if key == "accepted" or key == "reason" or not e2.has(key):
				continue
			if not _same(r2.get(key, null), e2[key]):
				return _bad(E_TABLE_CELL, {"row": i + 1, "field": key},
					e2[key], r2.get(key, null),
					"第 %d 行字段 %s 与期望不符：应为 %s，交 %s"
						% [i + 1, key, str(e2[key]), str(r2.get(key, null))])

	# 3) 位宽必须按 bit 给出，三项相加与 header_bytes 对得上，负载写作「可变」。
	var fw: Dictionary = (c.get("thresholds", {}) as Dictionary).get("field_width", {})
	if not fw.is_empty():
		var bits: Dictionary = fw.get("bits", {})
		var hb := int(fw.get("header_bytes", 0))
		var sum_bits := int(bits.get("type", 0)) + int(bits.get("len", 0)) + int(bits.get("ts", 0))
		if bits.is_empty() or hb <= 0 or sum_bits != hb * 8:
			return _bad(E_TABLE_CELL, {"field_width": fw},
				"bits 相加 == header_bytes × 8", "%d bit vs %d B" % [sum_bits, hb],
				"位宽与头长对不上：三项相加 %d bit，头 %d B（应为 %d bit）"
					% [sum_bits, hb, hb * 8])
		if not str(fw.get("payload_bits", "")).contains("可变"):
			return _bad(E_TABLE_CELL, {"payload_bits": fw.get("payload_bits", "")},
				"0..256 B 可变", fw.get("payload_bits", null),
				"负载宽度被写死：payload 是变长字段，宽度由 len 现算")

	# 4) meta：五项为真（含 field_width_ok）。
	var meta_v: Variant = got.get("meta", {})
	var meta: Dictionary = meta_v if (meta_v is Dictionary) else {}
	var want_meta: Dictionary = c.get("expect_meta", {})
	for k in want_meta.keys():
		if not meta.has(k) or not _same(meta[k], want_meta[k]):
			return _bad(E_OUTPUT_MISMATCH, {"meta": str(k)}, want_meta[k],
				meta.get(k, null),
				"meta.%s 不符：应为 %s，交 %s" % [str(k), str(want_meta[k]), str(meta.get(k, null))])

	var msg_list: Array = []
	for r in rows:
		msg_list.append(str((r as Dictionary).get("msg", "")))
	return {
		"ok": true,
		"code": E_TABLE_CELL,
		"actual": {
			"rows": rows,
			"meta": meta,
			"reason_enum": REASON_ENUM,
			"reason_count": _reason_count(rows),
			"first_fail_order": ["type", "len_width", "len_limit", "payload_match", "ts_width"],
		},
		"input": {"rows": rows.size(), "msg": msg_list},
		"expected": "S1–S8 逐字段一致；四种拒绝原因按首错即止现算",
		"detail": "8 行边界全对（payload 按字节数比对，reason 由公式现算）",
	}

static func _reason_count(rows: Array) -> Dictionary:
	var out := {}
	for raw in rows:
		if not (raw is Dictionary):
			continue
		var key := str((raw as Dictionary).get("reason", ""))
		out[key] = int(out.get(key, 0)) + 1
	return out

static func _fail(reason: String, detail: String) -> Dictionary:
	return {"accepted": reason.is_empty(), "reason": reason, "detail": detail}

static func _bad(code: int, input: Variant, expected: Variant, actual: Variant,
		detail: String) -> Dictionary:
	return {"ok": false, "code": code, "input": input,
		"expected": expected, "actual": actual, "detail": detail}

static func _payload_bytes(row: Dictionary) -> Variant:
	if row.has("payload_hex"):
		var h := str(row["payload_hex"])
		if h.length() % 2 != 0:
			return null
		if not h.is_empty() and not h.is_valid_hex_number():
			return null
		return h.length() / 2
	if row.has("payload_bytes"):
		return int(row["payload_bytes"])
	return null

static func _is_num(v: Variant) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT

static func _same(a: Variant, b: Variant) -> bool:
	if _is_num(a) and _is_num(b):
		return absf(float(a) - float(b)) <= 1e-9
	if a is Array and b is Array:
		var aa: Array = a
		var bb: Array = b
		if aa.size() != bb.size():
			return false
		for i in range(aa.size()):
			if not _same(aa[i], bb[i]):
				return false
		return true
	if a is Dictionary and b is Dictionary:
		var ad: Dictionary = a
		var bd: Dictionary = b
		if ad.size() != bd.size():
			return false
		for k in ad.keys():
			if not bd.has(k) or not _same(ad[k], bd[k]):
				return false
		return true
	return a == b
