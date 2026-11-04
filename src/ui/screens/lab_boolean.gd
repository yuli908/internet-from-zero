extends LabBase

## 1.3 布尔：AND / OR / NOT 真值表填写 + 德摩根等价验证。

var _filled: Dictionary = {}
var _cells: Dictionary = {}
var _dm_cells: Array = []
var _dm_note: Label

func _build() -> void:
	# ---- 左栏：任务说明 / 提示 ----
	side.add_child(_section("任务"))
	_add_teaching(side, 12)
	var hint_card := _hint_card(str(lab_data.get("hint", "点击格子循环 0 → 1 → ?；填完运行验收。")))
	side.add_child(hint_card)
	side.add_child(Ui.hline())
	side.add_child(_section("操作"))
	side.add_child(Ui.wrap("点格子循环：? → 0 → 1。填完点右下「运行验收 T1.3」。", UiTheme.F_META, UiTheme.MUTED))
	side.add_child(Ui.spacer())

	# ---- 中栏：三张真值表 ----
	var cols := Ui.hbox(10)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	center.add_child(cols)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL

	for raw in lab_data.get("gates", []):
		var g: Dictionary = raw
		var gid := str(g.get("id", ""))
		var card := Ui.card(UiTheme.BOARD_SUNK, UiTheme.LINE)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cols.add_child(card)
		var m := Ui.margin4(10, 10, 10, 10)
		card.add_child(m)
		var col := Ui.vbox(6)
		m.add_child(col)
		col.add_child(Ui.label(str(g.get("name", gid)), UiTheme.F_LABEL, UiTheme.CHALK))
		var grid := GridContainer.new()
		grid.columns = int(g.get("inputs", 2)) + 1
		grid.add_theme_constant_override("h_separation", 4)
		grid.add_theme_constant_override("v_separation", 4)
		col.add_child(grid)
		var inputs := int(g.get("inputs", 2))
		for k in inputs:
			grid.add_child(_cell_head("ABCD".substr(k, 1)))
		grid.add_child(_cell_head("Y"))
		var expected: Array = g.get("expected", [])
		var gate_rows: Array = g.get("rows", [])
		_filled[gid] = _filled.get(gid, [])
		while _filled[gid].size() < expected.size():
			_filled[gid].append("?")
		for i in expected.size():
			var rowdata: Array = gate_rows[i]
			for k in rowdata.size():
				grid.add_child(Ui.mono(str(int(rowdata[k])), UiTheme.F_BODY, UiTheme.MUTED))
			var idx := i
			var btn := Ui.toggle("?", func(): _cycle(gid, idx))
			btn.custom_minimum_size = Vector2(0, 40)
			btn.add_theme_font_override("font", UiTheme.mono_font())
			grid.add_child(btn)
			_cells["%s:%d" % [gid, i]] = btn

	# ---- 右栏：德摩根 + 验收 ----
	inspector.add_child(_section("德摩根"))
	var dcfg: Dictionary = lab_data.get("demorgan", {})
	inspector.add_child(Ui.wrap("%s ≡ %s" % [str(dcfg.get("left", "?")), str(dcfg.get("right", "?"))], UiTheme.F_BODY, UiTheme.CHALK))
	var dgrid := GridContainer.new()
	dgrid.columns = 4
	dgrid.add_theme_constant_override("h_separation", 4)
	dgrid.add_theme_constant_override("v_separation", 4)
	inspector.add_child(dgrid)
	for name_text in ["A", "B", str(dcfg.get("left", "左")), str(dcfg.get("right", "右"))]:
		dgrid.add_child(_cell_head(str(name_text)))
	var rows: Array = dcfg.get("rows", [])
	_filled["demorgan"] = _filled.get("demorgan", [])
	while _filled["demorgan"].size() < rows.size():
		_filled["demorgan"].append("?")
	for i in rows.size():
		var pair: Array = rows[i]
		dgrid.add_child(Ui.mono(str(int(pair[0])), UiTheme.F_BODY, UiTheme.MUTED))
		dgrid.add_child(Ui.mono(str(int(pair[1])), UiTheme.F_BODY, UiTheme.MUTED))
		dgrid.add_child(Ui.mono(SimValue.not3(SimValue.bin3("and", str(int(pair[0])), str(int(pair[1])))), UiTheme.F_BODY, UiTheme.CYAN))
		var idx := i
		var btn := Ui.toggle("?", func(): _cycle_dm(idx))
		btn.custom_minimum_size = Vector2(44, 40)
		btn.add_theme_font_override("font", UiTheme.mono_font())
		dgrid.add_child(btn)
		_dm_cells.append(btn)
	_dm_note = Ui.muted("填右列，使两边相等。", UiTheme.F_META)
	inspector.add_child(_dm_note)
	inspector.add_child(Ui.hline())
	inspector.add_child(Ui.spacer())
	inspector.add_child(Ui.button("运行验收 T1.3", func(): _run_cases(), true))

	_load_state()
	_refresh_cells()

func _cell_head(text: String) -> Label:
	var l := Ui.mono(text, UiTheme.F_META, UiTheme.MUTED)
	l.custom_minimum_size = Vector2(40, 0)
	return l

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
		b.add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if v != "?" else UiTheme.MUTED)
	var dm: Array = _filled.get("demorgan", [])
	for i in _dm_cells.size():
		var v := str(dm[i]) if dm.size() > i else "?"
		_dm_cells[i].text = v
		_dm_cells[i].add_theme_color_override("font_color", UiTheme.CHALK_BRIGHT if v != "?" else UiTheme.MUTED)

func _run_cases() -> void:
	var rep := LabChecks.boolean(lab_data, _filled)
	show_report(rep)
	if pass_report(rep):
		EventBus.toast("1.3 布尔 gate 全部通过", "ok")
	else:
		EventBus.toast("仍有格子填错；? 表示未填", "warn")

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

func scripted_solve() -> bool:
	## 脚本走查：把真值表与德摩根表填成正确值，再走真实验收/发奖链路。
	for raw in lab_data.get("gates", []):
		var g: Dictionary = raw
		var gid := str(g.get("id", ""))
		var expected: Array = g.get("expected", [])
		var arr: Array = _filled.get(gid, [])
		while arr.size() < expected.size():
			arr.append("?")
		for i in expected.size():
			arr[i] = str(int(expected[i]))
		_filled[gid] = arr
	var rows: Array = lab_data.get("demorgan", {}).get("rows", [])
	var dm: Array = _filled.get("demorgan", [])
	while dm.size() < rows.size():
		dm.append("?")
	for i in rows.size():
		var pair: Array = rows[i]
		var a := str(int(pair[0]))
		var b := str(int(pair[1]))
		dm[i] = SimValue.not3(SimValue.bin3("and", a, b))
	_filled["demorgan"] = dm
	_refresh_cells()
	_save_state()
	_run_cases()
	return is_done()
