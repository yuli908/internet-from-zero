extends RefCounted

## CH14.1 参考解释器：源码 → token 序列 → AST → 求值，三段都可导出。
## 生产：`lex` / `parse` / `eval`（本文件）。
## 消费：`tests/test_ch14.gd` 用它生成 T14.1-1 作答；`src/core/net_lab_kit.gd::_table`
##（:82-165）按 `expect_rows` 逐段比对 tokens / ast / value。

const TOKEN_KINDS := {
	"+": "op", "-": "op", "*": "op", "/": "op",
	"(": "lparen", ")": "rparen",
	"[": "lbracket", "]": "rbracket",
	",": "comma",
}

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
