extends RefCounted

## 18.4 剧本开关与证书结果可指认（提案 19 §2.8）。
##
## 规则（与 docs/design/19-interface-extension-proposal.md §2.8 同文，改一侧必须同步另一侧）：
##   - 表行在既有 `phase/intercepted/rejected/handshake_ms` 之外，必须再交三样可指认证据：
##     `switch`（on/off）、`cert_verify`（bool）、`reason`（拒绝理由）、`chain[]`
##     （逐级 `{node, sig_ok, reason}`）；
##   - 每遍剧本的"应有结果"由 cfg 的 `script.phases.<phase>` 声明：
##     `switch`、`cert_verify`、`expect`（intercepted/rejected/pass）、`reason`、`chain`；
##   - `intercepted/rejected` 两个布尔必须能组合出该遍 `expect`：`rejected`=true 且
##     `intercepted`=false → rejected；反之 → intercepted；两个都 false → pass；两个都 true → 7；
##   - 开关开着（switch=on）却把结果写成 pass，或结果与 `expect` 相反 → 10，detail 点名"剧本要求拒绝"；
##   - 证书校验结果与剧本不符（`cert_verify` 布尔反了、链上 `sig_ok`/`reason` 与剧本不一致）→ 10，detail 点名哪一级；
##   - 开关 off 时结果字段 `intercepted/rejected` 缺失或非布尔 → 7（不许只交开关不交结果）；
##   - 成功时表行整份进 `report.cases[].actual.rows`，下游可逐行读 switch/cert_verify/chain，不是只有 ok:true。

const SWITCHES := ["on", "off"]
const RESULTS := ["intercepted", "rejected", "pass"]

const E_TABLE_CELL := 7
const E_OUTPUT_MISMATCH := 10


static func _fail(code: int, detail: String, expected: Variant,
		actual: Variant) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail,
		"input": actual, "expected": expected, "actual": actual}


static func _row_text(row: Dictionary, key: String) -> String:
	return str(row.get(key, ""))


## 判据入口：rows 为提交的表行，want 为 cfg.script；返回 {ok, code, detail, input, expected, actual}。
static func validate_rows(rows: Array, want: Dictionary) -> Dictionary:
	var phases: Dictionary = want.get("phases", {})
	if phases.is_empty():
		return _fail(E_TABLE_CELL, "gate 配置缺 script.phases",
			"script.phases 非空", "missing")
	var row_key := str(want.get("row_key", "phase"))
	for phase in phases:
		var wp: Dictionary = phases[phase]
		var expect := str(wp.get("expect", ""))
		if not RESULTS.has(expect):
			return _fail(E_TABLE_CELL, "剧本 %s 的 expect=%s 不在 intercepted/rejected/pass"
				% [phase, expect], {"expect": "|".join(RESULTS)}, {"expect": expect})
		var row := _row_for(rows, row_key, phase)
		if row.is_empty():
			return _fail(E_TABLE_CELL, "剧本 %s 缺对应表行（开关与结果必须一起交）" % phase,
				{"phase": phase}, "missing")
		var sw := _row_text(row, "switch")
		if not SWITCHES.has(sw):
			return _fail(E_TABLE_CELL, "第 %s 遍 switch=%s 不在 on/off" % [phase, sw],
				{"switch": "on|off"}, {"switch": sw})
		if sw != str(wp.get("switch", "")):
			return _fail(E_OUTPUT_MISMATCH,
				"第 %s 遍开关状态与剧本不符：交 %s，剧本要 %s"
					% [phase, sw, str(wp.get("switch", ""))],
				{"switch": str(wp.get("switch", ""))}, {"switch": sw})
		var iv: Variant = row.get("intercepted", null)
		var rv: Variant = row.get("rejected", null)
		if typeof(iv) != TYPE_BOOL or typeof(rv) != TYPE_BOOL:
			return _fail(E_TABLE_CELL,
				"开关 %s 时结果为布尔字段 intercepted/rejected 缺失或非布尔（不许留空）" % phase,
				{"intercepted": "bool", "rejected": "bool"},
				{"intercepted": iv, "rejected": rv})
		var result := "pass"
		if bool(rv) and not bool(iv):
			result = "rejected"
		elif bool(iv) and not bool(rv):
			result = "intercepted"
		elif bool(iv) and bool(rv):
			return _fail(E_TABLE_CELL, "第 %s 遍 intercepted 与 rejected 同时为 true（结果不可指认）"
				% phase, {"intercepted": false, "rejected": false},
				{"intercepted": iv, "rejected": rv})
		var res := _row_text(row, "result")
		# 结果必须同时是"下游可读的字符串"和"由两布尔推得的结论"：只交布尔位下游读不出
		# 语义，只交字符串则可能和证据矛盾。缺失/留空 → 7；与组合不符 → 10。
		if res.is_empty() or not RESULTS.has(res):
			return _fail(E_TABLE_CELL,
				"第 %s 遍结果字段 result 缺失、留空或非法（须为 intercepted/rejected/pass）"
					% phase, {"result": "intercepted|rejected|pass"}, {"result": res})
		if res != result:
			return _fail(E_OUTPUT_MISMATCH,
				"第 %s 遍 result=\"%s\" 与 intercepted/rejected 组合（%s）不符"
					% [phase, res, result],
				{"result": result}, {"result": res})
		if result != expect:
			return _fail(E_OUTPUT_MISMATCH,
				"第 %s 遍剧本要求 %s，结果却是 %s（开关开着不能写成通过）"
					% [phase, expect, result],
				{"expect": expect}, {"result": result})
		var cv: Variant = row.get("cert_verify", null)
		if typeof(cv) != TYPE_BOOL:
			return _fail(E_TABLE_CELL, "第 %s 遍 cert_verify 缺失或非布尔" % phase,
				{"cert_verify": "bool"}, {"cert_verify": cv})
		if bool(cv) != bool(wp.get("cert_verify", false)):
			return _fail(E_OUTPUT_MISMATCH,
				"第 %s 遍证书校验结果与剧本不符：交 cert_verify=%s，剧本要 %s"
					% [phase, str(cv), str(wp.get("cert_verify", false))],
				{"cert_verify": bool(wp.get("cert_verify", false))}, {"cert_verify": bool(cv)})
		var reason := _row_text(row, "reason")
		var want_reason := str(wp.get("reason", ""))
		if reason != want_reason:
			return _fail(E_OUTPUT_MISMATCH,
				"第 %s 遍拒绝理由与剧本不符：交 \"%s\"，剧本要 \"%s\""
					% [phase, reason, want_reason],
				{"reason": want_reason}, {"reason": reason})
		var chain_v: Variant = row.get("chain", null)
		if not (chain_v is Array) or (chain_v as Array).is_empty():
			return _fail(E_TABLE_CELL, "第 %s 遍证书链缺失（拒绝原因必须能落到具体一级）"
				% phase, {"chain": "非空数组"}, {"chain": chain_v})
		var chain: Array = chain_v
		var want_chain: Array = wp.get("chain", [])
		if chain.size() != want_chain.size():
			return _fail(E_OUTPUT_MISMATCH, "第 %s 遍证书链条数不符：%d ≠ %d"
				% [phase, chain.size(), want_chain.size()],
				{"chain": want_chain}, {"chain": chain})
		for i in chain.size():
			var cn_v: Variant = chain[i]
			if not (cn_v is Dictionary):
				return _fail(E_TABLE_CELL, "第 %s 遍证书链第 %d 级不是对象" % [phase, i + 1],
					{"chain[%d]" % i: "object"}, {"chain[%d]" % i: cn_v})
			var cn: Dictionary = cn_v
			var wn: Dictionary = want_chain[i]
			var node := str(cn.get("node", ""))
			var sig_v: Variant = cn.get("sig_ok", null)
			if typeof(sig_v) != TYPE_BOOL:
				return _fail(E_TABLE_CELL, "第 %s 遍证书链第 %d 级 sig_ok 缺失或非布尔"
					% [phase, i + 1], {"sig_ok": "bool"}, {"sig_ok": sig_v})
			var sig_ok := bool(sig_v)
			var cr := str(cn.get("reason", ""))
			if node != str(wn.get("node", "")) or sig_ok != bool(wn.get("sig_ok", false)) \
					or cr != str(wn.get("reason", "")):
				return _fail(E_OUTPUT_MISMATCH,
					"第 %s 遍证书链第 %d 级 %s sig_ok=%s reason=\"%s\" 与剧本不符（应为 sig_ok=%s reason=\"%s\"）"
						% [phase, i + 1, node, str(sig_ok), cr,
							str(wn.get("sig_ok", false)), str(wn.get("reason", ""))],
					{"node": str(wn.get("node", "")), "sig_ok": bool(wn.get("sig_ok", false)),
						"reason": str(wn.get("reason", ""))},
					{"node": node, "sig_ok": sig_ok, "reason": cr})
	return {"ok": true, "code": 0, "detail": "剧本开关与证书结果可指认",
		"input": rows, "expected": want, "actual": {"rows": rows}}


static func _row_for(rows: Array, row_key: String, phase: String) -> Dictionary:
	for raw in rows:
		if raw is Dictionary and str((raw as Dictionary).get(row_key, "")) == phase:
			return raw
	return {}
