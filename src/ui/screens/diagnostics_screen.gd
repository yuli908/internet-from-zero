extends GameScreen

## 诊断页：数据加载状态、章节实验表、知识树与运行环境自检。

var _body: VBoxContainer

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func on_show() -> void:
	_refresh()

func _build() -> void:
	var page := Ui.vbox(10)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)

	var head := Ui.hbox(12)
	page.add_child(head)
	head.add_child(Ui.title("诊断 · 数据与自检", 22))
	head.add_child(Ui.spacer())
	var revalidate := Ui.button("重新校验数据", _on_revalidate)
	revalidate.custom_minimum_size = Vector2(132, 32)
	head.add_child(revalidate)

	var scroll := Ui.scroll()
	page.add_child(scroll)
	_body = Ui.vbox(10)
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_body)

func _clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

func _refresh() -> void:
	if _body == null:
		return
	_clear(_body)
	_body.add_child(_data_block())
	_body.add_child(_chapter_block())
	_body.add_child(_system_block())

func _block(title_text: String) -> Array:
	var card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	var m := Ui.margin4(12, 10, 12, 10)
	card.add_child(m)
	var col := Ui.vbox(6)
	m.add_child(col)
	col.add_child(Ui.label(title_text, 13, UiTheme.ACCENT))
	col.add_child(Ui.hline())
	return [card, col]

func _data_block() -> PanelContainer:
	var parts = _block("数据加载状态")
	var card: PanelContainer = parts[0]
	var col: VBoxContainer = parts[1]

	var status := Ui.hbox(14)
	col.add_child(status)
	status.add_child(Ui.status_dot(UiTheme.OK if DataDB.ready_ok else UiTheme.DANGER, 9))
	status.add_child(Ui.label("校验通过" if DataDB.ready_ok else "存在问题", 15, UiTheme.OK if DataDB.ready_ok else UiTheme.DANGER))
	status.add_child(Ui.spacer())
	status.add_child(Ui.stat("加载文件", str(DataDB.loaded_files)))
	status.add_child(Ui.stat("数据版本", "v%d" % DataDB.data_version))
	status.add_child(Ui.stat("清单条目", str(_manifest_count())))
	status.add_child(Ui.stat("章节", _chapter_id()))

	col.add_child(Ui.label("错误列表", 11, UiTheme.MUTED))
	var errs: Array = DataDB.errors
	if errs.is_empty():
		col.add_child(Ui.label("无（文件与引用关系全部通过校验）", 12, UiTheme.OK))
		return card
	col.add_child(Ui.label("%d 个问题" % errs.size(), 12, UiTheme.DANGER))
	for raw_err in errs:
		var row := Ui.hbox(8)
		row.add_child(Ui.status_dot(UiTheme.DANGER, 6))
		row.add_child(Ui.wrap(str(raw_err), 12, UiTheme.DANGER))
		col.add_child(row)
	return card

func _chapter_block() -> PanelContainer:
	var parts = _block("章节与实验")
	var card: PanelContainer = parts[0]
	var col: VBoxContainer = parts[1]

	var cp: Dictionary = ChapterFlow.progress()
	var head := Ui.hbox(14)
	col.add_child(head)
	head.add_child(Ui.mono(_chapter_id(), 17, UiTheme.ACCENT))
	head.add_child(Ui.label(_chapter_title(), 15, UiTheme.TEXT))
	head.add_child(Ui.spacer())
	head.add_child(Ui.stat("起始废铁", _start_scrap()))
	head.add_child(Ui.stat("目标进度", "%d / %d" % [int(cp.get("done", 0)), int(cp.get("total", 0))], UiTheme.OK))

	col.add_child(_lab_header())
	if DataDB.chapter == null:
		col.add_child(Ui.label("章节数据未加载", 12, UiTheme.DANGER))
		return card
	for raw_lab in DataDB.chapter.lab_order:
		col.add_child(_lab_row(str(raw_lab)))
	return card

func _lab_header() -> VBoxContainer:
	var col := Ui.vbox(3)
	var row := Ui.hbox(10)
	col.add_child(row)
	row.add_child(_cell("实验", 0, UiTheme.MUTED, 11))
	row.add_child(_cell("数据键", 96, UiTheme.MUTED, 11))
	row.add_child(_cell("解锁", 52, UiTheme.MUTED, 11))
	row.add_child(_cell("目标", 52, UiTheme.MUTED, 11))
	row.add_child(_cell("锁定原因", 0, UiTheme.MUTED, 11))
	col.add_child(Ui.hline())
	return col

func _lab_row(lab_id: String) -> HBoxContainer:
	var chapter = DataDB.chapter
	var lab: Dictionary = {}
	if chapter != null:
		lab = chapter.lab(lab_id)

	var unlocked := ChapterFlow.is_lab_unlocked(lab_id)
	var obj_id := str(lab.get("objective", ""))
	var obj_done := false
	var obj_title := ""
	if not obj_id.is_empty():
		obj_done = ChapterFlow.is_objective_done(obj_id)
		if chapter != null:
			obj_title = str(chapter.objective(obj_id).get("title", ""))
	var reason := ChapterFlow.lab_lock_reason(lab_id)

	var row := Ui.hbox(10)
	var title_cell := _cell(str(lab.get("title", lab_id)), 0, UiTheme.TEXT if unlocked else UiTheme.MUTED)
	if not obj_title.is_empty():
		title_cell.tooltip_text = obj_title
	row.add_child(title_cell)
	row.add_child(_cell(str(lab.get("data_key", "—")), 96, UiTheme.MUTED))
	row.add_child(_cell("可用" if unlocked else "锁定", 52, UiTheme.OK if unlocked else UiTheme.AMBER))
	row.add_child(_cell("已完成" if obj_done else "未完成", 52, UiTheme.OK if obj_done else UiTheme.MUTED))
	row.add_child(_cell(reason if not reason.is_empty() else "—", 0, UiTheme.AMBER if not reason.is_empty() else UiTheme.MUTED))
	return row

func _cell(text: String, width: int, color: Color, font_size: int = 12) -> Label:
	var l: Label = Ui.label(text, font_size, color)
	if width > 0:
		l.custom_minimum_size = Vector2(width, 0)
		l.clip_text = true
	else:
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _system_block() -> PanelContainer:
	var parts = _block("知识树与运行环境")
	var card: PanelContainer = parts[0]
	var col: VBoxContainer = parts[1]

	var kp: Dictionary = {"done": 0, "total": 0}
	if GameState.player != null:
		kp = Knowledge.progress()
	var nodes: Dictionary = {}
	if DataDB.skill_graph != null:
		var raw_nodes: Variant = DataDB.skill_nodes()
		if raw_nodes is Dictionary:
			nodes = raw_nodes
	var unlocked_count := 0
	var skill_count := 0
	if GameState.player != null:
		for raw_id in GameState.player.knowledge.keys():
			if nodes.has(str(raw_id)):
				unlocked_count += 1
	for raw_id in nodes.keys():
		var n: Dictionary = nodes[raw_id]
		if str(n.get("kind", "knowledge")) == "skill":
			skill_count += 1

	var stats := Ui.hbox(20)
	col.add_child(stats)
	stats.add_child(Ui.stat("知识树进度", "%d / %d" % [int(kp.get("done", 0)), int(kp.get("total", 0))], UiTheme.ACCENT))
	stats.add_child(Ui.stat("节点总数", str(nodes.size())))
	stats.add_child(Ui.stat("已解锁节点", str(unlocked_count), UiTheme.OK))
	stats.add_child(Ui.stat("技能节点", str(skill_count), UiTheme.AMBER))

	var info: Dictionary = SaveManager.slot_info(1)
	var info_ok := bool(info.get("ok", false))
	var slot_text := "槽位 1 · 空"
	var slot_color := UiTheme.MUTED
	if info_ok:
		slot_text = "槽位 1 · %s · %d 废铁 · Lv %d · %s" % [_fmt_time(info), int(info.get("scrap", 0)), _level_from_xp(int(info.get("xp", 0))), str(info.get("chapter_id", "—"))]
		slot_color = UiTheme.OK
	else:
		var err := str(info.get("error", ""))
		if not err.is_empty():
			slot_text = "槽位 1 · %s" % err
			slot_color = UiTheme.AMBER

	var save_row := Ui.hbox(12)
	col.add_child(save_row)
	save_row.add_child(Ui.label("当前存档", 11, UiTheme.MUTED))
	save_row.add_child(Ui.label(slot_text, 13, slot_color))
	save_row.add_child(Ui.spacer())
	var last := SaveManager.last_message
	save_row.add_child(Ui.label("最近：%s" % (last if not last.is_empty() else "—"), 11, UiTheme.MUTED))

	var ver: Dictionary = Engine.get_version_info()
	var env_row := Ui.hbox(18)
	col.add_child(env_row)
	env_row.add_child(Ui.stat("Godot", str(ver.get("string", "—"))))
	env_row.add_child(Ui.stat("版本号", "%s.%s.%s" % [str(ver.get("major", "?")), str(ver.get("minor", "?")), str(ver.get("patch", "?"))]))
	env_row.add_child(Ui.stat("平台", OS.get_name()))
	env_row.add_child(Ui.spacer())
	env_row.add_child(Ui.label("界面全部由 GDScript 构建 · 无 .tscn", 11, UiTheme.MUTED))
	return card

func _on_revalidate() -> void:
	if DataDB.has_method("validate"):
		DataDB.call("validate")
		EventBus.toast("已重新校验数据：%d 个问题" % DataDB.errors.size(), "info")
	elif DataDB.has_method("load_all"):
		DataDB.call("load_all")
		var msg := "已重新加载并校验：%d 个问题" % DataDB.errors.size()
		EventBus.toast(msg, ("ok" if DataDB.errors.is_empty() else "warn"))
	else:
		EventBus.toast("数据服务没有校验接口，当前记录 %d 个问题，已刷新显示" % DataDB.errors.size(), "warn")
	call_deferred("on_show")

func _chapter_id() -> String:
	if DataDB.chapter == null:
		return "—"
	var cid := str(DataDB.chapter.id())
	if cid.is_empty():
		return "—"
	return cid

func _chapter_title() -> String:
	if DataDB.chapter == null:
		return "—"
	var t := str(DataDB.chapter.title())
	if t.is_empty():
		return "—"
	return t

func _start_scrap() -> String:
	if DataDB.chapter == null:
		return "—"
	var raw: Variant = DataDB.chapter.data.get("start_scrap", null)
	if raw == null:
		return "—"
	return str(raw)

func _manifest_count() -> int:
	var files: Variant = DataDB.manifest.get("files", [])
	if files is Array:
		var files_arr: Array = files
		return files_arr.size()
	return 0

func _fmt_time(info: Dictionary) -> String:
	var t := str(info.get("updated_at", ""))
	if t.is_empty():
		return "—"
	return t.replace("T", " ")

func _level_from_xp(xp: int) -> int:
	var lv := 1
	for i in PlayerState.XP_LEVELS.size():
		if xp >= int(PlayerState.XP_LEVELS[i]):
			lv = i + 1
	return lv
