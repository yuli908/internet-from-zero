extends RefCounted

## 防增长守卫：`data/**` 的字段路径必须全部登记在 `docs/data/dead-fields-audit.md`（附录 D）。
##
## 为什么按「路径 + 父对象」而不是键名：`ports` 曾把 `gate_cases[].ports`（活）
## 与 `labs.encapsulation.ports`（死）合并成一条，按键名去重会把死字段藏起来。
## 本守卫的路径口径：含 `id` 的对象归一成 `*`，数组元素归一成 `[]`。
##
## 单向判红：数据里出现、登记里没有 → 红。
## 反向只警告：登记了但数据里已不存在 → 打印条数，不判红。

const DOC := "res://docs/data/dead-fields-audit.md"
const DATA_ROOT := "res://data"

const EXPECT := 6
const EXPECT_GROUPS := {
	"registry": 2, "unregistered": 1, "stale": 1, "selfcheck": 2,
}
const GROUP_DESCRIPTIONS := {
	"registry": "审计文档含登记块且条数 ≥1000",
	"unregistered": "data/** 的字段路径全部已登记（新增未登记即红并打印路径）",
	"stale": "反向核对：登记了但数据里不存在，仅警告不判红",
	"selfcheck": "守卫逻辑自检：新增路径能被识别、反向核对不漏",
}

func run(ctx: TestContext) -> void:
	var reg := _load_registry()
	ctx.begin_group("registry")
	ctx.check("审计文档含登记块", not reg.is_empty(), DOC)
	ctx.check("登记条数 ≥1000", reg.size() >= 1000, str(reg.size()))

	var actual := _scan_data()
	ctx.begin_group("unregistered")
	var missing: Array = []
	for p in actual.keys():
		if not reg.has(p):
			missing.append(p)
	ctx.check("数据字段路径全部已登记", missing.is_empty(),
		"新增 %d 条：%s" % [missing.size(), _join(missing)])
	print("FIELD_REGISTRY unregistered=%d" % missing.size())

	ctx.begin_group("stale")
	var stale: Array = []
	for p in reg.keys():
		if not actual.has(p):
			stale.append(p)
	# 只警告不判红：cond 恒真，条数写进 detail。
	ctx.check("过期登记（仅警告）", true, "%d 条：%s" % [stale.size(), _join(stale)])
	print("FIELD_REGISTRY stale=%d" % stale.size())

	ctx.begin_group("selfcheck")
	var probe := {"data": {"labs": {"transistor": {"id": "t", "title": "x", "new_field": 1}}}}
	var probe_paths := _collect(probe, "data/labs/probe.json")
	ctx.check("自检：新字段被识别为未登记",
		probe_paths.has("data/labs/probe.json :: data.labs.*.new_field"),
		_join(probe_paths.keys()))
	var shrunk := {"data/labs/probe.json :: data.labs.*.title": true}
	var stale_probe := 0
	for p in probe_paths.keys():
		if not shrunk.has(p):
			stale_probe += 1
	ctx.check("自检：反向核对能数出过期登记", stale_probe == 3, str(stale_probe))

func _load_registry() -> Dictionary:
	var out := {}
	var text := FileAccess.get_file_as_string(DOC)
	if text.is_empty():
		return out
	var inside := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if line == "<!-- REGISTRY:BEGIN -->":
			inside = true
			continue
		if line == "<!-- REGISTRY:END -->":
			break
		if inside and line.begins_with("- ") and line.find(" :: ") >= 0:
			out[line.substr(2)] = true
	return out

func _scan_data() -> Dictionary:
	var out := {}
	for f in _json_files(DATA_ROOT):
		var doc: Variant = JSON.parse_string(FileAccess.get_file_as_string(f))
		if doc == null:
			continue
		var rel: String = str(f).replace("res://", "")
		_walk(doc, "", rel, out)
	return out

func _collect(doc: Variant, rel: String) -> Dictionary:
	var out := {}
	_walk(doc, "", rel, out)
	return out

func _json_files(dir: String) -> Array:
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var names: Array = []
	d.list_dir_begin()
	var n := d.get_next()
	while n != "":
		if not n.begins_with("."):
			names.append(n)
		n = d.get_next()
	d.list_dir_end()
	names.sort()
	for name in names:
		var p := dir.path_join(str(name))
		if str(name).ends_with(".json"):
			out.append(p)
		elif DirAccess.dir_exists_absolute(p):
			out.append_array(_json_files(p))
	return out

func _walk(node: Variant, path: String, rel: String, out: Dictionary) -> void:
	if node is Array:
		for item in node:
			_walk(item, path + "[]", rel, out)
		return
	if not (node is Dictionary):
		return
	var base := path
	if (node as Dictionary).has("id") and not path.ends_with("[]"):
		base = (path.substr(0, path.rfind(".")) + ".*") if path.rfind(".") >= 0 else "*"
	var schema: bool = base.is_empty() or (node as Dictionary).has("id")
	for k in (node as Dictionary).keys():
		var key := str(k)
		var child: String = (base + "." + key) if not base.is_empty() else key
		if schema and _is_field(key):
			out[rel + " :: " + child] = true
		_walk((node as Dictionary)[k], child, rel, out)

func _is_field(key: String) -> bool:
	if key.is_empty():
		return false
	for i in key.length():
		var c := key[i]
		if not ((c >= "a" and c <= "z") or (c >= "0" and c <= "9") or c == "_"):
			return false
	return key[0] >= "a" and key[0] <= "z"

func _join(items: Array) -> String:
	var take := items.slice(0, 8)
	return "、".join(PackedStringArray(take)) + ("…" if items.size() > 8 else "")
