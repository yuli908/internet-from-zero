shader_type canvas_item;

// 静态粉笔颗粒：只在 UV 上采样一次预生成噪声，不含 TIME，不逐帧变化。
uniform sampler2D noise_tex : repeat_enable, filter_nearest;
uniform float strength = 0.085;
uniform vec4 chalk : source_color = vec4(0.91, 0.89, 0.84, 1.0);

void fragment() {
	float n = texture(noise_tex, UV * 3.0).r;
	float a = strength * (0.35 + 0.65 * n);
	COLOR = vec4(chalk.rgb, a);
}
