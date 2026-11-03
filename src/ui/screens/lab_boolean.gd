extends LabBase

## 1.3 布尔：AND / OR / NOT 真值表填写 + 德摩根等价验证。

var _filled: Dictionary = {}
var _cells: Dictionary = {}
var _dm_cells: Array = []
var _report_box: VBoxContainer
var _dm_note: Label

func _build() -> void:
	var root := Ui.vbox(10)
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(root)
	root.add_child(_build_header(str(lab_data.get("title", "布尔")), str(lab_data.get("subtitle", ""))))
	root.add_child(_body_card(str(lab_data.get("body", ""))))
	root.add_child(_hint_card(str(lab_data.get("hint", ""))))

	var cols := Ui.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)

	for raw in lab_data.get("gates", []):
		var g: Dictionary = raw
		var gid := str(g.get("id", ""))
		var card := Ui.card(UiTheme.PANEL_2, UiTheme.BORDER, 8)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(card)
		var m := Ui.margin4(10, 8, 10, 8)
		card.add_child(m)
		var col := Ui.vbox(6)
		m.add_child(col)
		col.add_child(Ui.label(str(g.get("name", gid)), 14, UiTheme.TEXT))
		var grid := GridContainer.new()
		grid.columns = int(g.get("inputs", 2)) + 1
		grid.add_theme_constant_override("h_separation", 6)
		grid.add_theme_constant_override("v_separation", 4)
		col.add_child(grid)
		var inputs := int(g.get("inputs", 2))
		for k in inputs:
			grid.add_child(Ui.mono("ABCD".substr(k, 1), 12, UiTheme.MUTED))
		grid.add_child(Ui.mono("Y", 12, UiTheme.MUTED))
		var expected: Array = g.get("expected", [])
		var gate_rows: Array = g.get("rows", [])
		_filled[gid] = _filled.get(gid, [])
		while _filled[gid].size() < expected.size():
			_filled[gid].append("?")
		for i in expected.size():
			var rowdata: Array = gate_rows[i]
			for k in rowdata.size():
				grid.add_child(Ui.mono(str(int(rowdata[k])), 13, UiTheme.TEXT))
			var idx := i
			var btn := Ui.toggle("?", func(): _cycle(gid, idx))
			btn.custom_minimum_size = Vector2(0, 28)
			btn.add_theme_font_override("font", UiTheme.mono_font())
			grid.add_child(btn)
			_cells["%s:%d" % [gid, i]] = btn

	var dm_card := Ui.card(UiTheme.PANEL, UiTheme.BORDER, 8)
	dm_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	cols.add_child(dm_card)
	var dm := Ui.margin4(10, 8, 10, 8)
	dm_card.add_child(dm)
	var dcol := Ui.vbox(6)
	dm.add_child(dcol)
	var dcfg: Dictionary = lab_data.get("demorgan", {})
	dcol.add_child(Ui.label("德摩根：%s ≡ %s" % [str(dcfg.get("left", "?")), str(dcfg.get("right", "?"))], 13, UiTheme.TEXT))
	var dgrid := GridContainer.new()
	dgrid.columns = 4
	dgrid.add_theme_constant_override("h_separation", 6)
	dgrid.add_theme_constant_override("v_separation", 4)
	dcol.add_child(dgrid)
	for name_text in ["A", "B", str(dcfg.get("left", "左")), str(dcfg.get("right", "右"))]:
		dgrid.add_child(Ui.mono(str(name_text), 11, UiTheme.MUTED))
	var rows: Array = dcfg.get("rows", [])
	_filled["demorgan"] = _filled.get("demorgan", [])
	while _filled["demorgan"].size() < rows.size():
		_filled["demorgan"].append("?")
	for i in rows.size():
		var pair: Array = rows[i]
		dgrid.add_child(Ui.mono(str(int(pair[0])), 12, UiTheme.TEXT))
		dgrid.add_child(Ui.mono(str(int(pair[1])), 12, UiTheme.TEXT))
		dgrid.add_child(Ui.mono(SimValue.not3(SimValue.bin3("and", str(int(pair[0])), str(int(pair[1])))), 12, UiTheme.ACCENT))
		var idx := i
		var btn := Ui.toggle("?", func(): _cycle_dm(idx))
		btn.custom_minimum_size = Vector2(40, 26)
		btn.add_theme_font_override("font", UiTheme.mono_font())
		dgrid.add_child(btn)
		_dm_cells.append(btn)
	_dm_note = Ui.muted("填右列，使两边相等。", 11)
	dcol.add_child(_dm_note)

	var bottom := Ui.hbox(8)
	root.add_child(bottom)
	var run_btn := Ui.button("运行验收 T1.3", func(): _run_cases(), true)
	bottom.add_child(run_btn)
	bottom.add_child(Ui.muted("填表后点验收；全部 4 条 gate 通过才写入知识树。", 11))

	_report_box = Ui.vbox(3)
	root.add_child(_report_box)

	_load_state()
	_refresh_cells()

func _cycle(gid: String, idx: int) -> void:
	var arr: Array = _filled.get(gid, [])
	var cur := str(arr[idx])
	if cur == "?":
		arr[idx] = "0"
	elif cur == "0":
		arr[idx] = "1"
	else:
		arr[idx] = "?"
	_filled[gid] = arr
	_refresh_cells()
	_save_state()

func _cycle_dm(idx: int) -> void:
	var arr: Array = _filled.get("demorgan", [])
	var cur := str(arr[idx])
	if cur == "?":
		arr[idx] = "0"
	elif cur == "0":
		arr[idx] = "1"
	else:
		arr[idx] = "?"
	_filled["demorgan"] = arr
	_refresh_cells()
	_save_state()

func _refresh_cells() -> void:
	for key in _cells.keys():
		var parts := str(key).split(":")
		var gid := parts[0]
		var idx := int(parts[1])
		var b: Button = _cells[key]
		var arr: Array = _filled.get(gid, [])
		var v := str(arr[idx]) if arr.size() > idx else "?"
		b.text = v
		b.add_theme_color_override("font_color", UiTheme.OK if v != "?" else UiTheme.MUTED)
	var dm: Array = _filled.get("demorgan", [])
	for i in _dm_cells.size():
		var v := str(dm[i]) if dm.size() > i else "?"
		_dm_cells[i].text = v
		_dm_cells[i].add_theme_color_override("font_color", UiTheme.OK if v != "?" else UiTheme.MUTED)

func _run_cases() -> void:
	var rep := LabChecks.boolean(lab_data, _filled)
	_show_report(rep)
	if pass_report(rep):
		EventBus.toast("1.3 布尔 gate 全部通过", "ok")
	else:
		EventBus.toast("仍有格子填错；? 表示未填", "warn")

func _show_report(rep: GateReport) -> void:
	for c in _report_box.get_children():
		c.queue_free()
	for raw in rep.cases:
		var c: Dictionary = raw
		var ok := bool(c.get("ok", false))
		var color := UiTheme.OK if ok else UiTheme.DANGER
		_report_box.add_child(Ui.label("%s %s  %s" % ["✓" if ok else "✗", str(c.get("id", "")), str(c.get("detail", ""))], 11, color))

func _save_state() -> void:
	save_state({"filled": _filled})

func _load_state() -> void:
	var st := load_state()
	if st.is_empty():
		return
	var f: Variant = st.get("filled", null)
	if f is Dictionary:
		for k in f.keys():
			_filled[str(k)] = f[k]
