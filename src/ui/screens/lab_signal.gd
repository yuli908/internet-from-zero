extends LabBase

## 1.5 信号：延迟测量、竞争毛刺、结构修复。

var _delay := -1
var _width := -1
var _clean := false
var _quiz_answer := -1
var _delay_label: Label
var _glitch_label: Label
var _fix_label: Label
var _quiz_status: Label
var _wave: Waveform

func _build() -> void:
	# ---- 左栏：课文卡（固定）+ 三段实验（随控件区滚动） ----
	_install_reader(_reader_slot, 14, UiTheme.F_LABEL)
	var chain: Dictionary = lab_data.get("chain", {})
	side.add_child(_section("A · 三级非门延迟"))
	side.add_child(Ui.label("每级 %d tick，串联 %d 级。" % [int(chain.get("delay_per_stage", 3)), int(chain.get("stages", 3))], UiTheme.F_META, UiTheme.MUTED))
	_delay_label = Ui.mono("未测量", UiTheme.F_BODY_LG, UiTheme.MUTED)
	side.add_child(_delay_label)
	side.add_child(Ui.ghost("测量延迟", func(): _measure()))
	side.add_child(Ui.hline())

	var hz: Dictionary = lab_data.get("hazard", {})
	side.add_child(_section("B · 竞争毛刺"))
	side.add_child(Ui.wrap("F = A·C + B·C′，A=B=1；C 由 1 变 0。", UiTheme.F_META, UiTheme.MUTED))
	_glitch_label = Ui.mono("未复现", UiTheme.F_BODY_LG, UiTheme.MUTED)
	side.add_child(_glitch_label)
	side.add_child(Ui.ghost("制造毛刺（偏斜 %d tick）" % int(hz.get("skew", 4)), func(): _glitch()))
	side.add_child(Ui.hline())

	var fx: Dictionary = lab_data.get("fix", {})
	side.add_child(_section("C · 结构修复"))
	side.add_child(Ui.wrap("均衡两条路径延迟，再翻转 %d 次观察。" % int(fx.get("toggles", 20)), UiTheme.F_META, UiTheme.MUTED))
	_fix_label = Ui.mono("未修复", UiTheme.F_BODY_LG, UiTheme.MUTED)
	side.add_child(_fix_label)
	side.add_child(Ui.ghost("均衡延迟并翻转 %d 次" % int(fx.get("toggles", 20)), func(): _fix()))
	side.add_child(Ui.spacer())

	# ---- 中栏：波形 ----
	var w_card := Ui.card(UiTheme.BOARD_SUNK, UiTheme.LINE)
	w_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(w_card)
	var wm := Ui.margin4(8, 8, 8, 8)
	w_card.add_child(wm)
	_wave = Waveform.new()
	wm.add_child(_wave)
	center.add_child(Ui.wrap("波形只显示 C 变化后的 F 跳变；窄脉冲宽度 ≥1 tick 即视为可观测毛刺。", UiTheme.F_BODY, UiTheme.MUTED))
	# 提示层：画布下方讲解带，attempt ≥ 1 才显形。
	_add_hint(center, 30)

	# ---- 右栏：辨析 + 验收 ----
	var quiz: Dictionary = lab_data.get("quiz", {})
	if not quiz.is_empty():
		inspector.add_child(_section("辨析题"))
		inspector.add_child(Ui.wrap(str(quiz.get("question", "")), UiTheme.F_BODY, UiTheme.CHALK))
		var options: Array = quiz.get("options", [])
		for i in options.size():
			var idx := i
			var b := Ui.ghost("%d. %s" % [i + 1, str(options[i])], func(): _pick_quiz(idx))
			b.alignment = HORIZONTAL_ALIGNMENT_LEFT
			b.clip_text = true
			b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			b.tooltip_text = str(options[i])
			inspector.add_child(b)
		_quiz_status = Ui.label("未选择", UiTheme.F_META, UiTheme.MUTED)
		_quiz_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		inspector.add_child(_quiz_status)
	inspector.add_child(Ui.hline())
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收 T1.5", func(): _run_cases(), true))

	_load_state()

func _measure() -> void:
	var chain: Dictionary = lab_data.get("chain", {})
	var res := SignalLabModel.measure_chain(int(chain.get("stages", 3)), int(chain.get("delay_per_stage", 3)))
	if bool(res.get("ok", false)):
		_delay = int(res.get("delay", -1))
		_delay_label.text = "%d tick（%.1f tick/级）" % [_delay, float(res.get("per_stage", 0.0))]
		_delay_label.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if _delay == int(chain.get("expected_delay", 9)) else UiTheme.DANGER)
		_save_state()
	else:
		EventBus.toast("测量失败：%s" % str(res.get("error", "")), "error")

func _glitch() -> void:
	var hz: Dictionary = lab_data.get("hazard", {})
	var res := SignalLabModel.pulse_after_c_fall(int(hz.get("skew", 4)), int(lab_data.get("chain", {}).get("delay_per_stage", 3)))
	if not bool(res.get("ok", false)):
		EventBus.toast("毛刺仿真失败：%s" % str(res.get("error", "")), "error")
		return
	_width = int(res.get("width", 0))
	var changes: Array = res.get("changes", [])
	_wave.set_changes(changes, 24, "F（C 下降后）")
	if _width >= int(hz.get("min_width", 1)):
		_glitch_label.text = "毛刺宽度 %d tick（已复现）" % _width
		_glitch_label.add_theme_color_override("font_color", UiTheme.DANGER)
	else:
		_glitch_label.text = "宽度 %d tick，未达可观测阈值" % _width
		_glitch_label.add_theme_color_override("font_color", UiTheme.MUTED)
	_save_state()

func _fix() -> void:
	var fx: Dictionary = lab_data.get("fix", {})
	var res := SignalLabModel.run_fixed(str(fx.get("mode", "equalize")), int(fx.get("toggles", 20)))
	if not bool(res.get("ok", false)):
		EventBus.toast("修复仿真失败：%s" % str(res.get("error", "")), "error")
		return
	_clean = bool(res.get("clean", false))
	_fix_label.text = "%d 次翻转，毛刺 %d 次" % [int(res.get("toggles", 0)), int(res.get("glitch_events", 0))]
	_fix_label.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if _clean else UiTheme.DANGER)
	_wave.set_changes([], 24, "F（修复后）")
	_save_state()

func _pick_quiz(idx: int) -> void:
	_quiz_answer = idx
	var quiz: Dictionary = lab_data.get("quiz", {})
	if idx == int(quiz.get("answer", -1)):
		_quiz_status.text = "正确：%s" % str(quiz.get("explain", ""))
		_quiz_status.add_theme_color_override("font_color", UiTheme.OK)
	else:
		_quiz_status.text = "再想想：C 与 C′ 到达 OR 的时间不同。"
		_quiz_status.add_theme_color_override("font_color", UiTheme.DANGER)
	_save_state()

func _run_cases() -> void:
	var rep := LabChecks.signal_cases(lab_data, _delay, _width, _clean, _quiz_answer, tracker)
	show_report(rep)
	if pass_report(rep):
		EventBus.toast("1.5 信号 gate 全部通过", "ok")
	else:
		EventBus.toast("仍有 gate 未通过：测延迟、复现毛刺、修复、答题", "warn")

func _on_attempt(a: int) -> void:
	_apply_hint(a)

func _save_state() -> void:
	save_state({"delay": _delay, "width": _width, "clean": _clean, "quiz": _quiz_answer})

func _load_state() -> void:
	var st := load_state()
	if st.is_empty():
		return
	_delay = int(st.get("delay", -1))
	_width = int(st.get("width", -1))
	_clean = bool(st.get("clean", false))
	_quiz_answer = int(st.get("quiz", -1))
	if _delay >= 0:
		_delay_label.text = "%d tick" % _delay
	if _width >= 0:
		_glitch_label.text = "毛刺宽度 %d tick" % _width
	if _clean:
		_fix_label.text = "已修复（无毛刺）"
		_fix_label.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT)
	if _quiz_answer >= 0:
		_pick_quiz(_quiz_answer)

func scripted_solve() -> bool:
	## 脚本走查：测延迟 → 复现毛刺 → 修复 → 答题，再走真实验收/发奖链路。
	_measure()
	_glitch()
	_fix()
	_pick_quiz(int(lab_data.get("quiz", {}).get("answer", -1)))
	_run_cases()
	return is_done()
