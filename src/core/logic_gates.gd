class_name LogicGates
extends RefCounted

## 门电路真值表与求值。电路仿真的唯一真值来源，UI 不得自行推算。

enum Type { AND, OR, NOT, XOR, NAND, NOR, XNOR, BUF }

const NAMES := {
	Type.AND: "与门",
	Type.OR: "或门",
	Type.NOT: "非门",
	Type.XOR: "异或门",
	Type.NAND: "与非门",
	Type.NOR: "或非门",
	Type.XNOR: "同或门",
	Type.BUF: "缓冲器",
}

const SYMBOLS := {
	Type.AND: "AND",
	Type.OR: "OR",
	Type.NOT: "NOT",
	Type.XOR: "XOR",
	Type.NAND: "NAND",
	Type.NOR: "NOR",
	Type.XNOR: "XNOR",
	Type.BUF: "BUF",
}

const KEYS := {
	"and": Type.AND,
	"or": Type.OR,
	"not": Type.NOT,
	"xor": Type.XOR,
	"nand": Type.NAND,
	"nor": Type.NOR,
	"xnor": Type.XNOR,
	"buf": Type.BUF,
}

static func from_string(s: String) -> int:
	return int(KEYS.get(s.to_lower(), -1))

static func key_for(type: int) -> String:
	## 反向查表：类型 → 小写键名（"and"/"or"/...）。未知返回空串。
	for k in KEYS.keys():
		if int(KEYS[k]) == type:
			return str(k)
	return ""

static func gate_key(type: int) -> String:
	return str(SYMBOLS.get(type, "UNKNOWN"))

static func display_name(type: int) -> String:
	return str(NAMES.get(type, "未知门"))

static func arity(type: int) -> int:
	return 1 if type == Type.NOT or type == Type.BUF else 2

static func evaluate(type: int, a: bool, b: bool = false) -> bool:
	match type:
		Type.AND:
			return a and b
		Type.OR:
			return a or b
		Type.NOT:
			return not a
		Type.XOR:
			return a != b
		Type.NAND:
			return not (a and b)
		Type.NOR:
			return not (a or b)
		Type.XNOR:
			return a == b
		Type.BUF:
			return a
	return false

static func truth_table(type: int) -> Array:
	var rows := []
	if arity(type) == 1:
		for a in [false, true]:
			rows.append({"a": a, "b": false, "out": evaluate(type, a, false)})
	else:
		for a in [false, true]:
			for b in [false, true]:
				rows.append({"a": a, "b": b, "out": evaluate(type, a, b)})
	return rows

static func signature(type: int) -> String:
	var s := ""
	for row in truth_table(type):
		s += "1" if bool(row.out) else "0"
	return s
