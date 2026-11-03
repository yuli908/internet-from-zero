extends LabBase

## 1.1 电平：0.8/2.0 V 双阈值判读，禁区为 X。

var _gauge: LevelGauge
var _slider: HSlider
var _value_label: Label
var _logic_label: Label
var _report_box: VBoxContainer
var _tasks: Dictionary = {}
var _voltage := 0.0
var _seen: Dictionary = {}

func _build() -> void:
	var title := str(lab_data.get("title", "电平"))
	var body := str(lab_data.get("body", ""))
	var root := Ui.vbox(10)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(_build_header(title, str(lab_data.get("subtitle", ""))))
	root.add_child(_body_card(body))
	root.add_child(_hint_card(str(lab_data.get("hint", "阈值来自配置：0.8 V 以下判 0，2.0 V 以上判 1，中间是禁止区 X。"))))

	var main_row := Ui.hbox(12)
	main_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(main_row)

	var gauge_card := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
	gauge_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_row.add_child(gauge_card)
	var gm := Ui.margin4(8, 6, 8, 6)
	gauge_card.add_child(gm)
	_gauge = LevelGauge.new()
	gm.add_child(_gauge)

	var side := Ui.vbox(8)
	side.custom_minimum_size = Vector2(300, 0)
	main_row.add_child(side)

	var read_card := Ui.card(UiTheme.PANEL_3, UiTheme.BORDER, 8)
	side.add_child(read_card)
	var rm := Ui.margin4(12, 9, 12, 9)
	read_card.add_child(rm)
	var rcol := Ui.vbox(4)
	rm.add_child(rcol)
	rcol.add_child(Ui.muted("当前电压", 10))
	_value_label = Ui.mono("0.00 V", 26, UiTheme.AMBER)
	rcol.add_child(_value_label)
	_logic_label = Ui.label("判读 X", 16, UiTheme.DANGER)
	rcol.add_child(_logic_label)

	var slider_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	side.add_child(slider_card)
	var sm := Ui.margin4(12, 8, 12, 8)
	slider_card.add_child(sm)
	var scol := Ui.vbox(6)
	sm.add_child(scol)
	scol.add_child(Ui.label("调压", 11, UiTheme.MUTED))
	_slider = HSlider.new()
	var th := VoltageModel.thresholds(lab_data)
	_slider.min_value = float(th.get("min", 0.0))
	_slider.max_value = float(th.get("max", 3.3))
	_slider.step = float(th.get("step", 0.05))
	_slider.value = 0.2
	_slider.custom_minimum_size = Vector2(0, 26)
	_slider.value_changed.connect(_on_voltage_changed)
	scol.add_child(_slider)
	var presets := GridContainer.new()
	presets.columns = 3
	presets.add_theme_constant_override("h_separation", 5)
	presets.add_theme_constant_override("v_separation", 5)
	scol.add_child(presets)
	for raw in lab_data.get("presets", []):
		var v := float(raw)
		presets.add_child(Ui.ghost("%.2f V" % v, func(): _slider.value = v))

	var task_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	side.add_child(task_card)
	var tm := Ui.margin4(12, 8, 12, 8)
	task_card.add_child(tm)
	var tcol := Ui.vbox(4)
	tm.add_child(tcol)
	tcol.add_child(Ui.label("操作任务", 11, UiTheme.MUTED))
	for pair in [["0", "让灯泡灭（判 0）"], ["1", "让灯泡亮（判 1）"], ["X", "进入禁止区（判 X）"]]:
		var arr := _task_row(str(pair[1]))
		tcol.add_child(arr[0])
		_tasks[str(pair[0])] = arr[1]

	var run_row := Ui.hbox(8)
	side.add_child(run_row)
	run_row.add_child(Ui.button("运行验收 T1.1", func(): _run_cases(), true))
	run_row.add_child(Ui.ghost("重置", func(): _slider.value = 0.2))

	_report_box = Ui.vbox(3)
	root.add_child(_report_box)

	_load_state()
	_on_voltage_changed(_voltage)

func _on_voltage_changed(v: float) -> void:
	_voltage = v
	var th := VoltageModel.thresholds(lab_data)
	var logic := VoltageModel.judge(v, float(th.get("low_max", 0.8)), float(th.get("high_min", 2.0)))
	_gauge.set_values(v, float(th.get("low_max", 0.8)), float(th.get("high_min", 2.0)), float(th.get("max", 3.3)))
	_value_label.text = "%.2f V" % v
	_logic_label.text = "判读 %s" % logic
	if logic == SimValue.ONE:
		_logic_label.add_theme_color_override("font_color", UiTheme.OK)
	elif logic == SimValue.X:
		_logic_label.add_theme_color_override("font_color", UiTheme.DANGER)
	else:
		_logic_label.add_theme_color_override("font_color", UiTheme.MUTED)
	_seen[logic] = true
	if _tasks.has(logic):
		var row_status: Label = _tasks[logic]
		_mark(row_status, true)
	_save_state()

func _run_cases() -> void:
	var rep := LabChecks.voltage(lab_data)
	_show_report(rep)
	var seen_all := bool(_seen.get("0", false)) and bool(_seen.get("1", false)) and bool(_seen.get("X", false))
	if not seen_all:
		EventBus.toast("先手动走遍三个判读区间，再运行验收", "warn")
		return
	if pass_report(rep):
		EventBus.toast("1.1 电平 gate 全部通过", "ok")
	else:
		EventBus.toast("还有 gate 未通过，见下方明细", "warn")

func _show_report(rep: GateReport) -> void:
	for c in _report_box.get_children():
		c.queue_free()
	for raw in rep.cases:
		var c: Dictionary = raw
		var ok := bool(c.get("ok", false))
		var color := UiTheme.OK if ok else UiTheme.DANGER
		var l := Ui.label("%s %s  %s" % ["✓" if ok else "✗", str(c.get("id", "")), str(c.get("detail", ""))], 11, color)
		_report_box.add_child(l)

func _save_state() -> void:
	save_state({"voltage": _voltage, "seen": _seen})

func _load_state() -> void:
	var st := load_state()
	if st.is_empty():
		return
	_seen = st.get("seen", {})
	_voltage = float(st.get("voltage", 0.2))
	_slider.set_value_no_signal(_voltage)
