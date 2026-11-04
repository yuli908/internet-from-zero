class_name StartScreen
extends GameScreen

## 开始界面：左侧错位叠字、右侧 45° 菱形碎片菜单。键盘可达，Esc 打开设置。

signal start_game
signal open_settings

const TITLE_FS := 104
const MENU_W := 500

var _title_stack: Control
var _ghost1: Label
var _ghost2: Label
var _ghost3: Label
var _ghosts: Array = []
var _bases: Array = []
var _players: Array = []
var _menu: Control
var _shards: Array = []
var _hint: Label
var _selected := 0
var _settings: SettingsPanel

func setup(main_ref: Control) -> void:
	super.setup(main_ref)
	_build()
	_settings = SettingsPanel.new()
	_settings.motion_changed.connect(func(_on): _apply_motion())
	add_child(_settings)

func _ready() -> void:
	_build_wobble()
	_apply_motion()
	_select(0)
	(_shards[0] as ShardButton).grab_focus()
	for i in _shards.size():
		var idx := i
		(_shards[i] as ShardButton).focus_entered.connect(func(): _select(idx))

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = UiTheme.BG
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var grain := GrainOverlay.new()
	grain.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(grain)

	var body := Ui.hbox(0)
	body.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(body)

	var left := Ui.margin4(72, 24, 54, 72)
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	var left_v := Ui.vbox(0)
	left.add_child(left_v)

	left_v.add_child(_spacer_v())
	var kicker := Ui.label("FROM VOLTAGE TO LOGIC", UiTheme.F_LABEL, Color("#AAB6AF"))
	kicker.add_theme_font_override("font", _spaced_font(5))
	left_v.add_child(kicker)
	left_v.add_child(Ui.gap(12))

	_title_stack = Control.new()
	_title_stack.custom_minimum_size = Vector2(660, 222)
	_title_stack.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_title_stack.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_v.add_child(_title_stack)
	_build_title()
	left_v.add_child(Ui.gap(40))

	var sub_row := Ui.hbox(14)
	sub_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var rule := ColorRect.new()
	rule.color = Color("#5E736A")
	rule.custom_minimum_size = Vector2(56, 1)
	rule.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sub_row.add_child(rule)
	sub_row.add_child(Ui.label("互联网 · 从零重建　第一章「电与逻辑」", 19, Color("#AAB6AF")))
	left_v.add_child(sub_row)
	left_v.add_child(_spacer_v())

	var right := Control.new()
	right.custom_minimum_size = Vector2(MENU_W, 0)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(right)

	_menu = Control.new()
	_menu.custom_minimum_size = Vector2(340, 340)
	_menu.size = Vector2(340, 340)
	_menu.pivot_offset = Vector2(170, 170)
	_menu.rotation = deg_to_rad(45.0)
	_menu.mouse_filter = Control.MOUSE_FILTER_PASS
	right.add_child(_menu)
	_menu.position = Vector2(82, 190)
	right.resized.connect(_place_menu)

	var shard_start := ShardButton.new()
	shard_start.setup("开始游戏", false)
	shard_start.position = Vector2(0, 173)
	shard_start.activated.connect(func(): start_game.emit())
	shard_start.hovered.connect(func(): _select(0))
	_menu.add_child(shard_start)
	_shards.append(shard_start)

	var shard_settings := ShardButton.new()
	shard_settings.setup("设置", true)
	shard_settings.position = Vector2(0, 0)
	shard_settings.activated.connect(func(): open_settings.emit(); open_settings_panel())
	shard_settings.hovered.connect(func(): _select(1))
	_menu.add_child(shard_settings)
	_shards.append(shard_settings)

	_hint = Ui.label("↑ ↓ 切换　ENTER 确认　当前：开始游戏", UiTheme.F_BODY, Color("#AAB6AF"))
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	_hint.offset_left = 15
	_hint.offset_right = -15
	_hint.offset_top = -36
	_hint.offset_bottom = -10
	right.add_child(_hint)

	var foot := MarginContainer.new()
	foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	foot.offset_top = -46
	foot.add_theme_constant_override("margin_left", 72)
	foot.add_theme_constant_override("margin_right", 72)
	foot.add_theme_constant_override("margin_bottom", 28)
	add_child(foot)
	var foot_row := Ui.hbox(20)
	foot.add_child(foot_row)
	for text in ["↑ ↓ 选择", "ENTER 确认", "ESC 设置", "单存档 · 36 节点"]:
		foot_row.add_child(Ui.label(text, UiTheme.F_BODY, UiTheme.MUTED))

func _build_title() -> void:
	# 叠加顺序：Ghost3 → Ghost2 → Ghost1 → Solid。
	_ghost3 = _make_title_layer("Ghost3", Vector2(6, 3), Color("#34433D"), 0.28, true)
	_ghost2 = _make_title_layer("Ghost2", Vector2(4, 2), Color("#5E736A"), 0.38, true)
	_ghost1 = _make_title_layer("Ghost1", Vector2(2, 1), Color("#9AAB9F"), 0.55, true)
	_make_title_layer("Solid", Vector2(0, 0), Color("#E9E5D8"), 1.0, false)
	_ghosts = [_ghost1, _ghost2, _ghost3]
	_bases = [Vector2(2, 1), Vector2(4, 2), Vector2(6, 3)]

func _make_title_layer(nm: String, pos: Vector2, color: Color, alpha: float, outline: bool) -> Label:
	var l := Label.new()
	l.name = nm
	l.text = "INTERNET\nFROM ZERO"
	l.position = pos
	l.size = Vector2(660, 222)
	l.clip_text = false
	l.autowrap_mode = TextServer.AUTOWRAP_OFF
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", UiTheme.title_font_variation(-4))
	l.add_theme_font_size_override("font_size", TITLE_FS)
	l.add_theme_constant_override("line_spacing", -14)
	if outline:
		l.add_theme_color_override("font_color", Color(0, 0, 0, 0))
		l.add_theme_color_override("font_outline_color", color)
		l.add_theme_constant_override("outline_size", 2)
		l.modulate.a = alpha
	else:
		l.add_theme_color_override("font_color", color)
		l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.30))
		l.add_theme_constant_override("shadow_offset_x", 1)
		l.add_theme_constant_override("shadow_offset_y", 2)
	_title_stack.add_child(l)
	return l

func _build_wobble() -> void:
	for i in 3:
		var p := AnimationPlayer.new()
		_title_stack.add_child(p)
		var anim := Animation.new()
		anim.length = 3.2
		anim.loop_mode = Animation.LOOP_LINEAR
		var tr := anim.add_track(Animation.TYPE_VALUE)
		anim.track_set_path(tr, "%s:position" % _ghosts[i].name)
		var base: Vector2 = _bases[i]
		anim.track_insert_key(tr, 0.0, base)
		anim.track_insert_key(tr, 1.6, base + Vector2(1.5, 0.75))
		anim.track_insert_key(tr, 3.2, base)
		var lib := AnimationLibrary.new()
		lib.add_animation("wobble", anim)
		p.add_animation_library("", lib)
		_players.append(p)

func _apply_motion() -> void:
	for i in _players.size():
		var p: AnimationPlayer = _players[i]
		if UiTheme.motion:
			p.play("wobble")
			p.seek([0.0, 1.0667, 2.1333][i], true)
		else:
			p.stop()
			(_ghosts[i] as Label).position = _bases[i]

func _select(idx: int) -> void:
	_selected = clampi(idx, 0, _shards.size() - 1)
	for i in _shards.size():
		(_shards[i] as ShardButton).set_selected(i == _selected)
	if _hint != null:
		_hint.text = "↑ ↓ 切换　ENTER 确认　当前：%s" % ("开始游戏" if _selected == 0 else "设置")

func open_settings_panel() -> void:
	if _settings != null:
		_settings.open()

func _unhandled_key_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.pressed or event.echo:
		return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		open_settings_panel()
		return
	if _settings != null and _settings.visible:
		return
	if event.keycode == KEY_UP or event.keycode == KEY_DOWN:
		get_viewport().set_input_as_handled()
		_select(1 - _selected)
		(_shards[_selected] as ShardButton).grab_focus()
	elif event.keycode == KEY_M:
		get_viewport().set_input_as_handled()
		UiTheme.motion = not UiTheme.motion
		_apply_motion()

func _place_menu() -> void:
	var right := _menu.get_parent() as Control
	if right == null:
		return
	_menu.position = Vector2(MENU_W - 78 - 340, (right.size.y - 340) * 0.5)

func _spacer_v() -> Control:
	var c := Control.new()
	c.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c

func _spaced_font(px: int) -> FontVariation:
	return UiTheme.title_font_variation(float(px))
