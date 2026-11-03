extends LabBase

## 1.4 门级：用 AND/OR/NOT 搭出目标函数。行为黑盒验收，允许多解。

var _editor: CircuitEditor
var _graphs: Dictionary = {}
var _current_task := ""
var _encapsulated := false
var _report_box: VBoxContainer
var _live: Label
var _task_buttons: Dictionary = {}
var _task_hint: Label

func _build() -> void:
	var root := Ui.vbox(8)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(_build_header(str(lab_data.get("title", "门级")), str(lab_data.get("subtitle", ""))))
	root.add_child(_body_card(str(lab_data.get("body", ""))))
	root.add_child(_hint_card(str(lab_data.get("hint", ""))))

	var row := Ui.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	var left := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
	left.custom_minimum_size = Vector2(232, 0)
	row.add_child(left)
	var lm := Ui.margin4(8, 8, 8, 8)
	left.add_child(lm)
	var lcol := Ui.vbox(5)
	lm.add_child(lcol)
	lcol.add_child(Ui.label("任务", 11, UiTheme.MUTED))
	_task_hint = Ui.wrap("", 10, UiTheme.MUTED)
	_task_hint.custom_minimum_size = Vector2(0, 40)
	lcol.add_child(_task_hint)
	lcol.add_child(Ui.hline())
	for raw in _all_tasks():
		var t: Dictionary = raw
		var tid := str(t.get("id", ""))
		var b := Ui.button(str(t.get("title", tid)), func(): _switch_task(tid), false)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(0, 32)
		lcol.add_child(b)
		_task_buttons[tid] = b
	lcol.add_child(Ui.spacer())
	lcol.add_child(Ui.hline())
	lcol.add_child(Ui.label("调色板", 11, UiTheme.MUTED))
	var pal := Ui.hbox(5)
	lcol.add_child(pal)
	for g in ["not", "and", "or"]:
		var gs := str(g)
		pal.add_child(Ui.ghost(gs.to_upper(), func(): _editor.set_selected_gate(gs)))
	_enc_btn = Ui.button("封装 MY-XOR", func(): _encapsulate(), false)
	lcol.add_child(_enc_btn)
	_enc_label = Ui.muted("未封装", 10)
	lcol.add_child(_enc_label)
	lcol.add_child(Ui.ghost("重置当前任务", func(): _reset_task()))

	var right := Ui.vbox(6)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(right)
	var editor_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	editor_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(editor_card)
	var em := Ui.margin4(4, 4, 4, 4)
	editor_card.add_child(em)
	_editor = CircuitEditor.new()
	_editor.custom_minimum_size = Vector2(0, 300)
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.changed.connect(_on_editor_changed)
	em.add_child(_editor)

	var bar := Ui.hbox(8)
	right.add_child(bar)
	_live = Ui.mono("等待搭建", 12, UiTheme.MUTED)
	bar.add_child(_live)
	bar.add_child(Ui.spacer())
	bar.add_child(Ui.button("运行验收 T1.4", func(): _run_cases(), true))

	_report_box = Ui.vbox(2)
	root.add_child(_report_box)

	_load_state()
	_switch_task(_current_task if not _current_task.is_empty() else str(_all_tasks()[0].get("id", "")))

func _all_tasks() -> Array:
	## 配置里的 4 个任务 + 从 xor 任务派生的「第二结构」任务。
	var out := []
	var xor_task := {}
	for raw in lab_data.get("tasks", []):
		var t: Dictionary = raw
		out.append(t)
		if str(t.get("target", "")) == "xor":
			xor_task = t
	if xor_task.is_empty():
		return out
	var second := {
		"id": "t_xor_2",
		"title": "任务 E：XOR 第二结构",
		"target": "xor",
		"palette": xor_task.get("palette", ["not", "and", "or"]),
		"input_ids": xor_task.get("input_ids", ["a", "b"]),
		"second_of": str(xor_task.get("id", "t_xor")),
	}
	out.append(second)
	return out

func _task_by_id(id: String) -> Dictionary:
	for raw in _all_tasks():
		var t: Dictionary = raw
		if str(t.get("id", "")) == id:
			return t
	return {}

var _enc_btn: Button
var _enc_label: Label

func _switch_task(id: String) -> void:
	if id.is_empty():
		return
	_save_current()
	var task := _task_by_id(id)
	var inputs := []
	for iid in task.get("input_ids", ["a", "b"]):
		inputs.append({"id": str(iid), "label": str(iid).to_upper()})
	_editor.setup(inputs, [{"id": "out", "label": "OUT"}], task.get("palette", ["not", "and", "or"]), int(lab_data.get("max_gates", 12)))
	if _graphs.has(id):
		_editor.load_dict(_graphs[id])
	_current_task = id
	_task_hint.text = "%s\n目标：%s；验收只看 a/b → out 的行为。" % [str(task.get("title", id)), str(task.get("target", ""))]
	for key in _task_buttons.keys():
		var b: Button = _task_buttons[key]
		b.modulate = Color(1, 1, 1, 1) if str(key) == id else Color(1, 1, 1, 0.65)
	_on_editor_changed()
	_update_enc_label()

func _save_current() -> void:
	if _current_task.is_empty() or _editor == null:
		return
	_graphs[_current_task] = _editor.to_dict()

func _on_editor_changed() -> void:
	var ev := _editor.evaluate()
	var values: Dictionary = ev.get("values", {})
	var out := str(values.get("out", "X"))
	var ok := bool(ev.get("ok", true))
	_live.text = "OUT = %s · 门 %d · %s" % [out, _editor.gate_count(), "无环" if ok else "存在环"]
	_live.add_theme_color_override("font_color", UiTheme.OK if out == "1" else (UiTheme.DANGER if out == "X" else UiTheme.MUTED))
	_save_state()

func _encapsulate() -> void:
	_save_current()
	var g: CircuitGraph = _graphs.get("t_xor", null)
	if g == null:
		EventBus.toast("先完成任务 D（XOR）再封装", "warn")
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
	if _enc_label == null:
		return
	_enc_label.text = "已封装 MY-XOR" if _encapsulated else "未封装"
	_enc_label.add_theme_color_override("font_color", UiTheme.OK if _encapsulated else UiTheme.MUTED)
	if _enc_btn != null:
		_enc_btn.disabled = _encapsulated

func _reset_task() -> void:
	if _current_task.is_empty():
		return
	var id := _current_task
	_graphs.erase(id)
	_current_task = ""
	_switch_task(id)

func _run_cases() -> void:
	_save_current()
	var rep := LabChecks.gate(lab_data, _graphs, {"encapsulated": _encapsulated})
	_show_report(rep)
	if pass_report(rep):
		EventBus.toast("1.4 门级 gate 全部通过", "ok")
	else:
		EventBus.toast("仍有 gate 未通过：三基础门、XOR 延迟、封装、第二结构", "warn")

func _show_report(rep: GateReport) -> void:
	for c in _report_box.get_children():
		c.queue_free()
	for raw in rep.cases:
		var c: Dictionary = raw
		var ok := bool(c.get("ok", false))
		var color := UiTheme.OK if ok else UiTheme.DANGER
		_report_box.add_child(Ui.label("%s %s  %s" % ["✓" if ok else "✗", str(c.get("id", "")), str(c.get("detail", ""))], 10, color))

func _save_state() -> void:
	if _editor != null and not _current_task.is_empty():
		_graphs[_current_task] = _editor.to_dict()
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
