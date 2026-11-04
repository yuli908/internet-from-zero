class_name SimMacro
extends RefCounted

## M4 · 宏单元目录（只读模型，不改变 L1/L2 求值）。
## 定位：对外 1 个节点，对内只在只读视图里看结构。
##  - decoder3 / comparator4 的仿真仍走 `SimModule`，可整块展开（11 / 33 门）；
##  - alu4 无门级网表（166 门 > 80 绝对上限），只给 7 个只读页，整块展开必返 `IFZ_E_SCALE`；
##  - 门数预算单一来源 `SimDelays`：>50 只提示"结构级表示"，>80 构建期拒绝，禁止只画一部分门。
## 数据单一来源：`data/sim/macros.json`（`ifz-macros/1`）。

const PATH := "res://data/sim/macros.json"
const FORMAT := "ifz-macros/1"
const ERROR_SCALE := "IFZ_E_SCALE"
const ERROR_UNKNOWN := "IFZ_E_UNKNOWN_MACRO"
const ERROR_PAGE := "IFZ_E_UNKNOWN_PAGE"

static var _doc: Dictionary = {}
static var _loaded := false

static func reload(doc: Dictionary = {}) -> void:
	## 测试与热重载用；空字典回到"从文件懒加载"。
	_doc = doc.duplicate(true)
	_loaded = not doc.is_empty()

static func _load() -> Dictionary:
	if not _loaded:
		var text := FileAccess.get_file_as_string(PATH)
		var parsed: Variant = JSON.parse_string(text) if not text.is_empty() else null
		_doc = parsed if parsed is Dictionary else {}
		_loaded = true
	return _doc

static func cells() -> Dictionary:
	var d := _load()
	var raw: Dictionary = d.get("cells", {})
	return raw.duplicate(true)

static func meta(kind: String) -> Dictionary:
	## 元数据 + 由延迟表推导的 `t_settle`（不写死在 JSON，避免编造）。
	var raw: Dictionary = (_load().get("cells", {}) as Dictionary).get(kind, {})
	if raw.is_empty():
		return {}
	var cell: Dictionary = (raw as Dictionary).duplicate(true)
	cell["kind"] = kind
	cell["pages"] = pages(kind)
	cell["t_settle"] = declared_settle(kind, int(cell.get("width", 1)))
	return cell

static func declared_settle(kind: String, width: int = 0) -> int:
	## decoder3 / comparator4 复用 `SimModule` 的结构推导；alu4 见 `alu4_settle()`。
	match kind:
		"decoder3":
			return SimModule.declared_settle("decoder3", 3)
		"comparator4":
			return SimModule.declared_settle("comparator4", maxi(1, width))
		"alu4":
			return alu4_settle(maxi(1, width))
	return 0

static func alu4_settle(width: int = 4) -> int:
	## 按 `components.py::ALU._build` 的关键路径推导（tick）：
	## 1) 控制：op → nop(not) → sub(and)                         = not + and
	## 2) 补码选择：sub → b_sel mux2(not+and+or)                 = not + and + or
	## 3) 行波加：b_sel → 4 位 FA 链（与 `SimModule` ripple 同构）  = xor + W*(and+or)
	## 4) 两级选择数据路径：sum → ga mux → y mux（各自 and+or=6）  = 2*(and+or)
	## 5) V 标志：结果 MSB → ns(not) → v.t2(and) → v.or(or) → flagv(and)
	##                                                          = not + and + or + and
	## Z 标志（nor=2）与 C（and=3）都在 3) 之后 ≤ 上述路径；移位是重接线，无门。
	return (SimDelays.delay("not") + SimDelays.delay("and")) \
		+ (SimDelays.delay("not") + SimDelays.delay("and") + SimDelays.delay("or")) \
		+ SimModule.declared_settle("ripple", maxi(1, width)) \
		+ 2 * (SimDelays.delay("and") + SimDelays.delay("or")) \
		+ (SimDelays.delay("not") + SimDelays.delay("and") + SimDelays.delay("or") + SimDelays.delay("and"))

static func pages(kind: String) -> Array:
	var raw: Array = (_load().get("pages", {}) as Dictionary).get(kind, [])
	return (raw as Array).duplicate(true)

static func page(kind: String, page_id: String) -> Dictionary:
	for raw in pages(kind):
		var p: Dictionary = raw
		if str(p.get("id", "")) == page_id:
			return p.duplicate(true)
	return {}

static func expand(kind: String, c: SimCircuit, prefix: String = "") -> Dictionary:
	## 整块展开：仅 `expandable=true` 且 合计门数 ≤ `gdscript_gate_hard_cap()`。
	## >50 但 ≤80 允许构建，用 `scale_warn` 让 UI 提示"该电路需要结构级表示"；>80 返回 `IFZ_E_SCALE`。
	var m := meta(kind)
	if m.is_empty():
		return {"ok": false, "error": ERROR_UNKNOWN, "kind": kind, "gates": 0}
	var cell_gates := int(m.get("gate_count", 0))
	if not bool(m.get("expandable", false)):
		return {"ok": false, "error": ERROR_SCALE, "kind": kind, "gates": cell_gates,
			"total": c.gate_count() + cell_gates}
	var total := c.gate_count() + cell_gates
	if total > SimDelays.gdscript_gate_hard_cap():
		return {"ok": false, "error": ERROR_SCALE, "kind": kind, "gates": cell_gates, "total": total}
	var p := prefix if not prefix.is_empty() else kind
	var mod := SimModule.create(str(m.get("module_kind", "")), p, int(m.get("width", 1)))
	var r := mod.build(c)
	if not bool(r.get("ok", false)):
		return {"ok": false, "error": str(r.get("error", "")), "kind": kind, "gates": 0,
			"total": c.gate_count()}
	return {
		"ok": true,
		"error": "",
		"kind": kind,
		"gates": cell_gates,
		"total": c.gate_count(),
		"scale_warn": total > SimDelays.gdscript_gate_limit(),
		"inputs": mod.inputs.duplicate(),
		"outputs": mod.outputs.duplicate(),
		"module": mod,
	}

static func expand_page(kind: String, page_id: String, c: SimCircuit, prefix: String = "") -> Dictionary:
	## 只读子视图：页门数必须 ≤ `gdscript_gate_limit()`。
	## 可展开宏单元（单页 = 整块）写入传入的临时 `SimCircuit`；alu4 只返回页结构，不写任何门。
	var m := meta(kind)
	if m.is_empty():
		return {"ok": false, "error": ERROR_UNKNOWN, "kind": kind, "page": page_id, "gates": 0}
	var pg := page(kind, page_id)
	if pg.is_empty():
		return {"ok": false, "error": ERROR_PAGE, "kind": kind, "page": page_id, "gates": 0}
	var pg_gates := int(pg.get("gates", 0))
	if pg_gates > SimDelays.gdscript_gate_limit():
		return {"ok": false, "error": ERROR_SCALE, "kind": kind, "page": page_id, "gates": pg_gates}
	if bool(m.get("expandable", false)):
		var r := expand(kind, c, prefix)
		if not bool(r.get("ok", false)):
			return r
		return {"ok": true, "error": "", "kind": kind, "page": page_id, "gates": pg_gates,
			"built": true, "read_only": false, "inputs": r["inputs"], "outputs": r["outputs"]}
	return {"ok": true, "error": "", "kind": kind, "page": page_id, "gates": pg_gates,
		"built": false, "read_only": true, "page_data": pg}

static func fold(kind: String, prefix: String = "") -> Dictionary:
	## 折叠边界：返回对外端口摘要与摘要值；调用方丢弃页内线网。
	var m := meta(kind)
	if m.is_empty():
		return {"ok": false, "error": ERROR_UNKNOWN, "kind": kind, "ports": {}, "digest": ""}
	var p := prefix if not prefix.is_empty() else kind
	var ports := ports_for(kind, p)
	var canonical := JSON.stringify({"kind": kind, "prefix": p, "ports": ports})
	return {"ok": true, "error": "", "kind": kind, "prefix": p, "ports": ports,
		"digest": SimCircuit.digest(canonical)}

static func ports_for(kind: String, prefix: String) -> Dictionary:
	## 端口命名与 `SimModule` 展开一致（decoder3 的 en 在 inputs 首位）。
	var p := prefix if not prefix.is_empty() else kind
	var ins: Array = []
	var outs: Array = []
	match kind:
		"decoder3":
			ins = ["%s.en" % p, "%s.a0" % p, "%s.a1" % p, "%s.a2" % p]
			for i in 8:
				outs.append("%s.y%d" % [p, i])
		"comparator4":
			for i in 4:
				ins.append("%s.a%d" % [p, i])
			for i in 4:
				ins.append("%s.b%d" % [p, i])
			outs = ["%s.EQ" % p, "%s.GT" % p, "%s.LT" % p]
		"alu4":
			for i in 4:
				ins.append("%s.a%d" % [p, i])
			for i in 4:
				ins.append("%s.b%d" % [p, i])
			for i in 3:
				ins.append("%s.op%d" % [p, i])
			for i in 4:
				outs.append("%s.y%d" % [p, i])
			outs.append_array(["%s.Z" % p, "%s.C" % p, "%s.V" % p, "%s.N" % p])
	return {"inputs": ins, "outputs": outs}
