extends RefCounted

## CH14.1 / CH14.2 参考解释器：源码 → token 序列 → AST → 求值，三段都可导出。
## 生产：`lex` / `parse` / `eval`（14.1 纯数值）；`run_typed`（14.2 逐值类型标签）。
## 消费：`tests/test_ch14.gd` 用 `lex/parse/eval` 生成 T14.1-1 作答、
## 用 `run_typed` 生成 T14.2-1 的逐值标签导出；`src/core/net_lab_kit.gd::_table`
##（:82-165）按 `expect_rows` 逐行逐格比对。

const TOKEN_KINDS := {
	"+": "op", "-": "op", "*": "op", "/": "op",
	"(": "lparen", ")": "rparen",
	"[": "lbracket", "]": "rbracket",
	",": "comma",
	"=": "assign", ";": "semi",
}

## 14.2 类型标签名（数据侧定稿：INT / STR / LIST / ERROR）。
const T_INT := "INT"
const T_STR := "STR"
const T_LIST := "LIST"
const T_ERROR := "ERROR"

static func lex(src: String) -> Array:
	var toks: Array = []
	var i := 0
	var line := 1
	while i < src.length():
		var ch := src[i]
		if ch == "\n":
			line += 1
			i += 1
		elif ch == " " or ch == "\t" or ch == "\r":
			i += 1
		elif ch >= "0" and ch <= "9":
			var s := i
			while i < src.length() and src[i] >= "0" and src[i] <= "9":
				i += 1
			toks.append({"i": toks.size(), "kind": "num", "text": src.substr(s, i - s), "line": line})
		elif (ch >= "a" and ch <= "z") or (ch >= "A" and ch <= "Z") or ch == "_":
			var s2 := i
			while i < src.length():
				var c := src[i]
				if not ((c >= "a" and c <= "z") or (c >= "A" and c <= "Z") \
						or (c >= "0" and c <= "9") or c == "_"):
					break
				i += 1
			toks.append({"i": toks.size(), "kind": "ident", "text": src.substr(s2, i - s2), "line": line})
		elif ch == "\"":
			var s3 := i + 1
			i += 1
			while i < src.length() and src[i] != "\"":
				i += 1
			if i >= src.length():
				return [{"i": toks.size(), "kind": "error", "text": ch, "line": line}]
			toks.append({"i": toks.size(), "kind": "str", "text": src.substr(s3, i - s3), "line": line})
			i += 1
		elif TOKEN_KINDS.has(ch):
			toks.append({"i": toks.size(), "kind": TOKEN_KINDS[ch], "text": ch, "line": line})
			i += 1
		else:
			return [{"i": toks.size(), "kind": "error", "text": ch, "line": line}]
	return toks

static func parse(tokens: Array) -> Dictionary:
	var cur := {"t": tokens, "i": 0}
	var node := _expr(cur)
	var left: Array = cur["t"]
	if int(cur["i"]) < left.size():
		return {"kind": "error", "message": "多余 token @%d" % int(cur["i"])}
	return node

static func eval(node: Dictionary, env: Dictionary = {}) -> Variant:
	match str(node.get("kind", "")):
		"num":
			return int(node.get("value", 0))
		"var":
			return int(env.get(str(node.get("name", "")), 0))
		"add":
			return int(eval((node["children"] as Array)[0], env)) + int(eval((node["children"] as Array)[1], env))
		"sub":
			return int(eval((node["children"] as Array)[0], env)) - int(eval((node["children"] as Array)[1], env))
		"mul":
			return int(eval((node["children"] as Array)[0], env)) * int(eval((node["children"] as Array)[1], env))
		"neg":
			return -int(eval((node["children"] as Array)[0], env))
		"call":
			var args: Array = node.get("children", [])
			var vals: Array = []
			for a in args:
				vals.append(eval(a, env))
			match str(node.get("name", "")):
				"fib":
					return _fib(int(vals[0]))
				"sum":
					var total := 0
					for v in (vals[0] as Array):
						total += int(v)
					return total
			return 0
		"list":
			var items: Array = []
			for c in (node.get("children", []) as Array):
				items.append(eval(c, env))
			return items
		"index":
			var base: Array = eval((node["children"] as Array)[0], env)
			var idx := int(eval((node["children"] as Array)[1], env))
			if idx < 0 or idx >= base.size():
				return 0
			return base[idx]
	return 0

static func _fib(n: int) -> int:
	if n <= 1:
		return n
	return _fib(n - 1) + _fib(n - 2)

static func _peek(cur: Dictionary) -> Dictionary:
	var t: Array = cur["t"]
	var i := int(cur["i"])
	if i >= t.size():
		return {}
	return t[i]

static func _take(cur: Dictionary) -> Dictionary:
	var t: Array = cur["t"]
	var i := int(cur["i"])
	if i >= t.size():
		return {}
	cur["i"] = i + 1
	return t[i]

static func _expect(cur: Dictionary, text: String) -> bool:
	var tk := _peek(cur)
	if tk.is_empty() or str(tk.get("text", "")) != text:
		return false
	_take(cur)
	return true

static func _expr(cur: Dictionary) -> Dictionary:
	var node := _term(cur)
	while true:
		var tk := _peek(cur)
		var text := str(tk.get("text", ""))
		if text != "+" and text != "-":
			break
		_take(cur)
		var right := _term(cur)
		node = {"kind": "add" if text == "+" else "sub", "children": [node, right]}
	return node

static func _term(cur: Dictionary) -> Dictionary:
	var node := _unary(cur)
	while true:
		var tk := _peek(cur)
		var text := str(tk.get("text", ""))
		if text != "*" and text != "/":
			break
		_take(cur)
		var right := _unary(cur)
		node = {"kind": "mul" if text == "*" else "div", "children": [node, right]}
	return node

static func _unary(cur: Dictionary) -> Dictionary:
	var tk := _peek(cur)
	if str(tk.get("text", "")) == "-":
		_take(cur)
		return {"kind": "neg", "children": [_unary(cur)]}
	return _postfix(cur)

static func _postfix(cur: Dictionary) -> Dictionary:
	var node := _primary(cur)
	while str(_peek(cur).get("text", "")) == "[":
		_take(cur)
		var idx := _expr(cur)
		if not _expect(cur, "]"):
			return {"kind": "error", "message": "缺 ]"}
		node = {"kind": "index", "children": [node, idx]}
	return node

static func _primary(cur: Dictionary) -> Dictionary:
	var tk := _peek(cur)
	if tk.is_empty():
		return {"kind": "error", "message": "意外结束"}
	var kind := str(tk.get("kind", ""))
	var text := str(tk.get("text", ""))
	if kind == "num":
		_take(cur)
		return {"kind": "num", "value": int(text)}
	if kind == "str":
		_take(cur)
		return {"kind": "str", "text": text}
	if kind == "ident":
		_take(cur)
		if str(_peek(cur).get("text", "")) == "(":
			_take(cur)
			var args: Array = []
			if str(_peek(cur).get("text", "")) != ")":
				while true:
					args.append(_expr(cur))
					if str(_peek(cur).get("text", "")) != ",":
						break
					_take(cur)
			if not _expect(cur, ")"):
				return {"kind": "error", "message": "缺 )"}
			return {"kind": "call", "name": text, "children": args}
		return {"kind": "var", "name": text}
	if text == "(":
		_take(cur)
		var inner := _expr(cur)
		if not _expect(cur, ")"):
			return {"kind": "error", "message": "缺 )"}
		return inner
	if text == "[":
		_take(cur)
		var items: Array = []
		if str(_peek(cur).get("text", "")) != "]":
			while true:
				items.append(_expr(cur))
				if str(_peek(cur).get("text", "")) != ",":
					break
				_take(cur)
		if not _expect(cur, "]"):
			return {"kind": "error", "message": "缺 ]"}
		return {"kind": "list", "children": items}
	return {"kind": "error", "message": "意外 token %s" % text}

# ---------------------------------------------------------------- 14.2 逐值标签

## 语句序列：按 `;` 切段，`ident = expr` 记为赋值，其余记为表达式语句。
## 每段的 token 仍交给 `parse`（不重写语法分析），所以 14.1 的纯表达式路径一字不改。
static func parse_program(tokens: Array) -> Dictionary:
	var stmts: Array = []
	var seg: Array = []
	for raw in tokens:
		var tk: Dictionary = raw
		if str(tk.get("kind", "")) == "semi":
			if not seg.is_empty():
				stmts.append(_stmt_of(seg))
				seg = []
			continue
		seg.append(tk)
	if not seg.is_empty():
		stmts.append(_stmt_of(seg))
	return {"kind": "program", "statements": stmts}

static func _stmt_of(seg: Array) -> Dictionary:
	if seg.size() >= 2 and str(seg[0].get("kind", "")) == "ident" \
			and str(seg[1].get("kind", "")) == "assign":
		return {
			"kind": "assign",
			"name": str(seg[0].get("text", "")),
			"expr": parse(seg.slice(2)),
			"line": int(seg[0].get("line", 1)),
		}
	return {"kind": "expr", "expr": parse(seg)}

## 跑一段带类型标签的程序，导出逐值标签（下游真读，不是布尔位）。
## 返回：
##   tokens  词法产物
##   program 语句序列（每段内含 AST）
##   tags    逐值标签行 [{stmt, node, type_tag, value}]，node 为 `root/0/1` 形式的 AST 路径，
##           同一节点的子先父后（求值顺序）；漏一个、多一个、绑错节点都会在表比对里判红
##   errors  类型错误记录 [{stmt, node, code, left, right}]，left/right 是两侧类型名
##   meta    {tag_follows_value, error_names_both, program_alive}，全部由本次实跑推出
static func run_typed(src: String) -> Dictionary:
	var tokens: Array = lex(src)
	var program: Dictionary = parse_program(tokens)
	var env: Dictionary = {}
	var tags: Array = []
	var errors: Array = []
	var var_tags: Dictionary = {}
	var executed := 0
	var stmts: Array = program.get("statements", [])
	for si in stmts.size():
		var st: Dictionary = stmts[si]
		var tv: Dictionary = _eval_tagged(st.get("expr", {}), env, si + 1, "root", tags, errors)
		executed += 1
		if str(st.get("kind", "")) == "assign" and str(tv["type_tag"]) != T_ERROR:
			var nm := str(st.get("name", ""))
			env[nm] = tv
			if not var_tags.has(nm):
				var_tags[nm] = []
			if not (var_tags[nm] as Array).has(str(tv["type_tag"])):
				(var_tags[nm] as Array).append(str(tv["type_tag"]))
	var alive := executed == stmts.size()
	return {
		"tokens": tokens,
		"program": program,
		"tags": tags,
		"errors": errors,
		"meta": _typed_meta(var_tags, errors, alive),
	}

## 标签是否「跟着值走」：同一变量在本次运行里出现过 ≥2 种标签。
## 错误是否可读：每条 TYPE_MISMATCH 都点出两个不同的类型名。
## 程序是否没崩：所有语句都执行到了。
static func _typed_meta(var_tags: Dictionary, errors: Array, alive: bool) -> Dictionary:
	var follows := false
	for nm in var_tags:
		if (var_tags[nm] as Array).size() >= 2:
			follows = true
	var both := true
	for raw in errors:
		var e: Dictionary = raw
		var l := str(e.get("left", ""))
		var r := str(e.get("right", ""))
		if l.is_empty() or r.is_empty() or l == r:
			both = false
	return {
		"tag_follows_value": follows,
		"error_names_both": both,
		"program_alive": alive,
	}

static func _eval_tagged(node: Dictionary, env: Dictionary, stmt: int, path: String,
		trace: Array, errors: Array) -> Dictionary:
	var tv := _tagged_of(node, env, stmt, path, trace, errors)
	trace.append({"stmt": stmt, "node": path, "type_tag": str(tv["type_tag"]),
		"value": str(tv.get("value", ""))})
	return tv

static func _child_tagged(node: Dictionary, i: int, env: Dictionary, stmt: int,
		path: String, trace: Array, errors: Array) -> Dictionary:
	var kids: Array = node.get("children", [])
	if i < 0 or i >= kids.size():
		return {"type_tag": T_ERROR, "value": "PARSE_ERROR"}
	return _eval_tagged(kids[i], env, stmt, path + "/" + str(i), trace, errors)

static func _mismatch(left: Dictionary, right: Dictionary, stmt: int, path: String,
		errors: Array) -> Dictionary:
	var e := {
		"stmt": stmt,
		"node": path,
		"code": "TYPE_MISMATCH",
		"left": str(left.get("type_tag", "")),
		"right": str(right.get("type_tag", "")),
	}
	errors.append(e)
	return {"type_tag": T_ERROR, "value": "TYPE_MISMATCH", "error": e}

static func _generic_error(code: String) -> Dictionary:
	return {"type_tag": T_ERROR, "value": code}

static func _tagged_of(node: Dictionary, env: Dictionary, stmt: int, path: String,
		trace: Array, errors: Array) -> Dictionary:
	var kind := str(node.get("kind", ""))
	match kind:
		"num":
			return {"type_tag": T_INT, "value": int(node.get("value", 0))}
		"str":
			return {"type_tag": T_STR, "value": str(node.get("text", ""))}
		"var":
			var nm := str(node.get("name", ""))
			if not env.has(nm):
				return _generic_error("UNDEFINED")
			return (env[nm] as Dictionary).duplicate()
		"add", "sub", "mul", "div":
			var a := _child_tagged(node, 0, env, stmt, path, trace, errors)
			var b := _child_tagged(node, 1, env, stmt, path, trace, errors)
			if str(a["type_tag"]) == T_ERROR:
				return a
			if str(b["type_tag"]) == T_ERROR:
				return b
			var ta := str(a["type_tag"])
			var tb := str(b["type_tag"])
			if ta != tb:
				return _mismatch(a, b, stmt, path, errors)
			if ta == T_INT:
				var x := int(a["value"])
				var y := int(b["value"])
				match kind:
					"add":
						return {"type_tag": T_INT, "value": x + y}
					"sub":
						return {"type_tag": T_INT, "value": x - y}
					"mul":
						return {"type_tag": T_INT, "value": x * y}
					_:
						if y == 0:
							return _generic_error("DIV_ZERO")
						return {"type_tag": T_INT, "value": int(x / y)}
			if kind == "add" and ta == T_STR:
				return {"type_tag": T_STR, "value": str(a["value"]) + str(b["value"])}
			return _mismatch(a, b, stmt, path, errors)
		"neg":
			var v := _child_tagged(node, 0, env, stmt, path, trace, errors)
			if str(v["type_tag"]) != T_INT:
				if str(v["type_tag"]) == T_ERROR:
					return v
				return _mismatch({"type_tag": T_INT}, v, stmt, path, errors)
			return {"type_tag": T_INT, "value": -int(v["value"])}
		"call":
			var args: Array = []
			var kids: Array = node.get("children", [])
			for ai in kids.size():
				var av := _child_tagged(node, ai, env, stmt, path, trace, errors)
				if str(av["type_tag"]) == T_ERROR:
					return av
				if str(av["type_tag"]) != T_INT:
					return _mismatch({"type_tag": T_INT}, av, stmt, path, errors)
				args.append(int(av["value"]))
			match str(node.get("name", "")):
				"fib":
					if args.is_empty():
						return _generic_error("ARGC")
					return {"type_tag": T_INT, "value": _fib(int(args[0]))}
			return _generic_error("UNSUPPORTED_CALL")
		"list":
			var items: Array = []
			var ck: Array = node.get("children", [])
			for li in ck.size():
				var item := _child_tagged(node, li, env, stmt, path, trace, errors)
				if str(item["type_tag"]) == T_ERROR:
					return item
				items.append(item["value"])
			return {"type_tag": T_LIST, "value": items}
		"index":
			var base := _child_tagged(node, 0, env, stmt, path, trace, errors)
			var idx := _child_tagged(node, 1, env, stmt, path, trace, errors)
			if str(base["type_tag"]) == T_ERROR:
				return base
			if str(idx["type_tag"]) == T_ERROR:
				return idx
			if str(base["type_tag"]) != T_LIST or str(idx["type_tag"]) != T_INT:
				return _mismatch(base, idx, stmt, path, errors)
			var arr: Array = base["value"]
			var k := int(idx["value"])
			if k < 0 or k >= arr.size():
				return _generic_error("INDEX_RANGE")
			return {"type_tag": T_INT, "value": int(arr[k])}
	return _generic_error("PARSE_ERROR")
