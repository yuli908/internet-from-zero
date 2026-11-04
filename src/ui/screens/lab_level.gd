extends LabBase

## 1.1 电平：0.8/2.0 V 双阈值判读，禁区为 X。

var _gauge: LevelGauge
var _slider: HSlider
var _value_label: Label
var _logic_label: Label
var _tasks: Dictionary = {}
var _voltage := 0.0
var _seen: Dictionary = {}

func _build() -> void:
	var th := VoltageModel.thresholds(lab_data)
	# ---- 左栏：任务说明 / 电压读数 / 调压 ----
	_install_reader(_reader_slot, 14, UiTheme.F_LABEL)
	side.add_child(_section("任务"))
	side.add_child(Ui.hline())
	side.add_child(_section("当前电压"))
	_value_label = Ui.mono("0.00 V", UiTheme.F_H1, UiTheme.AMBER)
	side.add_child(_value_label)
	_logic_label = Ui.label("判读 X", UiTheme.F_BODY_LG, UiTheme.DANGER)
	side.add_child(_logic_label)
	side.add_child(Ui.hline())
	side.add_child(_section("调压"))
	_slider = HSlider.new()
	_slider.min_value = float(th.get("min", 0.0))
	_slider.max_value = float(th.get("max", 3.3))
	_slider.step = float(th.get("step", 0.05))
	_slider.value = 0.2
	_slider.custom_minimum_size = Vector2(0, 30)
	_slider.value_changed.connect(_on_voltage_changed)
	side.add_child(_slider)
	side.add_child(Ui.hline())
	side.add_child(_section("操作任务"))
	for pair in [["0", "让灯泡灭（判 0）"], ["1", "让灯泡亮（判 1）"], ["X", "进入禁止区（判 X）"]]:
		var arr := _task_row(str(pair[1]))
		side.add_child(arr[0])
		_tasks[str(pair[0])] = arr[1]
	side.add_child(Ui.spacer())
	side.add_child(Ui.ghost("重置到 0.20 V", func(): _slider.value = 0.2))

	# ---- 中栏：灯泡与电压带 ----
	var gauge_card := Ui.card(UiTheme.BOARD_SUNK, UiTheme.LINE)
	gauge_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(gauge_card)
	var gm := Ui.margin4(8, 8, 8, 8)
	gauge_card.add_child(gm)
	_gauge = LevelGauge.new()
	gm.add_child(_gauge)
	center.add_child(Ui.wrap(str(lab_data.get("hint", "阈值来自配置：0.8 V 以下判 0，2.0 V 以上判 1，中间是禁止区 X。")), UiTheme.F_BODY, UiTheme.MUTED))

	# ---- 右栏：判读区间 / 快捷电压 / 验收 ----
	inspector.add_child(_section("判读区间"))
	inspector.add_child(_range_row(UiTheme.MUTED, "≤ %.2f V" % float(th.get("low_max", 0.8)), "判 0"))
	inspector.add_child(_range_row(UiTheme.DANGER, "%.2f – %.2f V" % [float(th.get("low_max", 0.8)), float(th.get("high_min", 2.0))], "判 X"))
	inspector.add_child(_range_row(UiTheme.OK, "≥ %.2f V" % float(th.get("high_min", 2.0)), "判 1"))
	inspector.add_child(Ui.hline())
	inspector.add_child(_section("快捷电压"))
	var presets := GridContainer.new()
	presets.columns = 2
	presets.add_theme_constant_override("h_separation", 6)
	presets.add_theme_constant_override("v_separation", 6)
	inspector.add_child(presets)
	for raw in lab_data.get("presets", []):
		var v := float(raw)
		presets.add_child(Ui.ghost("%.2f V" % v, func(): _slider.value = v))
	inspector.add_child(Ui.hline())
	inspector.add_child(_section("验收"))
	inspector.add_child(Ui.wrap("先手动走遍三个区间，再运行验收。", UiTheme.F_META, UiTheme.MUTED))
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收 T1.1", func(): _run_cases(), true))

	_load_state()
	_on_voltage_changed(_voltage)

func _range_row(color: Color, left: String, right: String) -> HBoxContainer:
	var row := Ui.hbox(8)
	row.add_child(Ui.status_dot(color, 8))
	row.add_child(Ui.label(left, UiTheme.F_LABEL, UiTheme.CHALK))
	row.add_child(Ui.spacer())
	row.add_child(Ui.label(right, UiTheme.F_META, color))
	return row

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
	show_report(rep)
	var seen_all := bool(_seen.get("0", false)) and bool(_seen.get("1", false)) and bool(_seen.get("X", false))
	if not seen_all:
		EventBus.toast("先手动走遍三个判读区间，再运行验收", "warn")
		return
	if pass_report(rep):
		EventBus.toast("1.1 电平 gate 全部通过", "ok")
	else:
		EventBus.toast("还有 gate 未通过，见下方结果条", "warn")

func _save_state() -> void:
	save_state({"voltage": _voltage, "seen": _seen})

func _load_state() -> void:
	var st := load_state()
	if st.is_empty():
		return
	_seen = st.get("seen", {})
	_voltage = float(st.get("voltage", 0.2))
	_slider.set_value_no_signal(_voltage)

func scripted_solve() -> bool:
	## 脚本走查：依次判读 0 / 1 / X 三个区间，再走真实验收/发奖链路。
	for v in [0.2, 1.65, 3.1]:
		_slider.set_value_no_signal(float(v))
		_on_voltage_changed(float(v))
	_run_cases()
	return is_done()
