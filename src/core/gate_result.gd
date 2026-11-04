class_name GateResult
extends RefCounted

## 结构化失败回传（M5 基础设施）。code 是稳定枚举（int），不是可变字符串。
## 每个失败结果统一形状：{code, gate_id, input, expected, actual, error_tags[], attempt}。
## 映射来源：`docs/curriculum/05-failure-diagnostics.md`（教学组交付后按其重映射；
## 该文件当前尚未入库，标签语义暂按六类首字母机器映射，见 `specs/m5/failure_contract.md`）。

const OK := 0
const E_MISSING_GRAPH := 1
const E_BUILD := 2
const E_UNCONNECTED := 3
const E_UNKNOWN_KIND := 4
const E_UNKNOWN_TARGET := 5
const E_TRUTH_ROW := 6
const E_TABLE_CELL := 7
const E_DELAY_EXCEED := 8
const E_DELAY_MISMATCH := 9
const E_OUTPUT_MISMATCH := 10
const E_STRUCTURE_SAME := 11
const E_ENCAPSULATION := 12
const E_COVERAGE := 13
const E_QUIZ := 14
const E_TARGET_UNREACHED := 15
const E_GLITCH := 16
const E_X_ROW := 17
const E_GENERIC := 99

## 六类错因标签（教学组口径）。
const TAG_K := "K"  # 概念/知识
const TAG_S := "S"  # 结构/连线
const TAG_C := "C"  # 计算/取值
const TAG_P := "P"  # 步骤/流程
const TAG_M := "M"  # 时序/亚稳
const TAG_R := "R"  # 兜底（其余失败；待 05 文档确认语义）
const TAGS := [TAG_K, TAG_S, TAG_C, TAG_P, TAG_M, TAG_R]

const NAMES := {
	OK: "OK",
	E_MISSING_GRAPH: "E_MISSING_GRAPH",
	E_BUILD: "E_BUILD",
	E_UNCONNECTED: "E_UNCONNECTED",
	E_UNKNOWN_KIND: "E_UNKNOWN_KIND",
	E_UNKNOWN_TARGET: "E_UNKNOWN_TARGET",
	E_TRUTH_ROW: "E_TRUTH_ROW",
	E_TABLE_CELL: "E_TABLE_CELL",
	E_DELAY_EXCEED: "E_DELAY_EXCEED",
	E_DELAY_MISMATCH: "E_DELAY_MISMATCH",
	E_OUTPUT_MISMATCH: "E_OUTPUT_MISMATCH",
	E_STRUCTURE_SAME: "E_STRUCTURE_SAME",
	E_ENCAPSULATION: "E_ENCAPSULATION",
	E_COVERAGE: "E_COVERAGE",
	E_QUIZ: "E_QUIZ",
	E_TARGET_UNREACHED: "E_TARGET_UNREACHED",
	E_GLITCH: "E_GLITCH",
	E_X_ROW: "E_X_ROW",
	E_GENERIC: "E_GENERIC",
}

const TAG_MAP := {
	OK: [],
	E_MISSING_GRAPH: [TAG_S],
	E_BUILD: [TAG_S],
	E_UNCONNECTED: [TAG_S],
	E_UNKNOWN_KIND: [TAG_P],
	E_UNKNOWN_TARGET: [TAG_P],
	E_TRUTH_ROW: [TAG_K, TAG_C],
	E_TABLE_CELL: [TAG_K, TAG_C],
	E_DELAY_EXCEED: [TAG_M],
	E_DELAY_MISMATCH: [TAG_M],
	E_OUTPUT_MISMATCH: [TAG_C],
	E_STRUCTURE_SAME: [TAG_S],
	E_ENCAPSULATION: [TAG_P],
	E_COVERAGE: [TAG_P],
	E_QUIZ: [TAG_K],
	E_TARGET_UNREACHED: [TAG_C],
	E_GLITCH: [TAG_M],
	E_X_ROW: [TAG_K, TAG_M],
	E_GENERIC: [TAG_R],
}

const DESCRIBE := {
	OK: "通过",
	E_MISSING_GRAPH: "缺少电路",
	E_BUILD: "电路无法构建",
	E_UNCONNECTED: "有输入未连接",
	E_UNKNOWN_KIND: "未知判定类型",
	E_UNKNOWN_TARGET: "未知目标函数",
	E_TRUTH_ROW: "真值表某行不正确",
	E_TABLE_CELL: "填表某格不正确",
	E_DELAY_EXCEED: "稳定时间超出上限",
	E_DELAY_MISMATCH: "稳定时间与期望不符",
	E_OUTPUT_MISMATCH: "输出与期望不符",
	E_STRUCTURE_SAME: "两种结构相同（要求不同结构）",
	E_ENCAPSULATION: "尚未封装",
	E_COVERAGE: "覆盖不完整",
	E_QUIZ: "选择题答案错误",
	E_TARGET_UNREACHED: "目标值尚未达成",
	E_GLITCH: "毛刺仍存在或未达宽度",
	E_X_ROW: "含 X 的用例失败",
	E_GENERIC: "未分类失败（已按兜底处理）",
}

static func is_ok(code: int) -> bool:
	return code == OK

static func normalize(code: int) -> int:
	return code if NAMES.has(code) else E_GENERIC

static func name_of(code: int) -> String:
	return str(NAMES.get(normalize(code), NAMES[E_GENERIC]))

static func tags_for(code: int) -> Array:
	return (TAG_MAP.get(normalize(code), [TAG_R]) as Array).duplicate()

static func describe(code: int) -> String:
	return str(DESCRIBE.get(normalize(code), DESCRIBE[E_GENERIC]))

static func make(code: int, gate_id: String, input: Variant, expected: Variant, actual: Variant, attempt: int = 0) -> Dictionary:
	## 未知 code 自动归一 `E_GENERIC`（不静默丢弃，也不抛错）。
	var c := normalize(code)
	return {
		"code": c,
		"code_name": name_of(c),
		"gate_id": gate_id,
		"input": input,
		"expected": expected,
		"actual": actual,
		"error_tags": tags_for(c),
		"attempt": maxi(0, attempt),
	}
