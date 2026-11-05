extends RefCounted

## 13.2 对象图判据（提案 19 §2.2）。
##
## 边语义（与 docs/design/19-interface-extension-proposal.md §2.2 同文，改这里必须同步改文档）：
##   - 节点与边端点共用同一套编号：`obj_addr`（对象起始地址字符串，如 "0x40"），不引入第二套 id；
##   - 边为有向三元组 `{kind, from, to, field}`：`from` = 持有者/子类/实现者，`to` = 被引用者/父类/接口表；
##   - `kind` 只允许 `parent`（子→父）、`iface`（实现者→接口表）、`field`（字段引用）；
##   - `field` 边必须带字段名，且该名字必须是 `from` 节点 `fields[]` 里的字段；非 `field` 边不得带字段名；
##   - 边无序（按多重集比对），禁重边、禁自环（from == to）；
##   - 硬上限：节点 64、边 128；超限直接判红（E_TABLE_CELL），不截断、不静默丢边。

const KINDS := ["parent", "iface", "field"]
const MAX_NODES := 64
const MAX_EDGES := 128

const E_UNCONNECTED := 3
const E_TABLE_CELL := 7
const E_OUTPUT_MISMATCH := 10

static func _fail(code: int, detail: String, input: Variant, expected: Variant,
		actual: Variant) -> Dictionary:
	return {"ok": false, "code": code, "detail": detail,
		"input": input, "expected": expected, "actual": actual}


static func _edge_key(e: Dictionary) -> String:
	return "%s|%s|%s|%s" % [str(e.get("kind", "")), str(e.get("from", "")),
		str(e.get("to", "")), str(e.get("field", ""))]


static func _field_names(n: Dictionary) -> Array:
	var out := []
	var fs: Variant = n.get("fields", [])
	if fs is Array:
		for raw in fs:
			if raw is Dictionary:
				out.append(str((raw as Dictionary).get("name", "")))
	return out


static func _norm_nodes(nodes: Array) -> Array:
	var out := []
	for raw in nodes:
		if not (raw is Dictionary):
			continue
		var n: Dictionary = raw
		var fields := []
		var fs: Variant = n.get("fields", [])
		if fs is Array:
			for f_raw in fs:
				if f_raw is Dictionary:
					var f: Dictionary = f_raw
					fields.append({"name": str(f.get("name", "")),
						"offset": int(f.get("offset", -1))})
		out.append({"obj_addr": str(n.get("obj_addr", "")),
			"type": str(n.get("type", "")), "fields": fields})
	out.sort_custom(func(a, b): return str(a["obj_addr"]) < str(b["obj_addr"]))
	return out


static func _norm_edges(edges: Array) -> Array:
	var out := []
	for raw in edges:
		if raw is Dictionary:
			out.append((raw as Dictionary).duplicate(true))
	return out


## 判据入口：sub 为玩家/仿真提交的 {nodes, edges}，want 为数据侧 expect。
## 返回 {ok, code, detail, input, expected, actual}；actual 带解析后的图，供下游真读。
static func validate(sub_raw: Variant, want: Dictionary) -> Dictionary:
	if not (sub_raw is Dictionary):
		return _fail(E_UNCONNECTED, "对象图未提交：缺 nodes/edges",
			sub_raw, "graph{nodes,edges}", "missing")
	var sub: Dictionary = sub_raw
	var nodes_v: Variant = sub.get("nodes", null)
	var edges_v: Variant = sub.get("edges", null)
	if not (nodes_v is Array) or not (edges_v is Array):
		return _fail(E_UNCONNECTED, "对象图未提交：nodes 与 edges 都必须是数组",
			sub, {"nodes": "Array", "edges": "Array"}, sub)
	var nodes: Array = nodes_v
	var edges: Array = edges_v
	if nodes.size() > MAX_NODES:
		return _fail(E_TABLE_CELL, "节点数 %d 超过上限 %d（超限判红，不截断）"
			% [nodes.size(), MAX_NODES], {"nodes": nodes.size()},
			{"nodes": "<= %d" % MAX_NODES}, {"nodes": nodes.size()})
	if edges.size() > MAX_EDGES:
		return _fail(E_TABLE_CELL, "边数 %d 超过上限 %d（超限判红，不截断）"
			% [edges.size(), MAX_EDGES], {"edges": edges.size()},
			{"edges": "<= %d" % MAX_EDGES}, {"edges": edges.size()})

	var addrs := {}
	for i in nodes.size():
		if not (nodes[i] is Dictionary):
			return _fail(E_TABLE_CELL, "第 %d 个节点不是对象" % (i + 1),
				nodes[i], "node{obj_addr,type,fields}", nodes[i])
		var n: Dictionary = nodes[i]
		var addr := str(n.get("obj_addr", ""))
		if addr.is_empty():
			return _fail(E_TABLE_CELL, "第 %d 个节点缺 obj_addr" % (i + 1),
				n, "obj_addr", n)
		if addrs.has(addr):
			return _fail(E_TABLE_CELL, "节点地址重复：%s（节点按起始地址唯一）" % addr,
				n, "唯一 obj_addr", addr)
		addrs[addr] = n

	var got_keys := []
	var seen := {}
	for i in edges.size():
		if not (edges[i] is Dictionary):
			return _fail(E_TABLE_CELL, "第 %d 条边不是对象" % (i + 1),
				edges[i], "edge{kind,from,to,field}", edges[i])
		var e: Dictionary = edges[i]
		var kind := str(e.get("kind", ""))
		if not KINDS.has(kind):
			return _fail(E_TABLE_CELL, "第 %d 条边 kind=%s 不在枚举 %s"
				% [i + 1, kind, str(KINDS)], e, {"kind": KINDS}, {"kind": kind})
		var from := str(e.get("from", ""))
		var to := str(e.get("to", ""))
		if not addrs.has(from):
			return _fail(E_UNCONNECTED, "第 %d 条边 from=%s 指向不存在的节点"
				% [i + 1, from], e, {"from": "已声明的 obj_addr"}, {"from": from})
		if not addrs.has(to):
			return _fail(E_UNCONNECTED, "第 %d 条边 to=%s 指向不存在的节点"
				% [i + 1, to], e, {"to": "已声明的 obj_addr"}, {"to": to})
		if from == to:
			return _fail(E_TABLE_CELL, "第 %d 条边是自环（%s→%s），对象图不许自环"
				% [i + 1, from, to], e, "from != to", e)
		var fname := str(e.get("field", ""))
		if kind == "field":
			if fname.is_empty():
				return _fail(E_TABLE_CELL, "第 %d 条 field 边缺字段名" % (i + 1),
					e, {"field": "非空字段名"}, {"field": ""})
			if not _field_names(addrs[from]).has(fname):
				return _fail(E_TABLE_CELL, "第 %d 条 field 边的字段 %s 不在 %s 的 fields 里"
					% [i + 1, fname, from], e,
					{"field": _field_names(addrs[from])}, {"field": fname})
		elif not fname.is_empty():
			return _fail(E_TABLE_CELL, "第 %d 条 %s 边不得带 field（%s）"
				% [i + 1, kind, fname], e, {"field": ""}, {"field": fname})
		var key := _edge_key(e)
		if seen.has(key):
			return _fail(E_TABLE_CELL, "重复边：%s（多重集里同一条边只允许一次）" % key,
				e, "唯一边", e)
		seen[key] = true
		got_keys.append(key)

	var want_nodes: Array = want.get("nodes", [])
	var want_edges: Array = want.get("edges", [])
	if _norm_nodes(nodes) != _norm_nodes(want_nodes):
		return _fail(E_OUTPUT_MISMATCH,
			"节点与机器期望不符：实得 %d 个 / 期望 %d 个（含 addr/type/fields 逐项）"
				% [nodes.size(), want_nodes.size()],
			{"nodes": _norm_nodes(nodes)}, {"nodes": _norm_nodes(want_nodes)},
			{"nodes": _norm_nodes(nodes)})
	var want_keys := _edge_keys(want_edges)
	got_keys.sort()
	if got_keys != want_keys:
		var rev := _reversed_detail(edges, want_keys)
		if not rev.is_empty():
			return _fail(E_OUTPUT_MISMATCH, rev,
				{"edges": _norm_edges(edges)}, {"edges": _norm_edges(want_edges)},
				{"edges": _norm_edges(edges)})
		return _fail(E_OUTPUT_MISMATCH,
			"边与机器期望不符：实得 %d 条 / 期望 %d 条（按 kind|from|to|field 多重集比对）"
				% [edges.size(), want_edges.size()],
			{"edges": _norm_edges(edges)}, {"edges": _norm_edges(want_edges)},
			{"edges": _norm_edges(edges)})

	return {"ok": true, "code": 0, "detail": "对象图节点/边与机器期望一致",
		"input": {"nodes": nodes, "edges": edges},
		"expected": {"nodes": want_nodes, "edges": want_edges},
		"actual": {"nodes": nodes, "edges": edges}}


static func _edge_keys(edges: Array) -> Array:
	var out := []
	for raw in edges:
		if raw is Dictionary:
			out.append(_edge_key(raw))
	out.sort()
	return out


## 方向颠倒要单独点名（from/to 交换后与期望里的另一条边相同）。
static func _reversed_detail(got: Array, want_keys: Array) -> String:
	var got_keys := _edge_keys(got)
	for raw in got:
		var e: Dictionary = raw
		var key := _edge_key(e)
		if want_keys.has(key) or got_keys.count(key) > 1:
			continue
		var rev := "%s|%s|%s|%s" % [str(e.get("kind", "")), str(e.get("to", "")),
			str(e.get("from", "")), str(e.get("field", ""))]
		if want_keys.has(rev):
			return "有向边方向颠倒：%s 边 %s→%s 与机器期望相反（应为 %s→%s）" % [
				str(e.get("kind", "")), str(e.get("from", "")), str(e.get("to", "")),
				str(e.get("to", "")), str(e.get("from", ""))]
	return ""
