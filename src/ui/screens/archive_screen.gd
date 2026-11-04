extends GameScreen

## 档案页：三槽位存档管理、读取、删除与机制说明。

const SLOT_COUNT = 3

var _slots_host: VBoxContainer

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func on_show() -> void:
	_refresh_slots()

func _build() -> void:
	# 抬头（标题 / 返回）由 main 统一绘制；本页只放三槽位列表，内容从 y92 起。
	var page := Ui.vbox(10)
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(page)

	var scroll := Ui.scroll()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(scroll)

	_slots_host = Ui.vbox(8)
	_slots_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_slots_host)

func _clear(container: Node) -> void:
	for c in container.get_children():
		container.remove_child(c)
		c.queue_free()

func _refresh_slots() -> void:
	if _slots_host == null:
		return
	_clear(_slots_host)
	for i in SLOT_COUNT:
		_slots_host.add_child(_slot_card(i + 1))

func _slot_card(slot: int) -> PanelContainer:
	var info: Dictionary = SaveManager.slot_info(slot)
	var exists := bool(info.get("ok", false))
	var err := str(info.get("error", ""))

	var card: PanelContainer
	if slot == 1:
		card = Ui.card(UiTheme.PANEL, UiTheme.alpha(UiTheme.ACCENT, 0.45), 8)
	else:
		card = Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	var m := Ui.margin4(12, 9, 12, 9)
	card.add_child(m)
	var col := Ui.vbox(6)
	m.add_child(col)

	var head := Ui.hbox(10)
	col.add_child(head)
	head.add_child(Ui.mono("槽 %d" % slot, 18, UiTheme.ACCENT))

	var dot_color := UiTheme.OK
	if not exists:
		dot_color = UiTheme.MUTED if (err == "空槽位" or err.is_empty()) else UiTheme.DANGER
	# 槽位状态只用圆点：绿=可读，灰=空，锈红=损坏；损坏原因走 tooltip，不常驻成句。
	var dot := Ui.status_dot(dot_color, 8)
	if not exists and dot_color == UiTheme.DANGER:
		dot.tooltip_text = "校验失败：%s" % err
	head.add_child(dot)
	head.add_child(Ui.spacer())
	head.add_child(Ui.label(_fmt_time(info) if exists else "—", UiTheme.F_META, UiTheme.MUTED))

	var lv_text := "—"
	var gold_text := "—"
	var chapter_text := "—"
	var obj_text := "—"
	var know_text := "—"
	if exists:
		var xp := int(info.get("xp", 0))
		lv_text = "Lv %d" % _level_from_xp(xp)
		gold_text = str(int(info.get("gold", 0)))
		var cid := str(info.get("chapter_id", ""))
		if not cid.is_empty():
			chapter_text = cid
		obj_text = "%d / %d" % [int(info.get("objectives", 0)), _objective_total()]
		know_text = "%d / %d" % [int(info.get("knowledge", 0)), _knowledge_total()]

	var stats := Ui.hbox(20)
	col.add_child(stats)
	stats.add_child(Ui.stat("等级", lv_text, UiTheme.ACCENT))
	stats.add_child(Ui.stat("金币", gold_text, UiTheme.AMBER))
	stats.add_child(Ui.stat("章节", chapter_text))
	stats.add_child(Ui.stat("目标", obj_text))
	stats.add_child(Ui.stat("知识", know_text))

	var actions := Ui.hbox(8)
	col.add_child(actions)
	actions.add_child(Ui.spacer())

	var save_btn := Ui.button("保存到此槽", _on_save.bind(slot), slot == 1)
	save_btn.custom_minimum_size = Vector2(112, 30)
	actions.add_child(save_btn)

	var load_btn := Ui.button("读取", _on_load.bind(slot))
	load_btn.custom_minimum_size = Vector2(78, 30)
	load_btn.disabled = not SaveManager.has_slot(slot)
	actions.add_child(load_btn)

	var del_btn := Ui.ghost("删除", _on_delete.bind(slot))
	del_btn.custom_minimum_size = Vector2(78, 30)
	del_btn.disabled = not SaveManager.has_slot(slot)
	del_btn.add_theme_color_override("font_color", UiTheme.DANGER)
	actions.add_child(del_btn)
	return card

func _on_save(slot: int) -> void:
	SaveManager.save_game(slot)
	call_deferred("on_show")

func _on_load(slot: int) -> void:
	SaveManager.load_game(slot)
	call_deferred("on_show")

func _on_delete(slot: int) -> void:
	var dlg := ConfirmationDialog.new()
	dlg.title = "确认删除"
	dlg.dialog_text = "删除槽位 %d 的存档？主文件与 .bak 备份都会被移除，且无法恢复。" % slot
	dlg.ok_button_text = "删除"
	dlg.cancel_button_text = "取消"
	dlg.exclusive = true
	if theme != null:
		dlg.theme = theme
	else:
		dlg.theme = UiTheme.build()
	add_child(dlg)
	dlg.confirmed.connect(_on_delete_confirmed.bind(slot, dlg))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered(Vector2i(460, 160))

func _on_delete_confirmed(slot: int, dlg: Window) -> void:
	SaveManager.delete_slot(slot)
	if is_instance_valid(dlg):
		dlg.queue_free()
	call_deferred("on_show")

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

func _objective_total() -> int:
	if DataDB.chapter == null:
		return 0
	return DataDB.chapter.objective_order.size()

func _knowledge_total() -> int:
	if DataDB.skill_graph == null:
		return 0
	return DataDB.skill_nodes().size()
