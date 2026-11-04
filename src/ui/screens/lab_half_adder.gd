extends LabBase

## 1.6 半加器：SUM = A ⊕ B，CARRY = A ∧ B；行为黑盒 + 三值随机。

var _editor: CircuitEditor
var _encapsulated := false
var _live: Label
var _report_box: VBoxContainer
var _enc_btn: Button
var _enc_label: Label

func _build() -> void:
	var root := Ui.vbox(8)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(_build_header(str(lab_data.get("title", "半加器")), str(lab_data.get("subtitle", ""))))
	root.add_child(_body_card(str(lab_data.get("body", ""))))
	root.add_child(_hint_card(str(lab_data.get("hint", ""))))

	var row := Ui.hbox(10)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	var editor_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	editor_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	editor_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(editor_card)
	var em := Ui.margin4(4, 4, 4, 4)
	editor_card.add_child(em)
	_editor = CircuitEditor.new()
	_editor.custom_minimum_size = Vector2(0, 330)
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.changed.connect(_on_editor_changed)
	em.add_child(_editor)

	var side := Ui.vbox(8)
	side.custom_minimum_size = Vector2(280, 0)
	row.add_child(side)

	var pal_card := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
	side.add_child(pal_card)
	var pm := Ui.margin4(10, 8, 10, 8)
	pal_card.add_child(pm)
	var pcol := Ui.vbox(5)
	pm.add_child(pcol)
	pcol.add_child(Ui.label("调色板", 11, UiTheme.MUTED))
	var pal := Ui.hbox(5)
	pcol.add_child(pal)
	for g in lab_data.get("palette", ["not", "and", "or", "xor"]):
		var gs := str(g)
		pal.add_child(Ui.ghost(gs.to_upper(), func(): _editor.set_selected_gate(gs)))
	pcol.add_child(Ui.muted("点门体可循环切换类型；右键删门/断线。", 10))

	var read_card := Ui.card(UiTheme.PANEL_3, UiTheme.BORDER, 8)
	side.add_child(read_card)
	var rm := Ui.margin4(10, 8, 10, 8)
	read_card.add_child(rm)
	var rcol := Ui.vbox(4)
	rm.add_child(rcol)
	rcol.add_child(Ui.label("实时输出", 11, UiTheme.MUTED))
	_live = Ui.mono("SUM = X  CARRY = X", 16, UiTheme.MUTED)
	rcol.add_child(_live)

	var enc_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	side.add_child(enc_card)
	var em2 := Ui.margin4(10, 8, 10, 8)
	enc_card.add_child(em2)
	var ecol := Ui.vbox(4)
	em2.add_child(ecol)
	_enc_btn = Ui.button("封装 HALF-ADDER", func(): _encapsulate(), false)
	ecol.add_child(_enc_btn)
	_enc_label = Ui.muted("未封装", 10)
	ecol.add_child(_enc_label)

	var bar := Ui.vbox(4)
	side.add_child(bar)
	bar.add_child(Ui.button("运行验收 T1.6", func(): _run_cases(), true))
	bar.add_child(Ui.ghost("清空电路", func(): _reset()))

	_report_box = Ui.vbox(2)
	root.add_child(_report_box)

	_load_state()

func _on_editor_changed() -> void:
	var ev := _editor.evaluate()
	var values: Dictionary = ev.get("values", {})
	var s := str(values.get("sum", "X"))
	var c := str(values.get("carry", "X"))
	_live.text = "SUM = %s  CARRY = %s · 门 %d" % [s, c, _editor.gate_count()]
	_live.add_theme_color_override("font_color", UiTheme.OK if s != "X" and c != "X" else UiTheme.MUTED)
	_save_state()

func _encapsulate() -> void:
	var res := BlackBox.check_outputs(_editor.graph, ["a", "b"], ["sum", "carry"], BlackBox.half_adder_rows())
	if not bool(res.get("ok", false)):
		EventBus.toast("四行真值未通过，不能封装", "warn")
		return
	_encapsulated = true
	_enc_label.text = "已封装 HALF-ADDER（端口 A/B/SUM/CARRY）"
	_enc_label.add_theme_color_override("font_color", UiTheme.OK)
	_enc_btn.disabled = true
	_save_state()
	EventBus.toast("已封装 HALF-ADDER；M1 仅复核行为，不产出可复用资源", "ok")

func _reset() -> void:
	_encapsulated = false
	_enc_label.text = "未封装"
	_enc_label.add_theme_color_override("font_color", UiTheme.MUTED)
	_enc_btn.disabled = false
	_setup_editor()
	_save_state()

func _setup_editor() -> void:
	_editor.setup(
		lab_data.get("inputs", [{"id": "a", "label": "A"}, {"id": "b", "label": "B"}]),
		lab_data.get("outputs", [{"id": "sum", "label": "SUM"}, {"id": "carry", "label": "CARRY"}]),
		lab_data.get("palette", ["not", "and", "or", "xor"]),
		int(lab_data.get("max_gates", 8))
	)

func _run_cases() -> void:
	var rep := LabChecks.half_adder(lab_data, _editor.graph, _encapsulated)
	_show_report(rep)
	if pass_report(rep):
		EventBus.toast("1.6 半加器 gate 全部通过", "ok")
	else:
		EventBus.toast("仍有 gate 未通过：真值、延迟、封装、含 X 随机", "warn")

func _show_report(rep: GateReport) -> void:
	for c in _report_box.get_children():
		c.queue_free()
	for raw in rep.cases:
		var c: Dictionary = raw
		var ok := bool(c.get("ok", false))
		var color := UiTheme.OK if ok else UiTheme.DANGER
		_report_box.add_child(Ui.label("%s %s  %s" % ["✓" if ok else "✗", str(c.get("id", "")), str(c.get("detail", ""))], 10, color))

func _save_state() -> void:
	save_state({"graph": _editor.to_dict() if _editor != null else {}, "encapsulated": _encapsulated})

func _load_state() -> void:
	var st := load_state()
	_setup_editor()
	if st.is_empty():
		return
	var doc: Variant = st.get("graph", null)
	if doc is Dictionary and not (doc as Dictionary).is_empty():
		_editor.load_dict(doc)
	_encapsulated = bool(st.get("encapsulated", false))
	if _encapsulated:
		_enc_label.text = "已封装 HALF-ADDER"
		_enc_label.add_theme_color_override("font_color", UiTheme.OK)
		_enc_btn.disabled = true
	_on_editor_changed()

func scripted_solve() -> bool:
	## 脚本走查：搭出 SUM=A⊕B、CARRY=A∧B 的正确电路，再走真实封装/验收/发奖链路。
	var g := CircuitGraph.new()
	g.add_input("a", "A", Vector2(40, 80))
	g.add_input("b", "B", Vector2(40, 200))
	g.add_gate("g_xor", LogicGates.Type.XOR, "XOR", Vector2(190, 80))
	g.add_gate("g_and", LogicGates.Type.AND, "AND", Vector2(190, 200))
	g.add_output("sum", "SUM", Vector2(340, 80))
	g.add_output("carry", "CARRY", Vector2(340, 200))
	g.link("a", "g_xor", 0)
	g.link("b", "g_xor", 1)
	g.link("g_xor", "sum", 0)
	g.link("a", "g_and", 0)
	g.link("b", "g_and", 1)
	g.link("g_and", "carry", 0)
	_editor.load_dict(g.to_dict())
	_on_editor_changed()
	_encapsulate()
	_run_cases()
	return is_done()
