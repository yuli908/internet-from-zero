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
var _visited: Dictionary = {}
var _achieved: Dictionary = {}
var _value := 0

func _build() -> void:
	# ---- 左栏：任务 / 8 位开关 / 覆盖进度 ----
	side.add_child(_section("任务"))
	var body := Ui.wrap(str(lab_data.get("body", "")), UiTheme.F_LABEL, UiTheme.MUTED)
	body.custom_minimum_size = Vector2(0, 64)
	side.add_child(body)
	side.add_child(Ui.hline())
	_switches = BitSwitches.new()
	_switches.setup(int(lab_data.get("bit_count", 8)), 0)
	_switches.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_switches.changed.connect(_on_bits_changed)
	side.add_child(_switches)
	side.add_child(Ui.hline())
	_cov = Ui.label("覆盖 0 / 16", UiTheme.F_LABEL, UiTheme.MUTED)
	side.add_child(_cov)
	side.add_child(Ui.ghost("全部清零", func(): _switches.set_value(0)))

	# ---- 中栏：数值读数 / 目标值 / 辨析题 ----
	var read_card := Ui.card(UiTheme.BOARD_SUNK, UiTheme.LINE)
	center.add_child(read_card)
	var rm := Ui.margin4(14, 10, 14, 10)
	read_card.add_child(rm)
	var rrow := Ui.hbox(16)
	rm.add_child(rrow)
	var dec_col := Ui.vbox(2)
	dec_col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rrow.add_child(dec_col)
	dec_col.add_child(_section("十进制"))
	_dec = Ui.mono("0", 40, UiTheme.AMBER)
	dec_col.add_child(_dec)
	var hex_col := Ui.vbox(2)
	hex_col.custom_minimum_size = Vector2(150, 0)
	rrow.add_child(hex_col)
	hex_col.add_child(_section("十六进制"))
	_hex = Ui.mono("0x00", 26, UiTheme.CYAN)
	hex_col.add_child(_hex)
	var bin_col := Ui.vbox(2)
	rrow.add_child(bin_col)
	bin_col.add_child(_section("二进制"))
	_bin = Ui.mono("0000 0000", UiTheme.F_H2, UiTheme.MUTED)
	bin_col.add_child(_bin)

	var target_card := Ui.card(UiTheme.alpha(UiTheme.CHALK, 0.04), UiTheme.LINE)
	center.add_child(target_card)
	var tm := Ui.margin4(14, 10, 14, 10)
	target_card.add_child(tm)
	var tcol := Ui.vbox(6)
	tm.add_child(tcol)
	tcol.add_child(_section("摆出目标值"))
	for raw in lab_data.get("targets", []):
		var t: Dictionary = raw
		var arr := _task_row("%s（%s）" % [str(t.get("label", "")), str(t.get("hint", ""))])
		tcol.add_child(arr[0])
		_target_status[str(t.get("id", ""))] = arr[1]

	var quiz: Dictionary = lab_data.get("quiz", {})
	if not quiz.is_empty():
		var q_card := Ui.card(UiTheme.alpha(UiTheme.CYAN, 0.04), UiTheme.alpha(UiTheme.CYAN, 0.35))
		center.add_child(q_card)
		var qm := Ui.margin4(14, 10, 14, 10)
		q_card.add_child(qm)
		var qcol := Ui.vbox(6)
		qm.add_child(qcol)
		qcol.add_child(_section("辨析题"))
		qcol.add_child(Ui.wrap(str(quiz.get("question", "")), UiTheme.F_BODY, UiTheme.CHALK))
		var opts := GridContainer.new()
		opts.columns = 2
		opts.add_theme_constant_override("h_separation", 8)
		opts.add_theme_constant_override("v_separation", 6)
		qcol.add_child(opts)
		var options: Array = quiz.get("options", [])
		for i in options.size():
			var idx := i
			var b := Ui.ghost("%d. %s" % [i + 1, str(options[i])], func(): _pick_quiz(idx))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			opts.add_child(b)
		_quiz_status = Ui.label("未选择", UiTheme.F_LABEL, UiTheme.MUTED)
		qcol.add_child(_quiz_status)
	center.add_child(Ui.spacer())

	# ---- 右栏：进度与验收 ----
	inspector.add_child(_section("验收"))
	inspector.add_child(Ui.wrap("覆盖 0–15、摆出两个目标、答对辨析题，三条 gate 全过才记账。", UiTheme.F_META, UiTheme.MUTED))
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收 T1.2", func(): _run_cases(), true))

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
	_cov.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if covered >= 16 else UiTheme.MUTED)
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
	show_report(rep)
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
