extends LabBase

## 1.2 二进制：8 位开关、十进制/十六进制、覆盖 0–15、三进制辨析。

var _switches: BitSwitches
var _dec: Label
var _hex: Label
var _bin: Label
var _cov: Label
var _target_status: Dictionary = {}
var _quiz_answer := -1
var _quiz_status: Label
var _report_box: VBoxContainer
var _visited: Dictionary = {}
var _achieved: Dictionary = {}
var _value := 0

func _build() -> void:
	var root := Ui.vbox(10)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(_build_header(str(lab_data.get("title", "二进制")), str(lab_data.get("subtitle", ""))))
	root.add_child(_body_card(str(lab_data.get("body", ""))))
	root.add_child(_hint_card("提示：位权是 2 的幂；0x2F 只是十六进制写法，数值仍是 47。"))

	var row := Ui.hbox(12)
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(row)

	var sw_card := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
	sw_card.custom_minimum_size = Vector2(230, 0)
	row.add_child(sw_card)
	var sm := Ui.margin4(10, 8, 10, 8)
	sw_card.add_child(sm)
	var scol := Ui.vbox(6)
	sm.add_child(scol)
	scol.add_child(Ui.label("8 位开关", 12, UiTheme.TEXT))
	_switches = BitSwitches.new()
	_switches.setup(int(lab_data.get("bit_count", 8)), 0)
	_switches.changed.connect(_on_bits_changed)
	scol.add_child(_switches)

	var right := Ui.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(right)

	var read_card := Ui.card(UiTheme.PANEL_3, UiTheme.BORDER, 8)
	right.add_child(read_card)
	var rm := Ui.margin4(12, 9, 12, 9)
	read_card.add_child(rm)
	var rcol := Ui.vbox(4)
	rm.add_child(rcol)
	_dec = Ui.mono("0", 30, UiTheme.AMBER)
	rcol.add_child(_dec)
	_hex = Ui.mono("0x00", 18, UiTheme.ACCENT)
	rcol.add_child(_hex)
	_bin = Ui.mono("0000 0000", 14, UiTheme.MUTED)
	rcol.add_child(_bin)
	_cov = Ui.label("覆盖 0 / 16", 11, UiTheme.MUTED)
	rcol.add_child(_cov)

	var target_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	right.add_child(target_card)
	var tm := Ui.margin4(12, 8, 12, 8)
	target_card.add_child(tm)
	var tcol := Ui.vbox(4)
	tm.add_child(tcol)
	tcol.add_child(Ui.label("摆出目标值", 11, UiTheme.MUTED))
	for raw in lab_data.get("targets", []):
		var t: Dictionary = raw
		var arr := _task_row("%s（%s）" % [str(t.get("label", "")), str(t.get("hint", ""))])
		tcol.add_child(arr[0])
		_target_status[str(t.get("id", ""))] = arr[1]

	var quiz: Dictionary = lab_data.get("quiz", {})
	if not quiz.is_empty():
		var q_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
		right.add_child(q_card)
		var qm := Ui.margin4(12, 8, 12, 8)
		q_card.add_child(qm)
		var qcol := Ui.vbox(5)
		qm.add_child(qcol)
		qcol.add_child(Ui.label("辨析题", 11, UiTheme.MUTED))
		qcol.add_child(Ui.wrap(str(quiz.get("question", "")), 12, UiTheme.TEXT))
		var opts := GridContainer.new()
		opts.columns = 2
		qcol.add_child(opts)
		var options: Array = quiz.get("options", [])
		for i in options.size():
			var idx := i
			opts.add_child(Ui.ghost("%d. %s" % [i + 1, str(options[i])], func(): _pick_quiz(idx)))
		_quiz_status = Ui.label("未选择", 11, UiTheme.MUTED)
		qcol.add_child(_quiz_status)

	var run := Ui.hbox(8)
	right.add_child(run)
	run.add_child(Ui.button("运行验收 T1.2", func(): _run_cases(), true))

	_report_box = Ui.vbox(3)
	root.add_child(_report_box)
	_load_state()

func _on_bits_changed(v: int) -> void:
	_value = v
	_visited[str(v)] = true
	_dec.text = str(v)
	_hex.text = "0x%02X" % v
	_bin.text = _bin_text(v)
	var covered := 0
	for i in range(0, int(lab_data.get("coverage_max", 15)) + 1):
		if bool(_visited.get(str(i), false)):
			covered += 1
	_cov.text = "覆盖 %d / 16" % covered
	for raw in lab_data.get("targets", []):
		var t: Dictionary = raw
		var tid := str(t.get("id", ""))
		if v == int(t.get("value", -1)):
			_achieved[tid] = true
		if _target_status.has(tid):
			_mark(_target_status[tid], bool(_achieved.get(tid, false)), "已摆出")
	_save_state()

func _pick_quiz(idx: int) -> void:
	_quiz_answer = idx
	var quiz: Dictionary = lab_data.get("quiz", {})
	var answer := int(quiz.get("answer", -1))
	if idx == answer:
		_quiz_status.text = "正确：%s" % str(quiz.get("explain", "三进制需要三态器件，成本与噪声容限都更差。"))
		_quiz_status.add_theme_color_override("font_color", UiTheme.OK)
	else:
		_quiz_status.text = "再想想：题目问的是历史上的三进制计算机。"
		_quiz_status.add_theme_color_override("font_color", UiTheme.DANGER)
	_save_state()

func _run_cases() -> void:
	var rep := LabChecks.binary(lab_data, _visited, _achieved, _quiz_answer)
	_show_report(rep)
	if pass_report(rep):
		EventBus.toast("1.2 二进制 gate 全部通过", "ok")
	else:
		EventBus.toast("还有 gate 未通过：覆盖 0–15、摆出两个目标、答对辨析题", "warn")

func _bin_text(v: int) -> String:
	var nibbles: Array = []
	for shift in [4, 0]:
		var chunk: int = (v >> int(shift)) & 0xF
		nibbles.append(_bin4(chunk))
	return " ".join(PackedStringArray(nibbles))

func _bin4(v: int) -> String:
	var s := ""
	for i in range(3, -1, -1):
		s += "1" if ((v >> i) & 1) == 1 else "0"
	return s

func _show_report(rep: GateReport) -> void:
	for c in _report_box.get_children():
		c.queue_free()
	for raw in rep.cases:
		var c: Dictionary = raw
		var ok := bool(c.get("ok", false))
		var color := UiTheme.OK if ok else UiTheme.DANGER
		_report_box.add_child(Ui.label("%s %s  %s" % ["✓" if ok else "✗", str(c.get("id", "")), str(c.get("detail", ""))], 11, color))

func _save_state() -> void:
	save_state({"value": _value, "visited": _visited, "achieved": _achieved, "quiz": _quiz_answer})

func _load_state() -> void:
	var st := load_state()
	if not st.is_empty():
		_value = int(st.get("value", 0))
		_visited = st.get("visited", {})
		_achieved = st.get("achieved", {})
		_quiz_answer = int(st.get("quiz", -1))
	_switches.set_value(_value)
	_on_bits_changed(_value)
	if _quiz_answer >= 0:
		_pick_quiz(_quiz_answer)

func scripted_solve() -> bool:
	## 脚本走查：走遍 0–15 覆盖、摆出两个目标数、答对辨析题，再走真实验收/发奖链路。
	for v in range(16):
		_switches.set_value(v)
		_on_bits_changed(v)
	for raw in lab_data.get("targets", []):
		var t: Dictionary = raw
		var v := int(t.get("value", -1))
		if v >= 0:
			_switches.set_value(v)
			_on_bits_changed(v)
	_pick_quiz(int(lab_data.get("quiz", {}).get("answer", -1)))
	_run_cases()
	return is_done()
