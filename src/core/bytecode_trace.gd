extends RefCounted

## CH13.1 参考执行器：把 lab 级 `program` 逐条执行，导出单步证据。
## 生产：`run(program)`（本文件）。
## 消费：`tests/test_ch13.gd` 用它生成 T13.1-1 作答；`src/core/net_lab_kit.gd::_table`
##（:82-165）按 `expect_rows` / `expect_meta` 逐格比对。
## 不新增 kind、不新增失败码：产物仍落在 table 的 rows + meta。

const STACK_EFFECT := {
	"PUSH": 1,
	"ADD": -1,
	"MUL": -1,
	"PRINT": -1,
	"HALT": 0,
}

static func run(program: Array) -> Dictionary:
	var stack: Array = []
	var out: Array = []
	var rows: Array = []
	var line_map: Array = []
	var lines: Array = []
	var unmapped: Array = []
	for raw in program:
		if not (raw is Dictionary):
			return {"ok": false, "error": "program 行不是对象"}
		var ins: Dictionary = raw
		var pc := int(ins.get("pc", rows.size()))
		var op := str(ins.get("opcode", ""))
		var src_line := int(ins.get("src_line", 0))
		if not STACK_EFFECT.has(op):
			return {"ok": false, "error": "未知 opcode %s @pc%d" % [op, pc]}
		if src_line <= 0:
			unmapped.append(pc)
		else:
			line_map.append({"pc": pc, "src_line": src_line})
			if not lines.has(src_line):
				lines.append(src_line)
		match op:
			"PUSH":
				stack.append(int(ins.get("operand", 0)))
			"ADD":
				if stack.size() < 2:
					return {"ok": false, "error": "ADD 栈下溢 @pc%d" % pc}
				var b := int(stack.pop_back())
				var a := int(stack.pop_back())
				stack.append(a + b)
			"MUL":
				if stack.size() < 2:
					return {"ok": false, "error": "MUL 栈下溢 @pc%d" % pc}
				var mb := int(stack.pop_back())
				var ma := int(stack.pop_back())
				stack.append(ma * mb)
			"PRINT":
				if stack.is_empty():
					return {"ok": false, "error": "PRINT 栈下溢 @pc%d" % pc}
				out.append(int(stack.pop_back()))
			"HALT":
				pass
		rows.append({"pc": pc, "opcode": op, "stack_after": stack.size()})
	lines.sort()
	return {
		"ok": true,
		"rows": rows,
		"line_map": line_map,
		"lines_covered": lines,
		"unmapped_pc": unmapped,
		"output": out,
		"stack_effect": STACK_EFFECT,
	}
