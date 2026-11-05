extends RefCounted
## 15.1 符号签名导出；同一张符号表也供 15.3（ABI 版本兼容）逐符号比签名。
##
## 签名 = 名称 + 有序参数类型 + 返回类型，形如 `area(int,char)->A`。
## 顺序参与比较：`int,char` 与 `char,int` 是两个不同签名（`diff_sig` 报 order_changed）。
##
## 15.1 的 meta 不对本行自比：
##   - `same_symbol`：比「不同程序各自声明的同一符号」——两个程序是两份数据；
##   - `abi_ok`：比「程序声明 vs 库导出」并查 ABI 类型词表——三个来源彼此独立。
## 15.3 的 `compat_report` 把每条签名差异摊成一行，`reason` 参与逐格判红；
## 版本规则：主版本变即拒绝；同主版本下 ABI 相同才 linked。

static func _types_of(params: Array) -> String:
	var parts := []
	for p in params:
		parts.append(str(p))
	return ",".join(parts)

static func signature(name: String, params: Array, ret: String) -> String:
	return "%s(%s)->%s" % [name, _types_of(params), ret]

## manifest: {"lib","programs":[{"id","declares":[{"name","params":[type...],"ret"}]}],
##            "symbols":[库导出的符号...],"abi_types":{"params":[...],"ret":[...]}, "blueprint":bool}
## rows 一行 = 一个程序读到的库符号（签名取自库导出，prog 取自程序 id）。
static func run(manifest: Dictionary) -> Dictionary:
	var lib := str(manifest.get("lib", ""))
	var programs: Array = manifest.get("programs", [])
	var exports: Array = manifest.get("symbols", [])
	var rows: Array = []
	for raw_p in programs:
		var p: Dictionary = raw_p
		var pid := str(p.get("id", ""))
		for raw_s in exports:
			var s: Dictionary = raw_s
			var name := str(s.get("name", ""))
			var params: Array = s.get("params", [])
			var ret := str(s.get("ret", ""))
			rows.append({
				"prog": pid,
				"symbol": name,
				"params": params.size(),
				"param_types": _types_of(params),
				"ret": ret,
				"lib": lib,
				"sig": signature(name, params, ret),
			})
	return {"rows": rows, "meta": meta(rows, manifest)}

static func meta(rows: Array, manifest: Dictionary) -> Dictionary:
	var abi_types: Dictionary = manifest.get("abi_types", {})
	var vocab_params: Array = abi_types.get("params", [])
	var vocab_ret: Array = abi_types.get("ret", [])
	var exports := {}
	for raw_s in (manifest.get("symbols", []) as Array):
		var s: Dictionary = raw_s
		var nm := str(s.get("name", ""))
		exports[nm] = signature(nm, s.get("params", []), str(s.get("ret", "")))
	var same_symbol := true
	var abi_ok := true
	var first := {}
	for raw_p in (manifest.get("programs", []) as Array):
		var p: Dictionary = raw_p
		var declares: Array = p.get("declares", [])
		for raw_d in declares:
			var d: Dictionary = raw_d
			var nm := str(d.get("name", ""))
			var sig := signature(nm, d.get("params", []), str(d.get("ret", "")))
			if first.has(nm):
				if str(first[nm]) != sig:
					same_symbol = false
			else:
				first[nm] = sig
			# 声明必须与库导出的同名签名一致，且类型在 ABI 词表内
			if not exports.has(nm) or str(exports[nm]) != sig or not _in_vocab(d, vocab_params, vocab_ret):
				abi_ok = false
		# rows 声称每个程序都读到了全部库符号，故每个程序都要声明它们
		for nm in exports:
			if not _declared(declares, str(nm)):
				abi_ok = false
	return {
		"same_symbol": same_symbol,
		"abi_ok": abi_ok,
		"blueprint": bool(manifest.get("blueprint", true)),
	}

static func _in_vocab(s: Dictionary, vocab_params: Array, vocab_ret: Array) -> bool:
	for t in (s.get("params", []) as Array):
		if not vocab_params.has(str(t)):
			return false
	return vocab_ret.has(str(s.get("ret", "")))

static func _declared(declares: Array, name: String) -> bool:
	for raw in declares:
		if str((raw as Dictionary).get("name", "")) == name:
			return true
	return false

static func _split(types: String) -> Array:
	if types.is_empty():
		return []
	return types.split(",")

static func _types(d: Dictionary) -> String:
	if d.has("param_types"):
		return str(d["param_types"])
	return _types_of(d.get("params", []))

## 15.3 签名差异：只比名称/有序参数类型/返回，不比实现。顺序敏感。
## a / b 可以是 {"name","params","ret"}，也可以是 rows 里的样式的行（用 symbol/param_types/ret）。
static func diff_sig(a: Dictionary, b: Dictionary) -> Dictionary:
	var reasons: Array = []
	var an := str(a.get("name", a.get("symbol", "")))
	var bn := str(b.get("name", b.get("symbol", "")))
	if an != bn:
		reasons.append("name_changed")
	var at := _split(_types(a))
	var bt := _split(_types(b))
	if at.size() != bt.size():
		reasons.append("arity_changed")
	elif at != bt:
		var rev := bt.duplicate()
		rev.reverse()
		reasons.append("order_changed" if at == rev else "type_changed")
	if str(a.get("ret", "")) != str(b.get("ret", "")):
		reasons.append("ret_changed")
	return {"same": reasons.is_empty(), "reasons": reasons}

## manifest: {"lib","req_version","lib_version","pairs":[{"old":{...},"new":{...}}, ...]}
## rows 一行 = 一对新旧符号；reason 是 `diff_sig` 现算，逐格参与判红。
static func compat_report(manifest: Dictionary) -> Dictionary:
	var req := str(manifest.get("req_version", ""))
	var libv := str(manifest.get("lib_version", ""))
	var pairs: Array = manifest.get("pairs", [])
	var rows: Array = []
	var changed := 0
	for raw in pairs:
		var pr: Dictionary = raw
		var old_s: Dictionary = pr.get("old", {})
		var new_s: Dictionary = pr.get("new", {})
		var d := diff_sig(old_s, new_s)
		var reasons: Array = d["reasons"]
		if not reasons.is_empty():
			changed += 1
		var abi_same := bool(d["same"])
		rows.append({
			"symbol": str(old_s.get("name", "")),
			"old_sig": signature(str(old_s.get("name", "")), old_s.get("params", []), str(old_s.get("ret", ""))),
			"new_sig": signature(str(new_s.get("name", "")), new_s.get("params", []), str(new_s.get("ret", ""))),
			"reason": ",".join(reasons),
			"compatible": abi_same,
			"result": _version_verdict(req, libv, abi_same),
		})
	return {"rows": rows, "meta": {
		"version_major_changed": _major(req) != _major(libv),
		"changed": changed,
		"unchanged": rows.size() - changed,
		"readable": _readable(rows),
		"report": rows.size() == pairs.size() and not rows.is_empty(),
	}}

static func _major(v: String) -> String:
	var i := v.find(".")
	return v if i < 0 else v.substr(0, i)

static func _version_verdict(req: String, libv: String, abi_same: bool) -> String:
	if _major(req) != _major(libv):
		return "rejected"  # 主版本变即拒绝
	return "linked" if abi_same else "rejected"

## 可读性：有差异必须点出符号与差异类型；无差异不许挂 reason。
static func _readable(rows: Array) -> bool:
	for raw in rows:
		var r: Dictionary = raw
		if str(r.get("symbol", "")).is_empty():
			return false
		var has_reason := not str(r.get("reason", "")).is_empty()
		if has_reason != not bool(r.get("compatible", true)):
			return false
	return true
