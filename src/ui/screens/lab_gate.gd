extends LabBase

## 1.4 门级：用 AND/OR/NOT 搭出目标函数。黑盒验收，允许多解。

## 中栏讲解带实际高度由最长段（170 字 / 每行 40 字 = 5 行）决定：实测 176。
## 目标条 46 + 调色板 44 + 带 176 + 3×6 间距 = 284，画布给 258 → 中栏合计 542 ≤ 544。
const GATE_CANVAS_H := 258

var _editor: CircuitEditor
var _graphs: Dictionary = {}
var _current_task := ""
var _encapsulated := false
var _live: Label
var _task_buttons: Dictionary = {}
var _task_hint: Label
var _target_label: Label
var _truth_box: VBoxContainer
var _enc_btn: Button
var _pal_buttons: Dictionary = {}

func _build() -> void:
	# ---- 左栏：任务与封装 ----
	side.add_child(_section("任务"))
	_task_hint = Ui.wrap("", UiTheme.F_BODY, UiTheme.MUTED)
	_task_hint.custom_minimum_size = Vector2(0, 76)
	side.add_child(_task_hint)
	side.add_child(Ui.hline())
	for raw in _all_tasks():
		var t: Dictionary = raw
		var tid := str(t.get("id", ""))
		var b := Ui.button(_short_title(str(t.get("title", tid))), func(): _switch_task(tid), false)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.tooltip_text = str(t.get("title", tid))
		b.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
		b.add_theme_font_size_override("font_size", UiTheme.F_LABEL)
		side.add_child(b)
		_task_buttons[tid] = b
	side.add_child(Ui.spacer())
	side.add_child(Ui.hline())
	side.add_child(_section("封装"))
	_enc_btn = Ui.button("封装 MY-XOR", func(): _encapsulate(), false)
	_enc_btn.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	side.add_child(_enc_btn)
	side.add_child(Ui.ghost("重置任务", func(): _reset_task()))

	# ---- 中栏：目标条 + 696×416 编辑器 + 调色板 ----
	var target_card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	target_card.custom_minimum_size = Vector2(0, 40)
	center.add_child(target_card)
	var tm := Ui.margin4(12, 4, 12, 4)
	target_card.add_child(tm)
	var trow := Ui.hbox(12)
	tm.add_child(trow)
	var tag := Ui.label("目标", UiTheme.F_META, UiTheme.MUTED)
	tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(tag)
	_target_label = Ui.label("", UiTheme.F_LABEL, UiTheme.CHALK)
	_target_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(_target_label)
	trow.add_child(Ui.spacer())
	var cap_label := Ui.muted("门上限 %d" % int(lab_data.get("max_gates", 12)), UiTheme.F_META)
	cap_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	trow.add_child(cap_label)

	var editor_card := Ui.card_tight(UiTheme.BOARD_SUNK, UiTheme.LINE)
	editor_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	editor_card.custom_minimum_size = Vector2(0, GATE_CANVAS_H)
	center.add_child(editor_card)
	_editor = CircuitEditor.new()
	_editor.custom_minimum_size = Vector2(696, GATE_CANVAS_H)
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.changed.connect(_on_editor_changed)
	editor_card.add_child(_editor)

	var pal := Ui.hbox(8)
	pal.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	center.add_child(pal)
	var pal_tag := Ui.label("调色板", UiTheme.F_META, UiTheme.MUTED)
	pal_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pal.add_child(pal_tag)
	for g in ["not", "and", "or"]:
		var gs := str(g)
		var b := Ui.ghost(gs.to_upper(), func(): _pick_gate(gs))
		b.custom_minimum_size = Vector2(76, UiTheme.CONTROL_H)
		pal.add_child(b)
		_pal_buttons[gs] = b
	pal.add_child(Ui.spacer())
	# 教学层：画布下方讲解带 = 分段课文阅读卡（例外，不走左栏）；翻页并到标题行压高度。
	_install_reader(center, 40, UiTheme.F_LABEL, true)
	# 讲解带吃掉一部分间距，保证中栏总高不越过 544。
	center.add_theme_constant_override("separation", 6)

	# ---- 右栏：目标真值表 + 验收 ----
	inspector.add_child(_section("目标真值表"))
	_truth_box = Ui.vbox(2)
	inspector.add_child(_truth_box)
	inspector.add_child(Ui.hline())
	inspector.add_child(_section("OUT"))
	_live = Ui.mono("X", UiTheme.F_BODY_LG, UiTheme.MUTED)
	inspector.add_child(_live)
	inspector.add_child(Ui.wrap("黑盒只看 a/b → out 的行为，允许多解。", UiTheme.F_BODY, UiTheme.MUTED))
	# 提示层：attempt ≥ 1 才显形，放右栏（不占画布高度）。
	_add_hint(inspector, 11)
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收 T%d.%d" % [int(DataDB.chapter.data.get("number", 1)), int(DataDB.chapter.lab(lab_id).get("order", 0))], func(): _run_cases(), true))

	_load_state()
	_switch_task(_current_task if not _current_task.is_empty() else str(_all_tasks()[0].get("id", "")))
	_pick_gate("not")
	_finish_shell()

func _all_tasks() -> Array:
	var out := []
	var xor_task := {}
	for raw in lab_data.get("tasks", []):
		var t: Dictionary = raw
		out.append(t)
		if str(t.get("target", "")) == "xor":
			xor_task = t
	if xor_task.is_empty():
		return out
	out.append({
		"id": "t_xor_2",
		"title": "任务 E：XOR 第二结构",
		"target": "xor",
		"palette": xor_task.get("palette", ["not", "and", "or"]),
		"input_ids": xor_task.get("input_ids", ["a", "b"]),
		"second_of": str(xor_task.get("id", "t_xor")),
	})
	return out

func _short_title(title: String) -> String:
	## 左栏宽 248，按钮文字截到 10 字，完整标题放 tooltip，避免撑破栏宽。
	var t := title.trim_prefix("任务 ")
	if t.length() <= 11:
		return t
	return t.substr(0, 10) + "…"

func _task_by_id(id: String) -> Dictionary:
	for raw in _all_tasks():
		var t: Dictionary = raw
		if str(t.get("id", "")) == id:
			return t
	return {}

func _switch_task(id: String) -> void:
	if id.is_empty():
		return
	if not _current_task.is_empty() and _current_task != id:
		_save_current()
	var task := _task_by_id(id)
	var inputs := []
	for iid in task.get("input_ids", ["a", "b"]):
		inputs.append({"id": str(iid), "label": str(iid).to_upper()})
	var doc: Variant = null
	if _graphs.has(id) and _graphs[id] is CircuitGraph:
		doc = (_graphs[id] as CircuitGraph).to_dict()
	_current_task = id
	_editor.setup(inputs, [{"id": "out", "label": "OUT"}], task.get("palette", ["not", "and", "or"]), int(lab_data.get("max_gates", 12)))
	if doc is Dictionary:
		_editor.load_dict(doc)
	_fit_editor_nodes()
	_task_hint.text = str(task.get("title", id))
	_target_label.text = "OUT = %s" % _target_expr(str(task.get("target", "")))
	_rebuild_truth(task)
	for key in _task_buttons.keys():
		var b: Button = _task_buttons[key]
		var on := str(key) == id
		b.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.CHALK if on else UiTheme.BOARD_HIGH, UiTheme.CHALK if on else UiTheme.LINE))
		b.add_theme_color_override("font_color", UiTheme.INK if on else UiTheme.CHALK)
	_on_editor_changed()
	_update_enc_label()

func _pick_gate(gs: String) -> void:
	_editor.set_selected_gate(gs)
	for key in _pal_buttons.keys():
		var b: Button = _pal_buttons[key]
		var on := str(key) == gs
		b.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.CHALK if on else UiTheme.BOARD_HIGH, UiTheme.CHALK if on else UiTheme.LINE))
		b.add_theme_color_override("font_color", UiTheme.INK if on else UiTheme.CHALK)

func _target_expr(target: String) -> String:
	match target:
		"not": return "NOT a"
		"and": return "a AND b"
		"or": return "a OR b"
		"xor": return "a XOR b"
	return target

func _target_out(target: String, a: bool, b: bool) -> bool:
	match target:
		"not": return not a
		"and": return a and b
		"or": return a or b
		"xor": return a != b
	return false

func _rebuild_truth(task: Dictionary) -> void:
	for c in _truth_box.get_children():
		c.queue_free()
	var target := str(task.get("target", ""))
	var header := Ui.hbox(6)
	header.add_theme_constant_override("separation", 6)
	for t in (["a", "out"] if target == "not" else ["a", "b", "out"]):
		var l := Ui.label(t, UiTheme.F_META, UiTheme.MUTED)
		l.custom_minimum_size = Vector2(54, 0)
		header.add_child(l)
	_truth_box.add_child(header)
	var rows := [[false], [true]] if target == "not" else [[false, false], [false, true], [true, false], [true, true]]
	for raw in rows:
		var row_vals: Array = raw
		var row := Ui.hbox(6)
		var a: bool = row_vals[0]
		row.add_child(_cell("1" if a else "0", UiTheme.CYAN))
		if target != "not":
			var b: bool = row_vals[1]
			row.add_child(_cell("1" if b else "0", UiTheme.CYAN))
		row.add_child(_cell("1" if _target_out(target, a, bool(row_vals[1]) if row_vals.size() > 1 else false) else "0", UiTheme.CHALK_BRIGHT))
		_truth_box.add_child(row)

func _cell(text: String, color: Color) -> Label:
	var l := Ui.mono(text, UiTheme.F_BODY, color)
	l.custom_minimum_size = Vector2(54, 0)
	return l

func _save_current() -> void:
	if _current_task.is_empty() or _editor == null:
		return
	_graphs[_current_task] = CircuitGraph.from_dict(_editor.to_dict())

func _on_editor_changed() -> void:
	if _editor == null or _live == null:
		return
	var ev := _editor.evaluate()
	var values: Dictionary = ev.get("values", {})
	var out := str(values.get("out", "X"))
	var ok := bool(ev.get("ok", true))
	_live.text = "%s · 门 %d · %s" % [out, _editor.gate_count(), "无环" if ok else "存在环"]
	_live.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if out == "1" else (UiTheme.DANGER if out == "X" else UiTheme.MUTED))
	_save_state()

func _encapsulate() -> void:
	_save_current()
	var g: CircuitGraph = _graphs.get("t_xor", null)
	if g == null:
		return
	var res := BlackBox.check_target(g, "xor", ["a", "b"], ["out"])
	if not bool(res.get("ok", false)):
		EventBus.toast("XOR 行为未通过，不能封装", "warn")
		return
	_encapsulated = true
	_update_enc_label()
	_save_state()
	EventBus.toast("已封装 MY-XOR（端口 a/b/out）；M1 只复核行为，不产出复用资源", "ok")

func _update_enc_label() -> void:
	if _enc_btn == null:
		return
	_enc_btn.disabled = _encapsulated
	_enc_btn.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.CHALK if _encapsulated else UiTheme.BOARD_HIGH, UiTheme.CHALK if _encapsulated else UiTheme.LINE))
	_enc_btn.add_theme_stylebox_override("hover", UiTheme.flat(UiTheme.CHALK, UiTheme.CHALK))
	_enc_btn.add_theme_color_override("font_color", UiTheme.INK if _encapsulated else UiTheme.CHALK)
	_enc_btn.add_theme_color_override("font_disabled_color", UiTheme.INK)

func _reset_task() -> void:
	if _current_task.is_empty():
		return
	var id := _current_task
	_graphs.erase(id)
	_current_task = ""
	_switch_task(id)

var _fail_shot := false

func _reset_for_fail_shot() -> void:
	_fail_shot = true

func _run_cases() -> void:
	_save_current()
	var graphs := {} if _fail_shot else _graphs
	var rep := LabChecks.gate(lab_data, graphs, {"encapsulated": _encapsulated}, tracker)
	show_report(rep)
	pass_report(rep)

func _on_attempt(a: int) -> void:
	_apply_hint(a)

func _save_state() -> void:
	if _editor != null and not _current_task.is_empty():
		_graphs[_current_task] = CircuitGraph.from_dict(_editor.to_dict())
	var docs := {}
	for k in _graphs.keys():
		if _graphs[k] is CircuitGraph:
			docs[str(k)] = (_graphs[k] as CircuitGraph).to_dict()
		else:
			docs[str(k)] = _graphs[k]
	save_state({"graphs": docs, "current": _current_task, "encapsulated": _encapsulated})

func _load_state() -> void:
	var st := load_state()
	if st.is_empty():
		return
	var docs: Variant = st.get("graphs", null)
	if docs is Dictionary:
		for k in docs.keys():
			_graphs[str(k)] = CircuitGraph.from_dict(docs[k])
	_current_task = str(st.get("current", ""))
	_encapsulated = bool(st.get("encapsulated", false))

func scripted_solve() -> bool:
	for raw in _all_tasks():
		var t: Dictionary = raw
		var tid := str(t.get("id", ""))
		_switch_task(tid)
		_graphs[tid] = _scripted_graph(t)
		_editor.load_dict((_graphs[tid] as CircuitGraph).to_dict())
		_fit_editor_nodes()
	_encapsulate()
	_run_cases()
	return is_done()

## 画布高度压到 GATE_CANVAS_H 后，把低于画布的节点上移，避免被裁切（不改图结构）。
func _fit_editor_nodes() -> void:
	var max_y := float(GATE_CANVAS_H - 48)
	for raw in _editor.graph.nodes.values():
		var n: Dictionary = raw
		var p: Vector2 = n.get("pos", Vector2.ZERO)
		if p.y > max_y:
			p.y = max_y
			n["pos"] = p
	_editor.queue_redraw()

func _scripted_graph(task: Dictionary) -> CircuitGraph:
	var g := CircuitGraph.new()
	var ids: Array = task.get("input_ids", ["a", "b"])
	for i in ids.size():
		var iid := str(ids[i])
		g.add_input(iid, iid.to_upper(), Vector2(40, 70 + i * 180))
	g.add_output("out", "OUT", Vector2(590, 139))
	var target := str(task.get("target", ""))
	var tid := str(task.get("id", ""))
	var y := 139.0
	if target == "not":
		g.add_gate("g_not", LogicGates.Type.NOT, "NOT", Vector2(330, y))
		g.link(str(ids[0]), "g_not", 0)
		g.link("g_not", "out", 0)
		return g
	if ids.size() < 2:
		return g
	var a := str(ids[0])
	var b := str(ids[1])
	if target == "and" or target == "or":
		var gt: int = LogicGates.Type.AND if target == "and" else LogicGates.Type.OR
		var label := "AND" if target == "and" else "OR"
		g.add_gate("g1", gt, label, Vector2(330, y))
		g.link(a, "g1", 0)
		g.link(b, "g1", 1)
		g.link("g1", "out", 0)
		return g
	if target != "xor":
		return g
	if tid == "t_xor_2":
		g.add_gate("g1", LogicGates.Type.AND, "AND", Vector2(210, y - 80))
		g.add_gate("g2", LogicGates.Type.OR, "OR", Vector2(210, y + 100))
		g.add_gate("g3", LogicGates.Type.NOT, "NOT", Vector2(330, y - 80))
		g.add_gate("g4", LogicGates.Type.AND, "AND", Vector2(450, y))
		g.link(a, "g1", 0); g.link(b, "g1", 1)
		g.link(a, "g2", 0); g.link(b, "g2", 1)
		g.link("g1", "g3", 0)
		g.link("g2", "g4", 0); g.link("g3", "g4", 1)
		g.link("g4", "out", 0)
	else:
		g.add_gate("g1", LogicGates.Type.NOT, "NOT", Vector2(210, y - 100))
		g.add_gate("g2", LogicGates.Type.NOT, "NOT", Vector2(210, y + 160))
		g.add_gate("g3", LogicGates.Type.AND, "AND", Vector2(330, y - 100))
		g.add_gate("g4", LogicGates.Type.AND, "AND", Vector2(330, y + 160))
		g.add_gate("g5", LogicGates.Type.OR, "OR", Vector2(450, y))
		g.link(a, "g1", 0); g.link(b, "g2", 0)
		g.link(a, "g3", 0); g.link("g2", "g3", 1)
		g.link(b, "g4", 0); g.link("g1", "g4", 1)
		g.link("g3", "g5", 0); g.link("g4", "g5", 1)
		g.link("g5", "out", 0)
	return g
