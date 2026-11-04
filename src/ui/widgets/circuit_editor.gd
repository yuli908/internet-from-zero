class_name CircuitEditor
extends Control

## 点击式组合逻辑编辑器：
##  - 调色板选门后，点空白落点放置；
##  - 点输出端口，再点目标输入端口连线；
##  - 右键输入端口断线，右键门体删除；
##  - 点输入节点翻转电平，点门体循环切换门类型。
## 只负责坐标与交互，逻辑一律走 CircuitGraph / SimCircuit / BlackBox。

signal changed

const NODE_SIZE := Vector2(94, 44)

var graph := CircuitGraph.new()
var palette: Array = ["and", "or", "not"]
var selected_gate := "and"
var max_gates := 0
var delay_per_gate := -1
var last_status := ""

var _link_from := ""
var _font: Font
var _mono: Font

func _init() -> void:
	# 内容侧硬约束：上限与仿真实测同源，不在此处另行硬编码。
	max_gates = SimDelays.gdscript_gate_limit()

func _ready() -> void:
	custom_minimum_size = Vector2(520, 340)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_font = UiTheme.cjk_font()
	_mono = UiTheme.mono_font()

func setup(inputs: Array, outputs: Array, palette_in: Array, max_gates_in: int = -1, delay_in: int = -1) -> void:
	graph = CircuitGraph.new()
	palette = palette_in.duplicate()
	selected_gate = str(palette[0]) if not palette.is_empty() else ""
	# 关卡可以更严（如 12 门），但不能超过 GDScript 实测量；更严的上限照旧生效。
	var cap := SimDelays.gdscript_gate_limit()
	max_gates = cap if max_gates_in <= 0 else mini(max_gates_in, cap)
	delay_per_gate = delay_in
	var i := 0
	for raw in inputs:
		var n: Dictionary = raw
		graph.add_input(str(n.get("id", "a")), str(n.get("label", n.get("id", ""))), Vector2(26, 46 + i * 84))
		i += 1
	i = 0
	for raw in outputs:
		var n: Dictionary = raw
		graph.add_output(str(n.get("id", "out")), str(n.get("label", n.get("id", ""))), Vector2(-1, 46 + i * 84))
		i += 1
	changed.emit()
	queue_redraw()

func set_selected_gate(kind: String) -> void:
	selected_gate = kind
	queue_redraw()

func gate_count() -> int:
	return graph.gate_ids().size()

func evaluate() -> Dictionary:
	return graph.evaluate()

func build_sim() -> Dictionary:
	# 超限不构建：要求走结构级（宏单元/L2 模块），不做静默截断。
	if gate_count() > max_gates:
		return {"ok": false, "sim": null, "inputs": [], "outputs": [], "error": "needs_structural_representation"}
	return SimCircuit.build_graph(graph, delay_per_gate)

func to_dict() -> Dictionary:
	return graph.to_dict()

func load_dict(doc: Dictionary) -> void:
	graph = CircuitGraph.from_dict(doc)
	changed.emit()
	queue_redraw()

func set_input_value(id: String, v: bool) -> void:
	graph.set_input_value(id, v)
	changed.emit()
	queue_redraw()

func _ensure_layout() -> void:
	if size.x < 100.0:
		return
	var i := 0
	for raw_id in graph.nodes.keys():
		var n: Dictionary = graph.nodes[raw_id]
		var pos: Vector2 = n.get("pos", Vector2.ZERO)
		if pos.x < 0.0:
			n["pos"] = Vector2(size.x - 132.0, 46.0 + i * 84.0)
		i += 1

func _draw() -> void:
	_ensure_layout()
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.043, 0.059, 0.075), true)
	for x in range(0, int(size.x), 32):
		draw_line(Vector2(x, 0), Vector2(x, size.y), UiTheme.alpha(UiTheme.BORDER, 0.18), 1.0)
	for y in range(0, int(size.y), 32):
		draw_line(Vector2(0, y), Vector2(size.x, y), UiTheme.alpha(UiTheme.BORDER, 0.18), 1.0)

	var ev := graph.evaluate()
	var values: Dictionary = ev.get("values", {})

	for raw_id in graph.nodes.keys():
		var id := str(raw_id)
		var n: Dictionary = graph.nodes[id]
		if str(n["kind"]) == CircuitGraph.KIND_GATE:
			_draw_link(str(n.get("a", "")), id, 0, values)
			if LogicGates.arity(int(n["gate"])) > 1:
				_draw_link(str(n.get("b", "")), id, 1, values)

	for raw_id in graph.nodes.keys():
		var id := str(raw_id)
		var n: Dictionary = graph.nodes[id]
		var r := _node_rect(id)
		var kind := str(n["kind"])
		var bg := UiTheme.PANEL_2
		var border := UiTheme.BORDER
		if kind == CircuitGraph.KIND_INPUT:
			bg = UiTheme.alpha(UiTheme.ACCENT, 0.12)
			border = UiTheme.ACCENT
		elif kind == CircuitGraph.KIND_OUTPUT:
			bg = UiTheme.alpha(UiTheme.OK, 0.10)
			border = UiTheme.OK
		draw_rect(r, bg, true)
		draw_rect(r, border, false, 1.5)

		if kind == CircuitGraph.KIND_INPUT:
			var on := bool(n.get("value", false))
			draw_string(_mono, Vector2(r.position.x + 8, r.position.y + 20), "%s = %d" % [str(n.get("label", id)), 1 if on else 0], HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 16, UiTheme.OK if on else UiTheme.MUTED)
			draw_string(_font, Vector2(r.position.x + 8, r.position.y + 37), "点击翻转", HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 10, UiTheme.MUTED)
		elif kind == CircuitGraph.KIND_GATE:
			var gname := LogicGates.gate_key(int(n["gate"]))
			draw_string(_mono, Vector2(r.position.x + 8, r.position.y + 27), gname, HORIZONTAL_ALIGNMENT_CENTER, r.size.x - 16, 20, UiTheme.TEXT)
			var v := str(values.get(id, "X"))
			draw_string(_mono, Vector2(r.position.x + 8, r.position.y + 41), "→ %s" % v, HORIZONTAL_ALIGNMENT_RIGHT, r.size.x - 16, 10, UiTheme.OK if v == "1" else UiTheme.MUTED)
		else:
			var src := str(n.get("a", ""))
			var v := str(values.get(src, "X")) if not src.is_empty() else "X"
			draw_string(_mono, Vector2(r.position.x + 8, r.position.y + 20), str(n.get("label", id)), HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 14, UiTheme.TEXT)
			draw_string(_mono, Vector2(r.position.x + 8, r.position.y + 38), "= %s" % v, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 16, 14, UiTheme.OK if v == "1" else UiTheme.MUTED)
		_draw_ports(id)

	if not _link_from.is_empty():
		draw_string(_font, Vector2(12, size.y - 12), "已选起点 %s，点击目标输入端口完成连线（右键取消）" % _link_from, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 11, UiTheme.AMBER)
	elif last_status.is_empty():
		draw_string(_font, Vector2(12, size.y - 12), "选中门：%s · 左键放门/连线 · 右键断线/删门" % selected_gate, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 11, UiTheme.MUTED)
	else:
		draw_string(_font, Vector2(12, size.y - 12), last_status, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 11, UiTheme.AMBER)

func _draw_link(src_id: String, dst_id: String, port: int, values: Dictionary) -> void:
	if src_id.is_empty() or not graph.nodes.has(src_id):
		return
	var a := _port_center(src_id, "out")
	var b := _port_center(dst_id, port)
	var v := str(values.get(src_id, "X"))
	var color := UiTheme.MUTED
	if v == "1":
		color = UiTheme.OK
	elif v == "0":
		color = UiTheme.ACCENT
	else:
		color = UiTheme.DANGER
	draw_line(a, b, color, 1.6, true)
	draw_circle(a, 3.0, color)
	draw_circle(b, 3.0, color)

func _draw_ports(id: String) -> void:
	var n: Dictionary = graph.nodes[id]
	var kind := str(n["kind"])
	if kind == CircuitGraph.KIND_GATE or kind == CircuitGraph.KIND_INPUT:
		var out := _port_center(id, "out")
		draw_rect(Rect2(out - Vector2(5, 5), Vector2(10, 10)), UiTheme.AMBER, false, 1.5)
	if kind == CircuitGraph.KIND_GATE:
		draw_rect(Rect2(_port_center(id, 0) - Vector2(5, 5), Vector2(10, 10)), UiTheme.ACCENT, false, 1.5)
		if LogicGates.arity(int(n["gate"])) > 1:
			draw_rect(Rect2(_port_center(id, 1) - Vector2(5, 5), Vector2(10, 10)), UiTheme.ACCENT, false, 1.5)
	elif kind == CircuitGraph.KIND_OUTPUT:
		draw_rect(Rect2(_port_center(id, 0) - Vector2(5, 5), Vector2(10, 10)), UiTheme.ACCENT, false, 1.5)

func _node_rect(id: String) -> Rect2:
	if not graph.nodes.has(id):
		return Rect2()
	var n: Dictionary = graph.nodes[id]
	var pos: Vector2 = n.get("pos", Vector2.ZERO)
	return Rect2(pos, NODE_SIZE)

func _port_center(id: String, which: Variant) -> Vector2:
	var r := _node_rect(id)
	if str(which) == "out":
		return Vector2(r.end.x, r.position.y + r.size.y * 0.5)
	var port := int(which)
	var y := (r.position.y + 13.0) if port == 0 else (r.position.y + 31.0)
	return Vector2(r.position.x, y)

func _port_hit(p: Vector2) -> Dictionary:
	for raw_id in graph.nodes.keys():
		var id := str(raw_id)
		var n: Dictionary = graph.nodes[id]
		var kind := str(n["kind"])
		if kind == CircuitGraph.KIND_GATE or kind == CircuitGraph.KIND_INPUT:
			if p.distance_to(_port_center(id, "out")) <= 9.0:
				return {"id": id, "port": "out"}
		if kind == CircuitGraph.KIND_GATE:
			if p.distance_to(_port_center(id, 0)) <= 9.0:
				return {"id": id, "port": 0}
			if LogicGates.arity(int(n["gate"])) > 1 and p.distance_to(_port_center(id, 1)) <= 9.0:
				return {"id": id, "port": 1}
		elif kind == CircuitGraph.KIND_OUTPUT:
			if p.distance_to(_port_center(id, 0)) <= 9.0:
				return {"id": id, "port": 0}
	return {}

func _node_hit(p: Vector2) -> String:
	var keys := graph.nodes.keys()
	for i in range(keys.size() - 1, -1, -1):
		var id := str(keys[i])
		if _node_rect(id).has_point(p):
			return id
	return ""

func _gui_input(event: InputEvent) -> void:
	if not (event is InputEventMouseButton) or not event.pressed:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT:
		_on_left(mb.position)
	elif mb.button_index == MOUSE_BUTTON_RIGHT:
		_on_right(mb.position)

func _on_left(p: Vector2) -> void:
	last_status = ""
	var port := _port_hit(p)
	if not port.is_empty():
		var pid := str(port["id"])
		var which: Variant = port["port"]
		if str(which) == "out":
			_link_from = pid
			queue_redraw()
			return
		if not _link_from.is_empty():
			var res := graph.link(_link_from, pid, int(which))
			if bool(res.get("ok", false)):
				last_status = "已连线 %s → %s" % [_link_from, pid]
				_link_from = ""
				changed.emit()
			else:
				last_status = str(res.get("error", "连线失败"))
				_link_from = ""
			queue_redraw()
			return
		last_status = "先点一个输出端口作为起点"
		queue_redraw()
		return

	var nid := _node_hit(p)
	if not nid.is_empty():
		var n: Dictionary = graph.nodes[nid]
		var kind := str(n["kind"])
		if kind == CircuitGraph.KIND_INPUT:
			graph.set_input_value(nid, not bool(n.get("value", false)))
			changed.emit()
		elif kind == CircuitGraph.KIND_GATE:
			if not palette.is_empty():
				var cur := LogicGates.gate_key(int(n["gate"]))
				var idx := palette.find(cur)
				var next := str(palette[(idx + 1) % palette.size()])
				graph.set_gate_type(nid, LogicGates.from_string(next))
				last_status = "门 %s → %s" % [nid, next]
				changed.emit()
		queue_redraw()
		return

	if selected_gate.is_empty():
		last_status = "请先在调色板选择门类型"
		queue_redraw()
		return
	if gate_count() >= max_gates:
		last_status = "门数量已达上限 %d：该电路需要结构级表示" % max_gates
		queue_redraw()
		return
	var gid := _next_gate_id()
	var pos := Vector2(
		clampf(p.x - NODE_SIZE.x * 0.5, 8.0, maxf(8.0, size.x - NODE_SIZE.x - 8.0)),
		clampf(p.y - NODE_SIZE.y * 0.5, 8.0, maxf(8.0, size.y - NODE_SIZE.y - 34.0))
	)
	graph.add_gate(gid, LogicGates.from_string(selected_gate), selected_gate.to_upper(), pos)
	last_status = "放置 %s（%s）" % [selected_gate.to_upper(), gid]
	changed.emit()
	queue_redraw()

func _on_right(p: Vector2) -> void:
	if not _link_from.is_empty():
		_link_from = ""
		last_status = "已取消连线"
		queue_redraw()
		return
	var port := _port_hit(p)
	if not port.is_empty() and str(port["port"]) != "out":
		var ok := graph.unlink(str(port["id"]), int(port["port"]))
		last_status = "已断线" if ok else "该端口没有连线"
		if ok:
			changed.emit()
		queue_redraw()
		return
	var nid := _node_hit(p)
	if not nid.is_empty() and str(graph.nodes[nid]["kind"]) == CircuitGraph.KIND_GATE:
		graph.remove_node(nid)
		last_status = "已删除 %s" % nid
		changed.emit()
		queue_redraw()

func _next_gate_id() -> String:
	var i := 1
	while graph.has_node("g%d" % i):
		i += 1
	return "g%d" % i
