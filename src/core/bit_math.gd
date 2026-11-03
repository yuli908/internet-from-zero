class_name BitMath
extends RefCounted

## 进制换算与位操作。纯函数，不依赖场景树，便于 headless 测试。

const DIGITS := "0123456789abcdefghijklmnopqrstuvwxyz"
const MAX_SAFE_INPUT := 1000000000000

static func to_base(value: int, base: int, min_digits: int = 0) -> String:
	if base < 2 or base > 36:
		return ""
	if value < 0:
		return ""
	if value == 0:
		return "0".repeat(maxi(min_digits, 1))
	var digits := ""
	var v := value
	while v > 0:
		var d: int = v % base
		digits = DIGITS[d] + digits
		v = floori(float(v - d) / float(base))
	if digits.length() < min_digits:
		digits = "0".repeat(min_digits - digits.length()) + digits
	return digits

static func from_base(text: String, base: int) -> Dictionary:
	if base < 2 or base > 36:
		return {"ok": false, "value": 0, "error": "进制 %d 不支持（只接受 2-36）" % base}
	var t := text.strip_edges().to_lower()
	if t.is_empty():
		return {"ok": false, "value": 0, "error": "输入为空"}
	var value := 0
	for i in t.length():
		var c := t[i]
		var idx := DIGITS.find(c)
		if idx < 0 or idx >= base:
			return {"ok": false, "value": 0, "error": "字符 '%s' 不属于 %d 进制" % [c, base]}
		value = value * base + idx
		if value > MAX_SAFE_INPUT:
			return {"ok": false, "value": 0, "error": "数值过大（上限 %d）" % MAX_SAFE_INPUT}
	return {"ok": true, "value": value, "error": ""}

static func binary(value: int, bits: int = 0) -> String:
	if value < 0:
		return ""
	var s := to_base(value, 2)
	if bits > 0:
		if s.length() > bits:
			return ""
		s = "0".repeat(bits - s.length()) + s
	return s

static func from_binary(text: String, bits: int = 0) -> Dictionary:
	var res := from_base(text, 2)
	if not res.ok:
		return res
	if bits > 0 and int(res.value) >= (1 << bits):
		return {"ok": false, "value": 0, "error": "超出 %d 位可表示范围 0-%d" % [bits, (1 << bits) - 1]}
	return res

static func max_value(bits: int) -> int:
	if bits <= 0:
		return 0
	return (1 << bits) - 1

static func bits_of(value: int, bit_count: int) -> Array:
	var out := []
	for i in range(bit_count - 1, -1, -1):
		out.append((value >> i) & 1)
	return out

static func value_of_bits(bits: Array) -> int:
	var v := 0
	for b in bits:
		v = (v << 1) | (1 if int(b) != 0 else 0)
	return v

static func grouped(bits: String, group: int = 4) -> String:
	var parts := []
	var i := bits.length()
	while i > 0:
		var start := maxi(i - group, 0)
		parts.push_front(bits.substr(start, i - start))
		i = start
	return " ".join(parts)
