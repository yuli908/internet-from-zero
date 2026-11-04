extends LabBase

## 第二章实验页（数据驱动，四节共用一张屏）：
##  2.1 器件探针（区域判读 + 选择题）、2.2 反相器（单图黑盒）、
##  2.3 万能门（多任务 NAND 图）、2.5 功耗与四门板（数值作答 + 四目标图）。
## 判定一律走 `Ch02Checks.run`；本页只采集输入与展示，不自行推算判据。

const REGION_KEYS := ["cutoff", "linear", "saturation"]
const REGION_TEXT := {"cutoff": "截止", "linear": "线性", "saturation": "饱和"}
const BOARD_TARGETS := ["not", "and", "or", "xor"]

var _answers: Dictionary = {}
var _graphs: Dictionary = {}
var _editor: CircuitEditor
var _current_task := ""
var _task_buttons: Dictionary = {}
var _region_buttons: Dictionary = {}
var _quiz_buttons: Dictionary = {}
var _marks: Dictionary = {}
var _live: Label
var _pending_label: Label
var _power_edit: LineEdit
var _ratio_edit: LineEdit

func _build() -> void:
	_load_state()
	if lab_data.has("device"):
		_build_probe()
	elif lab_data.has("tasks"):
		_build_tasks()
	elif lab_data.has("power_model"):
		_build_power()
	else:
		_build_single()
	_refresh_marks()

# ---------------------------------------------------------------- 2.1 器件探针

func _build_probe() -> void:
	side.add_child(_section("判读练习"))
	for raw in lab_data.get("gate_cases", []):
		var c: Dictionary = raw
		if str(c.get("kind", "")) != "mosfet_region":
			continue
		_add_case_row(str(c.get("id", "")), str(c.get("title", "")))
	side.add_child(Ui.hline())
	side.add_child(Ui.wrap(str(lab_data.get("hint", "")), UiTheme.F_BODY, UiTheme.MUTED))
	side.add_child(Ui.spacer())
	side.add_child(Ui.ghost("重置作答", func(): _reset_probe()))

	center.add_child(_section("测点读数 · 按 Vgs/Vds 判工作区"))
	for raw in lab_data.get("gate_cases", []):
		var c: Dictionary = raw
		if str(c.get("kind", "")) == "mosfet_region":
			center.add_child(_probe_card(c))
	center.add_child(Ui.spacer())

	inspector.add_child(_section("本节判据"))
	for raw in lab_data.get("gate_cases", []):
		var c: Dictionary = raw
		inspector.add_child(Ui.wrap(str(c.get("title", "")), UiTheme.F_BODY, UiTheme.MUTED))
	for raw in lab_data.get("gate_cases", []):
		var q: Dictionary = raw
		if str(q.get("kind", "")) == "quiz":
			inspector.add_child(_quiz_card(q))
	_editor = null
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收", func(): _run(str(lab_data.get("title", lab_id))), true))
	_pending_label = Ui.wrap("", UiTheme.F_META, UiTheme.MUTED)
	inspector.add_child(_pending_label)
	_update_pending()

func _probe_card(c: Dictionary) -> Control:
	var cid := str(c.get("id", ""))
	var card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	var m := Ui.margin4(12, 8, 12, 8)
	card.add_child(m)
	var v := Ui.vbox(6)
	m.add_child(v)
	var readout := Ui.label(_probe_text(c), UiTheme.F_BODY, UiTheme.CHALK)
	v.add_child(readout)
	var brow := Ui.hbox(8)
	brow.add_child(Ui.label("判读", UiTheme.F_META, UiTheme.MUTED))
	var btns := []
	for key in REGION_KEYS:
		var k := str(key)
		var b := Ui.ghost(REGION_TEXT[k], func(): _set_region(cid, k))
		b.custom_minimum_size = Vector2(84, UiTheme.CONTROL_H)
		b.add_theme_font_size_override("font_size", UiTheme.F_BODY)
		brow.add_child(b)
		btns.append([k, b])
	brow.add_child(Ui.spacer())
	v.add_child(brow)
	_region_buttons[cid] = btns
	return card

func _probe_text(c: Dictionary) -> String:
	## 只给 Vgs/Vds 与模型算出的 Id，工作区留给玩家判读。
	var dev: Dictionary = c.get("device", lab_data.get("device", {}))
	var vgs := float(c.get("vgs", 0.0))
	var probes: Array = c.get("equal_id_vds", [])
	var out := "Vgs %.2f V" % vgs
	if probes.is_empty():
		var vds := float(c.get("vds", 0.0))
		out += " · Vds %.2f V · Id %.2f µA" % [vds, Ch02Checks.id_ua_of(vgs, vds, dev)]
	else:
		var parts := []
		for raw_v in probes:
			var d := float(raw_v)
			parts.append("Vds %.1f→%.0f µA" % [d, Ch02Checks.id_ua_of(vgs, d, dev)])
		out += " · " + " / ".join(PackedStringArray(parts))
	return out

func _set_region(cid: String, region: String) -> void:
	_answers[cid] = region
	_refresh_choices()
	_save_state()

func _reset_probe() -> void:
	_answers.clear()
	_refresh_choices()
	_save_state()
	EventBus.toast("已清空本节作答", "ok")

# ---------------------------------------------------------------- 2.2 单图反相器

func _build_single() -> void:
	side.add_child(_section("本节判据"))
	for raw in lab_data.get("gate_cases", []):
		var c: Dictionary = raw
		_add_case_row(str(c.get("id", "")), str(c.get("title", "")))
	side.add_child(Ui.hline())
	side.add_child(Ui.wrap(str(lab_data.get("body", "")), UiTheme.F_BODY, UiTheme.MUTED))
	side.add_child(Ui.spacer())

	var target_card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	target_card.custom_minimum_size = Vector2(0, 40)
	center.add_child(target_card)
	var tm := Ui.margin4(12, 4, 12, 4)
	target_card.add_child(tm)
	var trow := Ui.hbox(12)
	tm.add_child(trow)
	trow.add_child(Ui.label("输入 a → 输出 out", UiTheme.F_BODY, UiTheme.CHALK))
	trow.add_child(Ui.spacer())
	trow.add_child(Ui.muted("三值传播也验收", UiTheme.F_META))

	var cap := int(lab_data.get("max_gates", 4))
	center.add_child(_editor_card([{"id": "a", "label": "A"}], ["not"], cap))

	var pal := Ui.hbox(8)
	pal.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	pal.add_child(Ui.label("调色板", UiTheme.F_META, UiTheme.MUTED))
	var nb := Ui.ghost("NOT", func(): _editor.set_selected_gate("not"))
	nb.custom_minimum_size = Vector2(76, UiTheme.CONTROL_H)
	pal.add_child(nb)
	pal.add_child(Ui.spacer())
	var hint := Ui.muted("放 1 个 NOT：a 接输入、输出接 out", UiTheme.F_BODY)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pal.add_child(hint)
	center.add_child(pal)
	center.add_child(Ui.spacer())

	inspector.add_child(_section("OUT 当前值"))
	_live = Ui.mono("X", UiTheme.F_BODY_LG, UiTheme.MUTED)
	inspector.add_child(_live)
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收", func(): _run(str(lab_data.get("title", lab_id))), true))
	_pending_label = Ui.wrap("", UiTheme.F_META, UiTheme.MUTED)
	inspector.add_child(_pending_label)
	_update_pending()

func _editor_card(inputs: Array, palette: Array, max_gates: int) -> Control:
	var card := Ui.card_tight(UiTheme.BOARD_SUNK, UiTheme.LINE)
	card.custom_minimum_size = Vector2(0, 418)
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	_editor = CircuitEditor.new()
	_editor.custom_minimum_size = Vector2(696, 416)
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.setup(inputs, [{"id": "out", "label": "OUT"}], palette, max_gates)
	_editor.changed.connect(_on_editor_changed)
	card.add_child(_editor)
	return card

# ---------------------------------------------------------------- 2.3 NAND 多任务

func _build_tasks() -> void:
	side.add_child(_section("任务"))
	side.add_child(Ui.wrap(str(lab_data.get("body", "")), UiTheme.F_BODY, UiTheme.MUTED))
	side.add_child(Ui.hline())
	for raw in _all_tasks():
		var t: Dictionary = raw
		var tid := str(t.get("id", ""))
		var b := Ui.button(str(t.get("title", tid)), func(): _switch_task(tid), false)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
		b.add_theme_font_size_override("font_size", UiTheme.F_LABEL)
		side.add_child(b)
		_task_buttons[tid] = b
	side.add_child(Ui.spacer())
	side.add_child(Ui.ghost("重置当前任务", func(): _reset_task()))

	var target_card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	target_card.custom_minimum_size = Vector2(0, 40)
	center.add_child(target_card)
	var tm := Ui.margin4(12, 4, 12, 4)
	target_card.add_child(tm)
	var trow := Ui.hbox(12)
	tm.add_child(trow)
	trow.add_child(Ui.label("目标", UiTheme.F_META, UiTheme.MUTED))
	var target_label := Ui.label("", UiTheme.F_BODY, UiTheme.CHALK)
	target_label.name = "TargetLabel"
	trow.add_child(target_label)
	trow.add_child(Ui.spacer())
	trow.add_child(Ui.muted("门上限 %d" % int(lab_data.get("max_gates", 6)), UiTheme.F_META))

	var cap := int(lab_data.get("max_gates", 6))
	center.add_child(_editor_card([{"id": "a", "label": "A"}, {"id": "b", "label": "B"}], ["nand"], cap))

	var pal := Ui.hbox(8)
	pal.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	pal.add_child(Ui.label("调色板", UiTheme.F_META, UiTheme.MUTED))
	var nb := Ui.ghost("NAND", func(): _editor.set_selected_gate("nand"))
	nb.custom_minimum_size = Vector2(76, UiTheme.CONTROL_H)
	pal.add_child(nb)
	pal.add_child(Ui.spacer())
	var hint := Ui.muted("只用 NAND；点输出端口再点输入端口连线", UiTheme.F_BODY)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pal.add_child(hint)
	center.add_child(pal)
	center.add_child(Ui.spacer())

	inspector.add_child(_section("OUT 当前值"))
	_live = Ui.mono("X", UiTheme.F_BODY_LG, UiTheme.MUTED)
	inspector.add_child(_live)
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收", func(): _run(str(lab_data.get("title", lab_id))), true))
	_pending_label = Ui.wrap("", UiTheme.F_META, UiTheme.MUTED)
	inspector.add_child(_pending_label)

	_switch_task(_current_task if not _current_task.is_empty() else str(_all_tasks()[0].get("id", "")))
	_update_pending()

func _all_tasks() -> Array:
	var out := []
	for raw in lab_data.get("tasks", []):
		out.append(raw)
	return out

func _task_by_id(tid: String) -> Dictionary:
	for raw in _all_tasks():
		var t: Dictionary = raw
		if str(t.get("id", "")) == tid:
			return t
	return {}

func _switch_task(tid: String) -> void:
	if tid.is_empty() or _editor == null:
		return
	if not _current_task.is_empty() and _current_task != tid:
		_save_current()
	var task := _task_by_id(tid)
	var inputs := []
	for iid in task.get("input_ids", ["a", "b"]):
		inputs.append({"id": str(iid), "label": str(iid).to_upper()})
	_current_task = tid
	_editor.setup(inputs, [{"id": "out", "label": "OUT"}], task.get("palette", ["nand"]), int(lab_data.get("max_gates", 6)))
	if _graphs.has(tid) and _graphs[tid] is CircuitGraph:
		_editor.load_dict((_graphs[tid] as CircuitGraph).to_dict())
	var tl := _center_find("TargetLabel") as Label
	if tl != null:
		tl.text = "OUT = %s" % _target_expr(str(task.get("target", "")))
	for key in _task_buttons.keys():
		_style_choice(_task_buttons[key], str(key) == tid)
	_on_editor_changed()

func _target_expr(target: String) -> String:
	match target:
		"not": return "NOT a"
		"and": return "a AND b"
		"or": return "a OR b"
		"xor": return "a XOR b"
		"nand": return "NOT (a AND b)"
	return target

func _center_find(node_name: String) -> Node:
	if center == null:
		return null
	return center.find_child(node_name, true, false)

func _reset_task() -> void:
	if _current_task.is_empty():
		return
	var tid := _current_task
	_graphs.erase(tid)
	_current_task = ""
	_switch_task(tid)

# ---------------------------------------------------------------- 2.5 功耗与四门板

func _build_power() -> void:
	var formula: Dictionary = lab_data.get("power_model", {})
	side.add_child(_section("手算 + 布线"))
	side.add_child(Ui.wrap(str(lab_data.get("body", "")), UiTheme.F_BODY, UiTheme.MUTED))
	side.add_child(Ui.hline())
	for raw in lab_data.get("gate_cases", []):
		var c: Dictionary = raw
		_add_case_row(str(c.get("id", "")), str(c.get("title", "")))
	side.add_child(Ui.spacer())
	side.add_child(Ui.wrap(str(lab_data.get("hint", "")), UiTheme.F_BODY, UiTheme.MUTED))

	var target_card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	target_card.custom_minimum_size = Vector2(0, 40)
	center.add_child(target_card)
	var tm := Ui.margin4(12, 4, 12, 4)
	target_card.add_child(tm)
	var trow := Ui.hbox(10)
	tm.add_child(trow)
	trow.add_child(Ui.label("四门板", UiTheme.F_META, UiTheme.MUTED))
	var target_label := Ui.label("OUT = NOT a", UiTheme.F_BODY, UiTheme.CHALK)
	target_label.name = "TargetLabel"
	trow.add_child(target_label)
	trow.add_child(Ui.spacer())
	trow.add_child(Ui.muted("%d 槽 · 总门数 ≤ %d" % [int(lab_data.get("board", {}).get("pcb_slots", 4)), Ch02Checks.BUILD_AREA_GATE_BUDGET], UiTheme.F_META))

	var cap := int(lab_data.get("max_gates", Ch02Checks.BUILD_AREA_GATE_BUDGET))
	center.add_child(_editor_card([{"id": "a", "label": "A"}], ["not", "and", "or"], cap))

	var pal := Ui.hbox(8)
	pal.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	pal.add_child(Ui.label("板位", UiTheme.F_META, UiTheme.MUTED))
	for name in BOARD_TARGETS:
		var tname := str(name)
		var b := Ui.ghost(tname.to_upper(), func(): _switch_board(tname))
		b.custom_minimum_size = Vector2(66, UiTheme.CONTROL_H)
		pal.add_child(b)
		_task_buttons[tname] = b
	pal.add_child(Ui.spacer())
	var hint := Ui.muted("每块板单独布线，验收看行为与总门数", UiTheme.F_BODY)
	hint.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pal.add_child(hint)
	center.add_child(pal)
	center.add_child(Ui.spacer())

	inspector.add_child(_section("手算作答"))
	var params_text := "P = α·C·V²·f；α=%.2f，C=%.0f pF，V=%.1f V，f=%.2f MHz" % [
		float(formula.get("alpha", 0.5)), float(formula.get("c_f", 1e-11)) * 1e12,
		float(formula.get("vdd", 3.3)), float(formula.get("f_hz", 1e6)) / 1e6]
	inspector.add_child(Ui.wrap(params_text, UiTheme.F_BODY, UiTheme.MUTED))
	_power_edit = _answer_edit("P（mW）", "T2.5-1")
	_ratio_edit = _answer_edit("降频后功耗比", "T2.5-2")
	for raw in lab_data.get("gate_cases", []):
		var q: Dictionary = raw
		if str(q.get("kind", "")) == "quiz":
			inspector.add_child(Ui.hline())
			inspector.add_child(Ui.wrap(str(q.get("quiz", {}).get("question", "")), UiTheme.F_BODY, UiTheme.CHALK))
			var opts := _quiz_options(q)
			for ob in opts:
				inspector.add_child(ob)
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收", func(): _run(str(lab_data.get("title", lab_id))), true))
	_pending_label = Ui.wrap("", UiTheme.F_META, UiTheme.MUTED)
	inspector.add_child(_pending_label)

	_switch_board(_current_task if not _current_task.is_empty() and BOARD_TARGETS.has(_current_task) else "not")
	_update_pending()

func _answer_edit(caption: String, cid: String) -> LineEdit:
	var row := Ui.hbox(8)
	row.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	inspector.add_child(row)
	var l := Ui.label(caption, UiTheme.F_BODY, UiTheme.MUTED)
	l.custom_minimum_size = Vector2(96, 0)
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(l)
	var e := LineEdit.new()
	e.focus_mode = Control.FOCUS_ALL
	e.custom_minimum_size = Vector2(0, UiTheme.CONTROL_H)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	e.add_theme_font_size_override("font_size", UiTheme.F_BODY)
	e.text = "" if not _answers.has(cid) else str(_answers[cid])
	e.text_changed.connect(func(t: String): _on_answer_changed(t, cid))
	row.add_child(e)
	return e

func _on_answer_changed(t: String, cid: String) -> void:
	var s := t.strip_edges()
	if s.is_empty() or not s.is_valid_float():
		_answers.erase(cid)
	else:
		_answers[cid] = s.to_float()
	_save_state()

func _switch_board(tname: String) -> void:
	if _editor == null:
		return
	if not _current_task.is_empty() and _current_task != tname:
		_save_current()
	_current_task = tname
	var inputs := [{"id": "a", "label": "A"}] if tname == "not" else [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}]
	_editor.setup(inputs, [{"id": "out", "label": "OUT"}], ["not", "and", "or"], int(lab_data.get("max_gates", Ch02Checks.BUILD_AREA_GATE_BUDGET)))
	if _graphs.has(tname) and _graphs[tname] is CircuitGraph:
		_editor.load_dict((_graphs[tname] as CircuitGraph).to_dict())
	var tl := _center_find("TargetLabel") as Label
	if tl != null:
		tl.text = "OUT = %s" % _target_expr(tname)
	for key in _task_buttons.keys():
		_style_choice(_task_buttons[key], str(key) == tname)
	_on_editor_changed()

# ---------------------------------------------------------------- 判定与状态

func _run(title: String) -> void:
	_save_state()
	var res := Ch02Checks.run(lab_id, lab_data, {"graph": _run_graph(), "graphs": _graphs, "answers": _answers})
	var rep: GateReport = res.get("report", null)
	show_report(rep)
	_update_pending()
	_refresh_marks()
	if pass_report(rep):
		EventBus.toast("%s 验收全部通过" % title, "ok")
	else:
		EventBus.toast("%s 仍有 gate 未通过" % title, "warn")

func _run_graph() -> CircuitGraph:
	## 只有单图实验（2.2）把当前编辑器当 `graph`；多图实验一律走 `graphs`。
	if _editor == null or lab_data.has("tasks") or lab_data.has("power_model"):
		return null
	return CircuitGraph.from_dict(_editor.to_dict())

func _update_pending() -> void:
	if _pending_label == null:
		return
	var _r := Ch02Checks.run(lab_id, lab_data, {"graph": _run_graph(), "graphs": _graphs, "answers": _answers})
	var pending: Array = _r.get("pending", [])
	if pending.is_empty():
		_pending_label.text = ""
	else:
		_pending_label.text = "%d 项待仿真层支持：%s" % [pending.size(), str(pending[0].get("id", ""))]
	_pending_label.visible = not pending.is_empty()

func _add_case_row(cid: String, title: String) -> void:
	var row := _task_row(title)
	side.add_child(row[0])
	_marks[cid] = row[1]

func _refresh_marks() -> void:
	for cid in _marks.keys():
		_mark(_marks[cid], gate_passed(str(cid)) or is_done())
	_refresh_choices()

func _refresh_choices() -> void:
	for cid in _region_buttons.keys():
		var got := str(_answers.get(cid, ""))
		for pair in _region_buttons[cid]:
			_style_choice(pair[1], str(pair[0]) == got)
	for cid in _quiz_buttons.keys():
		var got := int(_answers.get(cid, -1))
		for pair in _quiz_buttons[cid]:
			_style_choice(pair[1], int(pair[0]) == got)

func _style_choice(b: Button, on: bool) -> void:
	if b == null:
		return
	b.add_theme_stylebox_override("normal", UiTheme.flat(UiTheme.CHALK if on else UiTheme.BOARD_HIGH, UiTheme.CHALK if on else UiTheme.LINE))
	b.add_theme_color_override("font_color", UiTheme.INK if on else UiTheme.CHALK)

func _quiz_card(c: Dictionary) -> Control:
	var quiz: Dictionary = c.get("quiz", {})
	var card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	var m := Ui.margin4(12, 8, 12, 8)
	card.add_child(m)
	var v := Ui.vbox(6)
	m.add_child(v)
	v.add_child(Ui.wrap(str(quiz.get("question", "")), UiTheme.F_BODY, UiTheme.CHALK))
	for ob in _quiz_options(c):
		v.add_child(ob)
	return card

func _quiz_options(c: Dictionary) -> Array:
	var cid := str(c.get("id", ""))
	var quiz: Dictionary = c.get("quiz", {})
	var nodes := []
	var btns := []
	var idx := 0
	for raw in quiz.get("options", []):
		var i := idx
		## 选项写成"字母按钮 + 可换行正文"：窄栏也不撑破布局，正文不被截断。
		var row := Ui.hbox(6)
		row.mouse_filter = Control.MOUSE_FILTER_PASS
		var b := Ui.ghost(String.chr(65 + i), func(): _set_answer(cid, i))
		b.custom_minimum_size = Vector2(30, UiTheme.CONTROL_H)
		b.add_theme_font_size_override("font_size", UiTheme.F_BODY)
		b.tooltip_text = str(raw)
		row.add_child(b)
		var t := Ui.wrap(str(raw), UiTheme.F_BODY, UiTheme.CHALK)
		t.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		t.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(t)
		nodes.append(row)
		btns.append([i, b])
		idx += 1
	_quiz_buttons[cid] = btns
	return nodes

func _set_answer(cid: String, value: int) -> void:
	_answers[cid] = value
	_refresh_choices()
	_save_state()

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

func _save_current() -> void:
	if _current_task.is_empty() or _editor == null:
		return
	_graphs[_current_task] = CircuitGraph.from_dict(_editor.to_dict())

func _save_state() -> void:
	if _editor != null and not _current_task.is_empty():
		_graphs[_current_task] = CircuitGraph.from_dict(_editor.to_dict())
	var docs := {}
	for k in _graphs.keys():
		if _graphs[k] is CircuitGraph:
			docs[str(k)] = (_graphs[k] as CircuitGraph).to_dict()
	save_state({"answers": _answers.duplicate(), "graphs": docs, "current": _current_task})

func _load_state() -> void:
	var st := load_state()
	if st.is_empty():
		return
	var ans: Variant = st.get("answers", null)
	if ans is Dictionary:
		_answers = (ans as Dictionary).duplicate()
	var docs: Variant = st.get("graphs", null)
	if docs is Dictionary:
		for k in (docs as Dictionary).keys():
			_graphs[str(k)] = CircuitGraph.from_dict((docs as Dictionary)[k])
	_current_task = str(st.get("current", ""))

# ---------------------------------------------------------------- 走查用脚本解

func scripted_solve() -> bool:
	match lab_id:
		"transistor":
			for raw in lab_data.get("gate_cases", []):
				var c: Dictionary = raw
				var cid := str(c.get("id", ""))
				if str(c.get("kind", "")) == "quiz":
					_answers[cid] = int(c.get("quiz", {}).get("answer", 0))
				elif str(c.get("kind", "")) == "mosfet_region":
					var dev: Dictionary = c.get("device", lab_data.get("device", {}))
					_answers[cid] = Ch02Checks.region_of(float(c.get("vgs", 0.0)), float(c.get("vds", 0.0)), dev)
		"inverter":
			_graphs["single"] = _not_graph("a")
			if _editor == null:
				_editor = CircuitEditor.new()
			_editor.load_dict((_graphs["single"] as CircuitGraph).to_dict())
		"nand":
			for raw in _all_tasks():
				var t: Dictionary = raw
				_graphs[str(t.get("id", ""))] = _nand_task_graph(t)
		"power":
			_answers["T2.5-1"] = Ch02Checks.power_mw(lab_data.get("power_model", {}))
			_answers["T2.5-2"] = 0.5
			for raw in lab_data.get("gate_cases", []):
				var c: Dictionary = raw
				if str(c.get("kind", "")) == "quiz":
					_answers[str(c.get("id", ""))] = int(c.get("quiz", {}).get("answer", 0))
			for name in BOARD_TARGETS:
				_graphs[str(name)] = _board_graph(str(name))
	_run(str(lab_data.get("title", lab_id)))
	return is_done()

func _not_graph(input_id: String) -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input(input_id, input_id.to_upper(), Vector2(40, 139))
	g.add_output("out", "OUT", Vector2(590, 139))
	g.add_gate("g1", LogicGates.Type.NOT, "NOT", Vector2(330, 139))
	g.link(input_id, "g1", 0)
	g.link("g1", "out", 0)
	return g

func _nand_task_graph(task: Dictionary) -> CircuitGraph:
	var g := CircuitGraph.new()
	var ids: Array = task.get("input_ids", ["a", "b"])
	for i in ids.size():
		var iid := str(ids[i])
		g.add_input(iid, iid.to_upper(), Vector2(40, 70 + i * 180))
	g.add_output("out", "OUT", Vector2(590, 139))
	var target := str(task.get("target", ""))
	var a := str(ids[0])
	if target == "nand" or target == "and" or target == "xor":
		g.add_gate("n1", LogicGates.Type.NAND, "NAND", Vector2(330, 139))
		g.link(a, "n1", 0)
		g.link(str(ids[1]) if ids.size() > 1 else a, "n1", 1)
		if target == "nand":
			g.link("n1", "out", 0)
		else:
			g.add_gate("n2", LogicGates.Type.NAND, "NAND", Vector2(460, 139))
			g.link("n1", "n2", 0)
			g.link("n1", "n2", 1)
			g.link("n2", "out", 0)
		return g
	if target == "not":
		g.add_gate("n1", LogicGates.Type.NAND, "NAND", Vector2(330, 139))
		g.link(a, "n1", 0)
		g.link(a, "n1", 1)
		g.link("n1", "out", 0)
		return g
	# or：先各自取非，再 NAND
	g.add_gate("n1", LogicGates.Type.NAND, "NAND", Vector2(210, 60))
	g.add_gate("n2", LogicGates.Type.NAND, "NAND", Vector2(210, 220))
	g.add_gate("n3", LogicGates.Type.NAND, "NAND", Vector2(420, 139))
	g.link(a, "n1", 0); g.link(a, "n1", 1)
	g.link(str(ids[1]), "n2", 0); g.link(str(ids[1]), "n2", 1)
	g.link("n1", "n3", 0); g.link("n2", "n3", 1)
	g.link("n3", "out", 0)
	return g

func _board_graph(target: String) -> CircuitGraph:
	var g := CircuitGraph.new()
	g.add_input("a", "A", Vector2(40, 70))
	var two := target != "not"
	if two:
		g.add_input("b", "B", Vector2(40, 250))
	g.add_output("out", "OUT", Vector2(590, 139))
	var gt := LogicGates.Type.NOT
	if target == "and":
		gt = LogicGates.Type.AND
	elif target == "or":
		gt = LogicGates.Type.OR
	elif target == "xor":
		gt = LogicGates.Type.XOR
	g.add_gate("g1", gt, LogicGates.gate_key(gt), Vector2(330, 139))
	g.link("a", "g1", 0)
	if two:
		g.link("b", "g1", 1)
	g.link("g1", "out", 0)
	return g
