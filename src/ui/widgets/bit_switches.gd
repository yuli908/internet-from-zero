class_name BitSwitches
extends VBoxContainer

## 8 位（可配置）二进制开关。位 0 在最下方/最后，显示时高位在上。

signal changed(value: int)

var bit_count := 8
var _bits: Array = []
var _buttons: Array = []

func setup(count: int = 8, initial: int = 0) -> void:
	bit_count = count
	_bits.clear()
	_buttons.clear()
	for c in get_children():
		c.queue_free()
	add_theme_constant_override("separation", 3)
	for i in range(bit_count - 1, -1, -1):
		var bit := (initial >> i) & 1
		_bits.append(bit)
		var row := Ui.hbox(8)
		var weight := 1 << i
		var name_label := Ui.mono("b%d" % i, 14, UiTheme.MUTED)
		name_label.custom_minimum_size = Vector2(34, 0)
		row.add_child(name_label)
		var wlabel := Ui.label("×%d" % weight, 14, UiTheme.MUTED)
		wlabel.custom_minimum_size = Vector2(52, 0)
		row.add_child(wlabel)
		var btn := Ui.toggle("0", func(): _on_toggle(i), bit == 1)
		btn.custom_minimum_size = Vector2(0, 30)
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_override("font", UiTheme.mono_font())
		btn.add_theme_font_size_override("font_size", 15)
		row.add_child(btn)
		add_child(row)
		_buttons.append(btn)
	_refresh_labels()

func _on_toggle(index: int) -> void:
	_bits[index] = 0 if _bits[index] == 1 else 1
	_refresh_labels()
	changed.emit(value())

func _refresh_labels() -> void:
	for i in _buttons.size():
		var b: Button = _buttons[i]
		var on := int(_bits[i]) == 1
		b.text = "1" if on else "0"
		b.add_theme_color_override("font_color", UiTheme.OK if on else UiTheme.MUTED)

func value() -> int:
	var v := 0
	for i in _bits.size():
		var weight := 1 << (bit_count - 1 - i)
		if int(_bits[i]) == 1:
			v |= weight
	return v

func set_value(v: int) -> void:
	for i in _bits.size():
		var bit := (v >> (bit_count - 1 - i)) & 1
		_bits[i] = bit
		_buttons[i].set_pressed_no_signal(bit == 1)
	_refresh_labels()
