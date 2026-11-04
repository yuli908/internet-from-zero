class_name GrainOverlay
extends ColorRect

## 全屏颗粒层：1 次纹理采样，mouse_filter 永远 IGNORE，不参与交互。

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0, 0, 0, 0)
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://src/ui/shaders/chalk_grain.gdshader")
	mat.set_shader_parameter("noise_tex", UiTheme.grain_texture())
	mat.set_shader_parameter("strength", 0.085)
	material = mat
	visible = UiTheme.texture_enabled
	add_to_group("ifz_grain")

func apply_texture_enabled(on: bool) -> void:
	visible = on
