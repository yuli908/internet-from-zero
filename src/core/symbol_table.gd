extends RefCounted
## 15.1 符号签名导出；同一张符号表也为 15.3（ABI 版本兼容）预留。
##
## 签名 = 名称 + 有序参数类型 + 返回类型，形如 `area(int,char)->A`。
## 顺序参与比较：`int,char` 与 `char,int` 是两个不同签名（`diff_sig` 报 order_changed）。
## 本文件只导出签名与差异，不判断行为；15.3 目前仍用静态判据，未接线（见 §2.4 文档）。

static func _types_of(params: Array) -> String:
	var parts := []
	for p in params:
		parts.append(str(p))
	return ",".join(parts)

static func signature(name: String, params: Array, ret: String) -> String:
	return "%s(%s)->%s" % [name, _types_of(params), ret]

## manifest: {"lib","programs":[...],"symbols":[{"name","params":[type...],"ret"}]}
## 返回 {rows, meta}；rows 一行 = 一个程序里的一个符号，列可逐格比。
static func run(manifest: Dictionary) -> Dictionary:
	var lib := str(manifest.get("lib", ""))
	var programs: Array = manifest.get("programs", [])
	var symbols: Array = manifest.get("symbols", [])
	var rows: Array = []
	for p in programs:
		for raw in symbols:
			var s: Dictionary = raw
			var name := str(s.get("name", ""))
			var params: Array = s.get("params", [])
			var ret := str(s.get("ret", ""))
			rows.append({
				"prog": str(p),
				"symbol": name,
				"params": params.size(),
				"param_types": _types_of(params),
				"ret": ret,
				"lib": lib,
				"sig": signature(name, params, ret),
			})
	return {"rows": rows, "meta": meta(rows, manifest)}

static func meta(rows: Array, manifest: Dictionary) -> Dictionary:
	var same_symbol := true
	var sigs := {}
	for raw in rows:
		var r: Dictionary = raw
		var name := str(r.get("symbol", ""))
		var sig := str(r.get("sig", ""))
		if sigs.has(name) and str(sigs[name]) != sig:
			same_symbol = false
		sigs[name] = sig
	var abi_ok := true
	for raw in rows:
		var r: Dictionary = raw
		var types := _split(str(r.get("param_types", "")))
		if str(r.get("symbol", "")) == "" or str(r.get("ret", "")) == "" \
				or int(r.get("params", -1)) != types.size() or str(r.get("lib", "")) == "":
			abi_ok = false
	return {
		"same_symbol": same_symbol,
		"abi_ok": abi_ok,
		"blueprint": bool(manifest.get("blueprint", true)),
	}

static func _split(types: String) -> Array:
	if types.is_empty():
		return []
	return types.split(",")

## 15.3 预留：只比签名，不比实现。返回 changed 的字段名，顺序敏感。
## a / b 可以是 rows 里的行，也可以是 {"symbol","param_types","ret"}。
static func diff_sig(a: Dictionary, b: Dictionary) -> Dictionary:
	var reasons: Array = []
	if str(a.get("symbol", "")) != str(b.get("symbol", "")):
		reasons.append("name_changed")
	var at := _split(str(a.get("param_types", "")))
	var bt := _split(str(b.get("param_types", "")))
	if at.size() != bt.size():
		reasons.append("arity_changed")
	elif at != bt:
		var rev := bt.duplicate()
		rev.reverse()
		reasons.append("order_changed" if at == rev else "type_changed")
	if str(a.get("ret", "")) != str(b.get("ret", "")):
		reasons.append("ret_changed")
	return {"same": reasons.is_empty(), "reasons": reasons}
