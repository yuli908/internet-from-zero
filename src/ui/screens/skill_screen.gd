class_name SkillScreen
extends GameScreen

## 双树 + 技能树：进度 / 知识 / 技能三列，四态（已完成/可解锁/挑战/锁定）。

const TREE_DEFS := [
	{"id": "progress", "title": "进度", "hint": "章节里程碑"},
	{"id": "knowledge", "title": "知识", "hint": "概念卡"},
	{"id": "skill", "title": "技能", "hint": "工具与能力"},
]

var _columns: Dictionary = {}
var _detail_title: Label
var _detail_text: Label
var _unlock_host: HBoxContainer
var _selected := ""
var _stats: Label

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()

func _build() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var root := Ui.vbox(8)
	add_child(root)
	var head := Ui.hbox(10)
	root.add_child(head)
	head.add_child(Ui.label("知识树", 20, UiTheme.TEXT))
	_stats = Ui.label("", 11, UiTheme.MUTED)
	head.add_child(_stats)
	head.add_child(Ui.spacer())
	head.add_child(Ui.label("点击节点查看前置；可解锁的节点消耗 XP 或随 gate 自动解锁", 10, UiTheme.MUTED))

	var cols := Ui.hbox(8)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	for def in TREE_DEFS:
		var card := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cols.add_child(card)
		var m := Ui.margin4(9, 8, 9, 8)
		card.add_child(m)
		var col := Ui.vbox(5)
		m.add_child(col)
		var tr := Ui.hbox(6)
		col.add_child(tr)
		tr.add_child(Ui.label(str(def["title"]), 14, UiTheme.TEXT))
		tr.add_child(Ui.label(str(def["hint"]), 10, UiTheme.MUTED))
		col.add_child(Ui.hline())
		var scroll := Ui.scroll()
		scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
		col.add_child(scroll)
		var box := Ui.vbox(5)
		box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		scroll.add_child(box)
		_columns[str(def["id"])] = box

	var detail := Ui.card(UiTheme.PANEL_3, UiTheme.ACCENT, 8)
	detail.custom_minimum_size = Vector2(0, 92)
	root.add_child(detail)
	var dm := Ui.margin4(12, 8, 12, 8)
	detail.add_child(dm)
	var dcol := Ui.vbox(4)
	dm.add_child(dcol)
	_detail_title = Ui.label("选择一个节点", 14, UiTheme.TEXT)
	dcol.add_child(_detail_title)
	_detail_text = Ui.wrap("左侧/中间节点会显示说明与前置条件。", 11, UiTheme.MUTED)
	_detail_text.custom_minimum_size = Vector2(0, 32)
	dcol.add_child(_detail_text)
	_unlock_host = Ui.hbox(6)
	dcol.add_child(_unlock_host)

func on_show() -> void:
	_rebuild()

func _rebuild() -> void:
	for key in _columns.keys():
		var box: VBoxContainer = _columns[key]
		for c in box.get_children():
			c.queue_free()
		var graph := DataDB.skill_graph
		var ids: Array = graph.nodes_of_tree(str(key))
		ids.sort_custom(func(a, b):
			var pa: Dictionary = graph.node(str(a)).get("pos", {})
			var pb: Dictionary = graph.node(str(b)).get("pos", {})
			return int(pa.get("row", 0)) < int(pb.get("row", 0)) or (int(pa.get("row", 0)) == int(pb.get("row", 0)) and int(pa.get("col", 0)) < int(pb.get("col", 0)))
		)
		for raw_id in ids:
			var id := str(raw_id)
			box.add_child(_node_card(id))
		if ids.is_empty():
			box.add_child(Ui.muted("（空）", 11))
	var p := Knowledge.progress()
	_stats.text = "已解锁 %d / %d" % [int(p.get("done", 0)), int(p.get("total", 0))]
	if not _selected.is_empty():
		_select(_selected)

func _node_card(id: String) -> Control:
	var graph := DataDB.skill_graph
	var st := graph.node_state(GameState.player, id)
	var n: Dictionary = graph.node(id)
	var color := UiTheme.MUTED
	var label := "锁定"
	match st:
		"completed":
			color = UiTheme.OK
			label = "已完成"
		"available":
			color = UiTheme.ACCENT
			label = "可解锁"
		"challenge":
			color = UiTheme.AMBER
			label = "挑战"
		"locked":
			color = UiTheme.MUTED
			label = "锁定"
	var card := Ui.card(UiTheme.alpha(color, 0.10) if st != "locked" else UiTheme.PANEL, color, 6)
	var m := Ui.margin4(8, 5, 8, 5)
	card.add_child(m)
	var row := Ui.hbox(6)
	m.add_child(row)
	var b := Ui.button(str(n.get("title", id)), func(): _select(id), false)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.flat = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 12)
	row.add_child(b)
	row.add_child(Ui.label(label, 10, color))
	return card

func _select(id: String) -> void:
	_selected = id
	var graph := DataDB.skill_graph
	var n: Dictionary = graph.node(id)
	var st := graph.node_state(GameState.player, id)
	_detail_title.text = "%s · %s" % [str(n.get("title", id)), _state_text(st)]
	var lines := []
	var desc := str(n.get("desc", ""))
	if not desc.is_empty():
		lines.append(desc)
	var req: Dictionary = graph.requirements_met(GameState.player, id)
	if st == "locked" or st == "challenge":
		lines.append("未满足：%s" % str(req.get("error", "前置条件不足")))
	if int(n.get("xp_cost", 0)) > 0 and st != "completed":
		lines.append("解锁消耗 %d XP" % int(n.get("xp_cost", 0)))
	var eff: Variant = n.get("effects", null)
	if eff != null:
		lines.append("效果：%s" % str(eff))
	_detail_text.text = "\n".join(PackedStringArray(lines))
	for c in _unlock_host.get_children():
		c.queue_free()
	var check: Dictionary = graph.can_unlock(GameState.player, id)
	if st != "completed" and bool(check.get("ok", false)):
		_unlock_host.add_child(Ui.button("解锁 %s" % str(n.get("title", id)), func(): _do_unlock(id), true))
	else:
		_unlock_host.add_child(Ui.muted("状态：%s" % _state_text(st), 11))

func _do_unlock(id: String) -> void:
	var res := Knowledge.unlock(id)
	if not bool(res.get("ok", false)):
		EventBus.toast("解锁失败：%s" % str(res.get("error", "")), "error")
	_rebuild()

func _state_text(st: String) -> String:
	match st:
		"completed":
			return "已完成"
		"available":
			return "可解锁"
		"challenge":
			return "挑战"
		_:
			return "锁定"
