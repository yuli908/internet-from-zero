class_name TestContext
extends RefCounted

var checks := 0
var failures := 0
var suite := ""
var failure_messages: Array = []
var group := ""
var group_counts := {}

func begin(name: String) -> void:
	suite = name
	group = ""
	group_counts = {}

## 后续 check 归入该组；runner 用组名计数与各套件自报的 EXPECT_GROUPS 逐组比对。
func begin_group(name: String) -> void:
	group = name

func check(label: String, cond: bool, detail: String = "") -> bool:
	checks += 1
	if not group.is_empty():
		group_counts[group] = int(group_counts.get(group, 0)) + 1
		label = "%s::%s" % [group, label]
	if not cond:
		failures += 1
		var msg := "[%s] %s" % [suite, label]
		if not detail.is_empty():
			msg += " :: " + detail
		failure_messages.append(msg)
		print("  FAIL ", msg)
		return false
	return true

func eq(label: String, actual: Variant, expected: Variant) -> bool:
	return check(label, actual == expected, "期望 %s，实际 %s" % [str(expected), str(actual)])

func close(label: String, actual: float, expected: float, tol: float = 0.0001) -> bool:
	return check(label, absf(actual - expected) <= tol, "期望 %f，实际 %f" % [expected, actual])

func ne(label: String, actual: Variant, unexpected: Variant) -> bool:
	return check(label, actual != unexpected, "实际值不应等于 %s" % str(unexpected))

func report() -> bool:
	print("RESULT: %d checks, %d failures" % [checks, failures])
	if failures > 0:
		for msg in failure_messages:
			print("  - ", msg)
	return failures == 0

# 声明数与实际执行数比较：少执行即红。未声明的 suite（-1）同样判红。
static func verdict(expected: int, actual: int) -> Dictionary:
	var ok: bool = expected > 0 and actual >= expected
	return {"ok": ok, "expected": expected, "actual": actual}
