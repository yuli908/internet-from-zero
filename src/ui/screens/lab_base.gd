class_name LabBase
extends Control

## 三级页统一骨架：返回条 / 左步骤栏 / 中编辑区 / 右检查器 / 底部结果条。
## 子类只实现 `_build()`，把内容放进 side / center / inspector，结果写进 result。

signal solved(lab_id: String)

const Teach = preload("res://src/ui/teaching.gd")

var main: Control
var lab_id := ""
var lab_data: Dictionary = {}
var objective_id := ""
## 尝试次数跟踪：提示阶梯按 attempt 分级（1→L1、2→L2、≥3→L3）。
var tracker := GateAttemptTracker.new()

var side: VBoxContainer
var center: VBoxContainer
var inspector: VBoxContainer

var _side_card: PanelContainer
var _inspector_card: PanelContainer
var _header_title: Label
var _header_code: Label
var _status_badge: Label
var _gold_label: Label
var _result_strip: PanelContainer
var _result_bar: ColorRect
var _result_title: Label
var _result_detail: Label
var _result_ok := false

var _attempt := 0
var _teach_label: Label
var _hint_box: PanelContainer
var _hint_label: Label
var _feedback_label: Label

func setup(main_ref: Control, p_lab_id: String) -> void:
	main = main_ref
	lab_id = p_lab_id
	objective_id = DataDB.chapter.objective_for_lab(lab_id)
	var meta := DataDB.chapter.lab(lab_id)
	lab_data = DataDB.lab_data(str(meta.get("data_key", "")))
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell(meta)
	_build()
	_finish_shell()
	refresh_status()
	_shot_hooks()

func _build_shell(meta: Dictionary) -> void:
	# 背景 + 6px 木框 + 黑板。左右各 18 内容边距，中心净宽 696。
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var frame := ColorRect.new()
	frame.color = UiTheme.FRAME
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	var board := ColorRect.new()
	board.color = UiTheme.BOARD
	board.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	board.offset_left = 6
	board.offset_top = 6
	board.offset_right = -6
	board.offset_bottom = -6
	board.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(board)
	var grain := GrainOverlay.new()
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	grain.offset_left = 6
	grain.offset_top = 6
	grain.offset_right = -6
	grain.offset_bottom = -6
	add_child(grain)

	var content := Ui.margin4(18, 18, 18, 10)
	content.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	content.offset_left = 6
	content.offset_top = 6
	content.offset_right = -6
	content.offset_bottom = -6
	add_child(content)
	var root := Control.new()
	content.add_child(root)

	# 抬头 44：返回 44×44 @ (24,24)，标题 (86,24) 26 号，内容从 y=92 起。
	var back := Ui.back_icon(func(): _go_back())
	back.position = Vector2(0, 0)
	back.size = Vector2(44, 44)
	root.add_child(back)

	_header_title = Ui.label(str(lab_data.get("title", meta.get("title", lab_id))), UiTheme.F_H2, UiTheme.CHALK)
	_header_title.position = Vector2(62, 0)
	_header_title.size = Vector2(600, 34)
	_header_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_header_title.clip_text = true
	root.add_child(_header_title)

	_header_code = Ui.label(_code_text(meta), UiTheme.F_META, UiTheme.MUTED)
	_header_code.add_theme_font_override("font", UiTheme.mono_font())
	_header_code.position = Vector2(62, 34)
	_header_code.size = Vector2(820, 20)
	_header_code.clip_text = true
	root.add_child(_header_code)

	_status_badge = Ui.label("●", UiTheme.F_META, UiTheme.AMBER)
	_status_badge.position = Vector2(1000, 0)
	_status_badge.size = Vector2(40, 44)
	_status_badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_status_badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_status_badge)

	var gold_dot := ColorRect.new()
	gold_dot.color = UiTheme.AMBER
	gold_dot.position = Vector2(1064, 19)
	gold_dot.size = Vector2(6, 6)
	gold_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(gold_dot)
	_gold_label = Ui.label("金币 --", UiTheme.F_BODY, UiTheme.AMBER)
	_gold_label.position = Vector2(1080, 0)
	_gold_label.size = Vector2(152, 44)
	_gold_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_gold_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(_gold_label)

	# 三栏：内容区 (24,92,1232,544)。
	var body := Ui.hbox(18)
	body.position = Vector2(0, 68)
	body.size = Vector2(1232, 544)
	body.custom_minimum_size = Vector2(1232, 544)
	root.add_child(body)

	_side_card = Ui.card(UiTheme.alpha(UiTheme.CHALK, 0.04), UiTheme.LINE)
	_side_card.custom_minimum_size = Vector2(248, 0)
	_side_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_side_card)
	side = Ui.vbox(6)
	_side_card.add_child(side)

	center = Ui.vbox(8)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(center)

	_inspector_card = Ui.card(UiTheme.alpha(UiTheme.CHALK, 0.04), UiTheme.LINE)
	_inspector_card.custom_minimum_size = Vector2(252, 0)
	_inspector_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_inspector_card)
	inspector = Ui.vbox(6)
	_inspector_card.add_child(inspector)

	# 结果条 36：单行（验收标题 + 明细），把下方 24 px 让给误区条。
	_result_strip = Ui.card(UiTheme.BOARD_SUNK, UiTheme.LINE)
	_result_strip.position = Vector2(0, 622)
	_result_strip.size = Vector2(1232, 36)
	_result_strip.custom_minimum_size = Vector2(0, 36)
	var strip_sb: StyleBoxFlat = UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.LINE)
	strip_sb.content_margin_top = 5
	strip_sb.content_margin_bottom = 5
	_result_strip.add_theme_stylebox_override("panel", strip_sb)
	root.add_child(_result_strip)
	var rm := Ui.hbox(12)
	_result_strip.add_child(rm)
	_result_bar = ColorRect.new()
	_result_bar.color = UiTheme.LINE_STRONG
	_result_bar.custom_minimum_size = Vector2(3, 0)
	_result_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rm.add_child(_result_bar)
	var rc := Ui.hbox(12)
	rc.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rm.add_child(rc)
	_result_title = Ui.label("验收", UiTheme.F_BODY, UiTheme.CHALK)
	rc.add_child(_result_title)
	_result_detail = Ui.label("", UiTheme.F_BODY, UiTheme.MUTED)
	_result_detail.clip_text = true
	_result_detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_result_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rc.add_child(_result_detail)

	# 误区条：结果条下方专用一行（660–682），只在有 required 失败时出现；不压抬头、不进状态行。
	_feedback_label = Ui.label("", UiTheme.F_META, UiTheme.RUST)
	_feedback_label.position = Vector2(0, 660)
	_feedback_label.size = Vector2(1232, 22)
	_feedback_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_feedback_label.clip_text = true
	_feedback_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_feedback_label.tooltip_text = ""
	_feedback_label.visible = false
	root.add_child(_feedback_label)

func _build() -> void:
	pass

func _code_text(meta: Dictionary) -> String:
	## 编号跟着当前章节走：T2.1 / T3.4 …，不再固定 T1。
	var order := int(meta.get("order", 0))
	var gates: Array = meta.get("gate_ids", [])
	return "T%d.%d · %d 项验收 · %s" % [int(DataDB.chapter.data.get("number", 1)), order, gates.size(), str(meta.get("subtitle", ""))]

func _finish_shell() -> void:
	## 子类 `_build()` 结束后调用：没用的检查器列直接隐藏，把宽度让给编辑区。
	if _inspector_card != null and inspector.get_child_count() == 0:
		_inspector_card.visible = false

func refresh_status() -> void:
	if GameState.player == null:
		return
	if _status_badge != null:
		_status_badge.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if is_done() else UiTheme.AMBER)
	if _gold_label != null:
		_gold_label.text = "金币 %d" % GameState.player.gold

func is_done() -> bool:
	return ChapterFlow.is_objective_done(objective_id)

func complete_once() -> void:
	if is_done():
		return
	solved.emit(lab_id)
	refresh_status()
	if _result_ok:
		var reward: Dictionary = DataDB.chapter.lab(lab_id).get("reward", {})
		_result_detail.text = "已记账 · 金币 +%d · XP +%d" % [int(reward.get("gold", 0)), int(reward.get("xp", 0))]
		_result_detail.add_theme_color_override("font_color", UiTheme.CHALK)

func scripted_solve() -> bool:
	return false

func save_state(data: Dictionary) -> void:
	if GameState.player == null:
		return
	GameState.player.set_flag("labstate:%s" % lab_id, data)
	EventBus.state_changed.emit()

func load_state() -> Dictionary:
	if GameState.player == null:
		return {}
	var raw: Variant = GameState.player.get_flag("labstate:%s" % lab_id, {})
	return raw if raw is Dictionary else {}

func mark_gate(gate_id: String, ok: bool = true) -> void:
	if GameState.player == null:
		return
	GameState.player.set_flag("gate:%s" % gate_id, ok)

func gate_passed(gate_id: String) -> bool:
	return ChapterFlow.gate_passed(gate_id)

func pass_report(report: GateReport) -> bool:
	## gate 结果逐条写存档；全部 required 通过才允许完成。
	if report == null or not report.all_required_passed():
		return false
	for raw in report.cases:
		var c: Dictionary = raw
		if bool(c.get("ok", false)):
			mark_gate(str(c.get("id", "")), true)
	EventBus.state_changed.emit()
	complete_once()
	return true

func show_report(report: GateReport) -> void:
	if report == null:
		return
	var ok_count := 0
	var fail_details: Array = []
	for raw in report.cases:
		var c: Dictionary = raw
		if bool(c.get("ok", false)):
			ok_count += 1
		else:
			fail_details.append("%s %s" % [str(c.get("id", "")), str(c.get("detail", ""))])
	_result_ok = ok_count == report.cases.size()
	var color := UiTheme.CHALK_BRIGHT if _result_ok else UiTheme.DANGER
	_result_bar.color = color
	_result_strip.add_theme_stylebox_override("panel", UiTheme.flat(UiTheme.BOARD_SUNK, UiTheme.alpha(color, 0.7)))
	_result_title.text = "验收 · 通过 %d/%d" % [ok_count, report.cases.size()]
	_result_title.add_theme_color_override("font_color", color)
	if fail_details.is_empty():
		_result_detail.text = ""
		_result_detail.add_theme_color_override("font_color", UiTheme.CHALK)
		if is_done():
			var reward: Dictionary = DataDB.chapter.lab(lab_id).get("reward", {})
			_result_detail.text = "已记账 · 金币 +%d · XP +%d" % [int(reward.get("gold", 0)), int(reward.get("xp", 0))]
	else:
		_result_detail.text = "未通过：" + " / ".join(PackedStringArray(fail_details))
		_result_detail.add_theme_color_override("font_color", UiTheme.RUST)
	# 提示阶梯读到本次最大 attempt；误区只在 required 失败时出（成功即清空）。
	_attempt = 0
	for raw in report.cases:
		var c: Dictionary = raw
		_attempt = maxi(_attempt, int(c.get("attempt", 0)))
	var mis := Teach.misconception_on_report(lab_data, report)
	if _feedback_label != null:
		_feedback_label.text = mis
		_feedback_label.tooltip_text = mis
		_feedback_label.visible = not mis.is_empty()
	_on_attempt(_attempt)

func _on_attempt(_a: int) -> void:
	pass

func _go_back() -> void:
	if main != null and main.has_method("back_to_hub"):
		main.back_to_hub()

func _task_row(text: String) -> Array:
	var row := Ui.hbox(8)
	var name_label := Ui.label(text, UiTheme.F_BODY, UiTheme.CHALK)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.tooltip_text = text
	row.add_child(name_label)
	row.add_child(Ui.spacer())
	var status := Ui.label("·", UiTheme.F_META, UiTheme.MUTED)
	row.add_child(status)
	return [row, status]

func _mark(label: Label, done: bool, _done_text: String = "") -> void:
	## 状态用符号 + 颜色，不再写「已完成 / 待完成」。
	label.text = "✓" if done else "·"
	label.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if done else UiTheme.MUTED)

func _section(text: String) -> Label:
	var l := Ui.label(text, UiTheme.F_META, UiTheme.MUTED)
	return l

func _body_card(text: String) -> PanelContainer:
	var card := Ui.card(UiTheme.BOARD_HIGH, UiTheme.LINE)
	var m := Ui.margin4(12, 9, 12, 9)
	card.add_child(m)
	m.add_child(Ui.wrap(text, UiTheme.F_BODY, UiTheme.MUTED))
	return card

func _hint_card(text: String) -> PanelContainer:
	var card := Ui.card(UiTheme.alpha(UiTheme.CYAN, 0.05), UiTheme.alpha(UiTheme.CYAN, 0.35))
	var m := Ui.margin4(12, 8, 12, 8)
	card.add_child(m)
	m.add_child(Ui.wrap(text, UiTheme.F_BODY, UiTheme.CYAN))
	return card

## 教学层正文（body + rules）：常驻正文区，保存引用供验收断言。
## 手工折行：autowrap 在容器未定宽时按 0 宽计算最小高度（会撑爆布局），这里按字符数固定折行。
func _add_teaching(parent: Control, chars_per_line: int = 11, font_size: int = UiTheme.F_BODY) -> Label:
	_teach_label = Ui.label(_flow(Teach.teaching_text(lab_data), chars_per_line), font_size, UiTheme.MUTED)
	_teach_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(_teach_label)
	return _teach_label

## 提示层：空卡片挂在正文区，attempt ≥ 1 才显形（不许一开始就全显示）。
func _add_hint(parent: Control, chars_per_line: int = 11) -> void:
	_hint_box = Ui.card(UiTheme.alpha(UiTheme.CYAN, 0.05), UiTheme.alpha(UiTheme.CYAN, 0.35))
	var m := Ui.margin4(12, 8, 12, 8)
	_hint_label = Ui.label("", UiTheme.F_BODY, UiTheme.CYAN)
	_hint_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	m.add_child(_hint_label)
	_hint_box.add_child(m)
	_hint_box.visible = false
	_hint_box.set_meta("chars_per_line", chars_per_line)
	parent.add_child(_hint_box)

func _apply_hint(attempt: int) -> void:
	if _hint_label == null:
		return
	_hint_label.text = _flow(Teach.hint_for_attempt(lab_data, attempt), int(_hint_box.get_meta("chars_per_line", 11)))
	_hint_box.visible = not _hint_label.text.is_empty()

static func _flow(text: String, chars_per_line: int) -> String:
	var out := PackedStringArray()
	for para in text.split("\n"):
		var line := ""
		for ch in para:
			line += ch
			if line.length() >= chars_per_line:
				out.append(line)
				line = ""
		if not line.is_empty():
			out.append(line)
	return "\n".join(out)

## 折行只加换行、不改字：用于断言「界面上显示的」与数据字段一致（忽略换行/空白差异）。
static func flat_text(s: String) -> String:
	return s.replace("\n", "").replace(" ", "").replace("\t", "")

## 渲染证据：截图/走查时打印，用于断言「界面上真的显示了什么」，而不是只看代码存在。
func teach_probe() -> Dictionary:
	var t := _teach_label.text if _teach_label != null else ""
	var h := _hint_label.text if _hint_label != null else ""
	return {
		"lab": lab_id,
		"teach_len": t.length(),
		"teach_src_len": Teach.teaching_text(lab_data).length(),
		"teach_match": flat_text(t) == flat_text(Teach.teaching_text(lab_data)),
		"hint_len": h.length(),
		"hint_visible": _hint_box != null and _hint_box.visible,
		"misconception": _feedback_label.text if _feedback_label != null else "",
	}

func _shot_hooks() -> void:
	## 仅截图模式：--shot-fail 用真实数据跑一次必然失败的验收，用于拍失败态（含误区条）。
	if CliArgs.value("shot", "").is_empty():
		return
	if CliArgs.has_flag("shot-fail"):
		if has_method("_reset_for_fail_shot"):
			call("_reset_for_fail_shot")
		if has_method("_run_cases"):
			call("_run_cases")
	var p := teach_probe()
	print("IFZ_TEACH lab=%s teach_len=%d src_len=%d match=%s hint_len=%d hint_visible=%s misconception_len=%d" % [
		str(p["lab"]), int(p["teach_len"]), int(p["teach_src_len"]), str(p["teach_match"]),
		int(p["hint_len"]), str(p["hint_visible"]), str(p["misconception"]).length()])
