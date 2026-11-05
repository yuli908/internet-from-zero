extends RefCounted

## 19.3 采样链路判据（提案 19 §2.9）。
##
## 真值只来自 `src/sim/sim_sampling.gd::trace(cfg)`（真实跑链），不读任何期望表；
## 逐段比对做在原始字节/码值上（in_raw/out_raw/code），不先把码值翻译成人话。
## 失败码（与 specs/m5/failure_contract.md §13 同文）：
##   3  —— 整件 rows 未提交（由 _table 统一处理）；
##   13 —— 段数不符（缺一段/多一段，链路与提交的行数不同）；
##   10 —— 五段顺序错位、节点错位、网关声明 stage_count / 采样判据 meta 不符；
##   7  —— 某段原始字节/码值被换算或截断、配置非法（超限/声明与结构不一致）。

const Sim := preload("res://src/sim/sim_sampling.gd")

const E_TABLE_CELL := 7
const E_OUTPUT_MISMATCH := 10
const E_COVERAGE := 13

const RAW_KEYS := ["in_raw", "out_raw", "code", "sample_ms"]

static func _same(a: Variant, b: Variant) -> bool:
	var ta := typeof(a)
	var tb := typeof(b)
	if (ta == TYPE_INT or ta == TYPE_FLOAT) and (tb == TYPE_INT or tb == TYPE_FLOAT):
		return absf(float(a) - float(b)) < 1e-9
	if ta == TYPE_ARRAY and tb == TYPE_ARRAY:
		if (a as Array).size() != (b as Array).size():
			return false
		for i in (a as Array).size():
			if not _same((a as Array)[i], (b as Array)[i]):
				return false
		return true
	if ta == TYPE_DICTIONARY and tb == TYPE_DICTIONARY:
		if (a as Dictionary).size() != (b as Dictionary).size():
			return false
		for k in (a as Dictionary):
			if not (b as Dictionary).has(k):
				return false
			if not _same((a as Dictionary)[k], (b as Dictionary)[k]):
				return false
		return true
	return str(a) == str(b)

static func _fail(code: int, detail: String, expected: Variant,
		actual: Variant) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail, "input": actual,
		"expected": expected, "actual": actual}

## 入口：got = 玩家提交的 {rows, meta}；cfg = 数据里的 sampling 链路声明。
static func validate_gate(got: Dictionary, cfg: Dictionary) -> Dictionary:
	var tr: Dictionary = Sim.trace(cfg)
	if not bool(tr.get("ok", false)):
		return _fail(int(tr.get("code", E_TABLE_CELL)), str(tr.get("detail", "")),
			"链路可导出", {"sampling": "config_error"})
	var chain: Array = tr["stages"]
	var chain_meta: Dictionary = tr["meta"]
	var rows_v: Variant = got.get("rows", null)
	var rows: Array = rows_v if rows_v is Array else []
	if rows.size() != chain.size():
		return _fail(E_COVERAGE,
			"段数不符：交 %d 段，网关声明/链路 %d 段（缺段或多段）"
				% [rows.size(), chain.size()],
			{"stage_count": chain.size()}, {"stage_count": rows.size()})
	# 先判顺序/节点，再判原始值：顺序错位是链路语义错，不能被后面的格值错吞掉。
	for i in chain.size():
		if not (rows[i] is Dictionary):
			return _fail(E_TABLE_CELL, "第 %d 段不是对象（五段都要有记录）" % (i + 1),
				{"row": "object"}, {"row": rows[i]})
		var row: Dictionary = rows[i]
		var exp: Dictionary = chain[i]
		var got_stage := str(row.get("stage", ""))
		var exp_stage := str(exp.get("stage", ""))
		if got_stage != exp_stage:
			return _fail(E_OUTPUT_MISMATCH,
				"第 %d 段顺序错位：链路是 %s，交的是 %s"
					% [i + 1, exp_stage, got_stage],
				{"stage": exp_stage}, {"stage": got_stage})
		var got_node := str(row.get("node", ""))
		var exp_node := str(exp.get("node", ""))
		if got_node != exp_node:
			return _fail(E_OUTPUT_MISMATCH,
				"第 %d 段（%s）节点错位：链路是 %s，交的是 %s"
					% [i + 1, exp_stage, exp_node, got_node],
				{"node": exp_node}, {"node": got_node})
	for i in chain.size():
		var row: Dictionary = rows[i]
		var exp: Dictionary = chain[i]
		for key in RAW_KEYS:
			if not _same(row.get(key, null), exp.get(key, null)):
				return _fail(E_TABLE_CELL,
					"第 %d 段（%s）%s 被换算/截断：交 %s，链路原始值 %s"
						% [i + 1, str(exp.get("stage", "")), key,
							str(row.get(key, "?")), str(exp.get(key, "?"))],
					{str(key): exp.get(key, null)},
					{str(key): row.get(key, null)})
	var meta_v: Variant = got.get("meta", {})
	var meta: Dictionary = meta_v if meta_v is Dictionary else {}
	for key in chain_meta:
		if not _same(meta.get(key, null), chain_meta[key]):
			return _fail(E_OUTPUT_MISMATCH,
				"网关声明/采样判据 %s 不符：交 %s，链路 %s"
					% [str(key), str(meta.get(key, "?")), str(chain_meta[key])],
				{str(key): chain_meta[key]}, {str(key): meta.get(key, null)})
	return {
		"ok": true,
		"code": 0,
		"detail": "五段原始字节/码值逐段一致",
		"input": {"rows": rows, "meta": meta},
		"expected": {"stage_count": chain.size(), "chain": chain, "meta": chain_meta},
		# 下游读取点：actual.rows 是提交的逐段记录，actual.chain 是机器跑出的链路。
		"actual": {"rows": rows, "meta": meta, "chain": chain,
			"chain_meta": chain_meta},
	}
