class_name WorkbenchScreen
extends GameScreen

## 章节工作台：左侧 6 节实验导航，右侧嵌入对应实验页。
## 锁定实验在正常点击时拒绝打开；命令行截图（announce=false）允许预览。

const LAB_PATHS := {
	"level": "res://src/ui/screens/lab_level.gd",
	"binary": "res://src/ui/screens/lab_binary.gd",
	"boolean": "res://src/ui/screens/lab_boolean.gd",
	"gate": "res://src/ui/screens/lab_gate.gd",
	"signal": "res://src/ui/screens/lab_signal.gd",
	"half_adder": "res://src/ui/screens/lab_half_adder.gd",
}

var _list: VBoxContainer
var _host: Control
var _pages: Dictionary = {}
var _current := ""
var _chapter_title: Label
var _progress_label: Label
var _next_label: Label

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := Ui.hbox(10)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var left := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
	left.custom_minimum_size = Vector2(252, 0)
	left.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(left)
	var lm := Ui.margin4(10, 10, 10, 10)
	left.add_child(lm)
	var lcol := Ui.vbox(8)
	lm.add_child(lcol)
	_chapter_title = Ui.label("第一章", 16, UiTheme.TEXT)
	lcol.add_child(_chapter_title)
	_progress_label = Ui.label("0 / 6", 11, UiTheme.MUTED)
	lcol.add_child(_progress_label)
	lcol.add_child(Ui.hline())
	var scroll := Ui.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lcol.add_child(scroll)
	_list = Ui.vbox(6)
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	lcol.add_child(Ui.hline())
	_next_label = Ui.wrap("", 11, UiTheme.AMBER)
	_next_label.custom_minimum_size = Vector2(0, 44)
	lcol.add_child(_next_label)

	var right := Ui.vbox(8)
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(right)
	_host = Ui.vbox(0)
	_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_host)

func on_show() -> void:
	_refresh_list()
	if _current.is_empty():
		var order: Array = DataDB.chapter.lab_order
		if not order.is_empty():
			var first := str(order[0])
			for lid in order:
				if ChapterFlow.is_lab_unlocked(str(lid)):
					first = str(lid)
					break
			select_lab(first, false)
	elif _pages.has(_current):
		(_pages[_current] as LabBase).refresh_status()

func select_lab(lab_id: String, announce: bool = true) -> void:
	if not DataDB.chapter.labs.has(lab_id):
		return
	if announce and not ChapterFlow.is_lab_unlocked(lab_id):
		EventBus.toast("未解锁：%s" % ChapterFlow.lab_lock_reason(lab_id), "warn")
		return
	_open(lab_id)
	EventBus.fire("lab_opened:%s" % lab_id)

func _open(lab_id: String) -> void:
	if _current == lab_id and _pages.has(lab_id):
		(_pages[lab_id] as LabBase).visible = true
		return
	for key in _pages.keys():
		(_pages[key] as Control).visible = false
	if not _pages.has(lab_id):
		var path := str(LAB_PATHS.get(lab_id, ""))
		if path.is_empty() or not ResourceLoader.exists(path):
			EventBus.toast("实验页缺失：%s" % lab_id, "error")
			return
		var script: Script = load(path)
		var page: LabBase = script.new()
		page.setup(main, lab_id)
		page.solved.connect(_on_lab_solved)
		_host.add_child(page)
		_pages[lab_id] = page
	var page: LabBase = _pages[lab_id]
	page.visible = true
	page.refresh_status()
	_current = lab_id
	_refresh_list()

func page_for(lab_id: String) -> LabBase:
	var page: Variant = _pages.get(lab_id, null)
	return page if page is LabBase else null

func _on_lab_solved(lab_id: String) -> void:
	var res := ChapterFlow.complete_lab(lab_id)
	if bool(res.get("ok", false)):
		EventBus.fire("lab_completed:%s" % lab_id)
	_refresh_list()
	if _pages.has(lab_id):
		(_pages[lab_id] as LabBase).refresh_status()

func _refresh_list() -> void:
	if _list == null:
		return
	for c in _list.get_children():
		c.queue_free()
	var ct := DataDB.chapter.title()
	_chapter_title.text = ct if not ct.is_empty() else "第一章"
	var cp := ChapterFlow.progress()
	_progress_label.text = "进度 %d / %d" % [int(cp.get("done", 0)), int(cp.get("total", 0))]
	var order: Array = DataDB.chapter.lab_order
	for raw_id in order:
		var lid := str(raw_id)
		var lab: Dictionary = DataDB.chapter.lab(lid)
		var unlocked := ChapterFlow.is_lab_unlocked(lid)
		var done := ChapterFlow.is_objective_done(str(lab.get("objective", "")))
		var gate_ids: Array = lab.get("gate_ids", [])
		var passed := 0
		for gid in gate_ids:
			if ChapterFlow.gate_passed(str(gid)):
				passed += 1
		var card := Ui.card(
			UiTheme.alpha(UiTheme.OK, 0.10) if done else (UiTheme.PANEL_3 if _current == lid else UiTheme.PANEL),
			UiTheme.OK if done else (UiTheme.ACCENT if _current == lid else UiTheme.BORDER),
			6
		)
		var m := Ui.margin4(9, 7, 9, 7)
		card.add_child(m)
		var col := Ui.vbox(3)
		m.add_child(col)
		var top := Ui.hbox(6)
		col.add_child(top)
		var name_text := "%s %s" % [str(lab.get("order", "?")), str(lab.get("title", lid))]
		var btn := Ui.button(name_text, func(): _click(lid), false)
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", 13)
		top.add_child(btn)
		if done:
			top.add_child(Ui.badge("已完成", UiTheme.OK))
		elif not unlocked:
			top.add_child(Ui.badge("锁定", UiTheme.MUTED))
		else:
			top.add_child(Ui.badge("进行中", UiTheme.AMBER))
		col.add_child(Ui.label(str(lab.get("subtitle", "")), 10, UiTheme.MUTED))
		if not unlocked:
			col.add_child(Ui.label("需先完成：%s" % ChapterFlow.lab_lock_reason(lid), 10, UiTheme.DANGER))
		else:
			col.add_child(Ui.label("gate %d / %d · 奖励 %d 金币 / %d XP" % [passed, gate_ids.size(), int(lab.get("reward", {}).get("gold", 0)), int(lab.get("reward", {}).get("xp", 0))], 10, UiTheme.MUTED))
		_list.add_child(card)
	var nxt := ChapterFlow.next_objective()
	if nxt.is_empty():
		_next_label.text = "本章完成。" if ChapterFlow.chapter_complete() else "全部实验已完成。"
	else:
		_next_label.text = "下一目标：%s" % str(nxt.get("title", ""))

func _click(lab_id: String) -> void:
	select_lab(lab_id, true)
