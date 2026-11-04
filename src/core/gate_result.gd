class_name GateResult
extends RefCounted

## 结构化失败回传（M5 基础设施）。code 是稳定枚举（int），不是可变字符串。
## 每个失败结果统一形状：{code, gate_id, input, expected, actual, error_tags[], attempt}。
## 映射来源：`docs/curriculum/05-failure-diagnostics.md`（19 条 code 的教学组定稿；
## 18–25 为 CH02 追加，不在该表内）。字段与精度见 `specs/m5/failure_contract.md`。

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
## CH02 新判定 kind 的 code（只增不改：18–24 为 M5 追加，25 为"暂不支持"标记）。
const E_REGION := 18
const E_STATIC_CURRENT := 19
const E_RAIL_MARGIN := 20
const E_EQUIV := 21
const E_AREA := 22
const E_POWER_CALC := 23
const E_POWER_RATIO := 24
const E_PENDING := 25
const E_HOLD_TICKS := 26
const E_TIMING_MARGIN := 27
const E_GENERIC := 99

## 六类错因标签（教学组口径）。
const TAG_K := "K"  # 概念/知识
const TAG_S := "S"  # 结构/连线
const TAG_C := "C"  # 计算/取值
const TAG_P := "P"  # 步骤/流程
const TAG_M := "M"  # 建模层（含时序/亚稳/三值这类模型错误）
const TAG_R := "R"  # 推理 + 技术兜底（4/5/10/99 只进日志，不进玩家提示阶梯）
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
	E_REGION: "E_REGION",
	E_STATIC_CURRENT: "E_STATIC_CURRENT",
	E_RAIL_MARGIN: "E_RAIL_MARGIN",
	E_EQUIV: "E_EQUIV",
	E_AREA: "E_AREA",
	E_POWER_CALC: "E_POWER_CALC",
	E_POWER_RATIO: "E_POWER_RATIO",
	E_PENDING: "E_PENDING",
	E_HOLD_TICKS: "E_HOLD_TICKS",
	E_TIMING_MARGIN: "E_TIMING_MARGIN",
	E_GENERIC: "E_GENERIC",
}

const TAG_MAP := {
	OK: [],
	E_MISSING_GRAPH: [TAG_S],
	E_BUILD: [TAG_S],
	E_UNCONNECTED: [TAG_S],
	E_UNKNOWN_KIND: [TAG_R],
	E_UNKNOWN_TARGET: [TAG_R],
	E_TRUTH_ROW: [TAG_K, TAG_S],
	E_TABLE_CELL: [TAG_K],
	E_DELAY_EXCEED: [TAG_M, TAG_S],
	E_DELAY_MISMATCH: [TAG_M, TAG_R],
	E_OUTPUT_MISMATCH: [TAG_R],
	E_STRUCTURE_SAME: [TAG_S, TAG_P],
	E_ENCAPSULATION: [TAG_P],
	E_COVERAGE: [TAG_P],
	E_QUIZ: [TAG_K],
	E_TARGET_UNREACHED: [TAG_C, TAG_P],
	E_GLITCH: [TAG_M, TAG_S],
	E_X_ROW: [TAG_K, TAG_M],
	E_REGION: [TAG_K, TAG_C],
	E_STATIC_CURRENT: [TAG_C],
	E_RAIL_MARGIN: [TAG_C],
	E_EQUIV: [TAG_K, TAG_C],
	E_AREA: [TAG_S, TAG_C],
	E_POWER_CALC: [TAG_C, TAG_K],
	E_POWER_RATIO: [TAG_C, TAG_K],
	E_PENDING: [TAG_R],
	E_HOLD_TICKS: [TAG_M, TAG_P],
	E_TIMING_MARGIN: [TAG_M, TAG_C],
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
	E_REGION: "MOS 工作区判错",
	E_STATIC_CURRENT: "静态电流超出上限",
	E_RAIL_MARGIN: "输出电平未达轨到轨",
	E_EQUIV: "与参考函数不等价",
	E_AREA: "门数超出上限",
	E_POWER_CALC: "功耗计算不符",
	E_POWER_RATIO: "功耗比不符",
	E_PENDING: "仿真层暂不支持（待接入）",
	E_HOLD_TICKS: "保持若干 tick 中途翻转",
	E_TIMING_MARGIN: "建立/保持余量为负",
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
