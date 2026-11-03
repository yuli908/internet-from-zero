class_name SimValue
extends RefCounted

## 三值逻辑（Kleene 强完备）：0 / 1 / X。
## 与 docs/simulation/ref/simcore/logic.py 的 _KLEENE 完全一致。
## 约定：X 表示未知/竞争/亚稳态，不是第三路电平；总线的高阻 Z 不在此层建模。

const X := "X"
const ZERO := "0"
const ONE := "1"

const GATE_DELAY := {
	"buf": 1, "not": 1,
	"nand": 2, "nor": 2,
	"and": 3, "or": 3,
	"xor": 4, "xnor": 5,
}

const _AND := {
	"0|0": "0", "0|1": "0", "0|X": "0",
	"1|0": "0", "1|1": "1", "1|X": "X",
	"X|0": "0", "X|1": "X", "X|X": "X",
}
const _OR := {
	"0|0": "0", "0|1": "1", "0|X": "X",
	"1|0": "1", "1|1": "1", "1|X": "1",
	"X|0": "X", "X|1": "1", "X|X": "X",
}
const _XOR := {
	"0|0": "0", "0|1": "1", "0|X": "X",
	"1|0": "1", "1|1": "0", "1|X": "X",
	"X|0": "X", "X|1": "X", "X|X": "X",
}

static func not3(v: String) -> String:
	if v == ZERO:
		return ONE
	if v == ONE:
		return ZERO
	return X

static func bin3(kind: String, a: String, b: String) -> String:
	var key := "%s|%s" % [a, b]
	match kind:
		"and":
			return str(_AND.get(key, X))
		"or":
			return str(_OR.get(key, X))
		"xor":
			return str(_XOR.get(key, X))
		_:
			return X

static func gate(kind: String, values: Array) -> String:
	if values.is_empty():
		return X
	if kind == "buf":
		return str(values[0])
	if kind == "not":
		return not3(str(values[0]))
	var base := kind
	var invert := false
	if kind == "nand":
		base = "and"
		invert = true
	elif kind == "nor":
		base = "or"
		invert = true
	elif kind == "xnor":
		base = "xor"
		invert = true
	if base not in ["and", "or", "xor"]:
		return X
	var acc := str(values[0])
	for i in range(1, values.size()):
		acc = bin3(base, acc, str(values[i]))
	return not3(acc) if invert else acc

static func is_unknown(bits: String) -> bool:
	return bits.contains(X)

static func bits_of(value: int, width: int) -> String:
	if width <= 0:
		return ""
	var v := value
	if v < 0:
		v = v + (1 << width)
	if v >= (1 << width):
		v = v % (1 << width)
	var out := ""
	for i in range(width):
		out = (ONE if (v & 1) == 1 else ZERO) + out
		v = v >> 1
	return out

static func value_of(bits: String) -> int:
	if bits.contains(X):
		return -1
	return bits.bin_to_int() if not bits.is_empty() else 0

static func label(v: String) -> String:
	if v == X:
		return "X（未知/竞争）"
	return "1（高）" if v == ONE else "0（低）"
