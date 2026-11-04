extends LabBase

## 1.6 半加器：SUM = A ⊕ B，CARRY = A ∧ B；行为黑盒 + 三值随机。

var _editor: CircuitEditor
var _encapsulated := false
var _live: Label
var _enc_label: Label
var _enc_btn: Button

func _build() -> void:
	# ---- 左栏：任务 / 调色板 / 封装 ----
	_install_reader(_reader_slot, 14, UiTheme.F_LABEL)
	side.add_child(_section("任务"))
	side.add_child(_hint_card(str(lab_data.get("hint", ""))))
	side.add_child(Ui.hline())
	side.add_child(_section("调色板"))
	var pal := GridContainer.new()
	pal.columns = 2
	pal.add_theme_constant_override("h_separation", 6)
	pal.add_theme_constant_override("v_separation", 6)
	side.add_child(pal)
	for g in lab_data.get("palette", ["not", "and", "or", "xor"]):
		var gs := str(g)
		pal.add_child(Ui.ghost(gs.to_upper(), func(): _editor.set_selected_gate(gs)))
	side.add_child(Ui.spacer())
	side.add_child(Ui.ghost("清空电路", func(): _reset()))

	# ---- 中栏：696×416 编辑器 ----
	var editor_card := Ui.card_tight(UiTheme.BOARD_SUNK, UiTheme.LINE)
	editor_card.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	editor_card.custom_minimum_size = Vector2(0, 418)
	center.add_child(editor_card)
	_editor = CircuitEditor.new()
	_editor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.changed.connect(_on_editor_changed)
	editor_card.add_child(_editor)
	center.add_child(Ui.wrap("输入 A/B 在左，输出 SUM/CARRY 在右；点输出端口再点输入端口连线。点门体循环切类型，右键删门或断线。", UiTheme.F_BODY))
	center.add_child(Ui.spacer())

	# ---- 右栏：实时输出 + 验收 ----
	inspector.add_child(_section("实时输出"))
	_live = Ui.mono("SUM = X\nCARRY = X", UiTheme.F_BODY_LG, UiTheme.MUTED)
	_live.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(_live)
	inspector.add_child(Ui.hline())
	inspector.add_child(_section("封装"))
	_enc_btn = Ui.button("封装 HALF-ADDER", func(): _encapsulate(), false)
	inspector.add_child(_enc_btn)
	_enc_label = Ui.label("未封装", UiTheme.F_META, UiTheme.MUTED)
	_enc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspector.add_child(_enc_label)
	inspector.add_child(Ui.hline())
	inspector.add_child(_section("验收"))
	inspector.add_child(Ui.wrap("真值四行、无环、封装、含 X 随机；全过才记账。", UiTheme.F_META, UiTheme.MUTED))
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收 T1.6", func(): _run_cases(), true))

	_load_state()

func _on_editor_changed() -> void:
	var ev := _editor.evaluate()
	var values: Dictionary = ev.get("values", {})
	var s := str(values.get("sum", "X"))
	var c := str(values.get("carry", "X"))
	_live.text = "SUM = %s\nCARRY = %s\n门 %d 个" % [s, c, _editor.gate_count()]
	_live.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if s != "X" and c != "X" else UiTheme.MUTED)
	_save_state()

func _encapsulate() -> void:
	var res := BlackBox.check_outputs(_editor.graph, ["a", "b"], ["sum", "carry"], BlackBox.half_adder_rows())
	if not bool(res.get("ok", false)):
		EventBus.toast("四行真值未通过，不能封装", "warn")
		return
	_encapsulated = true
	_enc_label.text = "已封装 HALF-ADDER（端口 A/B/SUM/CARRY）"
	_enc_label.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT)
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
	show_report(rep)
	if pass_report(rep):
		EventBus.toast("1.6 半加器 gate 全部通过", "ok")
	else:
		EventBus.toast("仍有 gate 未通过：真值、延迟、封装、含 X 随机", "warn")

func _save_state() -> void:
	save_state({"graph": _editor.to_dict() if _editor != null else {}, "encapsulated": _encapsulated})

func _load_state() -> void:
	var st := load_state()
	_setup_editor()
	if st.is_empty():
		_on_editor_changed()
		return
	var doc: Variant = st.get("graph", null)
	if doc is Dictionary and not (doc as Dictionary).is_empty():
		_editor.load_dict(doc)
	_encapsulated = bool(st.get("encapsulated", false))
	if _encapsulated:
		_enc_label.text = "已封装 HALF-ADDER"
		_enc_label.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT)
		_enc_btn.disabled = true
	_on_editor_changed()

func scripted_solve() -> bool:
	## 脚本走查：搭出 SUM=A⊕B、CARRY=A∧B 的正确电路，再走真实封装/验收/发奖链路。
	var g := CircuitGraph.new()
	g.add_input("a", "A", Vector2(40, 70))
	g.add_input("b", "B", Vector2(40, 250))
	g.add_gate("g_xor", LogicGates.Type.XOR, "XOR", Vector2(250, 70))
	g.add_gate("g_and", LogicGates.Type.AND, "AND", Vector2(250, 250))
	g.add_output("sum", "SUM", Vector2(590, 139))
	g.add_output("carry", "CARRY", Vector2(590, 300))
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
